#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sdk="${ANDROID_JAR:?Set ANDROID_JAR}"
jdk="${JAVA_HOME:?Set JAVA_HOME}/bin"
engine="${GODOT_AAR:?Set GODOT_AAR}"
out=$(mktemp -d "${TMPDIR:-/tmp}/shieldamp-capture-XXXXXXXX")
trap 'rm -rf "$out"' EXIT
printf '%s  %s\n' 8375005ada94c72d2a2608cc3c09a24a77cf640cde04126b43365faf6e4775a3 "$engine" | sha256sum -c - >/dev/null
unzip -p "$engine" classes.jar > "$out/godot.jar"
mkdir "$out/classes" "$out/tests"
"$jdk/javac" --release 8 -classpath "$sdk:$out/godot.jar" -d "$out/classes" "$root"/src/au/local/shieldamp/capture/*.java
"$jdk/javac" --release 8 -classpath "$out/classes" -d "$out/tests" "$root"/tests/CaptureEnvelopeTest.java
"$jdk/java" -classpath "$out/classes:$out/tests" au.local.shieldamp.capture.CaptureEnvelopeTest
mkdir -p "$HOME/.cache/shieldamp-playback-capture-build"
python3 - "$out/classes" "$root/AndroidManifest.xml" "$HOME/.cache/shieldamp-playback-capture-build/ShieldAmpPlaybackCapture.aar" <<'PY'
import io, pathlib, sys, zipfile
classes, manifest, target = map(pathlib.Path, sys.argv[1:])
jar = io.BytesIO()
with zipfile.ZipFile(jar, 'w', zipfile.ZIP_DEFLATED) as z:
    for f in sorted(classes.rglob('*.class')):
        z.writestr(f.relative_to(classes).as_posix(), f.read_bytes())
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('AndroidManifest.xml', manifest.read_bytes())
    z.writestr('classes.jar', jar.getvalue())
    z.writestr('R.txt', b'')
print('UNSHIPPED_PLUGIN_AAR', target)
PY
printf '%s\n' 'GODOT_PLUGIN_COMPILED_API34; SYNTHETIC_ENVELOPE_TESTS_PASSED'
