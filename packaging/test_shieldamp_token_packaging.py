import importlib.util
from pathlib import Path
import unittest

path=Path(__file__).with_name('android_checks.py')
spec=importlib.util.spec_from_file_location('build_candidate_guard',path)
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)

class TokenPluginGuardTest(unittest.TestCase):
    manifest='''  E: meta-data (line=1)
    A: android:name="org.godotengine.plugin.v1.ShieldAmpTokenStore"
    A: android:value="au.local.shieldamp.ShieldAmpTokenStore"
  E: activity (line=2)
'''
    dex='''Class #0            -
  Class descriptor  : 'Lau/local/shieldamp/ShieldAmpTokenStore;'
  Superclass        : 'Lorg/godotengine/godot/plugin/GodotPlugin;'
  Virtual methods -
      name          : 'loadTokenStaged'
      name          : 'storageStatus'
      name          : 'loadSendspinSnapshotBase64'
      name          : 'replaceSendspinSnapshotBase64'
      name          : 'sendspinSnapshotStatus'
      name          : 'hasUsbWebcam'
      name          : 'processCpuTimeMs'
      type          : '()Ljava/lang/String;'
      name          : 'thermalStatus'
      type          : '()I'
      name          : 'loadTokenForEndpoint'
      type          : '(Ljava/lang/String;)Ljava/lang/String;'
      name          : 'storeTokenForEndpoint'
      type          : '(Ljava/lang/String;Ljava/lang/String;)Z'
      name          : 'tokenEndpoint'
      type          : '()Ljava/lang/String;'
      name          : 'forgetToken'
      type          : '()Z'
      name          : 'staleTaskPrunedCount'
      type          : '()I'
      name          : 'beginOfflineImport'
      type          : '(Ljava/lang/String;)Z'
      name          : 'offlineImportStatus'
      type          : '()Ljava/lang/String;'
      name          : 'cancelOfflineImport'
      type          : '()Z'
Class #1            -
  Class descriptor  : 'Lunrelated/Example;'
'''
    def test_credential_lifecycle_api_is_packaged(self):
        for name in ['loadTokenForEndpoint','storeTokenForEndpoint','tokenEndpoint','forgetToken','staleTaskPrunedCount']:
            with self.subTest(name=name), self.assertRaises(RuntimeError):build.validate_token_dex([self.dex.replace("'"+name+"'","'missing'")])
    def test_offline_import_jni_apis_are_exact_unique_and_local(self):
        for method,signature in (("beginOfflineImport","(Ljava/lang/String;)Z"),("offlineImportStatus","()Ljava/lang/String;"),("cancelOfflineImport","()Z")):
            declaration="      name          : '"+method+"'\n      type          : '"+signature+"'\n"
            with self.subTest(method=method):
                for text in (self.dex.replace(declaration,""),self.dex.replace(declaration,"")+declaration,self.dex.replace(declaration,declaration+declaration),self.dex.replace(declaration,declaration.replace(signature,"()J")),self.dex.replace(declaration,declaration.replace(signature,"()Ljava/lang/Object;"))):
                    with self.assertRaises(RuntimeError):build.validate_token_dex([text])
    def test_valid_config(self):
        build.validate_token_export_config('custom_build/use_custom_build=true\nplugins/ShieldAmpTokenStore=true\n')
    def test_prebuilt_or_disabled_config_rejected(self):
        for text in ('', 'custom_build/use_custom_build=false\nplugins/ShieldAmpTokenStore=true', 'custom_build/use_custom_build=true\nplugins/ShieldAmpTokenStore=false', 'custom_build/use_custom_build=true\ncustom_build/use_custom_build=false\nplugins/ShieldAmpTokenStore=true'):
            with self.subTest(text=text), self.assertRaises(RuntimeError):build.validate_token_export_config(text)
    def test_manifest_requires_unique_correct_registration(self):
        build.validate_token_manifest(self.manifest)
        for text in ('', self.manifest.replace('au.local.shieldamp.ShieldAmpTokenStore','wrong.Plugin'), self.manifest+self.manifest):
            with self.subTest(text=text), self.assertRaises(RuntimeError):build.validate_token_manifest(text)
    def test_dex_requires_plugin_and_both_methods_in_same_class(self):
        build.validate_token_dex([self.dex])
        for text in ('', self.dex.replace('loadTokenStaged','oldMethod'), self.dex.replace("'storageStatus'","'missing'"), self.dex+self.dex, self.dex.replace("'Lorg/godotengine/godot/plugin/GodotPlugin;'","'Ljava/lang/Object;'")):
            with self.subTest(text=text[:30]), self.assertRaises(RuntimeError):build.validate_token_dex([text])
    def test_legacy_byte_array_only_plugin_is_rejected(self):
        for name in ('loadSendspinSnapshotBase64','replaceSendspinSnapshotBase64','sendspinSnapshotStatus'):
            with self.subTest(method=name), self.assertRaises(RuntimeError):
                build.validate_token_dex([self.dex.replace(name,'missing')])
    def test_webcam_api_missing_or_in_other_class_is_rejected(self):
        method_line="      name          : 'hasUsbWebcam'\n"
        missing=self.dex.replace(method_line,'')
        for text in (missing,missing+method_line):
            with self.subTest(text=text[-80:]), self.assertRaisesRegex(RuntimeError,'hasUsbWebcam'):
                build.validate_token_dex([text])
    def test_adaptive_metrics_required_on_same_plugin_class(self):
        for method in ('processCpuTimeMs','thermalStatus'):
            with self.subTest(method=method):
                absent=self.dex.replace("      name          : '"+method+"'\n",'')
                with self.assertRaises(RuntimeError):build.validate_token_dex([absent])
                other_class=absent+"      name          : '"+method+"'\n"
                with self.assertRaises(RuntimeError):build.validate_token_dex([other_class])
    def test_metrics_reject_unsupported_godot3_jni_return_types(self):
        for method,expected in (("processCpuTimeMs","()Ljava/lang/String;"),("thermalStatus","()I")):
            for wrong in ("()J","()Ljava/lang/Object;","()Z", "()I" if expected!="()I" else "()Ljava/lang/String;"):
                with self.subTest(method=method,descriptor=wrong):
                    original="name          : '"+method+"'\n      type          : '"+expected+"'"
                    replaced="name          : '"+method+"'\n      type          : '"+wrong+"'"
                    self.assertIn(original,self.dex)
                    with self.assertRaises(RuntimeError):build.validate_token_dex([self.dex.replace(original,replaced)])
    def test_metrics_reject_duplicate_overloads_and_missing_descriptor(self):
        for method,expected in (("processCpuTimeMs","()Ljava/lang/String;"),("thermalStatus","()I")):
            declaration="      name          : '"+method+"'\n      type          : '"+expected+"'\n"
            with self.subTest(method=method):
                with self.assertRaises(RuntimeError):build.validate_token_dex([self.dex.replace(declaration,declaration+declaration)])
                with self.assertRaises(RuntimeError):build.validate_token_dex([self.dex.replace(declaration,"      name          : '"+method+"'\n")])
    def test_methods_in_other_class_do_not_satisfy_guard(self):
        text=self.dex.replace("      name          : 'loadTokenStaged'\n",'')+"      name          : 'loadTokenStaged'\n"
        with self.assertRaises(RuntimeError):build.validate_token_dex([text])

if __name__=='__main__':unittest.main()
