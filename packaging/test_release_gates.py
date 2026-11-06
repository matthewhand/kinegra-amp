import struct,tempfile,unittest,zipfile
from pathlib import Path
from release_gates import validate_release_manifest,validate_native_alignment,resolve_banner_resource

MANIFEST="""E: manifest
  E: application (line=1)
    A: android:allowBackup(0x01010280)=(type 0x12)0x0
    E: activity (line=2)
      A: android:name(0x01010003)=\"com.godot.game.GodotApp\"
      A: android:launchMode(0x0101001d)=(type 0x10)0x2
"""
def elf(alignment=16384):
    data=bytearray(120);data[:6]=b'\x7fELF\x02\x01';data[18:20]=b'\xb7\x00'
    struct.pack_into('<Q',data,32,64);struct.pack_into('<HH',data,54,56,1)
    struct.pack_into('<IIQQQQQQ',data,64,1,5,0,0,0,120,120,alignment)
    return data
def apk(path,alignment=16384,pad=True,compressed=False):
    item=zipfile.ZipInfo('lib/arm64-v8a/test.so')
    if pad:
        n=(-(30+len(item.filename)))%16384
        item.extra=struct.pack('<HH',0xcafe,n-4)+b'\0'*(n-4)
    item.compress_type=zipfile.ZIP_DEFLATED if compressed else zipfile.ZIP_STORED
    with zipfile.ZipFile(path,'w') as z:z.writestr(item,elf(alignment))
class ReleaseGatesTest(unittest.TestCase):
    def test_safe_manifest_and_default_debug_false(self):validate_release_manifest(MANIFEST)
    def test_debug_backup_and_duplicate_attributes_rejected(self):
        for line in ['    A: android:debuggable(0x0101000f)=(type 0x12)0xffffffff\n','    A: android:allowBackup(0x01010280)=(type 0x12)0x0\n']:
            with self.assertRaises(RuntimeError):validate_release_manifest(MANIFEST.replace('    E: activity',line+'    E: activity'))
        with self.assertRaises(RuntimeError):validate_release_manifest(MANIFEST.replace('0x12)0x0','0x12)0xffffffff'))
    def test_unsupported_multitask_mode_rejected(self):
        with self.assertRaises(RuntimeError):validate_release_manifest(MANIFEST.replace('0x10)0x2','0x10)0x4'))
    def test_obfuscated_release_banner_mapping(self):
        text='resource 0x7f06000c org.example:drawable/splash: t=0x03\n  (string8) "res/k_.png"\n'
        self.assertEqual(resolve_banner_resource(text),'res/k_.png')
        for invalid in [text+text,text.replace('res/k_.png','res/../secret.png'),text.replace('res/k_.png','https://example.invalid/cover.png'),'']:
            with self.assertRaises(RuntimeError):resolve_banner_resource(invalid)
    def test_16k_elf_and_zip_layout(self):
        with tempfile.TemporaryDirectory() as t:
            p=Path(t)/'ok.apk';apk(p);self.assertEqual(validate_native_alignment(p),1)
            for alignment,pad,compressed in [(4096,True,False),(16384,False,False),(16384,True,True)]:
                apk(p,alignment,pad,compressed)
                with self.assertRaises(RuntimeError):validate_native_alignment(p)
if __name__=='__main__':unittest.main()
