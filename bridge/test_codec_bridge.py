import io
import pathlib
import shutil
import subprocess
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import codec_bridge as b


class CodecIntegration(unittest.TestCase):
    def test_url_scope(self):
        self.assertEqual(b.validate_ma_url("http://10.77.0.111:8097/stream/abc?x=2", "http://10.77.0.111:8097"),
                         "http://10.77.0.111:8097/stream/abc?x=2")
        bad = [
            "http://10.77.0.111:8095/stream",
            "http://127.0.0.1:8097/stream",
            "http://198.51.100.23:8097/stream",  # RFC 5737 TEST-NET-2: wrong origin.
            "http://10.77.0.111:8097@evil.test/stream",
            "http://user:pass@10.77.0.111:8097/stream",
            "https://10.77.0.111:8097/stream",
            "http://10.77.0.111:8097/../admin",
            "http://10.77.0.111:8097/abc#fragment",
            "http://10.77.0.111:8097/abc\r\nBad: yes",
        ]
        for url in bad:
            with self.subTest(url=url), self.assertRaises(ValueError):
                b.validate_ma_url(url, "http://10.77.0.111:8097")

    def test_loopback_only(self):
        with self.assertRaises(ValueError):
            b.DecoderServer(("0.0.0.0", 0))
        server = b.DecoderServer(("127.0.0.1", 0))
        try:
            self.assertFalse(server.allow_ma)
            self.assertEqual(server.server_address[0], "127.0.0.1")
        finally:
            server.server_close()

    def test_chunked_wire_protocol(self):
        sink = io.BytesIO()
        framed = b.ChunkedSink(sink)
        framed.write(b"123")
        framed.finish()
        self.assertEqual(sink.getvalue(), b"3" + bytes([13,10]) + b"123" + bytes([13,10]) + b"0" + bytes([13,10,13,10]))

    def test_decoder_pin(self):
        self.assertEqual(b.FFMPEG_ARGS[0], "/usr/bin/ffmpeg")
        self.assertIn("pipe:0", b.FFMPEG_ARGS)
        self.assertIn("pipe:1", b.FFMPEG_ARGS)
        self.assertIn("-vn", b.FFMPEG_ARGS)
        self.assertNotIn("http://", " ".join(b.FFMPEG_ARGS))

    @unittest.skipUnless(shutil.which("ffmpeg"), "local synthetic FFmpeg unavailable")
    def test_synthetic_codec_roundtrip(self):
        for codec, options in [
            ("mp3", ["-f", "mp3", "-c:a", "libmp3lame"]),
            ("ogg", ["-f", "ogg", "-c:a", "libvorbis"]),
            ("wav", ["-f", "wav", "-c:a", "pcm_s16le"]),
            ("flac", ["-f", "flac", "-c:a", "flac"]),
            ("aac-adts", ["-f", "adts", "-c:a", "aac"]),
        ]:
            with self.subTest(codec=codec):
                cmd = ["/usr/bin/ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
                       "-f", "lavfi", "-i", "sine=frequency=440:duration=0.35",
                       "-ar", "48000", "-ac", "2"] + options + ["pipe:1"]
                sample = subprocess.run(cmd, capture_output=True, timeout=12, check=True).stdout
                self.assertLess(len(sample), 400_000)
                sink = io.BytesIO()
                bytes_out = b.decode_stream(io.BytesIO(sample), sink, max_seconds=6)
                output = sink.getvalue()
                self.assertEqual(output[:4], b"RIFF")
                self.assertEqual(output[8:12], b"WAVE")
                self.assertEqual(output[36:40], b"data")
                self.assertGreater(bytes_out, 0)
                self.assertLess(bytes_out, 150_000)
                self.assertNotEqual(set(output[44:]), {0})


if __name__ == "__main__":
    unittest.main(verbosity=2)
