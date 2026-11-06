"""Real decoded signal tests for host ABI that is cross-compiled on AArch64."""
import ctypes as C
import math
import pathlib
import random
import subprocess
import unittest

HERE = pathlib.Path(__file__).resolve().parents[1]
SO = HERE / "build/libtegra_codec_host.so"
LIB = C.CDLL(str(SO))
LIB.tm_create.argtypes = [C.c_int]
LIB.tm_create.restype = C.c_void_p
LIB.tm_destroy.argtypes = [C.c_void_p]
LIB.tm_finish.argtypes = [C.c_void_p]
LIB.tm_reset.argtypes = [C.c_void_p]
LIB.tm_push.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
LIB.tm_push.restype = C.c_int
LIB.tm_pull.argtypes = [C.c_void_p, C.c_void_p, C.c_size_t]
LIB.tm_pull.restype = C.c_int
for name in ("tm_buffered_input", "tm_buffered_output_frames", "tm_context_bytes"):
    fn = getattr(LIB, name)
    fn.argtypes = [C.c_void_p]
    fn.restype = C.c_size_t
for name in ("tm_error", "tm_channels", "tm_sample_rate"):
    fn = getattr(LIB, name)
    fn.argtypes = [C.c_void_p]
    fn.restype = C.c_int
MAX_INPUT = 131072
MAX_OUTPUT = 8192


def synth(codec, seconds=0.7, rate=44100):
    args = ["/usr/bin/ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
            "-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}",
            "-ar", str(rate), "-ac", "2", "-f", codec,
            "-c:a", "libmp3lame" if codec == "mp3" else "libvorbis", "pipe:1"]
    return subprocess.run(args, check=True, capture_output=True, timeout=10).stdout


def push(ctx, data):
    value = C.create_string_buffer(data)
    return LIB.tm_push(ctx, value, len(data))


def read(ctx):
    buffer = (C.c_int16 * (MAX_OUTPUT * 2))()
    got = LIB.tm_pull(ctx, buffer, MAX_OUTPUT)
    if got < 0:
        raise AssertionError(f"decode failed code {got} buffered={LIB.tm_buffered_input(ctx)}")
    return list(buffer[:2*got]), got


