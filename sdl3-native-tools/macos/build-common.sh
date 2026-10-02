#!/usr/bin/env bash
# ==============================================================================================
# build-common.sh - shared machinery for the macOS SDL3 builds (osx-arm64, osx-x64)
# ==============================================================================================
#
# Sourced by build-osx-arm64.sh and build-osx-x64.sh; not meant to be run directly.
#
#   NEVER YET RUN. Written on Linux on 2026-10-01, modelled on CodeBrix.Ollama's
#   llama-native-tools/macos/ (which ran for real on an Intel and an Apple Silicon Mac mini) and
#   CodeBrix.VideoPlayback.Dav1d's dav1d-native-tools/macos/. Their run-tested lessons are built
#   in: the `head -1` SIGPIPE trap, strip -> codesign ordering, measuring size after signing, the
#   deployment-target stamp CHECKED rather than reported, and the LC_UUID that no two builds
#   share. Expect to fix something on the first real run; fix it IN THE SCRIPT and record it in
#   ../BUILD-PROVENANCE.txt, then rewrite the status block of README.txt.
#
# Everything it needs is in this repository: ../SDL (the vendored, unmodified SDL snapshot),
# ../patches (empty), ../smoke-test.c, and ../linux/pins.env (the version pins shared by every
# platform - see README.txt for why they live in the linux folder). Nothing is downloaded.
# ==============================================================================================

set -euo pipefail

trap 'rc=$?; echo "ERROR: the macOS SDL3 build failed (exit $rc) at line $LINENO: $BASH_COMMAND" >&2' ERR

# The first line of stdin, without the `head -1` trap: `cmd | head -1` inside $(...) under
# `set -o pipefail` can report 141 because head exits first and the writer takes SIGPIPE.
# `sed -n 1p` reads its input to the end. (Learned the hard way in dav1d-native-tools.)
first_line() { sed -n '1p'; }

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # sdl3-native-tools/
PINS_FILE="$TOOLS_DIR/linux/pins.env"

[ -f "$PINS_FILE" ] || {
    echo "ERROR: $PINS_FILE is missing. It is part of the repository; if it vanished after a" >&2
    echo "       clone, check the root .gitignore's blanket '*.env' rule (see ../.gitignore)." >&2
    exit 1; }
# Only the platform-neutral keys are used: SDL_DIR, SDL_VERSION, SDL_COMMIT, SDL_COMMIT_SUBJECT,
# SDL_REVISION_STRING, SDL_VERSION_NUM, REQUIRED_SYMBOLS, LICENSE_FILE_NAME, CMAKE_VERSION,
# NINJA_VERSION.
# shellcheck source=../linux/pins.env
. "$PINS_FILE"

SRC_DIR="$TOOLS_DIR/$SDL_DIR"
PATCH_DIR="$TOOLS_DIR/patches"
SMOKE_SRC="$TOOLS_DIR/smoke-test.c"
SYM_FILE="$SRC_DIR/src/dynapi/SDL_dynapi.sym"
LIB_NAME="libSDL3.dylib"                       # the shipped, unversioned name DllImport("SDL3") probes
# SDL's CMake names the library libSDL3.0.dylib (+ a libSDL3.dylib symlink) and gives it this
# install name. It is KEPT as built - the same choice the Linux build makes for the SONAME, and
# what the adopted ppy dylibs carry. .NET loads the file by path, so the id is never consulted.
EXPECTED_INSTALL_NAME="@rpath/libSDL3.0.dylib"

