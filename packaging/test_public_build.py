#!/usr/bin/env python3
"""Public-stage privacy boundaries; no Android inputs or device access."""
from pathlib import Path
import subprocess,tempfile,unittest
import build_public
class PublicStageTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.root=Path(self.tmp.name)/'source';self.root.mkdir()
        subprocess.run(['git','init','--quiet',str(self.root)],check=True)
        self.put('app/scripts/OfflineMusic.gd','const SOURCES = []\n')
        self.put('app/scripts/MusicFirstUI.gd','const TRACK_COVERS = []\n')
        self.put('app/Main.tscn','[gd_scene format=2]\n')
        self.put('app/project.godot','config_version=4\n')
        self.put('app/export_presets.cfg','[preset.0]\n')
        self.out=Path(self.tmp.name)/'output'
    def tearDown(self):self.tmp.cleanup()
    def put(self,name,data,tracked=True):
        p=self.root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(data)
        if tracked:subprocess.run(['git','-C',str(self.root),'add','-f','--',name],check=True)
        return p
    def test_production_preset_always_disables_development_default(self):
        self.put('app/project.godot','config/version="1.0.0"\n')
        self.put('app/export_presets.cfg','[preset.0]\ncustom_features=""\n[preset.0.options]\nversion/code=76\n')
        app=build_public.stage_app(self.root,self.out)
        version,code=build_public.preset(self.root,app)
        self.assertEqual((version,code),('1.0.0',76))
        self.assertIn('custom_features="shieldamp_production"',(app/'export_presets.cfg').read_text())
    def test_filters_tracked_media_keys_settings_and_untracked_files(self):
        names=['app/assets/music/owner.ogg','app/assets/music/artwork/cover.jpg','app/native/bin/old.so',
               'app/android/settings.cfg','app/installation.cfg','app/.import/old.stex','app/assets/private/settings.json']
        for name in names:self.put(name,'SENTINEL_NOT_RELEASE_DATA')
        self.put('app/scripts/untracked.gd','SENTINEL_UNTRACKED',tracked=False)
        self.put('app/assets/branding/icon.png','CLEARED_BRANDING')
        before={name:(self.root/name).read_bytes() for name in names}
        app=build_public.stage_app(self.root,self.out)
        payload=b''.join(p.read_bytes() for p in app.rglob('*') if p.is_file())
        self.assertNotIn(b'SENTINEL',payload)
        self.assertTrue((app/'assets/branding/icon.png').is_file())
        for name,data in before.items():self.assertEqual((self.root/name).read_bytes(),data)
    def test_refuses_bundled_runtime_paths(self):
        self.put('app/scripts/OfflineMusic.gd','const SOURCES = ["res://assets/music/old.ogg"]\n')
        with self.assertRaisesRegex(ValueError,'no bundled music sources'):build_public.stage_app(self.root,self.out)
    def test_rejects_source_symlinks(self):
        p=self.root/'app/scripts/linked.gd';p.symlink_to(self.root/'app/scripts/OfflineMusic.gd')
        subprocess.run(['git','-C',str(self.root),'add','--','app/scripts/linked.gd'],check=True)
        with self.assertRaisesRegex(ValueError,'symlinks'):build_public.stage_app(self.root,self.out)
    def test_refuses_existing_output_without_touching_it(self):
        self.out.mkdir();sentinel=self.out/'keep';sentinel.write_text('KEEP')
        with self.assertRaisesRegex(ValueError,'must be new'):build_public.stage_app(self.root,self.out)
        self.assertEqual(sentinel.read_text(),'KEEP')
if __name__=='__main__':unittest.main()
