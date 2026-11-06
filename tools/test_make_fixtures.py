#!/usr/bin/env python3
"""Synthetic regression: source previews never inherit private media/runtime state."""
from pathlib import Path
import hashlib,json,shutil,subprocess,tempfile,unittest
from make_fixtures import make_fixtures

def hashes(root):return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob("*") if p.is_file()}

@unittest.skipUnless(shutil.which("ffmpeg"),"FFmpeg is needed for synthetic Ogg generation")
class Fixtures(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix="shieldamp-fixture-regression-")
  self.root=Path(self.temp.name)/"source";app=self.root/"app"
  for name in ["scripts","tests","assets/music/artwork","native/bin",".import",".state","android/build"]:(app/name).mkdir(parents=True,exist_ok=True)
  (app/"project.godot").write_text('config_version=4\n[application]\nconfig/name="Synthetic test"\n')
  (app/"scripts/OfflineMusic.gd").write_text('extends Node\nconst TITLES = ["Owner track A", "Owner track B", "Owner track C", "Owner track D"]\n')
  (app/"scripts/MusicFirstUI.gd").write_text('extends Node\nfunc example():\n    _set_fullscreen_track(name, "Owner credit / original", "OFFLINE")\n')
  (app/"tests/example.gd").write_text('extends Node\nvar title="Owner track A"\nvar artist="Owner credit / original"\n')
  self.sentinels=["assets/music/track_01.ogg","assets/music/artwork/track_01.jpg","assets/music/manifest.json","native/bin/libowner.so",".import/cache.stex",".state/session.json","android/build/key.jks","music_assistant.cfg","export_presets.cfg"]
  for name in self.sentinels:(app/name).write_bytes(("SENTINEL-PRIVATE-INPUT:"+name).encode())
  (self.root/"tools").mkdir()
  self.update_manifest()
 def update_manifest(self):
  files={str(p.relative_to(self.root)):{} for p in (self.root/"app").rglob("*") if p.is_file()}
  (self.root/"tools/SOURCE-MANIFEST.json").write_text(json.dumps({"files":files}))
 def tearDown(self):self.temp.cleanup()
 def test_clean_source_copy_and_generic_media(self):
  before=hashes(self.root);app=make_fixtures(self.root,Path(self.temp.name)/"preview")
  self.assertEqual(before,hashes(self.root))
  for name in ["native/bin/libowner.so",".import/cache.stex",".state/session.json","android/build/key.jks","music_assistant.cfg","export_presets.cfg"]:self.assertFalse((app/name).exists(),name)
  for file in app.rglob("*"):
   if file.is_file():
    self.assertNotIn(b"SENTINEL-PRIVATE-INPUT",file.read_bytes(),str(file))
    if file.suffix==".gd":
     self.assertNotIn("Owner track",file.read_text());self.assertNotIn("Owner credit",file.read_text())
  self.assertIn("Review sample 1",(app/"scripts/OfflineMusic.gd").read_text())
  self.assertIn("Synthetic sample artist",(app/"scripts/MusicFirstUI.gd").read_text())
  self.assertEqual(len(list((app/"assets/music").glob("*.ogg"))),4)
 def test_conditional_bundled_artist_is_generic_in_copy_only(self):
  stage=self.root/"app/scripts/MusicFirstUI.gd"
  stage.write_text('extends Node\nfunc example():\n    _set_fullscreen_track(name, "Owner credit / original" if app.offline_music.track_index < 4 else "Imported audio", "OFFLINE")\n    _set_fullscreen_track(app.offline_music.current_title(), "Owner credit / original" if app.offline_music.track_index < 4 else "Imported audio", "OFFLINE")\n')
  before=stage.read_bytes()
  app=make_fixtures(self.root,Path(self.temp.name)/"conditional-preview")
  self.assertEqual(stage.read_bytes(),before)
  copied=(app/"scripts/MusicFirstUI.gd").read_text()
  self.assertEqual(copied.count("Synthetic sample artist"),2)
  self.assertIn('else "Imported audio"',copied)
  self.assertNotIn("Owner credit",copied)
  self.assertNotIn("Owner credit",(app/"tests/example.gd").read_text())
 def test_repeatable_fixture_bytes_with_same_tools(self):
  one=make_fixtures(self.root,Path(self.temp.name)/"one")
  two=make_fixtures(self.root,Path(self.temp.name)/"two")
  self.assertEqual(hashes(one),hashes(two))
 def test_existing_output_is_not_overwritten(self):
  target=Path(self.temp.name)/"existing";target.mkdir();(target/"keep").write_text("unchanged")
  with self.assertRaises(ValueError):make_fixtures(self.root,target)
  self.assertEqual((target/"keep").read_text(),"unchanged")
 def test_source_child_is_rejected(self):
  with self.assertRaises(ValueError):make_fixtures(self.root,self.root/"app/generated-preview")
 def test_source_symlink_is_rejected(self):
  outside=Path(self.temp.name)/"outside";outside.write_text("not source")
  (self.root/"app/scripts/external.gd").symlink_to(outside)
  self.update_manifest()
  with self.assertRaises(ValueError):make_fixtures(self.root,Path(self.temp.name)/"linked-preview")
 def test_unlisted_archive_assets_and_config_are_not_copied(self):
  (self.root/"app/assets/unlisted-photo.png").write_bytes(b"private photo sentinel")
  (self.root/"app/scripts/unlisted-token.json").write_text("private token sentinel")
  app=make_fixtures(self.root,Path(self.temp.name)/"manifest-preview")
  self.assertFalse((app/"assets/unlisted-photo.png").exists())
  self.assertFalse((app/"scripts/unlisted-token.json").exists())
 def test_untracked_git_assets_and_config_are_not_copied(self):
  subprocess.run(["git","init","-q",str(self.root)],check=True)
  subprocess.run(["git","-C",str(self.root),"add","app"],check=True)
  (self.root/"app/assets/untracked-photo.png").write_bytes(b"private photo sentinel")
  (self.root/"app/scripts/untracked-token.json").write_text("private token sentinel")
  app=make_fixtures(self.root,Path(self.temp.name)/"git-preview")
  self.assertFalse((app/"assets/untracked-photo.png").exists())
  self.assertFalse((app/"scripts/untracked-token.json").exists())
 def test_unindexed_source_without_manifest_is_rejected(self):
  (self.root/"tools/SOURCE-MANIFEST.json").unlink()
  with self.assertRaises(ValueError):make_fixtures(self.root,Path(self.temp.name)/"unknown-preview")
if __name__=="__main__":unittest.main()
