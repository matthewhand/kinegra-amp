"""Receipt policy regressions; synthetic ELF bytes are not runtime proof."""
from pathlib import Path
import copy,hashlib,json,struct,tempfile,unittest,subprocess,sys
from arm_noise_gate import validate_arm_noise_proof,NOISE_REVISION

def sha(data):return hashlib.sha256(data).hexdigest()
class AndroidNoiseProofGate(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.receipt=self.root/"proof.json"
        fixture=self.root/"native/tests/test_noise_pattern_bounds.c";fixture.parent.mkdir(parents=True);fixture.write_bytes(b"synthetic regression source")
        patch=self.root/"native/noise-pattern-bounds.patch";patch.write_bytes(b"synthetic reviewed patch")
        elf=bytearray(64);elf[:6]=b"\x7fELF\x02\x01";struct.pack_into("<H",elf,18,183);elf+=b"/system/bin/linker64\x00";self.binary=self.root/"noise-proof.elf";self.binary.write_bytes(elf)
        self.native="a"*64
        self.valid={"schema":1,"native_arm64_sha256":self.native,"proof_source_sha256":sha(fixture.read_bytes()),"noise_patch_sha256":sha(patch.read_bytes()),"noise_revision":NOISE_REVISION,"noise_archive_sha256":"b"*64,"proof_binary_sha256":sha(elf),"proof_binary_filename":self.binary.name,"device_codename":"darcy","android_api":26,"abi":"arm64-v8a","optimization":"-O3","fortify_source":2,"executed_on_android":True,"device_identity_verified":True,"media_muted_verified":True,"exit_code":0,"stdout":"NOISE_BOUNDS_PASS checks=96257 patterns=15 constructors=30 modifier_sequences=5985 paired_suite_constructors=2\n"}
    def tearDown(self):self.temp.cleanup()
    def validate(self,proof=None):
        self.receipt.write_text(json.dumps(self.valid if proof is None else proof))
        return validate_arm_noise_proof(self.root,self.native,self.receipt)
    def test_valid_policy_fixture(self):
        result=self.validate();self.assertTrue(result["android_fortify_runtime_proof"]);self.assertEqual(result["checks"],96257)
    def test_optimized_python_still_rejects_stale_native(self):
        self.validate()
        code="from arm_noise_gate import validate_arm_noise_proof\nimport sys\ntry: validate_arm_noise_proof(sys.argv[1],sys.argv[2],sys.argv[3])\nexcept RuntimeError: sys.exit(0)\nelse: sys.exit(1)"
        result=subprocess.run([sys.executable,"-O","-c",code,str(self.root),"c"*64,str(self.receipt)],cwd=Path(__file__).resolve().parent,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
    def test_missing_receipt_blocks(self):
        for path in [None,self.receipt]:
            with self.subTest(path=bool(path)),self.assertRaises(RuntimeError):validate_arm_noise_proof(self.root,self.native,path)
    def test_required_fields_and_no_unreviewed_extras(self):
        for key in self.valid:
            proof=copy.deepcopy(self.valid);del proof[key]
            with self.subTest(key=key),self.assertRaises(RuntimeError):self.validate(proof)
        proof=copy.deepcopy(self.valid);proof["ignored"]=True
        with self.assertRaises(RuntimeError):self.validate(proof)
    def test_stale_or_weak_runtime_receipts_block(self):
        bad={"schema":[2,True],"native_arm64_sha256":["c"*64],"proof_source_sha256":["c"*64],"noise_patch_sha256":["c"*64],"noise_revision":["c"*40],"noise_archive_sha256":["invalid"],"proof_binary_sha256":["c"*64],"proof_binary_filename":["../noise-proof.elf","/tmp/noise-proof.elf"],"device_codename":["other"],"android_api":[0,True],"abi":["x86_64"],"optimization":["-O0",""],"fortify_source":[0,True],"executed_on_android":[False,"true"],"device_identity_verified":[False],"media_muted_verified":[False],"exit_code":[1,False],"stdout":["NOISE_BOUNDS_FAIL\n","NOISE_BOUNDS_PASS checks=1 patterns=15 constructors=30 modifier_sequences=5985 paired_suite_constructors=2\n",self.valid["stdout"]+"unexpected output\n"]}
        for key,values in bad.items():
            for value in values:
                proof=copy.deepcopy(self.valid);proof[key]=value
                with self.subTest(key=key,value=value),self.assertRaises(RuntimeError):self.validate(proof)
    def test_modified_fixture_or_patch_blocks(self):
        for name in ["native/tests/test_noise_pattern_bounds.c","native/noise-pattern-bounds.patch"]:
            p=self.root/name;old=p.read_bytes();p.write_bytes(old+b" changed")
            with self.subTest(path=name),self.assertRaises(RuntimeError):self.validate()
            p.write_bytes(old)
    def test_missing_or_modified_binary_blocks(self):
        self.binary.unlink()
        with self.assertRaises(RuntimeError):self.validate()
        self.binary.write_bytes(b"not ELF")
        with self.assertRaises(RuntimeError):self.validate()
    def test_non_android_non_arm_binary_blocks_even_rehashed(self):
        for offset,value in [(18,62),(0,0)]:
            data=bytearray(self.binary.read_bytes());data[offset]=value;self.binary.write_bytes(data);proof=copy.deepcopy(self.valid);proof["proof_binary_sha256"]=sha(data)
            with self.subTest(offset=offset),self.assertRaises(RuntimeError):self.validate(proof)
    def test_symlink_or_duplicate_json_blocks(self):
        self.receipt.symlink_to(self.binary)
        with self.assertRaises(RuntimeError):validate_arm_noise_proof(self.root,self.native,self.receipt)
        self.receipt.unlink();self.receipt.write_text('{"schema":1,"schema":1}')
        with self.assertRaises(RuntimeError):validate_arm_noise_proof(self.root,self.native,self.receipt)
if __name__=="__main__":unittest.main()