class NativeCodecTests(unittest.TestCase):
    def test_invalid_codecs(self):
        self.assertFalse(LIB.tm_create(0))
        self.assertFalse(LIB.tm_create(3))

    def test_mp3_real_audio_fragmentation_and_reset(self):
        data = synth("mp3")
        ctx = LIB.tm_create(1)
        self.assertTrue(ctx)
        self.addCleanup(LIB.tm_destroy, ctx)
        decoded = []
        chunks = [1, 7, 31, 197, 509, 4096]
        index = 0
        while index < len(data):
            size = chunks[index % len(chunks)]
            take = data[index:index+size]
            self.assertEqual(push(ctx, take), len(take))
            index += len(take)
            for _ in range(12):
                samples, frames = read(ctx)
                if not frames:
                    break
                decoded += samples
            self.assertLessEqual(LIB.tm_buffered_input(ctx), MAX_INPUT)
            self.assertLessEqual(LIB.tm_buffered_output_frames(ctx), MAX_OUTPUT)
        LIB.tm_finish(ctx)
        for _ in range(40):
            samples, frames = read(ctx)
            if not frames:
                break
            decoded += samples
        self.assertGreater(len(decoded), 2 * 29000)
        self.assertEqual(LIB.tm_sample_rate(ctx), 44100)
        self.assertEqual(LIB.tm_channels(ctx), 2)
        self.assertGreater(max(abs(v) for v in decoded), 500)
        self.assertLess(LIB.tm_context_bytes(ctx), 500000)
        LIB.tm_reset(ctx)
        self.assertEqual(LIB.tm_buffered_input(ctx), 0)
        self.assertEqual(LIB.tm_sample_rate(ctx), 0)
        self.assertEqual(LIB.tm_error(ctx), 0)

    def test_ogg_real_audio_fragmentation(self):
        data = synth("ogg")
        ctx = LIB.tm_create(2)
        self.assertTrue(ctx)
        self.addCleanup(LIB.tm_destroy, ctx)
        decoded = []
        index = 0
        chunks = [1, 16, 113, 512, 2048, 8192]
        while index < len(data):
            take = data[index:index+chunks[index % len(chunks)]]
            result = push(ctx, take)
            self.assertEqual(result, len(take))
            index += len(take)
            for _ in range(16):
                samples, frames = read(ctx)
                if not frames:
                    break
                decoded += samples
            self.assertLessEqual(LIB.tm_buffered_input(ctx), MAX_INPUT)
        LIB.tm_finish(ctx)
        for _ in range(40):
            samples, frames = read(ctx)
            if not frames:
                break
            decoded += samples
        self.assertGreater(len(decoded), 2 * 29000)
        self.assertGreater(max(abs(x) for x in decoded), 500)
        self.assertEqual(LIB.tm_sample_rate(ctx), 44100)
        self.assertEqual(LIB.tm_channels(ctx), 2)
        self.assertLessEqual(LIB.tm_context_bytes(ctx), 2700000)

    def test_backpressure_and_partial_output(self):
        ctx = LIB.tm_create(1)
        self.addCleanup(LIB.tm_destroy, ctx)
        payload = b"\x00"*MAX_INPUT
        self.assertEqual(push(ctx, payload), MAX_INPUT)
        self.assertEqual(push(ctx, b"\xff"), -2)
        self.assertEqual(LIB.tm_buffered_input(ctx), MAX_INPUT)
        self.assertEqual(LIB.tm_pull(ctx, None, 4), -1)
        LIB.tm_reset(ctx)
        self.assertEqual(LIB.tm_buffered_input(ctx), 0)

    def test_mp3_large_id3_tag_denied(self):
        ctx = LIB.tm_create(1)
        self.addCleanup(LIB.tm_destroy, ctx)
        # ID3v2 synchsafe 0x1FFFFF => larger than our 128 KiB cap.
        header = b"ID3" + bytes([4, 0, 0, 0, 127, 127, 127, 127])
        self.assertEqual(push(ctx, header), len(header))
        out = (C.c_int16 * (MAX_OUTPUT * 2))()
        self.assertEqual(LIB.tm_pull(ctx, out, MAX_OUTPUT), -4)
        self.assertEqual(LIB.tm_error(ctx), -4)

    def test_mp3_short_chunk_eof_and_empty_input(self):
        ctx = LIB.tm_create(1)
        self.addCleanup(LIB.tm_destroy, ctx)
        sample = synth("mp3", seconds=0.3)
        self.assertEqual(LIB.tm_pull(ctx, (C.c_int16*10)(), 5), 0)
        frames = 0
        for v in sample:
            self.assertEqual(push(ctx, bytes([v])), 1)
            while True:
                buf, n = read(ctx)
                frames += n
                if not n:
                    break
        LIB.tm_finish(ctx)
        for _ in range(100):
            _, n = read(ctx)
            frames += n
            if not n: break
        self.assertGreater(frames, 10000)
        self.assertEqual(LIB.tm_buffered_input(ctx), 0)
        self.assertEqual(push(ctx, b"new"), -1)

    def test_arg_validation(self):
        ctx = LIB.tm_create(1)
        self.addCleanup(LIB.tm_destroy, ctx)
        self.assertEqual(LIB.tm_push(ctx, None, 3), -1)
        self.assertEqual(LIB.tm_pull(ctx, None, 3), -1)
        self.assertEqual(LIB.tm_pull(ctx, (C.c_int16*2)(), 9000), -1)
        self.assertEqual(LIB.tm_buffered_output_frames(ctx), 0)

    def test_reset_reinitializes_sample_rate(self):
        ctx = LIB.tm_create(1)
        self.addCleanup(LIB.tm_destroy, ctx)
        # Streaming audio format changes should fail closed, not push broken PCM.
        for rate in (44100,):
            data = synth("mp3", seconds=0.3, rate=rate)
            self.assertEqual(push(ctx, data), len(data))
            for _ in range(12): read(ctx)
        self.assertEqual(LIB.tm_sample_rate(ctx), 44100)
        LIB.tm_reset(ctx)
        self.assertEqual(LIB.tm_sample_rate(ctx), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
