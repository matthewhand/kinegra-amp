#!/usr/bin/env python3
"""No first-frame import success: metadata and actual cache are both required."""
from pathlib import Path
import os,sys,tempfile,time,unittest
from build_preview import import_assets,imports_ready,fixture_assets
class ImportCompletion(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix="shieldamp-import-completion-")
  self.app=Path(self.temp.name)/"app";self.app.mkdir()
  self.asset=self.app/"tone.ogg";self.asset.write_bytes(b"OggS synthetic")
  (self.app/".import").mkdir()
 def tearDown(self):self.temp.cleanup()
 def metadata(self,remap=".import/tone.oggstr"):
  Path(str(self.asset)+".import").write_text('[remap]\npath="res://'+remap+'"\n')
 def test_metadata_without_cache_is_not_success(self):
  self.assertFalse(imports_ready(self.app,[self.asset]))
  self.metadata();self.assertFalse(imports_ready(self.app,[self.asset]))
  (self.app/".import/tone.oggstr").write_bytes(b"resource")
  self.assertTrue(imports_ready(self.app,[self.asset]))
 def test_unexpected_remap_cannot_satisfy_cache(self):
  self.metadata("../outside")
  (Path(self.temp.name)/"outside").write_bytes(b"wrong")
  self.assertFalse(imports_ready(self.app,[self.asset]))
 def test_editor_can_complete_after_first_iteration(self):
  worker=Path(self.temp.name)/"importer.py"
  worker.write_text('from pathlib import Path\nimport sys,time\np=Path(sys.argv[1])\n(p/\'tone.ogg.import\').write_text(\'[remap]\\npath="res://.import/tone.oggstr"\\n\')\ntime.sleep(.2)\n(p/\'.import/tone.oggstr\').write_bytes(b\'resource\')\ntime.sleep(10)\n')
  started=time.monotonic()
  import_assets([sys.executable,str(worker),str(self.app)],os.environ,self.app,Path(self.temp.name)/"import.log",timeout=2,assets=[self.asset])
  self.assertGreaterEqual(time.monotonic()-started,.15)
  self.assertTrue(imports_ready(self.app,[self.asset]))
 def test_zero_exit_before_cache_is_failure(self):
  with self.assertRaisesRegex(RuntimeError,"exited before"):
   import_assets([sys.executable,"-c","pass"],os.environ,self.app,Path(self.temp.name)/"early.log",timeout=1,assets=[self.asset])
 def test_missing_cache_times_out_in_bounded_time(self):
  started=time.monotonic()
  with self.assertRaisesRegex(RuntimeError,"within the bound"):
   import_assets([sys.executable,"-c","import time;time.sleep(10)"],os.environ,self.app,Path(self.temp.name)/"timeout.log",timeout=.2,assets=[self.asset])
  self.assertLess(time.monotonic()-started,2)
 def test_direct_font_data_is_not_mistaken_for_an_import(self):
  for i in range(1,5):
   for name in ["assets/music/track_%02d.ogg"%i,"assets/music/artwork/track_%02d.jpg"%i]:
    file=self.app/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(b"synthetic")
  font=self.app/"assets/fonts/font.ttf";font.parent.mkdir();font.write_bytes(b"font")
  self.assertNotIn(font,fixture_assets(self.app))
 def test_incomplete_generated_media_cannot_false_pass(self):
  with self.assertRaisesRegex(RuntimeError,"fixture media is incomplete"):fixture_assets(self.app)
if __name__=="__main__":unittest.main()
