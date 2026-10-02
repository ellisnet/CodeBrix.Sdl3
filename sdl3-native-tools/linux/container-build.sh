#!/usr/bin/env bash
# ==============================================================================================
# container-build.sh - builds AND verifies libSDL3.so INSIDE the build container
# ==============================================================================================
#
# Do not run this on your workstation. build.sh runs it inside the derived image
# (codebrix-sdl3-build-<arch>) for the requested architecture, WITH THE NETWORK DISABLED:
#
#     podman run --network none ... codebrix-sdl3-build-<arch> bash /work/linux/container-build.sh
#
# That is not decoration. It is the mechanical proof of the rule this folder exists for: if any
# step ever tried to fetch a source file or a dependency, it would fail here instead of quietly
# working on the machine that happened to have a network. Step 0 below prints the proof into
# the build log.
#
# It expects:
#   /work            sdl3-native-tools/, mounted read-write (only output/ is written)
#   $TARGET_RID      linux-x64 | linux-arm64 | linux-riscv64
#   the pins         passed through the environment by build.sh, which sources pins.env
#
# Everything it compiles is already in the repository: /work/SDL is the vendored upstream
# snapshot and /work/smoke-test.c is the gate's load-and-run program. There is nothing to
# download. Modelled on CodeBrix.VideoPlayback.Dav1d's and CodeBrix.Ollama's container-build.sh.
# ==============================================================================================

set -euo pipefail

trap 'rc=$?; echo "ERROR: container-build.sh failed (exit $rc) at line $LINENO: $BASH_COMMAND" >&2' ERR

# first_line: the first line of stdin WITHOUT the `head -1` pitfall. `cmd | head -1` inside $(...)
# under `set -o pipefail` can kill the script silently: head exits early, the writer gets
# SIGPIPE, the pipeline reports 141. It did exactly that to dav1d's emulated builds on
# 2026-08-28. `sed -n 1p` reads its input to the end.
first_line() { sed -n '1p'; }

WORK=/work
SRC="$WORK/${SDL_DIR:-SDL}"
PATCHES="$WORK/patches"
SCRATCH=/tmp/codebrix-sdl3-src
BUILD=/tmp/codebrix-sdl3-build
OUT="$WORK/output/$TARGET_RID"
STARTED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
START_SECONDS="$SECONDS"
CONTAINER_OS="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | first_line | cut -d= -f2- | tr -d '"')"

echo "=============================================================================="
echo " SDL $SDL_VERSION ($SDL_COMMIT) - $TARGET_RID"
echo "=============================================================================="
echo " started   : $STARTED_AT"
echo " container : $CONTAINER_OS"
echo " image     : ${DERIVED_IMAGE:-unknown}"
echo " base      : ${BASE_IMAGE_REF:-unknown}"
echo " arch      : $(uname -m)"
echo

# ----------------------------------------------------------------------------------------------
# 0. Prove there is no network. With --network none the container has only the loopback
#    interface, so this is a fact about the sandbox, not a promise about the script.
# ----------------------------------------------------------------------------------------------
IFACES="$(ls /sys/class/net 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
echo "--- network ---"
echo "  interfaces: ${IFACES:-none}"
if [ "$IFACES" = "lo" ] || [ -z "$IFACES" ]; then
    echo "  [ok] no external network interface - this build cannot reach outside the repository"
else
    echo "  [warn] this container HAS a network interface ($IFACES)."
    echo "         The build still fetches nothing, but the proof is weaker. build.sh normally"
    echo "         passes --network none; something overrode it."
fi
echo

# ----------------------------------------------------------------------------------------------
# 1. Toolchain. Everything here was installed by Containerfile.<arch> when the derived image was
#    built - the one documented, network-using step. Nothing is installed now.
# ----------------------------------------------------------------------------------------------
echo "--- toolchain ---"
for t in cc cmake ninja pkg-config file nm objdump readelf strip patch; do
    command -v "$t" > /dev/null 2>&1 || { echo "ERROR: $t is missing from this image. Rebuild it: FORCE_IMAGE_REBUILD=1 ./build.sh" >&2; exit 1; }
