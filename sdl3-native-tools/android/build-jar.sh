#!/usr/bin/env bash
# ==============================================================================
# build-jar.sh - build SDL3AndroidBridge.jar from the vendored SDL Java sources
# ==============================================================================
# The Java half of SDL on Android (org.libsdl.app.SDLActivity and friends) is
# compiled from ../SDL/android-project/app/src/main/java/org/libsdl/app/*.java
# against the Android SDK's android.jar (compile-time stubs only; nothing from it
# ends up in the jar), then packed with `jar`. No Gradle, no network.
#
#   ./build-jar.sh [path/to/android.jar]
#
# Default android.jar: $ANDROID_HOME (or ~/Android/Sdk)/platforms/<jar.android_platform
# in pins.json>/android.jar. Output: ../output/android/SDL3AndroidBridge.jar,
# BUILD-INFO.txt and classes.txt beside it.
#
# Reproducible: classes are compiled with --release 11 (class file 55, what SDL's
# own Gradle project and the reference jar target), entries are added in sorted
# order and every timestamp is pinned with `jar --date` to the SDL commit date,
# so the same JDK and android.jar give a byte-identical jar.
# ==============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$(dirname "$HERE")"
SRC="$TOOLS/SDL/android-project/app/src/main/java"
OUT="$TOOLS/output/android"
SCRATCH="$TOOLS/output/build-scratch/android-jar"

pin() { python3 -c "import json,sys; print(json.load(open('$HERE/pins.json'))['jar'][sys.argv[1]])" "$1"; }
PLATFORM="$(pin android_platform)"
RELEASE="$(pin javac_release)"
JAR_NAME="$(pin name)"
JAR_DATE="2026-07-19T00:00:00Z"   # SDL commit a8591d9's date; pins every entry timestamp

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
ANDROID_JAR="${1:-$SDK/platforms/$PLATFORM/android.jar}"
[ -f "$ANDROID_JAR" ] || { echo "ERROR: android.jar not found: $ANDROID_JAR (see README.txt, TOOLS)" >&2; exit 1; }
for t in javac jar python3 sha256sum; do
    command -v "$t" >/dev/null || { echo "ERROR: $t is not on PATH (see README.txt, TOOLS)" >&2; exit 1; }
done

rm -rf "$SCRATCH" "$OUT"
mkdir -p "$SCRATCH/classes" "$OUT"

echo "javac   : $(javac -version 2>&1)"
JDK_PIN="$(pin jdk_major)"
JDK_MAJOR="$(javac -version 2>&1 | sed -E 's/^javac ([0-9]+).*/\1/')"
if [ "$JDK_MAJOR" != "$JDK_PIN" ]; then
    echo "NOTE: JDK $JDK_MAJOR is not the pinned JDK $JDK_PIN - the jar will be valid and carry the same"
    echo "      class set, but its bytes will not match the shipped one (see README.txt, REPRODUCIBILITY)"
fi
echo "jar     : $(jar --version 2>&1)"
echo "android : $ANDROID_JAR"

# Compile. -Xlint:-options silences only the "release 11 is old" notice; any real
# warning in the SDL sources still prints (and is recorded in BUILD-INFO.txt).
( cd "$SRC" && javac --release "$RELEASE" -encoding utf8 -nowarn -Xlint:-options \
      -classpath "$ANDROID_JAR" -d "$SCRATCH/classes" org/libsdl/app/*.java ) 2>&1 | tee "$SCRATCH/javac.log"
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "ERROR: javac failed" >&2; exit 1; }

# Pack, in sorted order, with pinned timestamps.
( cd "$SCRATCH/classes" && find org -name '*.class' | LC_ALL=C sort > "$SCRATCH/entries.txt" \
  && jar --create --file "$OUT/$JAR_NAME" --date="$JAR_DATE" @"$SCRATCH/entries.txt" )

# Record what was built.
( cd "$SCRATCH/classes" && LC_ALL=C sort "$SCRATCH/entries.txt" ) > "$OUT/classes.txt"
CLASS_COUNT="$(wc -l < "$OUT/classes.txt")"
ENTRY_COUNT="$(python3 -c "import zipfile,sys; print(len(zipfile.ZipFile(sys.argv[1]).namelist()))" "$OUT/$JAR_NAME")"
MAJOR="$(python3 -c "
import zipfile,sys,struct
z=zipfile.ZipFile(sys.argv[1]); majors={struct.unpack('>H', z.read(n)[6:8])[0] for n in z.namelist() if n.endswith('.class')}
print(' '.join(map(str,sorted(majors))))" "$OUT/$JAR_NAME")"
cp "$TOOLS/SDL/LICENSE.txt" "$OUT/LICENSE-SDL3.txt"

cat > "$OUT/BUILD-INFO.txt" <<INFO
$JAR_NAME - built by sdl3-native-tools/android/build-jar.sh
Built (UTC)       : $(date -u '+%Y-%m-%d %H:%M:%S')
Sources           : SDL/android-project/app/src/main/java/org/libsdl/app/*.java ($(ls "$SRC"/org/libsdl/app/*.java | wc -l) files)
SDL commit        : $(python3 -c "import json; print(json.load(open('$HERE/pins.json'))['source_commit'])")
javac             : $(javac -version 2>&1)  --release $RELEASE -encoding utf8
jar               : $(jar --version 2>&1)  --date=$JAR_DATE, entries sorted
android.jar       : $ANDROID_JAR
android.jar sha256: $(sha256sum "$ANDROID_JAR" | cut -d' ' -f1)
Class files       : $CLASS_COUNT (class file major version(s): $MAJOR)
Jar entries       : $ENTRY_COUNT (classes + META-INF/ + META-INF/MANIFEST.MF)
javac output      : $( [ -s "$SCRATCH/javac.log" ] && echo "see below" || echo "none (no warnings, no notes)")
$(sed 's/^/                    /' "$SCRATCH/javac.log")
Size              : $(stat -c %s "$OUT/$JAR_NAME") bytes
SHA-256           : $(sha256sum "$OUT/$JAR_NAME" | cut -d' ' -f1)
INFO
rm -rf "$SCRATCH"
rmdir "$TOOLS/output/build-scratch" 2>/dev/null || true
cat "$OUT/BUILD-INFO.txt"
