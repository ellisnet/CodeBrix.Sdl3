#!/usr/bin/env bash
# ==============================================================================================
# build-osx-arm64.sh - build libSDL3.dylib for the osx-arm64 runtime identifier
# ==============================================================================================
#
#   NEVER YET RUN. Written on Linux on 2026-10-01. Expect to fix something on the first real
#   run; fix it IN THE SCRIPT (or build-common.sh) and record it in ../BUILD-PROVENANCE.txt.
#   Then rewrite this header and README.txt's status block with what the run established.
#
# USAGE
#     cd sdl3-native-tools/macos
#     ./build-osx-arm64.sh
#
# TWO ROUTES, chosen automatically from the host:
#   * On an Apple Silicon Mac (uname -m = arm64): native. The whole gate runs. PREFERRED.
#   * On an Intel Mac (x86_64): a cross build via -DCMAKE_OSX_ARCHITECTURES=arm64 (Apple's clang
#     is a cross compiler by nature, and the option is passed on BOTH routes, as ppy did). An
#     Intel Mac cannot execute arm64 code, so the smoke test cannot run: it is reported as a
#     FAILURE and the script exits 1 with "Gate status: INCOMPLETE" recorded. Finish the gate on
#     an Apple Silicon Mac before adopting (README.txt).
#
# Deployment target 11.0 (MACOS_MIN_ARM64 in build-common.sh) - the first macOS on Apple Silicon,
# and what the adopted ppy dylib carries.
#
# Output: ../output/osx-arm64/
# It installs nothing: anything missing is named with the command that installs it.
# ==============================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=build-common.sh
. "$SCRIPT_DIR/build-common.sh"

if [ "$(uname -m)" = "arm64" ]; then
    CAN_RUN=yes
    ROUTE="native (Apple Silicon)"
else
    CAN_RUN=no
    ROUTE="cross-compiled on $(uname -m) via CMAKE_OSX_ARCHITECTURES=arm64 - smoke test cannot run here"
fi

run_macos_build osx-arm64 arm64 "$MACOS_MIN_ARM64" "$CAN_RUN" "$ROUTE" build-osx-arm64.sh