# ----------------------------------------------------------------------------------------------
# The SDL CMake options for macOS. ppy/SDL3-CS 2026.722.0 (whose osx dylibs are the ones
# currently adopted) passed, for SDL:
#     -DCMAKE_OSX_ARCHITECTURES=<x86_64|arm64> -DCMAKE_OSX_DEPLOYMENT_TARGET=<10.14|11.0>
#     -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF
# These options reproduce that, plus: only the library (no test library, tests or examples),
# nothing installed, no Apple framework bundle (a plain dylib is what runtimes/<rid>/native/
# wants), no rpath, SDL_REVISION pinned (the scratch copy has no .git), and -g so dsymutil has
# DWARF to collect (the shipped file is stripped afterwards). The architecture and the
# deployment target are added per RID by build_sdl.
# ----------------------------------------------------------------------------------------------
SDL_CMAKE_OPTIONS_MACOS="-DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF -DSDL_INSTALL=OFF -DSDL_FRAMEWORK=OFF -DSDL_RPATH=OFF"

# ----------------------------------------------------------------------------------------------
# Deployment targets - the oldest macOS each slice loads on. ppy's for this SDL commit, kept so a
# rebuild is a drop-in replacement for the adopted dylibs with no change of floor:
#   osx-arm64 11.0   the first macOS that exists on Apple Silicon
#   osx-x64   10.14  ppy's choice; SDL's own docs build with 10.13
# Why two floors and not llama's single 13.3: README.txt, THE MINIMUM macOS VERSION. The gate
# checks both the stamp and that the stamp is real (no unguarded newer-API use).
# ----------------------------------------------------------------------------------------------
MACOS_MIN_ARM64="11.0"
MACOS_MIN_X64="10.14"

GATE_FAILED=0
UNRUN_ONLY=1        # stays 1 while every failure so far is an "unrun" one (see gate_unrun)
gate_pass()  { echo "  [ok] $1"; }
gate_fail()  { echo "  [FAIL] $1"; GATE_FAILED=1; UNRUN_ONLY=0; }
gate_unrun() { echo "  [FAIL] $1"; GATE_FAILED=1; }

# ----------------------------------------------------------------------------------------------
require_tool() {
    local tool="$1" hint="$2"
    command -v "$tool" > /dev/null 2>&1 || {
        echo "ERROR: $tool is not on PATH." >&2
        echo >&2
        echo "$hint" >&2
        echo >&2
        echo "This script installs nothing. See README.txt, PREREQUISITES." >&2
        exit 1; }
}

check_common_prerequisites() {
    require_tool cc      'Install the Xcode Command Line Tools:   xcode-select --install'
    require_tool cmake   "Install it with Homebrew:   brew install cmake   (the Linux build pins $CMAKE_VERSION; SDL needs >= 3.16)"
    require_tool ninja   "Install it with Homebrew:   brew install ninja   (the Linux build pins $NINJA_VERSION)"
    for t in otool nm lipo file dsymutil dwarfdump strip codesign shasum xcrun; do
        require_tool "$t" 'Part of the Xcode Command Line Tools:   xcode-select --install'
    done
    for f in "$SRC_DIR/CMakeLists.txt" "$SRC_DIR/LICENSE.txt" "$SYM_FILE" "$SMOKE_SRC"; do
        [ -f "$f" ] || {
            echo "ERROR: $f is missing. It is part of the repository and is not downloaded -" >&2
            echo "       restore it from git." >&2
            exit 1; }
    done
}

