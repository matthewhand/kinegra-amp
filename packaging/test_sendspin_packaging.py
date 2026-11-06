import hashlib,importlib.util,tempfile,unittest,zipfile
from pathlib import Path
p=Path(__file__).with_name('android_checks.py')
spec=importlib.util.spec_from_file_location('build_candidate_guard',p)
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
class SendspinGuardTests(unittest.TestCase):
 def test_minimum_sdk_fails_closed(self):
  for config in ('', 'custom_build/min_sdk=23', 'custom_build/min_sdk=25', 'custom_build/min_sdk=bogus', 'custom_build/min_sdk=26\ncustom_build/min_sdk=26'):
   with self.subTest(config=config), self.assertRaises(RuntimeError): build.validate_sendspin_min_sdk(config)
  for version in (26, 30): build.validate_sendspin_min_sdk('custom_build/min_sdk=%s' % version)
 def test_source_missing_wrong_and_valid(self):
  with tempfile.TemporaryDirectory() as t:
   app=Path(t); native=app/'native'; (native/'bin').mkdir(parents=True)
   with self.assertRaises(RuntimeError): build.validate_sendspin_source(app)
   (native/'ShieldSendspin.gdns').write_text('class_name="ShieldSendspin"\nres://native/ShieldSendspin.gdnlib')
   (native/'ShieldSendspin.gdnlib').write_text('Android.arm64-v8a="res://native/bin/libshield_sendspin_arm64.so"')
   lib=native/'bin/libshield_sendspin_arm64.so'; lib.write_bytes(b'bad')
   with self.assertRaises(RuntimeError): build.validate_sendspin_source(app)
   fake=bytearray(4096);fake[:6]=b'\x7fELF\x02\x01';fake[18:20]=b'\xb7\x00';lib.write_bytes(fake)
   self.assertEqual(build.validate_sendspin_source(app),hashlib.sha256(fake).hexdigest())
 def test_apk_requires_unique_resources_and_exact_library(self):
  with tempfile.TemporaryDirectory() as t:
   apk=Path(t)/'candidate.apk'; data=b'synthetic only'; digest=hashlib.sha256(data).hexdigest()
   entries={'assets/native/ShieldSendspin.gdns':b'a','assets/native/ShieldSendspin.gdnlib':b'b','lib/arm64-v8a/libshield_sendspin_arm64.so':data}
   def write(items):
    with zipfile.ZipFile(apk,'w') as z:
     for k,v in items.items():z.writestr(k,v)
   write(entries);build.validate_sendspin_apk(apk,digest)
   for missing in entries:
    write({k:v for k,v in entries.items() if k!=missing})
    with self.subTest(missing=missing),self.assertRaises(RuntimeError):build.validate_sendspin_apk(apk,digest)
   write(entries)
   with self.assertRaises(RuntimeError):build.validate_sendspin_apk(apk,'0'*64)
   write(dict(entries,**{'lib/x86_64/libshield_sendspin_x11.so':b'x'}))
   with self.assertRaises(RuntimeError):build.validate_sendspin_apk(apk,digest)
if __name__=='__main__':unittest.main()