done
CC_VERSION="$(cc --version | first_line)"
LD_VERSION="$(ld --version | first_line)"
CMAKE_ACTUAL="$(cmake --version | first_line)"
NINJA_ACTUAL="$(ninja --version)"
GLIBC_ACTUAL="$(ldd --version | first_line)"
echo "  cc      : $CC_VERSION"
echo "  ld      : $LD_VERSION"
echo "  cmake   : $CMAKE_ACTUAL (pinned $CMAKE_VERSION)"
echo "  ninja   : $NINJA_ACTUAL (pinned $NINJA_VERSION)"
echo "  glibc   : $GLIBC_ACTUAL"
PACKAGES_FILE=/usr/local/share/codebrix-sdl3-build/packages.txt
if [ -f "$PACKAGES_FILE" ]; then
    echo "  SDL backend -devel packages in this image (from Containerfile step 1):"
    sed 's/^/    /' "$PACKAGES_FILE"
    PACKAGES_TABLE="$(cat "$PACKAGES_FILE")"
else
    echo "  [warn] $PACKAGES_FILE is missing - was this image built from Containerfile.<arch>?"
    PACKAGES_TABLE="(not recorded - the image has no $PACKAGES_FILE)"
fi
echo

# ----------------------------------------------------------------------------------------------
# 2. Source. The vendored tree is copied to scratch and built THERE, so /work/SDL is never
#    written to and stays a verifiable, unmodified upstream snapshot. Patches (none today) are
#    applied to the copy.
# ----------------------------------------------------------------------------------------------
echo "--- source ---"
[ -f "$SRC/CMakeLists.txt" ] && [ -f "$SRC/include/SDL3/SDL_version.h" ] \
    || { echo "ERROR: no vendored SDL source at $SRC" >&2; exit 1; }
rm -rf "$SCRATCH" "$BUILD"
cp -a "$SRC" "$SCRATCH"
echo "  copied $SRC -> $SCRATCH"

