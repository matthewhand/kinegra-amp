#!/usr/bin/env python3
"""Export or verify the exact pinned Noise-C plus the reviewed bounds patch.

Usage: prepare_noise_source.py [--verify] <clean-pinned-checkout> <patched-source>
No checkout or existing export is modified. No network access is performed.
"""
import argparse
import hashlib
import io
from pathlib import Path
import subprocess
import tarfile
import tempfile

PIN = "a1e08809a1b8f65cd91765ba7d68a6d00648ad61"


def run(*args):
    return subprocess.check_output(args)


def snapshot(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("checkout", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    checkout = args.checkout.resolve(strict=True)
    output = args.output.resolve()
    if run("git", "-C", str(checkout), "rev-parse", "HEAD").decode().strip() != PIN:
        parser.error("Noise-C revision does not match pin")
    if run("git", "-C", str(checkout), "status", "--porcelain").strip():
        parser.error("Noise-C checkout must be clean")
    if output == checkout or checkout in output.parents:
        parser.error("Patched export must be outside the checkout")
    if not args.verify and output.exists():
        parser.error("Refusing to overwrite an existing export")
    patch = Path(__file__).with_name("noise-pattern-bounds.patch").resolve()
    with tempfile.TemporaryDirectory(prefix="shieldamp-noise-pin-") as scratch:
        expected = Path(scratch) / "source"
        expected.mkdir()
        archive = run("git", "-C", str(checkout), "archive", PIN)
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(expected, filter="data")
        subprocess.run(["git", "-C", str(expected), "apply", "--check", str(patch)], check=True)
        subprocess.run(["git", "-C", str(expected), "apply", str(patch)], check=True)
        if args.verify:
            if not output.is_dir() or snapshot(expected) != snapshot(output):
                parser.error("Noise-C export differs from pin plus reviewed bounds patch")
        else:
            import shutil
            shutil.copytree(expected, output)
    print("NOISE_PINNED_BOUNDS_SOURCE=" + str(output))


if __name__ == "__main__":
    main()
