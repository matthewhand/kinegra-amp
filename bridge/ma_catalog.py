#!/usr/bin/env python3
"""Portable, bounded MA catalog adapter. No playback/queue/library mutations.

Owner credentials live in memory. CLI credentials are getpass/TTY only. A media
identifier is never converted to a stream URL, and selecting an item never plays.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import getpass
import http.client
import ipaddress
import json
import math
import re
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.parse
from pathlib import Path

MAX_REPLY = 2 * 1024 * 1024
MAX_PAGE = 25
MAX_PLAYLIST_ITEMS = 250
MAX_OFFSET = 10000
MAX_SECONDS = 8.0
MAX_SELECTION_AGE = 60.0
CONTROL = re.compile(r'[\x00-\x1f\x7f-\x9f]')
ALLOWED_COMMANDS = frozenset({
    'players/all', 'player_queues/all', 'music/tracks/library_items',
    'music/playlists/library_items', 'music/tracks/get', 'music/playlists/get',
    'music/playlists/playlist_tracks',
})


class CatalogError(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def safe_text(value, limit=160):
    text = CONTROL.sub(' ', str(value or ''))
    text = re.sub(r'(?:https?|wss?)://\S+', '[URL REDACTED]', text, flags=re.I)
    return text[:limit]


def identifier(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 200 or CONTROL.search(value):
        raise CatalogError('invalid_identifier')
    return value


def origin(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 256 or CONTROL.search(value):
        raise CatalogError('invalid_endpoint')
    try:
        parsed = urllib.parse.urlsplit(value)
        port = parsed.port
    except ValueError:
        raise CatalogError('invalid_endpoint') from None
    if (parsed.scheme not in ('https', 'http') or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or parsed.query or parsed.fragment or parsed.path not in ('', '/')
            or '\\' in value or '%' in value or ' ' in value
            or parsed.hostname.startswith('.') or parsed.hostname.endswith('.')):
        raise CatalogError('invalid_endpoint')
    if not re.fullmatch(r'[A-Za-z0-9.-]+', parsed.hostname):
        raise CatalogError('invalid_endpoint')
    if port is not None and not 1 <= port <= 65535:
        raise CatalogError('invalid_endpoint')
    return parsed.scheme + '://' + parsed.netloc.lower()


@dataclass(frozen=True)
class Installation:
    api_origin: str = ''
    stream_origins: tuple[str, ...] = ()
    tailscale_node_id: str = ''

    @classmethod
    def from_dict(cls, value):
        if not isinstance(value, dict) or set(value) - {'version', 'api_origin', 'stream_origins', 'tailscale_node_id'}:
            raise CatalogError('invalid_configuration')
        if value.get('version', 1) != 1:
            raise CatalogError('unsupported_configuration_version')
        api = value.get('api_origin', '')
        api = origin(api) if api else ''
        streams = value.get('stream_origins', [])
        node = value.get('tailscale_node_id', '')
        if not isinstance(streams, list) or len(streams) > 4 or not isinstance(node, str) or len(node) > 100:
            raise CatalogError('invalid_configuration')
        streams = tuple(origin(item) for item in streams)
        if api.startswith('http://'):
            try:
                address = ipaddress.ip_address(urllib.parse.urlsplit(api).hostname)
            except ValueError:
                raise CatalogError('http_requires_verified_tailnet') from None
            if address not in ipaddress.ip_network('100.64.0.0/10') or not node:
                raise CatalogError('http_requires_verified_tailnet')
        return cls(api, streams, node)

    @classmethod
    def read(cls, path):
        if Path(path).stat().st_size > 4096:
            raise CatalogError('configuration_too_large')
        try:
            return cls.from_dict(json.loads(Path(path).read_text()))
        except (ValueError, UnicodeError):
            raise CatalogError('invalid_configuration') from None

    def verify_api_transport(self, run=subprocess.run):
        if not self.api_origin:
            raise CatalogError('not_configured')
        endpoint = urllib.parse.urlsplit(self.api_origin)
        if endpoint.scheme == 'https':
            return
        try:
            route = run(['ip', 'route', 'get', endpoint.hostname], capture_output=True,
                        text=True, timeout=3, check=True).stdout
            peer = run(['tailscale', 'whois', '--json', endpoint.hostname], capture_output=True,
                       text=True, timeout=3, check=True).stdout
            if ' dev tailscale0 ' not in ' ' + route + ' ':
                raise CatalogError('tailnet_identity_unverified')
            if json.loads(peer)['Node']['StableID'] != self.tailscale_node_id:
                raise CatalogError('tailnet_identity_unverified')
        except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError):
            raise CatalogError('tailnet_identity_unverified') from None


def validate_command(command, args):
    if command not in ALLOWED_COMMANDS or not isinstance(args, dict):
        raise CatalogError('operation_not_readonly')
    if command == 'players/all':
        valid = args == {'return_unavailable': True, 'return_disabled': True}
    elif command == 'player_queues/all':
        valid = not args
    elif command.endswith('/library_items'):
        valid = (set(args) == {'limit', 'offset', 'search', 'order_by', 'summary'}
                 and type(args['limit']) is int and 1 <= args['limit'] <= MAX_PAGE
                 and type(args['offset']) is int and 0 <= args['offset'] <= MAX_OFFSET
                 and isinstance(args['search'], str) and len(args['search']) <= 100
                 and not CONTROL.search(args['search'])
                 and args['order_by'] == 'sort_name' and args['summary'] is True)
    elif command.endswith('/get'):
        valid = set(args) == {'item_id', 'provider_instance_id_or_domain', 'allow_update_metadata'} and args['allow_update_metadata'] is False
        if valid:
            identifier(args['item_id'])
            identifier(args['provider_instance_id_or_domain'])
    else:
        valid = (set(args) == {'item_id', 'provider_instance_id_or_domain', 'force_refresh', 'allow_dynamic_tracks'}
                 and args['force_refresh'] is False and args['allow_dynamic_tracks'] is False)
        if valid:
            identifier(args['item_id'])
            identifier(args['provider_instance_id_or_domain'])
    if not valid:
        raise CatalogError('invalid_read_arguments')


class HTTPTransport:
    """No proxy/redirect handling, normal HTTPS validation and absolute deadline.

    Socket shutdown enforces the total timeout even for a drip-feeding server.
    No URL/response/error-body/credential is included in diagnostics.
    """
    def __init__(self, installation, verify=None):
        self.installation = installation
        self.verify = verify or installation.verify_api_transport
        self._socket = None

    def cancel(self):
        sock = self._socket
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    def request(self, token, command, args, message_id, cancel):
        if cancel.is_set():
            raise CatalogError('cancelled')
        self.verify()
        if cancel.is_set():
            raise CatalogError('cancelled')
        endpoint = urllib.parse.urlsplit(self.installation.api_origin)
        cls = http.client.HTTPSConnection if endpoint.scheme == 'https' else http.client.HTTPConnection
        connection = cls(endpoint.hostname, endpoint.port, timeout=6)
        start = time.monotonic()
        watchdog = None
        expired = threading.Event()
        try:
            connection.connect()
            if cancel.is_set():
                raise CatalogError('cancelled')
            self._socket = connection.sock
            sock = self._socket
            def timeout():
                expired.set()
                try:
                    sock.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
            watchdog = threading.Timer(max(.001, MAX_SECONDS - (time.monotonic() - start)), timeout)
            watchdog.daemon = True
            watchdog.start()
            body = json.dumps({'message_id': message_id, 'command': command, 'args': args}, separators=(',', ':')).encode()
            connection.request('POST', '/api', body, {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token, 'Connection': 'close'})
            response = connection.getresponse()
            if response.status in (401, 403):
                raise CatalogError('auth_expired' if response.status == 401 else 'permission_denied')
            if response.status != 200:
                raise CatalogError('server_rejected_request')
            length = response.getheader('Content-Length')
            if length is not None and (not length.isdigit() or int(length) > MAX_REPLY):
                raise CatalogError('reply_too_large')
            parts = bytearray()
            while True:
                if cancel.is_set():
                    raise CatalogError('cancelled')
                if expired.is_set():
                    raise CatalogError('timeout')
                block = response.read(min(16384, MAX_REPLY + 1 - len(parts)))
                if not block:
                    break
                parts.extend(block)
                if len(parts) > MAX_REPLY:
                    raise CatalogError('reply_too_large')
            if expired.is_set():
                raise CatalogError('timeout')
            try:
                return json.loads(parts)
            except (ValueError, UnicodeError, RecursionError):
                raise CatalogError('malformed_reply') from None
        except CatalogError:
            raise
        except (OSError, http.client.HTTPException, ValueError):
            raise CatalogError('cancelled' if cancel.is_set() else ('timeout' if expired.is_set() else 'disconnected')) from None
        finally:
            if watchdog is not None:
                watchdog.cancel()
            self._socket = None
            connection.close()


def summary(item):
    if not isinstance(item, dict):
        raise CatalogError('unexpected_catalog_shape')
    result = {'item_id': identifier(item.get('item_id')), 'provider': identifier(item.get('provider')),
              'name': safe_text(item.get('name')), 'media_type': safe_text(item.get('media_type'), 30),
              'available': item.get('is_playable', True) is True}
    # Never expose provider URLs, raw metadata/details or artwork fetches in the
    # portable listing. Selection keeps stable IDs, not copied music or a token.
    if type(item.get('duration')) in (int, float) and math.isfinite(item['duration']):
        result['duration_seconds'] = max(0, min(86400, item['duration']))
    return result


class CatalogSession:
    def __init__(self, installation, token='', transport=None, clock=time.monotonic):
        self.installation = installation
        self.token = token
        self.transport = transport or HTTPTransport(installation)
        self.clock = clock
        self.epoch = 0
        self.sequence = 0
        self.selection = None
        self._player_media = {}
        self._players_at = 0
        self._players_epoch = -1
        self._cancel = threading.Event()
        self._lock = threading.Lock()
        self.state = 'ready' if token else 'auth_required'

    def cancel(self):
        self.epoch += 1
        self.selection = None
        self._player_media.clear()
        self._cancel.set()
        self.transport.cancel()
        self.state = 'cancelled'

    def close(self):
        self.cancel()
        self.token = ''  # Python immutable strings cannot be guaranteed zeroized.
        self.state = 'closed'

    def request(self, command, args):
        validate_command(command, args)
        if not self.installation.api_origin:
            raise CatalogError('not_configured')
        if not isinstance(self.token, str) or not 10 <= len(self.token) <= 8192 or CONTROL.search(self.token) or not self.token.isascii():
            raise CatalogError('auth_required')
        if not self._lock.acquire(blocking=False):
            raise CatalogError('busy')
        epoch = self.epoch
        cancel = threading.Event()
        self._cancel = cancel
        self.sequence += 1
        message_id = 'shield-catalog-' + str(self.sequence)
        self.state = 'loading'
        try:
            value = self.transport.request(self.token, command, args, message_id, cancel)
            if epoch != self.epoch or cancel.is_set():
                raise CatalogError('cancelled')
            if isinstance(value, dict) and ('error' in value or value.get('success') is False):
                raise CatalogError('command_failed')
            if isinstance(value, dict) and 'message_id' in value:
                if str(value['message_id']) != message_id:
                    raise CatalogError('stale_reply')
                value = value.get('result')
            self.state = 'ready'
            return value
        except CatalogError as error:
            self.state = error.code
            if error.code in ('auth_expired', 'permission_denied'):
                self.token = ''
                self._player_media.clear()
                self.selection = None
            raise
        finally:
            self._lock.release()

    def page(self, kind='tracks', search='', offset=0, limit=MAX_PAGE):
        if kind not in ('tracks', 'playlists'):
            raise CatalogError('unsupported_collection')
        self.selection = None
        value = self.request('music/' + kind + '/library_items', {'limit': limit, 'offset': offset, 'search': search, 'order_by': 'sort_name', 'summary': True})
        if not isinstance(value, list) or len(value) > limit:
            raise CatalogError('unexpected_catalog_shape')
        return {'contract': 'shield.catalog.v1', 'kind': kind, 'epoch': self.epoch, 'sequence': self.sequence,
                'offset': offset, 'limit': limit, 'may_have_more': len(value) == limit,
                'items': [summary(item) for item in value]}

    def select(self, item):
        row = summary(item)
        self.selection = {'contract': 'shield.selection.v1', 'epoch': self.epoch,
                          'selected_monotonic': self.clock(), 'item': row}
        return self.selection.copy()

    def selection_item(self):
        if not self.selection or self.selection['epoch'] != self.epoch or self.clock() - self.selection['selected_monotonic'] > MAX_SELECTION_AGE:
            self.selection = None
            raise CatalogError('selection_expired')
        return self.selection['item'].copy()

    def details(self):
        selected = self.selection_item()
        kind = 'playlists' if selected['media_type'] == 'playlist' else 'tracks'
        value = self.request('music/' + kind + '/get', {'item_id': selected['item_id'], 'provider_instance_id_or_domain': selected['provider'], 'allow_update_metadata': False})
        return summary(value)

    def playlist_items(self):
        selected = self.selection_item()
        if selected['media_type'] != 'playlist':
            raise CatalogError('select_playlist_first')
        value = self.request('music/playlists/playlist_tracks', {'item_id': selected['item_id'], 'provider_instance_id_or_domain': selected['provider'], 'force_refresh': False, 'allow_dynamic_tracks': False})
        if not isinstance(value, list):
            raise CatalogError('unexpected_catalog_shape')
        return {'contract': 'shield.catalog.v1', 'kind': 'playlist_items', 'items': [summary(item) for item in value[:MAX_PLAYLIST_ITEMS]],
                'truncated': len(value) > MAX_PLAYLIST_ITEMS, 'server_pagination': False}

    def discover_players(self):
        value = self.request('players/all', {'return_unavailable': True, 'return_disabled': True})
        if not isinstance(value, list):
            raise CatalogError('unexpected_player_shape')
        players = []
        self._player_media.clear()
        for player in value[:100]:
            if not isinstance(player, dict):
                raise CatalogError('unexpected_player_shape')
            player_id = identifier(player.get('player_id'))
            players.append({'player_id': player_id, 'name': safe_text(player.get('display_name') or player.get('name')),
                            'state': safe_text(player.get('playback_state', 'unknown'), 30)})
            if isinstance(player.get('current_media'), dict):
                self._player_media[player_id] = player['current_media'].copy()
        self._players_at = self.clock()
        self._players_epoch = self.epoch
        return {'contract': 'shield.players.v1', 'items': players, 'truncated': len(value) > 100}

    def existing_stream_candidate(self, player_id):
        """Inspect fresh media from this session's authenticated players read only.

        No externally supplied dict or library identifier can gain provenance.
        The URI is never generated, probed, downloaded, persisted or played.
        """
        identifier(player_id)
        if (not self.token or self._players_epoch != self.epoch
                or self.clock() - self._players_at > MAX_SELECTION_AGE
                or player_id not in self._player_media):
            raise CatalogError('player_observation_expired')
        player_media = self._player_media[player_id]
        uri = player_media.get('uri', '')
        if not isinstance(uri, str) or len(uri) > 2048 or CONTROL.search(uri):
            raise CatalogError('invalid_stream_candidate')
        try:
            parsed = urllib.parse.urlsplit(uri)
        except ValueError:
            raise CatalogError('invalid_stream_candidate') from None
        if parsed.scheme not in ('http', 'https'):
            return {'status': 'unresolved_library_identifier', 'playable': False}
        if parsed.username is not None or parsed.password is not None or parsed.query or parsed.fragment or '\\' in uri or '%' in uri:
            raise CatalogError('unsafe_stream_candidate')
        candidate_origin = origin(parsed.scheme + '://' + parsed.netloc)
        if candidate_origin not in self.installation.stream_origins or not parsed.path.startswith('/') or parsed.path.startswith('//') or '..' in parsed.path.split('/'):
            raise CatalogError('stream_origin_not_configured')
        return {'contract': 'shield.stream-candidate.v1', 'status': 'existing_player_uri_unverified',
                'playable': False, 'requires_format_probe': True, 'epoch': self.epoch,
                'uri': uri, 'source': 'authenticated_player_media'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--live', action='store_true')
    parser.add_argument('--kind', choices=['tracks', 'playlists'], default='tracks')
    parser.add_argument('--search', default='')
    parser.add_argument('--offset', type=int, default=0)
    parser.add_argument('--limit', type=int, default=MAX_PAGE)
    args = parser.parse_args()
    installation = Installation.read(args.config)
    if not args.live:
        print(json.dumps({'state': 'configured' if installation.api_origin else 'not_configured', 'live': False, 'contract': 'shield.catalog.v1'}))
        return
    installation.verify_api_transport()
    if not sys.stdin.isatty():
        raise CatalogError('interactive_tty_required')
    token = getpass.getpass('Owner-provisioned MA token (hidden, not saved): ')
    session = CatalogSession(installation, token)
    token = None
    try:
        print(json.dumps(session.page(args.kind, args.search, args.offset, args.limit), ensure_ascii=True, indent=2))
    finally:
        session.close()


if __name__ == '__main__':
    try:
        main()
    except (CatalogError, OSError) as error:
        print(json.dumps({'state': error.code if isinstance(error, CatalogError) else 'configuration_unavailable', 'live': False}), file=sys.stderr)
        raise SystemExit(2)
