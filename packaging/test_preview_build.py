#!/usr/bin/env python3
"""Preview isolation and signing/package guard regressions; no SDK/device needed."""
from pathlib import Path
import json,tempfile,unittest,subprocess
import build_preview as preview

class PreviewGuards(unittest.TestCase):
 def setUp(self):self.temp=tempfile.TemporaryDirectory(prefix="preview-builder-guards-");self.root=Path(self.temp.name)
 def tearDown(self):self.temp.cleanup()
 def test_build_sdk_cannot_contact_real_adb(self):
  sdk=self.root/"sdk";(sdk/"platform-tools").mkdir(parents=True);(sdk/"platforms").mkdir()
  real=sdk/"platform-tools/adb";real.write_text("#!/bin/sh\nexit 99\n");real.chmod(0o700)
  result=preview.stage_build_sdk(sdk,self.root)
  self.assertTrue((result/"platforms").is_symlink())
  devices=subprocess.run([result/"platform-tools/adb","devices"],capture_output=True,text=True)
  self.assertEqual(devices.returncode,0);self.assertEqual(devices.stdout,"List of devices attached\n\n")
  blocked=subprocess.run([result/"platform-tools/adb","shell","echo","bad"],capture_output=True)
  self.assertEqual(blocked.returncode,1)
  self.assertEqual(real.read_text(),"#!/bin/sh\nexit 99\n")
 def test_production_package_and_key_overrides_rejected(self):
  for field in ["package","signing_keystore","signing_password"]:
   config=self.root/(field+".json");config.write_text(json.dumps({field:"production-input"}))
   with self.assertRaises(ValueError):preview.load_config(config,self.root)
 def test_export_is_distinct_and_has_no_production_settings(self):
  source=self.root/"source";app=self.root/"preview/app";(source/"app").mkdir(parents=True);app.mkdir(parents=True)
  original='[preset.0.options]\npackage/unique_name="org.local.tegramilkdrop"\nversion/code=64\nkeystore/debug="OWNER-KEY-SENTINEL"\n'
  (source/"app/export_presets.cfg").write_text(original)
  (app/"project.godot").write_text('config_version=4\n[application]\nconfig/name="Kinegra Amp"\nconfig/version="0.8.36"\n')
  version,code=preview.export_preset(app,source)
  exported=(app/"export_presets.cfg").read_text()
  self.assertEqual((version,code),("0.8.36-preview",64))
  self.assertIn('package/unique_name="org.kinegra.shieldamp.preview"',exported)
  self.assertNotIn("org.local.tegramilkdrop",exported);self.assertNotIn("OWNER-KEY",exported)
  self.assertIn("plugins/ShieldAmpTokenStore=true",exported);self.assertIn("custom_build/min_sdk=26",exported)
  self.assertEqual((source/"app/export_presets.cfg").read_text(),original)
 def test_template_excludes_cached_assets_keys_native_and_properties(self):
  template=self.root/"template";source=self.root/"source";app=self.root/"preview/app"
  template.mkdir();(source/"android_secure_storage").mkdir(parents=True);app.mkdir(parents=True)
  (source/"android_secure_storage/ShieldAmpTokenStore.gdap").write_text("generic plugin descriptor")
  for name in ["build.gradle","config.gradle","settings.gradle","AndroidManifest.xml"]:(template/name).write_text("generic template source")
  forbidden=["assets/account.json","libs/debug/owner.so",".gradle/session","build/output.apk","local.properties","gradle.properties","owner.keystore"]
  for name in forbidden:
   path=template/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text("OWNER-INPUT-SENTINEL")
  engine=self.root/"godot.aar";engine.write_bytes(b"PINNED-ENGINE-INPUT")
  target,_=preview.stage_template(source,app,{"android_template":template,"godot_debug_aar":engine,"gradle":Path("/opt/gradle/bin/gradle")})
  for file in target.rglob("*"):
   if file.is_file():self.assertNotIn(b"OWNER-INPUT-SENTINEL",file.read_bytes(),str(file))
  self.assertEqual((target/"libs/debug/godot-lib.debug.aar").read_bytes(),engine.read_bytes())
  self.assertIn("--offline --no-daemon",(target/"gradlew").read_text())
if __name__=="__main__":unittest.main()
