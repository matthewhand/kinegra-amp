#!/usr/bin/env python3
"""Kinegra Amp's LAN remote: Python 3 standard library, no stored credentials."""
import argparse
import ipaddress
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

MAX_REPLY = 2 * 1024 * 1024
PRIVATE = (ipaddress.ip_network((0x0a000000, 8)),) + tuple(ipaddress.ip_network(n) for n in (
     '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8', '169.254.0.0/16'))


class RemoteError(Exception):
    pass


def origin(value):
    try:
        u = urllib.parse.urlsplit(value)
        host = u.hostname
        address = ipaddress.ip_address('127.0.0.1' if host == 'localhost' else host)
        port = u.port or 8765
        if (u.scheme != 'http' or u.username is not None or u.password is not None
                or u.path not in ('', '/') or u.query or u.fragment
                or address.version != 4 or not any(address in block for block in PRIVATE)
                or not 1 <= port <= 65535):
            raise ValueError()
        return 'http://%s:%d' % (address, port)
    except (ValueError, TypeError):
        raise RemoteError('Use an HTTP address on your private IPv4 LAN, such as http://192.168.1.20:8765.') from None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Remote:
    def __init__(self, address, key='', wait=42.0):
        self.address, self.key, self.wait = origin(address), key, wait
        # Never send a LAN key through an ambient HTTP proxy or a redirect.
        self.http = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def request(self, path, body=None):
        headers = {'Accept': 'application/json'}
        if self.key:
            headers['Authorization'] = 'Bearer ' + self.key
        data = None
        if body is not None:
            headers['Content-Type'] = 'application/json'
            data = json.dumps(body).encode('utf-8')
        req = urllib.request.Request(self.address + path, headers=headers, data=data)
        try:
            with self.http.open(req, timeout=5) as response:
                raw = response.read(MAX_REPLY + 1)
                if len(raw) > MAX_REPLY:
                    raise RemoteError('Reply exceeds the client limit.')
                result = json.loads(raw)
                if not isinstance(result, dict):
                    raise RemoteError('Unreadable reply from Kinegra Amp.')
                return result
        except urllib.error.HTTPError as error:
            if error.code == 401:
                raise RemoteError('Access key rejected. Use the current key shown in Kinegra Amp Settings.') from None
            if error.code == 403:
                raise RemoteError('Access denied. Check trusted LAN ranges in Kinegra Amp Settings.') from None
            if error.code == 409:
                raise RemoteError('The page or playback session changed, or another request is running. Refresh before choosing music.') from None
            raise RemoteError('Kinegra Amp returned HTTP %d. No request was retried.' % error.code) from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise RemoteError('Cannot reach Kinegra Amp or the connection ended. No request was retried; check Queue before repeating a playback or queue change.') from None
        except (ValueError, UnicodeError):
            raise RemoteError('Unreadable reply from Kinegra Amp. No request was retried.') from None

    def connect(self, no_key=False):
        access = self.request('/api/access')
        if access.get('require_key') is False:
            self.key = ''
        elif no_key:
            raise RemoteError('This Kinegra Amp session requires a key; no action was sent.')
        elif not re.fullmatch('[0-9a-fA-F]{16}', self.key):
            raise RemoteError('Set KINEGRA_AMP_ACCESS_KEY to the current 16-character key from Kinegra Amp Settings.')

    def operation(self, path, body):
        job = self.request(path, body)
        operation = str(job.get('operation', ''))
        if not operation.isdecimal() or len(operation) > 20:
            raise RemoteError('Missing operation identifier. Check Queue before repeating a change.')
        end = time.monotonic() + self.wait
        while time.monotonic() < end:
            result = self.request('/api/operations/' + operation)
            if result.get('state') == 'done':
                return result
            if result.get('state') == 'error':
                raise RemoteError(str(result.get('message', 'Request failed. Check Queue before repeating a change.')))
            time.sleep(.25)
        raise RemoteError('Operation timed out. It may have completed; check Queue before retrying. No request was repeated.')


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--url', required=True, help='Address shown in Kinegra Amp Settings, including port')
    p.add_argument('--no-key', action='store_true', help='Require the TV to have key-free trusted-LAN access enabled')
    p.add_argument('--wait-seconds', type=float, default=42, help='Operation polling bound, 1–60 seconds')
    sub = p.add_subparsers(dest='command', required=True)
    for name in ['status', 'diagnostics', 'play', 'pause', 'previous', 'next', 'stop', 'queue']:
        sub.add_parser(name)
    browse = sub.add_parser('browse')
    browse.add_argument('kind', choices=['tracks', 'albums', 'playlists'])
    browse.add_argument('--search', default='')
    browse.add_argument('--offset', type=int, default=0)
    for name in ['open', 'play-item', 'add']:
        command = sub.add_parser(name)
        command.add_argument('--page-id', type=int, required=True)
        command.add_argument('--item', type=int, required=True)
        if name != 'open':
            command.add_argument('--request-id', help='Reuse only for the exact same ambiguous action; never automatically retry')
    page = sub.add_parser('page')
    page.add_argument('--page-id', type=int, required=True)
    page.add_argument('--offset', type=int, default=0)
    page.add_argument('--search', default='')
    page = sub.add_parser('add-page')
    page.add_argument('--page-id', type=int, required=True)
    page.add_argument('--request-id')
    return p


def main(argv=None):
    args = parser().parse_args(argv)
    try:
        if not 1 <= args.wait_seconds <= 60:
            raise RemoteError('--wait-seconds must be between 1 and 60.')
        if hasattr(args, 'search') and len(args.search) > 100:
            raise RemoteError('Search must be at most 100 characters.')
        for name in ['page_id', 'item', 'offset']:
            if hasattr(args, name) and not 0 <= getattr(args, name) <= 100000:
                raise RemoteError('Page, item and offset must be bounded nonnegative integers.')
        request_id = None
        if args.command in ['play-item', 'add', 'add-page']:
            request_id = args.request_id or uuid.uuid4().hex
            if not re.fullmatch('[A-Za-z0-9_-]{8,64}', request_id):
                raise RemoteError('Request IDs need 8–64 letters, numbers, underscores or hyphens.')
        remote = Remote(args.url, os.environ.get('KINEGRA_AMP_ACCESS_KEY', '').strip(), args.wait_seconds)
        remote.connect(args.no_key)
        cmd = args.command
        if cmd in ['status', 'diagnostics']:
            result = remote.request('/api/' + cmd)
        elif cmd in ['play', 'pause', 'previous', 'next', 'stop']:
            result = remote.request('/api/control', {'action': cmd})
            print('Request accepted is not proof of audio; use diagnostics or listen on the device.', file=sys.stderr)
        else:
            if cmd == 'browse':
                path, body = '/api/library', {'kind': args.kind, 'search': args.search, 'offset': args.offset}
            elif cmd == 'queue':
                path, body = '/api/queue/refresh', {}
            else:
                path = {'open': '/api/library/open', 'page': '/api/library/page', 'play-item': '/api/library/play', 'add': '/api/queue/add', 'add-page': '/api/queue/add-page'}[cmd]
                body = {'page_id': args.page_id}
                if cmd in ['open', 'play-item', 'add']:
                    body['item'] = args.item
                elif cmd == 'page':
                    body.update(offset=args.offset, search=args.search)
                if request_id:
                    body['request_id'] = request_id
            if request_id:
                print('Request ID: ' + request_id, file=sys.stderr)
            result = remote.operation(path, body)
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0
    except RemoteError as error:
        print('Kinegra Amp: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