PATCHES_APPLIED="none"
if [ -d "$PATCHES" ] && ls "$PATCHES"/*.patch > /dev/null 2>&1; then
    PATCHES_APPLIED=""
    for p in "$PATCHES"/*.patch; do
        echo "  applying $(basename "$p")"
        ( cd "$SCRATCH" && patch -p1 --forward --batch < "$p" ) \
            || { echo "ERROR: patch $(basename "$p") did not apply. Fix it; patches are never applied best-effort." >&2; exit 1; }
        PATCHES_APPLIED="$PATCHES_APPLIED $(basename "$p")"
    done
    PATCHES_APPLIED="${PATCHES_APPLIED# }"
fi
echo "  patches applied: $PATCHES_APPLIED"
echo

# ----------------------------------------------------------------------------------------------
# 3. Configure + build. The options come from pins.env so a build log and the pins can never
#    disagree. The compile flags add, to CMake's Release -O3 -DNDEBUG:
#      -g                         debug info, so the unstripped twin is useful for crash triage
#                                 (it does not change the generated code; strip removes it)
#      -ffile-prefix-map=...      rewrite the scratch paths, so no build path lands in the
#                                 binary and repeat builds are byte-identical
#    and the link adds --build-id=sha1, the identity that ties the stripped file to its twin.
# ----------------------------------------------------------------------------------------------
C_FLAGS="-g -ffile-prefix-map=$SCRATCH=SDL -ffile-prefix-map=$BUILD=build -ffile-prefix-map=$WORK=sdl3-native-tools"

# Vendored pkg-config folders (pins.env SDL_VENDORED_PKGCONFIG_<ARCH>): today only the libdecor
# header + stub for the AlmaLinux 8 images. They are read in place from /work, so the vendored
# files in the repository are visibly the source; the image is not changed.
VENDORED_PC_RECORD="none"
if [ -n "${SDL_VENDORED_PKGCONFIG:-}" ]; then
    VENDORED_PC_RECORD=""
    for d in $SDL_VENDORED_PKGCONFIG; do
        [ -d "$WORK/$d" ] || { echo "ERROR: vendored pkg-config folder $WORK/$d is missing; it is part of the repository." >&2; exit 1; }
        export PKG_CONFIG_PATH="$WORK/$d${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
        for pc in "$WORK/$d"/*.pc; do
            VENDORED_PC_RECORD="$VENDORED_PC_RECORD $d/$(basename "$pc") ($(pkg-config --modversion "$(basename "$pc" .pc)"))"
        done
        for h in "$WORK/$d"/*.h; do
            VENDORED_PC_RECORD="$VENDORED_PC_RECORD $d/$(basename "$h") sha256 $(sha256sum "$h" | cut -c1-64)"
        done
    done
    VENDORED_PC_RECORD="${VENDORED_PC_RECORD# }"
    echo "--- vendored pkg-config / headers ---"
    echo "  PKG_CONFIG_PATH=$PKG_CONFIG_PATH"
    printf '%s\n' "$VENDORED_PC_RECORD" | sed 's/) /)\n/g' | sed 's/^/  /'
    echo
fi
LINK_FLAGS="-Wl,--build-id=sha1"
echo "--- configuring ---"
echo "  cmake -S $SCRATCH -B $BUILD -G Ninja"
echo "        $SDL_CMAKE_OPTIONS"
echo "        ${SDL_CMAKE_OPTIONS_ARCH:-(no per-architecture options)}"
echo "        -DSDL_REVISION=$SDL_REVISION_STRING"
echo "        -DCMAKE_C_FLAGS=\"$C_FLAGS\""
echo "        -DCMAKE_SHARED_LINKER_FLAGS=\"$LINK_FLAGS\""
mkdir -p "$BUILD"
# shellcheck disable=SC2086
cmake -S "$SCRATCH" -B "$BUILD" -G Ninja \
    $SDL_CMAKE_OPTIONS ${SDL_CMAKE_OPTIONS_ARCH:-} \
    -DSDL_REVISION="$SDL_REVISION_STRING" \
    -DCMAKE_C_FLAGS="$C_FLAGS" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LINK_FLAGS" > "$BUILD/configure.log" 2>&1 \
    || { echo "ERROR: cmake configure failed:" >&2; tail -60 "$BUILD/configure.log" >&2; exit 1; }

# SDL's own end-of-configure summary - the authoritative list of what was compiled in.
SUMMARY="$(sed -n '/SDL3 was configured with the following options:/,$p' "$BUILD/configure.log" \
    | sed 's/^-- //' | sed -n '/^Enabled backends:/,/^$/p')"
SUMMARY_FULL="$(sed -n '/SDL3 was configured with the following options:/,$p' "$BUILD/configure.log" | sed 's/^-- //')"
# The libdecor version SDL compiled against (0/0/0 or absent when libdecor is off).
CONFIG_H="$(find "$BUILD" -name SDL_build_config.h | sort | first_line)"
LIBDECOR_DEFINES="$(grep -E 'define (SDL_LIBDECOR_VERSION_(MAJOR|MINOR|PATCH)|SDL_VIDEO_DRIVER_WAYLAND_DYNAMIC_LIBDECOR)' "$CONFIG_H" 2>/dev/null | sed 's/^#define //' | tr '\n' ';' | sed 's/;$//; s/;/; /g' || true)"
echo "  libdecor in SDL_build_config.h: ${LIBDECOR_DEFINES:-(none)}"
echo "  CMake feature summary (SDL's own):"
printf '%s\n' "$SUMMARY" | sed 's/^/    /'
grep -E 'CMake Warning' "$BUILD/configure.log" | sed 's/^/  /' || true

echo
echo "--- building ($(nproc) jobs) ---"
cmake --build "$BUILD" -j "$(nproc)" > "$BUILD/build.log" 2>&1 \
    || { echo "ERROR: build failed:" >&2; grep -E -B2 -A8 'error:|FAILED:' "$BUILD/build.log" | head -80 >&2; exit 1; }
echo "  $(tail -1 "$BUILD/build.log")"
WARNINGS="$(grep -c 'warning:' "$BUILD/build.log" || true)"
echo "  compiler warnings: $WARNINGS"
echo

# ----------------------------------------------------------------------------------------------
# 4. Collect. CMake produces libSDL3.so.0.<minor>.<micro> (the real file) plus the symlinks
#    libSDL3.so.0 and libSDL3.so. The package ships ONE unversioned regular file called
#    libSDL3.so, because DllImport("SDL3") probes exactly that name and does not follow sonames.
#    The SONAME libSDL3.so.0 stays inside the file, as built, and is recorded.
# ----------------------------------------------------------------------------------------------
BUILT_REAL="$(find "$BUILD" -maxdepth 1 -name 'libSDL3.so.*' -type f | sort | first_line)"
[ -n "$BUILT_REAL" ] && [ -f "$BUILT_REAL" ] || { echo "ERROR: no libSDL3.so.* regular file was produced in $BUILD" >&2; ls -la "$BUILD" >&2; exit 1; }

echo "--- collecting ---"
echo "  built file: $(basename "$BUILT_REAL")"
rm -rf "$OUT"
mkdir -p "$OUT/unstripped"
cp "$BUILT_REAL" "$OUT/unstripped/$LIB_NAME"
cp "$BUILT_REAL" "$OUT/$LIB_NAME"
chmod 0755 "$OUT/$LIB_NAME" "$OUT/unstripped/$LIB_NAME"
SIZE_UNSTRIPPED="$(stat -c %s "$OUT/unstripped/$LIB_NAME")"
strip --strip-unneeded "$OUT/$LIB_NAME"
SIZE_STRIPPED="$(stat -c %s "$OUT/$LIB_NAME")"
# readelf -n exits 1 on these files even though it prints every note: the Red Hat toolchain's
# annobin plugin leaves .gnu.build.attributes notes and readelf warns "Gap in build notes".
# Hence the `|| true` - the Build ID line is all that is wanted here.
build_id_of() { { readelf -n "$1" 2>/dev/null || true; } | awk '/Build ID/{print $3}' | first_line; }
BUILD_ID="$(build_id_of "$OUT/$LIB_NAME")"
BUILD_ID_UNSTRIPPED="$(build_id_of "$OUT/unstripped/$LIB_NAME")"
echo "  unstripped: $SIZE_UNSTRIPPED bytes -> stripped: $SIZE_STRIPPED bytes"
echo "  build-id  : ${BUILD_ID:-none}"
cp "$SRC/LICENSE.txt" "$OUT/$LICENSE_FILE_NAME"
echo "  $LICENSE_FILE_NAME : SDL's LICENSE.txt (zlib) copied beside the binary"
echo

# ----------------------------------------------------------------------------------------------
# 5. THE GATE. A build that fails any check is reported as failed and this script exits
#    non-zero; output/<rid> is left for inspection but must not be adopted.
# ----------------------------------------------------------------------------------------------
echo "--- verifying ---"
FAILED=0
fail() { echo "  [FAIL] $1"; FAILED=1; }
pass() { echo "  [ok] $1"; }

LIB="$OUT/$LIB_NAME"

# 5a. ELF class and machine.
FILE_OUT="$(file -b "$LIB")"
ELF_CLASS="$(readelf -h "$LIB" | awk -F: '/Class:/{gsub(/^ +/,"",$2); print $2}')"
ELF_MACHINE="$(readelf -h "$LIB" | awk -F: '/Machine:/{gsub(/^ +/,"",$2); print $2}')"
case "$TARGET_RID" in
    linux-x64)     WANT_MACHINE="Advanced Micro Devices X86-64" ;;
    linux-arm64)   WANT_MACHINE="AArch64" ;;
    linux-riscv64) WANT_MACHINE="RISC-V" ;;
    *)             WANT_MACHINE="?" ;;
esac
if [ "$ELF_CLASS" = "ELF64" ] && [ "$ELF_MACHINE" = "$WANT_MACHINE" ]; then
    pass "ELF class/machine: $ELF_CLASS / $ELF_MACHINE ($FILE_OUT)"
else
    fail "ELF class/machine: got '$ELF_CLASS' / '$ELF_MACHINE', expected ELF64 / '$WANT_MACHINE'"
fi

# 5b. SONAME, as built.
SONAME="$(readelf -d "$LIB" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p')"
if [ "$SONAME" = "$SDL_SONAME" ]; then
    pass "SONAME: $SONAME"
else
    fail "SONAME: got '$SONAME', expected '$SDL_SONAME'"
fi

# 5c. No RPATH / RUNPATH, no TEXTREL.
RPATHS="$(readelf -d "$LIB" | grep -E '\((RPATH|RUNPATH)\)' || true)"
if [ -z "$RPATHS" ]; then pass "no RPATH / RUNPATH"; else fail "RPATH/RUNPATH present: $RPATHS"; fi
if readelf -d "$LIB" | grep -q TEXTREL; then fail "TEXTREL present (non-PIC code)"; else pass "no TEXTREL"; fi

# 5d. Required exports.
# SDL exports through a version script, so nm prints e.g. SDL_Init@@SDL3_0.0.0 - the version
# suffix is cut off before comparing names.
EXPORTS="$(nm -D --defined-only "$LIB" | awk '{n=$3; sub(/@.*/, "", n); print n}' | sort -u)"
SYMBOL_VERSIONS="$(nm -D --defined-only "$LIB" | awk '{print $3}' | grep -oE '@@?[A-Za-z0-9_.]+' | tr -d '@' | sort -u | tr '\n' ' ' | sed 's/ *$//')"
EXPORT_COUNT="$(printf '%s\n' "$EXPORTS" | grep -c '^SDL_' || true)"
MISSING=""
for sym in $REQUIRED_SYMBOLS; do
    printf '%s\n' "$EXPORTS" | grep -x "$sym" > /dev/null || MISSING="$MISSING $sym"
