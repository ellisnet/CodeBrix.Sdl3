#!/usr/bin/env bash
# ==============================================================================================
# build-osx-x64.sh - build libSDL3.dylib for the osx-x64 runtime identifier
# ==============================================================================================
#
#   NEVER YET RUN. Written on Linux on 2026-10-01. Expect to fix something on the first real
#   run; fix it IN THE SCRIPT (or build-common.sh) and record it in ../BUILD-PROVENANCE.txt.
#   Then rewrite this header and README.txt's status block with what the run established.
#
# USAGE
#     cd sdl3-native-tools/macos
#     ./build-osx-x64.sh
#
# TWO ROUTES, chosen automatically from the host:
#   * On an Intel Mac (uname -m = x86_64): native. The whole gate runs.
#   * On an Apple Silicon Mac (arm64): a cross build via -DCMAKE_OSX_ARCHITECTURES=x86_64 - the
#     route ppy's CI took for the adopted dylib (macos-latest is Apple Silicon). ROSETTA 2 IS
#     NEEDED TO VERIFY, not to build: the smoke test has to RUN x86_64 code. Without Rosetta it
#     is reported as a FAILURE rather than skipped quietly:
#         softwareupdate --install-rosetta
#
# Deployment target 10.14 (MACOS_MIN_X64 in build-common.sh) - what the adopted ppy dylib carries.
#
# The two macOS slices stay TWO SEPARATE THIN DYLIBS in two RID folders, deliberately not a
# universal binary: runtimes/osx-x64/native/ and runtimes/osx-arm64/native/ each want their own
# file, and a fat binary would put both slices in both places for nothing.
#
# Output: ../output/osx-x64/
# It installs nothing: anything missing is named with the command that installs it.
# ==============================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-common.sh
. "$SCRIPT_DIR/build-common.sh"

if [ "$(uname -m)" = "x86_64" ]; then
    CAN_RUN=yes
    ROUTE="native (Intel Mac)"
else
    ROUTE="cross-compiled on $(uname -m) via CMAKE_OSX_ARCHITECTURES=x86_64"
    # Rosetta 2 present? (the same test llama-native-tools uses)
    if /usr/bin/pgrep -q oahd 2>/dev/null || [ -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ]; then
        CAN_RUN=yes
        ROUTE="$ROUTE, verified under Rosetta 2"
    else
        CAN_RUN=no
        ROUTE="$ROUTE - Rosetta 2 NOT installed, smoke test cannot run"
    fi
fi

run_macos_build osx-x64 x86_64 "$MACOS_MIN_X64" "$CAN_RUN" "$ROUTE" build-osx-x64.sh