# ----------------------------------------------------------------------------------------------
# The vendored tree is copied to scratch and built there, so ../SDL is never written to and stays
# a verifiable, unmodified upstream snapshot. Patches (none today) apply to the copy, in order.
# ----------------------------------------------------------------------------------------------
copy_source_to_scratch() {
    local scratch="$1"
    rm -rf "$scratch"
    cp -a "$SRC_DIR" "$scratch"
    echo "  copied $SRC_DIR -> $scratch"

    PATCHES_APPLIED="none"
    if [ -d "$PATCH_DIR" ] && ls "$PATCH_DIR"/*.patch > /dev/null 2>&1; then
        PATCHES_APPLIED=""
        for p in "$PATCH_DIR"/*.patch; do
            echo "  applying $(basename "$p")"
            ( cd "$scratch" && patch -p1 --forward --batch < "$p" ) \
                || { echo "ERROR: patch $(basename "$p") did not apply. Fix it; patches are never applied best-effort." >&2; exit 1; }
            PATCHES_APPLIED="$PATCHES_APPLIED $(basename "$p")"
        done
        PATCHES_APPLIED="${PATCHES_APPLIED# }"
    fi
    echo "  patches applied: $PATCHES_APPLIED"
}

# ----------------------------------------------------------------------------------------------
# Configure + build SDL.
#   $1 scratch source   $2 build dir   $3 arch (arm64 | x86_64)   $4 deployment target
# Writes configure.log, build.log and cmake-summary.txt (SDL's own end-of-configure summary - the
# authoritative list of what was compiled in) into the build dir, and sets
# UNGUARDED_AVAILABILITY_WARNINGS (see THE MINIMUM macOS VERSION in README.txt).
# ----------------------------------------------------------------------------------------------
build_sdl() {
    local scratch="$1" build="$2" arch="$3" minos="$4"
    rm -rf "$build"
    mkdir -p "$build"
    export MACOSX_DEPLOYMENT_TARGET="$minos"

    CMAKE_COMMAND_LINE="cmake -S <scratch> -B <build> -G Ninja $SDL_CMAKE_OPTIONS_MACOS -DSDL_REVISION=$SDL_REVISION_STRING -DCMAKE_OSX_ARCHITECTURES=$arch -DCMAKE_OSX_DEPLOYMENT_TARGET=$minos -DCMAKE_C_FLAGS=-g -DCMAKE_CXX_FLAGS=-g"
    echo "  $CMAKE_COMMAND_LINE"
    # shellcheck disable=SC2086
    cmake -S "$scratch" -B "$build" -G Ninja $SDL_CMAKE_OPTIONS_MACOS \
        -DSDL_REVISION="$SDL_REVISION_STRING" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$minos" \
        -DCMAKE_C_FLAGS="-g" -DCMAKE_CXX_FLAGS="-g" \
        > "$build/configure.log" 2>&1 \
        || { echo "ERROR: cmake configure failed - see $build/configure.log" >&2; tail -30 "$build/configure.log" >&2; exit 1; }

    sed -n '/SDL3 was configured with the following options:/,$p' "$build/configure.log" | sed 's/^-- //' > "$build/cmake-summary.txt"
    if [ -s "$build/cmake-summary.txt" ]; then
        grep -E '^ *(Platform|Revision|Video drivers|Render drivers|GPU drivers|Audio drivers|Joystick drivers|Camera drivers):' \
            "$build/cmake-summary.txt" | sed 's/^/    /' || true
    else
        echo "  [warn] SDL's configure summary was not found in configure.log; cmake-summary.txt is empty."
    fi
    grep -E 'CMake Warning|CMake Error' "$build/configure.log" | sed 's/^/  /' || true

    echo "  building (log: $build/build.log) ..."
    cmake --build "$build" -j "$(sysctl -n hw.ncpu)" > "$build/build.log" 2>&1 \
        || { echo "ERROR: build failed - see $build/build.log" >&2; grep -E -B2 -A8 'error:|FAILED:' "$build/build.log" | sed -n '1,60p' >&2; exit 1; }
    echo "  built: $(tail -1 "$build/build.log")"

    UNGUARDED_AVAILABILITY_WARNINGS="$(grep -c -E 'Wunguarded-availability' "$build/build.log" || true)"
    echo "  -Wunguarded-availability warnings in the build log: $UNGUARDED_AVAILABILITY_WARNINGS"
}

# ----------------------------------------------------------------------------------------------
# Collect: unstripped copy, dSYM, strip, sign, licence, cmake summary.
#   $1 build dir   $2 output dir
# Order matters: strip, THEN codesign. Stripping invalidates a signature, so signing has to be
# last (the linker ad-hoc signs arm64 output but NOT x86_64; either way it is replaced here). The
# install name is NOT rewritten (EXPECTED_INSTALL_NAME, above).
# ----------------------------------------------------------------------------------------------
collect_dylib() {
    local build="$1" out="$2"
    # libSDL3.dylib in the build tree is a symlink to libSDL3.0.dylib; cp -L takes the real file.
    [ -e "$build/$LIB_NAME" ] || { echo "ERROR: $build/$LIB_NAME was not produced." >&2; ls -l "$build"/*.dylib >&2 || true; exit 1; }

    rm -rf "$out"
    mkdir -p "$out/unstripped"
    cp -L "$build/$LIB_NAME" "$out/unstripped/$LIB_NAME"
    cp -L "$build/$LIB_NAME" "$out/$LIB_NAME"
    chmod 0755 "$out/$LIB_NAME" "$out/unstripped/$LIB_NAME"
    SIZE_UNSTRIPPED="$(stat -f %z "$out/unstripped/$LIB_NAME")"

    dsymutil "$out/unstripped/$LIB_NAME" -o "$out/$LIB_NAME.dSYM" || \
        echo "  [warn] dsymutil failed; crash reports from this build will be harder to read."

    strip -x "$out/$LIB_NAME"
    codesign --force --sign - "$out/$LIB_NAME"
    # Measure AFTER signing: the ad-hoc signature is part of the shipped file. (llama's first
    # osx-x64 record was taken before signing and understated the shipped size by ~50 KB.)
    SIZE_STRIPPED="$(stat -f %z "$out/$LIB_NAME")"

    cp "$SRC_DIR/LICENSE.txt" "$out/$LICENSE_FILE_NAME"
    cp "$build/cmake-summary.txt" "$out/cmake-summary.txt" 2>/dev/null || true
    echo "  unstripped: $SIZE_UNSTRIPPED bytes -> stripped + signed: $SIZE_STRIPPED bytes"
    echo "  $LICENSE_FILE_NAME : SDL's LICENSE.txt (zlib), verbatim"
}

# ----------------------------------------------------------------------------------------------
# The smoke test, compiled for the TARGET architecture at the same deployment target.
#   $1 gate dir   $2 arch   $3 deployment target
# ----------------------------------------------------------------------------------------------
build_smoke_test() {
    local gate="$1" arch="$2" minos="$3"
    mkdir -p "$gate"
    cc -std=c11 -O1 -arch "$arch" -mmacosx-version-min="$minos" -o "$gate/smoke-test" "$SMOKE_SRC" \
        > "$gate/smoke-test-build.log" 2>&1 \
        || { echo "ERROR: the smoke test did not compile - see $gate/smoke-test-build.log" >&2; cat "$gate/smoke-test-build.log" >&2; exit 1; }
    echo "  $gate/smoke-test ($(lipo -archs "$gate/smoke-test" 2>/dev/null || echo "arch unknown"))"
}

# ----------------------------------------------------------------------------------------------
# THE GATE.
#   $1 the staged dylib (stripped + signed - the file that ships)
#   $2 expected arch (arm64 | x86_64)   $3 expected minimum macOS   $4 gate dir (smoke-test)
#   $5 can this machine run $2 code (yes | no)
# Sets SMOKE_OUTPUT for BUILD-INFO.txt.
# ----------------------------------------------------------------------------------------------
verify_dylib() {
    local dylib="$1" want_arch="$2" want_minos="$3" gate="$4" can_run="$5"
    SMOKE_OUTPUT="  not run"

    # 1. Architecture, two ways: `file`, and lipo must call it a THIN file (one slice - the
    #    package wants one file per RID, never a universal binary) of the right architecture.
    local file_out lipo_out
    file_out="$(file -b "$dylib")"
    case "$file_out" in
        *"Mach-O 64-bit"*"$want_arch"*) gate_pass "file: $file_out" ;;
        *)                              gate_fail "architecture mismatch: expected a $want_arch Mach-O, file says: $file_out" ;;
    esac
    lipo_out="$(lipo -info "$dylib" 2>&1)"
    case "$lipo_out" in
        *"Non-fat file"*"is architecture: $want_arch"*) gate_pass "lipo: thin, $want_arch" ;;
        *)                                              gate_fail "lipo -info: '$lipo_out' (expected a non-fat $want_arch file)" ;;
    esac

    # 2. Exports: EXACTLY SDL's export list (src/dynapi/SDL_dynapi.sym, read at gate time so it
    #    cannot drift). nm -gU prints "<addr> T _SDL_Init"; the leading underscore is dropped.
    local expected actual missing extra
    # LC_ALL=C: a byte-wise, case-sensitive sort for sort -u and comm alike - SDL exports both
    # SDL_Log and SDL_log, which no locale-aware comparison may fold together.
    expected="$(grep -E '^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*;[[:space:]]*$' "$SYM_FILE" | tr -d ' \t;' | LC_ALL=C sort -u)"
    actual="$(nm -gU "$dylib" | awk '{print $NF}' | sed 's/^_//' | LC_ALL=C sort -u)"
    missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | tr '\n' ' ')"
    extra="$(LC_ALL=C comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | tr '\n' ' ')"
    [ -z "${missing// /}" ] || gate_fail "missing exports: $(printf '%s' "$missing" | cut -c1-300)"
    [ -z "${extra// /}" ]   || gate_fail "unexpected exports: $(printf '%s' "$extra" | cut -c1-300)"
    if [ -z "${missing// /}" ] && [ -z "${extra// /}" ]; then
        gate_pass "exports are exactly the $(printf '%s\n' "$expected" | grep -c .) names in SDL_dynapi.sym"
    fi
    local sample_missing=""
    for sym in $REQUIRED_SYMBOLS; do
        printf '%s\n' "$actual" | grep -qx "$sym" || sample_missing="$sample_missing $sym"
    done
    if [ -n "$sample_missing" ]; then gate_fail "pins.env REQUIRED_SYMBOLS not exported:$sample_missing"
    else gate_pass "pins.env REQUIRED_SYMBOLS (SDL_Init, SDL_GetVersion, ...) all exported"; fi

    # 3. Install name - kept as SDL builds it.
    local install_name
    install_name="$(otool -D "$dylib" | sed -n '2p')"
    if [ "$install_name" = "$EXPECTED_INSTALL_NAME" ]; then gate_pass "install name: $install_name"
    else gate_fail "install name is '$install_name', expected $EXPECTED_INSTALL_NAME"; fi

    # 4. Dependencies: system libraries and frameworks only. Anything under /usr/local, /opt
    #    (Homebrew) or @rpath/@loader_path would make the package demand something be installed.
    local deps bad=""
    deps="$(otool -L "$dylib" | tail -n +2 | awk '{print $1}' | grep -v -x "$EXPECTED_INSTALL_NAME" || true)"
    for d in $deps; do
        case "$d" in
            /usr/lib/*|/System/Library/Frameworks/*) ;;
            *) bad="$bad $d" ;;
        esac
    done
    if [ -n "$bad" ]; then gate_fail "non-system dynamic dependencies:$bad"
    else gate_pass "dependencies are system-only ($(printf '%s\n' "$deps" | grep -c .) - /usr/lib and /System/Library/Frameworks)"; fi

    # 5. No LC_RPATH in a library that lands in somebody else's app.
    if otool -l "$dylib" | grep -q 'cmd LC_RPATH'; then gate_fail "the dylib carries an LC_RPATH"
    else gate_pass "no LC_RPATH"; fi

    # 6. Deployment target - CHECKED, not merely reported. Without it clang stamps the build
    #    machine's macOS version in and dyld refuses the file on every older Mac.
    local minos
    minos="$(otool -l "$dylib" | awk '/LC_BUILD_VERSION/{f=1} f && /minos/{print $2; exit}')"
    if [ -z "$minos" ]; then
        minos="$(otool -l "$dylib" | awk '/LC_VERSION_MIN_MACOSX/{f=1} f && /version/{print $2; exit}')"
    fi
    if [ "$minos" = "$want_minos" ]; then gate_pass "minimum macOS: $minos"
    else gate_fail "minimum macOS is '$minos', expected $want_minos - a build on a newer Mac must not silently raise the floor"; fi
    MINOS_FOUND="$minos"

    # 7. ...and the stamp is a real floor: no unguarded use of an API newer than it. clang warns
    #    (-Wunguarded-availability[-new], on by default) and the linker turns such a symbol into a
    #    WEAK import that is NULL on the older macOS - the trap llama's 11.0 floor fell into. SDL
    #    guards its newer calls with @available, so the count must be zero.
    if [ "${UNGUARDED_AVAILABILITY_WARNINGS:-0}" -eq 0 ]; then gate_pass "no -Wunguarded-availability warnings in the build log"
    else gate_fail "$UNGUARDED_AVAILABILITY_WARNINGS -Wunguarded-availability warning lines in build.log - the $want_minos floor is not real; see README.txt, THE MINIMUM macOS VERSION"; fi
    WEAK_IMPORTS="$(nm -m "$dylib" | grep -c 'weak external' || true)"
    echo "  [info] weak imports (guarded newer APIs and weak frameworks): $WEAK_IMPORTS"

    # 8. Code signature, valid after strip.
    if codesign -v "$dylib" > /dev/null 2>&1; then gate_pass "code signature valid (ad-hoc)"
    else gate_fail "codesign -v fails - Apple Silicon refuses to load an unsigned or broken-signature arm64 dylib"; fi

    if [ "$can_run" != "yes" ]; then
        gate_unrun "smoke test NOT RUN - this machine cannot execute $want_arch code. Reported as a failure on purpose: an unrun check is not a passed check."
        return
    fi

    # 9. dlopen smoke test against the STAGED file (copied beside the program and passed by full
    #    path, so the shipped bytes are what loads - never a libSDL3 from Homebrew or elsewhere).
    echo "  --- dlopen smoke test (dummy video driver) ---"
    cp "$dylib" "$gate/$LIB_NAME"
    local rc=0
    SMOKE_OUTPUT="$("$gate/smoke-test" "$gate/$LIB_NAME" "$SDL_VERSION_NUM" 2>&1)" || rc=$?
    printf '%s\n' "$SMOKE_OUTPUT" | sed 's/^/    /'
    if [ "$rc" -eq 0 ]; then gate_pass "smoke test (SDL_GetVersion == $SDL_VERSION_NUM, init, window, renderer, draw + read-back, quit)"
    else gate_fail "smoke test exited $rc"; fi

    # 10. The revision string.
    if printf '%s\n' "$SMOKE_OUTPUT" | grep -q "^SDL_GetRevision *: $SDL_REVISION_STRING\$"; then
        gate_pass "SDL_GetRevision() = $SDL_REVISION_STRING"
    else
        gate_fail "SDL_GetRevision() is not $SDL_REVISION_STRING"
    fi
}

# ----------------------------------------------------------------------------------------------
# THE WHOLE BUILD, for one RID. The two architecture scripts decide the route and call this, so
# the two slices cannot drift apart.
#   $1 RID   $2 arch (arm64 | x86_64)   $3 deployment target   $4 can run (yes | no)
#   $5 route text   $6 script name
# Exit code: 0 = every check ran and passed; 1 = a check failed OR could not run.
# ----------------------------------------------------------------------------------------------
run_macos_build() {
    RID="$1"; local arch="$2" minos="$3" can_run="$4" route="$5" script_name="$6"
    local out="$TOOLS_DIR/output/$RID"
    local scratch="/tmp/codebrix-sdl3-src-$RID"
    local build="/tmp/codebrix-sdl3-build-$RID"
    local gate="/tmp/codebrix-sdl3-gate-$RID"
    local started_at start_seconds="$SECONDS"
    started_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

    echo "=============================================================================="
    echo " SDL $SDL_VERSION (${SDL_COMMIT:0:7}) - $RID"
    echo "=============================================================================="
    echo " started : $started_at"
    echo " host    : $(uname -m), macOS $(sw_vers -productVersion 2>/dev/null || echo unknown)"
    echo " route   : $route"
    echo " source  : $SRC_DIR  (vendored - nothing is downloaded)"
    echo

    echo "--- prerequisites ---"
    check_common_prerequisites
    local cc_version sdk_version
    cc_version="$(cc --version | first_line)"
    sdk_version="$(xcrun --show-sdk-version 2>/dev/null || echo unknown)"
    echo "  cc       : $cc_version"
    echo "  SDK      : macOS $sdk_version"
    echo "  cmake    : $(cmake --version | first_line)"
    echo "  ninja    : $(ninja --version)"
    echo "  min macOS: $minos"
    if [ "$can_run" = "yes" ]; then
        echo "  execute  : $arch code runs on this machine - the full gate will be applied"
    else
        echo "  execute  : NOT AVAILABLE for $arch on this machine. The build and the static checks run;"
        echo "             the smoke test cannot, and is reported as a FAILURE (see README.txt)."
    fi
    echo

    echo "--- source ---"
    copy_source_to_scratch "$scratch"
    echo

    echo "--- building ---"
    build_sdl "$scratch" "$build" "$arch" "$minos"
    echo

    echo "--- smoke test program ---"
    rm -rf "$gate"
    build_smoke_test "$gate" "$arch" "$minos"
    echo

    echo "--- collecting ---"
    collect_dylib "$build" "$out"
    echo

    echo "--- verifying ---"
    verify_dylib "$out/$LIB_NAME" "$arch" "$minos" "$gate" "$can_run"

    if [ "$GATE_FAILED" -ne 0 ] && [ "$UNRUN_ONLY" -ne 1 ]; then
        echo
        echo "VERIFICATION FAILED for $RID - see above. $out is left for inspection, but this build"
        echo "must not be adopted into the package."
        exit 1
    fi
    local gate_status
    if [ "$GATE_FAILED" -eq 0 ]; then gate_status="COMPLETE - every check ran and passed"
    else gate_status="INCOMPLETE - every check that could run passed; the smoke test is UNRUN ($arch cannot execute here). Finish it before adopting (README.txt)."; fi
    echo

    # --- record + stage --------------------------------------------------------------------------
    local sha sha_unstripped uuid uuid_unstripped elapsed
    sha="$(shasum -a 256 "$out/$LIB_NAME" | cut -d' ' -f1)"
    sha_unstripped="$(shasum -a 256 "$out/unstripped/$LIB_NAME" | cut -d' ' -f1)"
    uuid="$(dwarfdump --uuid "$out/$LIB_NAME" 2>/dev/null | awk '{print $2}' | first_line)"
    uuid_unstripped="$(dwarfdump --uuid "$out/unstripped/$LIB_NAME" 2>/dev/null | awk '{print $2}' | first_line)"
    ( cd "$out" && shasum -a 256 "$LIB_NAME" "unstripped/$LIB_NAME" "$LICENSE_FILE_NAME" > SHA256SUMS.txt )
    mkdir -p "$TOOLS_DIR/output/staging/$RID"
    # gzip, not xz: gzip is in the box on macOS and xz is not (Linux stages .xz, Windows .zip).
    gzip -9 -c "$out/$LIB_NAME" > "$TOOLS_DIR/output/staging/$RID/$LIB_NAME.gz"
    elapsed=$(( SECONDS - start_seconds ))

    cat > "$out/BUILD-INFO.txt" <<EOF
SDL3 native library - build information
==============================================================================
RID              : $RID
Gate status      : $gate_status
Built            : $started_at
Build duration   : ${elapsed}s
Built by         : sdl3-native-tools/macos/$script_name  ($route)

Build machine
------------------------------------------------------------------------------
macOS            : $(sw_vers -productVersion 2>/dev/null || echo unknown) ($(uname -m))
Compiler         : $cc_version
SDK              : macOS $sdk_version
cmake            : $(cmake --version | first_line)
ninja            : $(ninja --version)
$arch execution : $can_run

Source (vendored in-repo; nothing fetched at build time)
------------------------------------------------------------------------------
SDL              : $SDL_VERSION, commit $SDL_COMMIT ("$SDL_COMMIT_SUBJECT")
Vendored at      : sdl3-native-tools/SDL/ (see UPSTREAM.txt)
Patches applied  : $PATCHES_APPLIED

Configuration
------------------------------------------------------------------------------
cmake            : $CMAKE_COMMAND_LINE
Deployment target: $minos (MACOSX_DEPLOYMENT_TARGET and CMAKE_OSX_DEPLOYMENT_TARGET; checked: $MINOS_FOUND)
Unguarded-availability warnings: $UNGUARDED_AVAILABILITY_WARNINGS
Weak imports     : $WEAK_IMPORTS

Enabled backends (SDL's own CMake summary; the full summary is cmake-summary.txt)
------------------------------------------------------------------------------
$(grep -E '^ *(Video drivers|Render drivers|GPU drivers|Audio drivers|Joystick drivers|Camera drivers):' "$out/cmake-summary.txt" 2>/dev/null | sed 's/^ */                   /' || echo '                   (cmake-summary.txt missing)')

Result
------------------------------------------------------------------------------
File             : $LIB_NAME  (unversioned - DllImport("SDL3") probes this name)
Install name     : $(otool -D "$out/$LIB_NAME" | sed -n '2p')  (as SDL builds it)
Size (stripped)  : $SIZE_STRIPPED bytes (after signing - the shipped size)
Size (unstripped): $SIZE_UNSTRIPPED bytes -> unstripped/$LIB_NAME
SHA256           : $sha
SHA256 unstripped: $sha_unstripped
LC_UUID          : ${uuid:-unknown}  (unstripped: ${uuid_unstripped:-unknown} - must be equal)
Debug symbols    : $LIB_NAME.dSYM (not shipped)
Signature        : ad-hoc (codesign --sign -), applied after strip
Dependencies     : $(otool -L "$out/$LIB_NAME" | tail -n +2 | awk '{print $1}' | grep -v -x "$EXPECTED_INSTALL_NAME" | tr '\n' ' ')
Licence beside it: $LICENSE_FILE_NAME (SDL's LICENSE.txt, zlib, verbatim)

Smoke test ($([ "$can_run" = "yes" ] && echo 'ran on this machine' || echo 'NOT RUN'))
------------------------------------------------------------------------------
$(printf '%s\n' "$SMOKE_OUTPUT" | sed 's/^/  /')
EOF

    echo "--- done ---"
    echo "  $out/$LIB_NAME"
    echo "  sha256 $sha"
    echo "  LC_UUID ${uuid:-unknown}"
    echo "  staged $TOOLS_DIR/output/staging/$RID/$LIB_NAME.gz"
    echo "  ${elapsed}s"
    echo
    if [ "$GATE_FAILED" -ne 0 ]; then
        echo "GATE INCOMPLETE: this dylib has NOT been executed. Finish the gate on a Mac that runs $arch"
        echo "code before adopting it - README.txt, \"FINISHING A CROSS-BUILT SLICE\"."
        exit 1
    fi
    echo "To adopt this binary into the package, follow ADOPTING A BUILT BINARY in README.txt."
}