done
if [ -n "$MISSING" ]; then
    fail "missing exports:$MISSING"
else
    pass "all $(printf '%s\n' $REQUIRED_SYMBOLS | grep -c .) required symbols exported ($EXPORT_COUNT SDL_* exports in total)"
fi

# 5e. Dependencies: system-only. With SDL_DEPS_SHARED=ON every backend library is dlopen()ed,
#     so libX11 / libwayland / libasound / libpulse / libudev ... must NOT be NEEDED here.
DEPS="$(objdump -p "$LIB" | awk '/NEEDED/ {print $2}' | sort)"
UNEXPECTED=""
for d in $DEPS; do
    case " $ALLOWED_DEPS " in
        *" $d "*) ;;
        *) UNEXPECTED="$UNEXPECTED $d" ;;
    esac
done
if [ -n "$UNEXPECTED" ]; then
    fail "unexpected dynamic dependencies:$UNEXPECTED (allowed: $ALLOWED_DEPS)"
else
    pass "NEEDED is system-only: $(printf '%s ' $DEPS)"
fi

LDD_OUT="$(ldd -r "$LIB" 2>&1 || true)"
UNDEFINED="$(printf '%s\n' "$LDD_OUT" | grep -i 'undefined symbol' || true)"
if [ -n "$UNDEFINED" ]; then
    fail "ldd -r reports undefined symbols:"
    printf '%s\n' "$UNDEFINED" | sed 's/^/         /'
