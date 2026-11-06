"""Require an exact-native Android/Fortify runtime proof before production packaging."""
from pathlib import Path
import hashlib,json,re,struct
NOISE_REVISION="a1e08809a1b8f65cd91765ba7d68a6d00648ad61"

def _digest(data):return hashlib.sha256(data).hexdigest()
def _require(condition):
    if not condition:raise ValueError("Invalid Android Noise proof")
def _unique(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise ValueError("Duplicate Android Noise proof field")
        result[key]=value
    return result

def validate_arm_noise_proof(source_root,native_sha256,receipt_path):
    if not receipt_path:raise RuntimeError("Production packaging requires --arm-noise-proof from a successful optimized Android ARM run")
    path=Path(receipt_path)
    if path.is_symlink() or not path.is_file() or path.stat().st_size>32768:
        raise RuntimeError("Android Noise proof receipt is missing or invalid")
    try:
        raw=path.read_bytes();proof=json.loads(raw,object_pairs_hook=_unique)
        required={"schema","native_arm64_sha256","proof_source_sha256","noise_patch_sha256","noise_revision","noise_archive_sha256","proof_binary_sha256","proof_binary_filename","device_codename","android_api","abi","optimization","fortify_source","executed_on_android","device_identity_verified","media_muted_verified","exit_code","stdout"}
        _require(isinstance(proof,dict) and set(proof)==required)
        _require(type(proof["schema"]) is int and proof["schema"]==1)
        _require(proof["native_arm64_sha256"]==native_sha256 and re.fullmatch("[a-f0-9]{64}",native_sha256))
        root=Path(source_root)
        _require(proof["proof_source_sha256"]==_digest((root/"native/tests/test_noise_pattern_bounds.c").read_bytes()))
        _require(proof["noise_patch_sha256"]==_digest((root/"native/noise-pattern-bounds.patch").read_bytes()))
        _require(proof["noise_revision"]==NOISE_REVISION)
        _require(re.fullmatch("[a-f0-9]{64}",proof["noise_archive_sha256"]))
        _require(re.fullmatch("[a-f0-9]{64}",proof["proof_binary_sha256"]))
        filename=proof["proof_binary_filename"]
        _require(isinstance(filename,str) and re.fullmatch(r"[A-Za-z0-9_-]{1,80}\.elf",filename))
        binary=path.parent/filename
        _require(not binary.is_symlink() and binary.is_file() and binary.stat().st_size<=16777216)
        artifact=binary.read_bytes()
        _require(_digest(artifact)==proof["proof_binary_sha256"])
        _require(len(artifact)>=20 and artifact[:6]==b"\x7fELF\x02\x01" and struct.unpack_from("<H",artifact,18)[0]==183 and b"/system/bin/linker64\x00" in artifact)
        _require(proof["device_codename"]=="darcy" and proof["abi"]=="arm64-v8a")
        _require(type(proof["android_api"]) is int and proof["android_api"]==26)
        _require(proof["optimization"]=="-O3" and type(proof["fortify_source"]) is int and proof["fortify_source"]==2)
        _require(all(proof[key] is True for key in ["executed_on_android","device_identity_verified","media_muted_verified"]))
        _require(type(proof["exit_code"]) is int and proof["exit_code"]==0)
        match=re.fullmatch(r"NOISE_BOUNDS_PASS checks=([0-9]+) patterns=15 constructors=30 modifier_sequences=5985 paired_suite_constructors=2\n?",proof["stdout"])
        _require(match and 96000<=int(match[1])<=1000000)
    except (OSError,ValueError,TypeError,KeyError,struct.error):
        raise RuntimeError("Android Noise proof does not match this optimized ARM native build, source or passing device run") from None
    return {"receipt_sha256":_digest(raw),"native_arm64_sha256":native_sha256,"proof_binary_sha256":proof["proof_binary_sha256"],"proof_source_sha256":proof["proof_source_sha256"],"noise_patch_sha256":proof["noise_patch_sha256"],"noise_archive_sha256":proof["noise_archive_sha256"],"stdout_sha256":_digest(proof["stdout"].encode()),"checks":int(match[1]),"android_fortify_runtime_proof":True}
