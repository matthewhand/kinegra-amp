import http.server
import json
from pathlib import Path
import subprocess
import sys
import threading
import time
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parent))
import ma_catalog as m

TOKEN = 'synthetic-owner-token'
ITEM = {'item_id': '12', 'provider': 'library', 'name': 'Synthetic tune', 'media_type': 'track', 'uri': 'library://track/12'}

class FakeTransport:
    def __init__(self, value=None):
        self.value = [ITEM] if value is None else value
        self.calls = []
        self.cancelled = False
    def request(self, token, command, args, message_id, cancel):
        self.calls.append((command, args))
        if isinstance(self.value, Exception):
            raise self.value
        return self.value
    def cancel(self):
        self.cancelled = True

class CatalogTests(unittest.TestCase):
    def session(self, value=None, clock=time.monotonic):
        return m.CatalogSession(m.Installation.from_dict({'api_origin': 'https://ma.example', 'stream_origins': ['https://audio.example']}), TOKEN, FakeTransport(value), clock)

    def test_empty_setup(self):
        session = m.CatalogSession(m.Installation())
        with self.assertRaisesRegex(m.CatalogError, 'not_configured'):
            session.page()

    def test_configuration_fail_closed(self):
        for config in [
            {'api_origin': 'http://10.77.0.1:8095'}, {'api_origin': 'http://100.64.0.1'},
            {'api_origin': 'https://user:secret@host'}, {'api_origin': 'https://host/api'},
            {'api_origin': 'https://host?token=secret'}, {'api_origin': 'https://host:0'},
            {'api_origin': 'https://host:65536'}, {'version': 2}, {'token': TOKEN},
            {'api_origin': 'https://host\r\nHeader: yes'},
        ]:
            with self.subTest(config=config), self.assertRaises(m.CatalogError):
                m.Installation.from_dict(config)

    def test_identity_bound_tailscale(self):
        installation = m.Installation.from_dict({'api_origin': 'http://100.64.0.1:8095', 'tailscale_node_id': 'approved-node'})
        def run(args, **kwargs):
            return subprocess.CompletedProcess(args, 0, stdout='100.64.0.1 dev tailscale0 src 100.64.0.2' if args[0] == 'ip' else json.dumps({'Node': {'StableID': 'approved-node'}}))
        installation.verify_api_transport(run)
        def wrong(args, **kwargs):
            return subprocess.CompletedProcess(args, 0, stdout='100.64.0.1 dev eth0 src 10.77.0.1')
        with self.assertRaisesRegex(m.CatalogError, 'tailnet_identity_unverified'):
            installation.verify_api_transport(wrong)

    def test_page_and_safe_summary(self):
        value = dict(ITEM, name='Name\x1b[31m https://private/secret', provider_mappings=[{'url': 'secret'}])
        session = self.session([value])
        page = session.page(search='synthetic')
        self.assertEqual(page['contract'], 'shield.catalog.v1')
        self.assertNotIn('secret', json.dumps(page))
        self.assertNotIn('\x1b', page['items'][0]['name'])
        self.assertEqual(session.transport.calls[0][1]['limit'], 25)

    def test_bounded_catalog_arguments(self):
        for kwargs in [{'limit': 26}, {'offset': -1}, {'offset': 10001}, {'search': 'a'*101}, {'search': '\x00'}]:
            with self.assertRaises(m.CatalogError):
                self.session().page(**kwargs)

    def test_no_write_commands_or_impersonation(self):
        for command in ['player_queues/play_media', 'music/library/add_item', 'auth/token', 'music/tracks/preview']:
            with self.assertRaises(m.CatalogError):
                self.session().request(command, {})
        with self.assertRaises(m.CatalogError):
            self.session().request('music/tracks/library_items', {'user': 'other'})

    def test_metadata_refresh_disabled(self):
        session = self.session(ITEM)
        session.select(ITEM)
        self.assertEqual(session.details()['item_id'], '12')
        self.assertIs(session.transport.calls[0][1]['allow_update_metadata'], False)

    def test_selection_is_not_playback_and_expires(self):
        now = [1.0]
        session = self.session(clock=lambda: now[0])
        session.select(ITEM)
        self.assertEqual(session.transport.calls, [])
        now[0] = 62
        with self.assertRaisesRegex(m.CatalogError, 'selection_expired'):
            session.selection_item()

    def test_cancel_rejects_obsolete_reply(self):
        session = self.session()
        def request(*args):
            session.cancel()
            return [ITEM]
        session.transport.request = request
        with self.assertRaisesRegex(m.CatalogError, 'cancelled'):
            session.page()
        self.assertIsNone(session.selection)

    def test_auth_errors_drop_token(self):
        for code in ['auth_expired', 'permission_denied']:
            session = self.session(m.CatalogError(code))
            with self.assertRaises(m.CatalogError):
                session.page()
            self.assertEqual(session.token, '')

    def test_stale_envelope_and_error(self):
        for value in [{'message_id': 'obsolete', 'result': []}, {'error': 'secret'}, {'success': False}]:
            with self.assertRaises(m.CatalogError):
                self.session(value).page()

    def test_page_server_limit_enforced(self):
        with self.assertRaises(m.CatalogError):
            self.session([ITEM]*26).page()

    def test_playlist_preview_has_explicit_cap(self):
        session = self.session([ITEM] * 251)
        session.select(dict(ITEM, media_type='playlist'))
        page = session.playlist_items()
        self.assertEqual(len(page['items']), 250)
        self.assertTrue(page['truncated'])
        self.assertFalse(page['server_pagination'])
        self.assertIs(session.transport.calls[0][1]['force_refresh'], False)

    def test_library_uri_never_becomes_stream(self):
        session = self.session([{'player_id': 'player', 'current_media': {'uri': 'library://track/12'}}])
        session.discover_players()
        self.assertEqual(session.existing_stream_candidate('player'), {'status': 'unresolved_library_identifier', 'playable': False})

    def test_existing_stream_requires_known_origin_and_provenance(self):
        session = self.session()
        session.transport.value = [{'player_id': 'player', 'current_media': {'uri': 'https://audio.example/existing.mp3'}}]
        session.discover_players()
        candidate = session.existing_stream_candidate('player')
        self.assertFalse(candidate['playable'])
        self.assertTrue(candidate['requires_format_probe'])
        for uri in ['https://unknown.example/a', 'https://audio.example/a?token=x', 'https://u:p@audio.example/a', 'https://audio.example/../a']:
            with self.assertRaises(m.CatalogError):
                session.transport.value = [{'player_id': 'player', 'current_media': {'uri': uri}}]
                session.discover_players()
                session.existing_stream_candidate('player')

    def test_no_external_or_cancelled_stream_provenance(self):
        session = self.session()
        with self.assertRaises(m.CatalogError):
            session.existing_stream_candidate('unknown-player')
        session.transport.value = [{'player_id': 'player', 'current_media': {'uri': 'https://audio.example/a'}}]
        session.discover_players()
        session.cancel()
        with self.assertRaises(m.CatalogError):
            session.existing_stream_candidate('player')

    def test_close_never_persists_token(self):
        session = self.session()
        session.close()
        self.assertEqual(session.token, '')
        self.assertTrue(session.transport.cancelled)