else
    pass "ldd -r: no undefined symbols"
fi

# 5f. glibc floor - CHECKED, not merely reported.
GLIBC_FLOOR="$(objdump -T "$LIB" | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/GLIBC_//' | sort -V -u | tail -1)"
GLIBC_FLOOR="${GLIBC_FLOOR:-none}"
if [ "$GLIBC_FLOOR" = "none" ]; then
    pass "glibc floor: none referenced"
elif printf '%s\n%s\n' "$GLIBC_FLOOR" "$GLIBC_MAX" | sort -V -C; then
    pass "glibc floor: $GLIBC_FLOOR (allowed <= $GLIBC_MAX)"
else
    fail "glibc floor $GLIBC_FLOOR is NEWER than the allowed $GLIBC_MAX - this binary would not load on the systems the package promises"
fi

# 5g. Stripped and unstripped are the same build.
if [ -n "$BUILD_ID" ] && [ "$BUILD_ID" = "$BUILD_ID_UNSTRIPPED" ]; then
    pass "build-id $BUILD_ID identical in the stripped file and its unstripped twin"
else
    fail "build-id mismatch or missing: stripped '$BUILD_ID', unstripped '$BUILD_ID_UNSTRIPPED'"
fi

# 5h. dlopen smoke test, against the STAGED (stripped) file - the bytes that ship.
echo "  --- dlopen smoke test ---"
cc -std=c11 -O1 -o "$OUT/smoke-test" "$WORK/smoke-test.c" -ldl
SMOKE_OUT="$("$OUT/smoke-test" "$LIB" "$SDL_VERSION_NUM" 2>&1)" && SMOKE_RC=0 || SMOKE_RC=$?
printf '%s\n' "$SMOKE_OUT" | sed 's/^/    /'
if [ "$SMOKE_RC" -eq 0 ]; then
    pass "smoke test (SDL_GetVersion == $SDL_VERSION_NUM, dummy video Init, window + renderer, draw + read-back, Quit)"
