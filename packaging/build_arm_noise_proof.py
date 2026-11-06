#!/usr/bin/env python3
"""Compile an isolated optimized Android Noise proof. Never runs adb or a device."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,sys

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source",type=Path,required=True)
    p.add_argument("--sdk-build",type=Path,required=True)
    p.add_argument("--native",type=Path,required=True)
    p.add_argument("--ndk",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args();source=a.source.resolve();sdk=a.sdk_build.resolve();out=a.output.resolve()
    if out.exists() or a.output.is_symlink():p.error("Use a new proof output directory")
    cache=(sdk/"CMakeCache.txt").read_text()
    def setting(key):
        m=re.search(r"(?m)^"+re.escape(key)+r":[^=]+=(.+)$",cache)
        if not m:raise ValueError("Required Noise build provenance is missing")
        return Path(m[1])
    clean=setting("KINEGRA_NOISE_PINNED_CHECKOUT");patched=setting("FETCHCONTENT_SOURCE_DIR_NOISE_C")
    subprocess.run([sys.executable,str(source/"native/prepare_noise_source.py"),"--verify",str(clean),str(patched)],check=True,capture_output=True,text=True)
    flags=(sdk/"CMakeFiles/noise_c.dir/flags.make").read_text()
    if not re.search(r"(?m)^C_FLAGS = .* -O3(?: |$)",flags) or "-D_FORTIFY_SOURCE=2" not in flags:raise ValueError("Proof requires the actual optimized Fortify-enabled Android Noise archive")
    compiler=a.ndk.resolve()/"toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"
    fixture=source/"native/tests/test_noise_pattern_bounds.c";archive=sdk/"libnoise_c.a"
    if not compiler.is_file() or not a.native.is_file():raise ValueError("Explicit Android compiler/native artifact is missing")
    out.mkdir(mode=0o700);header=out/"android-proof-build-checks.h"
    header.write_text('#include <sys/cdefs.h>\n#if !defined(__ANDROID__) || !defined(__aarch64__) || !defined(__BIONIC__) || __ANDROID_API__ != 26 || !defined(__OPTIMIZE__) || _FORTIFY_SOURCE != 2\n#error Expected optimized Android ARM64 API26 Fortify2 proof\n#endif\n')
    binary=out/"noise-pattern-proof-arm64.elf"
    command=[str(compiler),"-std=c99","-O3","-D_FORTIFY_SOURCE=2","-fstack-protector-strong","-fPIE","-pie","-Wall","-Wextra","-Werror","-include",str(header),"-I"+str(patched/"include"),"-I"+str(patched/"src"),str(fixture),str(archive),"-Wl,-z,max-page-size=16384","-o",str(binary),"-lm"]
    result=subprocess.run(command,capture_output=True,text=True);(out/"proof-build.log").write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError("Android Noise proof compilation failed; inspect proof-build.log")
    binary.chmod(0o700)
    record={"schema":1,"native_arm64_sha256":sha(a.native),"proof_source_sha256":sha(fixture),"noise_patch_sha256":sha(source/"native/noise-pattern-bounds.patch"),"noise_revision":"a1e08809a1b8f65cd91765ba7d68a6d00648ad61","noise_archive_sha256":sha(archive),"proof_binary_sha256":sha(binary),"proof_binary_filename":binary.name,"android_api":26,"abi":"arm64-v8a","optimization":"-O3","fortify_source":2,"device_execution_performed":False,"compiler_version":subprocess.check_output([str(compiler),"--version"],text=True).splitlines()[0]}
    (out/"proof-build.json").write_text(json.dumps(record,indent=2)+"\n")
    print(json.dumps(record,indent=2))
if __name__=="__main__":main()
