"""Portable native metadata is a release boundary, not a signing-time cleanup."""
from pathlib import Path
import tempfile, unittest, zipfile
from android_checks import validate_native_source_paths

class NativeSourcePaths(unittest.TestCase):
    def check_payload(self, data):
        with tempfile.TemporaryDirectory() as folder:
            apk=Path(folder)/'fixture.apk'
            with zipfile.ZipFile(apk,'w') as z:
                z.writestr('lib/arm64-v8a/libshield_sendspin_arm64.so',data)
            validate_native_source_paths(apk)

    def test_portable_source_and_build_names_are_allowed(self):
        self.check_payload(b'ELF\0(lambda at /src/sendspin/ws_server.cpp:1:2)\0/build/sendspin\0/toolchain/android-ndk')

    def test_local_user_and_mount_paths_are_rejected(self):
        paths=[b'/' + b'home/' + b'example-user/project/file.cpp',
               b'/' + b'Users/' + b'example-user/project/file.cpp',
               b'/' + b'mnt/' + b'downloads/cache/file.cpp',
               b'/' + b'mnt/' + b'data/cache/file.cpp',
               b'C:' + bytes([92]) + b'Users' + bytes([92]) + b'example-user' + bytes([92]) + b'project']
        for path in paths:
            with self.subTest(path=path), self.assertRaisesRegex(RuntimeError,'source path'):
                self.check_payload(b'ELF\0(lambda at '+path+b':96:38)\0')

if __name__=='__main__': unittest.main()