else
    fail "smoke test exited $SMOKE_RC"
fi

# Record (not gate) the sonames SDL will dlopen() at run time - the backends compiled in.
# 5i. The backends that must be compiled in: their sonames are the strings SDL dlopen()s, so each
#     one in REQUIRED_DLOPEN_SONAMES (pins.env) must appear in the binary. This catches a backend
#     that CMake silently switched off because a header went missing from an image.
DLOPEN_SONAMES="$( { strings "$LIB" | grep -E '^lib[A-Za-z0-9_.+-]+\.so(\.[0-9]+)*$' || true; } | sort -u | tr '\n' ' ' | sed 's/ *$//')"
MISSING_DL=""
for so in ${REQUIRED_DLOPEN_SONAMES:-}; do
    case " $DLOPEN_SONAMES " in *" $so "*) ;; *) MISSING_DL="$MISSING_DL $so" ;; esac
done
if [ -n "$MISSING_DL" ]; then
    fail "backend sonames missing from the binary (backend compiled out?):$MISSING_DL"
else
    pass "required backend sonames present: ${REQUIRED_DLOPEN_SONAMES:-(none required)}"
fi
echo "  dlopen() sonames referenced: $DLOPEN_SONAMES"

if [ "$FAILED" -ne 0 ]; then
    echo
    echo "VERIFICATION FAILED for $TARGET_RID. output/$TARGET_RID is left in place for inspection,"
    echo "but this build must not be adopted into the package."
    exit 1
fi
echo