class Server(http.server.BaseHTTPRequestHandler):
    mode = 'normal'
    seen = []
    def log_message(self, *args):
        pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.seen.append((self.path, body, self.headers.get('Authorization')))
        if self.mode == 'auth':
            self.send_response(401)
            self.end_headers()
            return
        if self.mode == 'redirect':
            self.send_response(302)
            self.send_header('Location', 'https://evil.example')
            self.end_headers()
            return
        self.send_response(200)
        if self.mode == 'oversize':
            self.send_header('Content-Length', str(m.MAX_REPLY + 1))
        else:
            data = json.dumps([ITEM]).encode()
            self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        try:
            if self.mode == 'drip':
                for byte in data:
                    self.wfile.write(bytes([byte]))
                    self.wfile.flush()
                    time.sleep(.05)
            elif self.mode != 'oversize':
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

class TransportTests(unittest.TestCase):
    def setUp(self):
        Server.seen = []
        Server.mode = 'normal'
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Server)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        # Test-only transport identity override; production from_dict refuses this HTTP origin.
        install = m.Installation(api_origin='http://127.0.0.1:' + str(self.server.server_port))
        self.transport = m.HTTPTransport(install, verify=lambda: None)
        self.session = m.CatalogSession(install, TOKEN, self.transport)
    def tearDown(self):
        self.session.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)
    def test_actual_http_raw_reply(self):
        self.assertEqual(self.session.page()['items'][0]['name'], 'Synthetic tune')
        self.assertEqual(Server.seen[0][0], '/api')
        self.assertEqual(Server.seen[0][2], 'Bearer ' + TOKEN)
    def test_actual_auth_redaction(self):
        Server.mode = 'auth'
        with self.assertRaisesRegex(m.CatalogError, '^auth_expired$'):
            self.session.page()
        self.assertEqual(self.session.token, '')
    def test_no_redirect(self):
        Server.mode = 'redirect'
        with self.assertRaisesRegex(m.CatalogError, 'server_rejected_request'):
            self.session.page()
    def test_declared_oversize_before_body(self):
        Server.mode = 'oversize'
        with self.assertRaisesRegex(m.CatalogError, 'reply_too_large'):
            self.session.page()
    def test_total_deadline_against_drip(self):
        Server.mode = 'drip'
        start = time.monotonic()
        with patch.object(m, 'MAX_SECONDS', .15), self.assertRaisesRegex(m.CatalogError, 'timeout'):
            self.session.page()
        self.assertLess(time.monotonic() - start, 1)
    def test_cancel_before_transport_sends_no_request(self):
        cancel = threading.Event()
        cancel.set()
        with self.assertRaisesRegex(m.CatalogError, 'cancelled'):
            self.transport.request(TOKEN, 'players/all', {}, 'test', cancel)
        self.assertEqual(Server.seen, [])

    def test_cancel_during_blocked_read(self):
        Server.mode = 'drip'
        timer = threading.Timer(.12, self.session.cancel)
        timer.start()
        try:
            with self.assertRaisesRegex(m.CatalogError, 'cancelled'):
                self.session.page()
        finally:
            timer.cancel()

if __name__ == '__main__':
    unittest.main(verbosity=2)