# ----------------------------------------------------------------------------------------------
# 6. Record.
# ----------------------------------------------------------------------------------------------
SHA="$(sha256sum "$LIB" | cut -d' ' -f1)"
SHA_UNSTRIPPED="$(sha256sum "$OUT/unstripped/$LIB_NAME" | cut -d' ' -f1)"
ELAPSED=$(( SECONDS - START_SECONDS ))
( cd "$OUT" && sha256sum "$LIB_NAME" "unstripped/$LIB_NAME" "$LICENSE_FILE_NAME" smoke-test > SHA256SUMS.txt )
printf '%s\n' "$SUMMARY_FULL" > "$OUT/cmake-summary.txt"
cp "$BUILD/configure.log" "$OUT/cmake-configure.log"

cat > "$OUT/BUILD-INFO.txt" <<EOF
SDL3 native library - build information
==============================================================================
RID              : $TARGET_RID
Built            : $STARTED_AT
Build duration   : ${ELAPSED}s (wall clock inside the container)
Built by         : sdl3-native-tools/linux/build.sh -> container-build.sh
Network          : DISABLED during this build (interfaces: ${IFACES:-none})

Build machine
------------------------------------------------------------------------------
Derived image    : ${DERIVED_IMAGE:-unknown}
Base image       : ${BASE_IMAGE_REF:-unknown}
Container OS     : $CONTAINER_OS
Machine          : $(uname -m)
Compiler         : $CC_VERSION
Linker           : $LD_VERSION
cmake            : $CMAKE_ACTUAL (pinned $CMAKE_VERSION)
ninja            : $NINJA_ACTUAL (pinned $NINJA_VERSION)
Container glibc  : $GLIBC_ACTUAL

Source (vendored in-repo; nothing fetched at build time)
------------------------------------------------------------------------------
SDL              : $SDL_VERSION, commit $SDL_COMMIT ("$SDL_COMMIT_SUBJECT")
Vendored at      : sdl3-native-tools/SDL/ (see UPSTREAM.txt)
Patches applied  : $PATCHES_APPLIED

Configuration
------------------------------------------------------------------------------
cmake options    : -G Ninja $SDL_CMAKE_OPTIONS
arch options     : ${SDL_CMAKE_OPTIONS_ARCH:-(none)}
Vendored pkgconf : $VENDORED_PC_RECORD
libdecor config  : ${LIBDECOR_DEFINES:-(none)}
                   -DSDL_REVISION=$SDL_REVISION_STRING
CMAKE_C_FLAGS    : $C_FLAGS   (on top of Release's -O3 -DNDEBUG)
Linker flags     : $LINK_FLAGS
Compiler warnings: $WARNINGS

SDL backend -devel packages in the image
------------------------------------------------------------------------------
$PACKAGES_TABLE

Enabled backends (SDL's own CMake summary; full summary in cmake-summary.txt)
------------------------------------------------------------------------------
$SUMMARY

Result
------------------------------------------------------------------------------
File             : $LIB_NAME  (unversioned on purpose - DllImport("SDL3") probes this name)
Built as         : $(basename "$BUILT_REAL")
SONAME           : $SONAME
Build-id         : ${BUILD_ID:-none}
Size (stripped)  : $SIZE_STRIPPED bytes
Size (unstripped): $SIZE_UNSTRIPPED bytes  -> unstripped/$LIB_NAME
SHA256           : $SHA
SHA256 unstripped: $SHA_UNSTRIPPED
ELF              : $ELF_CLASS, $ELF_MACHINE
glibc floor      : ${GLIBC_FLOOR} (allowed <= ${GLIBC_MAX:-n/a})
Dynamic deps     : $(printf '%s ' $DEPS)
dlopen() sonames : $DLOPEN_SONAMES
SDL_* exports    : $EXPORT_COUNT  (symbol version(s): ${SYMBOL_VERSIONS:-none})
Licence beside it: $LICENSE_FILE_NAME (a verbatim copy of SDL's LICENSE.txt, zlib)

Smoke test (smoke-test.c against the stripped file)
------------------------------------------------------------------------------
$SMOKE_OUT
EOF

echo "--- done ---"
echo "  $OUT/$LIB_NAME"
echo "  sha256 $SHA"
echo "  ${ELAPSED}s"
