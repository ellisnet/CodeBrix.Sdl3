================================================================================
sdl3-native-tools/macos - building libSDL3.dylib for osx-arm64 and osx-x64
================================================================================

>>> STATUS: NEVER YET RUN. These scripts were written on Linux on 2026-10-01,
    modelled on CodeBrix.Ollama's llama-native-tools/macos/ (run for real on an
    Intel and an Apple Silicon Mac mini, 2026-09-15) and
    CodeBrix.VideoPlayback.Dav1d's dav1d-native-tools/macos/, and on the recipe
    ppy/SDL3-CS used for the dylibs that are shipped today. Nothing they do
    differently from those - SDL's CMake, the export check against SDL's own
    list, the kept install name, the availability-warning check - has
    executed. Expect to fix something on the first real run. Fix it IN THE
    SCRIPT and commit that; then rewrite this status block and the osx-*
    sections of ../BUILD-PROVENANCE.txt with what the run established.

    WHAT SHIPS TODAY: the osx-arm64 and osx-x64 libSDL3.dylib in
    ../../native_libraries/<rid>/ were NOT built by these scripts. They are
    ADOPTED from the ppy.SDL3-CS 2026.722.0 NuGet package, which built them from
    the same SDL commit (Jeremy's ruling, 2026-10-01); each has a
    libSDL3.dylib.provenance.txt beside it. These scripts exist so that both
    RIDs can be rebuilt from this repository alone. Run them when convenient;
    adopt a result only if its gate passes. <<<

WHAT THIS IS
--------------------------------------------------------------------------------
Everything needed to build the two macOS SDL3 libraries this package ships,
from the SDL snapshot vendored in ../SDL/. Nothing is downloaded. The only
things from outside are the tools you install on the Mac, listed below with
the command that installs each one.

  osx-arm64   ./build-osx-arm64.sh   native on an Apple Silicon Mac (preferred),
                                     or cross-built on an Intel Mac (gate
                                     incomplete - the smoke test cannot run)
  osx-x64     ./build-osx-x64.sh     native on an Intel Mac, or cross-built on
                                     an Apple Silicon Mac (verified under
                                     Rosetta 2) - the route ppy took

They stay TWO SEPARATE THIN DYLIBS in two separate RID folders - deliberately
not a universal binary. The package's runtimes/osx-arm64/native/ and
runtimes/osx-x64/native/ folders each want their own file; a fat binary would
put both slices in both places and double the size of each for nothing. (The
adopted ppy dylibs are thin too.)


================================================================================
PREREQUISITES
================================================================================
  1. Xcode Command Line Tools (clang, otool, nm, lipo, strip, codesign,
     dsymutil, dwarfdump, xcrun).

       xcode-select --install

     Verify: cc --version     (should say "Apple clang")

  2. cmake and ninja.

       brew install cmake ninja

     Verify: cmake --version   ninja --version
     SDL needs cmake >= 3.16. The Linux build pins cmake 4.4.3 and ninja
     1.13.2 (../linux/pins.env); newer is fine, and BUILD-INFO.txt records
     what was actually used, so a difference is never invisible.

     On an Intel Mac Homebrew is "Tier 3" (unsupported) as of 2026 and some
     formulae compile from source; cmake and ninja installed fine there for
     llama-native-tools on 2026-09-15.

  3. Rosetta 2 - FOR THE osx-x64 CROSS ROUTE ONLY, and only to VERIFY, not to
     build: on an Apple Silicon Mac the smoke test has to RUN x86_64 code.

       softwareupdate --install-rosetta

  4. Homebrew itself, if you do not already have it: https://brew.sh

  NOT required: Xcode.app (the Command Line Tools suffice), any SDL from
  Homebrew (the scripts never use one - and the gate's smoke test loads the
  staged file by path so an installed libSDL3 cannot interfere).


================================================================================
USAGE
================================================================================
    cd sdl3-native-tools/macos
    ./build-osx-arm64.sh
    ./build-osx-x64.sh

  Both can run on one Apple Silicon Mac (x64 cross, verified under Rosetta 2).
  Each script removes its own scratch, build and gate directories under /tmp
  on every run, so re-running is always safe. Neither installs anything.

  EXIT CODES. 0 means every check ran and passed. 1 means a check failed - or
  could not run (a cross build whose target cannot execute here); read the
  summary at the end, and "Gate status" in BUILD-INFO.txt.

  Timings: unknown until the first run.

  Output, git-ignored:
    ../output/<rid>/libSDL3.dylib             the file the package ships
                                              (stripped, ad-hoc signed)
    ../output/<rid>/libSDL3.dylib.dSYM        debug symbols. NOT shipped
    ../output/<rid>/unstripped/libSDL3.dylib  the pre-strip binary
    ../output/<rid>/LICENSE-SDL3.txt          SDL's LICENSE.txt, verbatim
    ../output/<rid>/BUILD-INFO.txt            toolchain, SDK, options, floor,
                                              enabled backends, sizes, sha256,
                                              LC_UUID, smoke-test output
    ../output/<rid>/cmake-summary.txt         SDL's own configure summary
    ../output/<rid>/SHA256SUMS.txt            hashes of the dylib, its
                                              unstripped twin and the licence
    ../output/staging/<rid>/libSDL3.dylib.gz  compressed copy for moving to
                                              whichever machine assembles the
                                              package (.gz because gzip is in
                                              the box on macOS and xz is not)


================================================================================
THE BUILD, IN ONE PARAGRAPH
================================================================================
build-common.sh copies ../SDL to /tmp, applies any patches from ../patches
(none), and configures the copy with cmake + ninja: Release, SDL_SHARED=ON,
SDL_STATIC=OFF, tests, test library and examples OFF, SDL_INSTALL=OFF,
SDL_FRAMEWORK=OFF (a plain dylib, not a .framework), SDL_RPATH=OFF,
SDL_REVISION pinned to pins.env's string (the scratch copy has no .git),
CMAKE_OSX_ARCHITECTURES=<the slice> and CMAKE_OSX_DEPLOYMENT_TARGET=<its floor>
(also exported as MACOSX_DEPLOYMENT_TARGET), and -g so there is DWARF for the
dSYM. It compiles ../smoke-test.c for the same architecture and floor, then
collects: an unstripped copy, dsymutil -> .dSYM, strip -x, codesign --sign -
(in that order: stripping invalidates a signature, so signing is last), and
runs the gate on the collected file.

Compared with ppy's CI for the shipped dylibs (-DCMAKE_OSX_ARCHITECTURES=...
-DCMAKE_OSX_DEPLOYMENT_TARGET=... -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON
-DSDL_STATIC=OFF, default Makefile generator), the differences are: ninja; no
tests/test library/examples; SDL_REVISION explicit (same string); -g, then
strip -x on the shipped file (ppy's dylibs are NOT stripped - they keep about
7,500-7,900 local symbols and no DWARF - so a rebuild is somewhat smaller; the
local symbols survive here in the unstripped twin and the dSYM instead); and
an explicit ad-hoc signature on both slices
(ppy's osx-x64 dylib carries NO signature - the linker signs arm64 output
only - which macOS accepts for x86_64 code). The install name is kept as SDL
builds it, @rpath/libSDL3.0.dylib, exactly as in ppy's files.


================================================================================
THE MINIMUM macOS VERSION - 11.0 FOR arm64, 10.14 FOR x64, AND WHY TWO FLOORS
================================================================================
A Mach-O binary records the oldest macOS it will run on. With no explicit
deployment target, clang stamps in the version of the machine doing the
building, and dyld then refuses the file on every older Mac. So both scripts
state the floor (MACOS_MIN_ARM64 / MACOS_MIN_X64 in build-common.sh), and the
gate CHECKS the built file carries it (otool -l, LC_BUILD_VERSION minos).

THE CHOICE. The floors are ppy's for this SDL commit - 11.0 for arm64 (the
first macOS that exists on Apple Silicon) and 10.14 for x64 - which are what
the adopted dylibs carry (read from them: minos 11.0 / 10.14, SDK 26.5). A
rebuild is therefore a drop-in replacement with no change of floor, which is
the point of these scripts while the ppy binaries are what ships.

WHY NOT llama-native-tools' SINGLE 13.3 FLOOR. llama raised both slices to
13.3 because its code calls Accelerate's new-LAPACK interface (macOS 13.3) and
a Metal API (12.0) WITHOUT @available guards, so its 11.0 stamp was a lie: the
library loaded on 11.0-13.2 and crashed at the first call. SDL is written for
old floors - its own docs build with 10.13 - and guards newer APIs with
@available, weak-linking the frameworks that are newer than its floor (the
shipped dylibs weak-link CoreHaptics and UniformTypeIdentifiers). There is no
llama-style reason to raise the floor, and raising it would drop Macs the
shipped binaries support. (.NET itself needs a newer macOS than either floor,
so for .NET consumers the floor is never the binding constraint; it matters
only that it is real.)

THE LESSON llama's run taught IS KEPT: a stamp is not a floor unless nothing
unguarded calls past it. When code uses an API newer than the deployment
target without an @available guard, clang warns (-Wunguarded-availability /
-Wunguarded-availability-new, both on by default) and the linker turns the
symbol into a weak import that is NULL on the older macOS. The gate therefore
COUNTS those warnings in build.log and fails the build if there is even one;
BUILD-INFO.txt records the count and the number of weak imports. (llama made
the warning a -Werror in its own wrapper project; here there is no wrapper, so
the gate reads the log instead - same strictness, and you get the whole log.)

If a future SDL snapshot does trip it: either raise the floor for that slice
(edit build-common.sh, rebuild, record it in ../BUILD-PROVENANCE.txt and in
the RID's provenance file) or guard the call with a patch in ../patches/.
Never silence the warning.


================================================================================
THE VERIFICATION GATE
================================================================================
A build that fails any check exits non-zero and must not be adopted.

  1. Architecture - `file` must report a 64-bit Mach-O of the slice's
     architecture, and `lipo -info` must call it a NON-FAT file of that
     architecture.

  2. Exports - `nm -gU` must list EXACTLY the names in
     ../SDL/src/dynapi/SDL_dynapi.sym (1303 at this commit: 1302 SDL_* and
     JNI_OnLoad), none missing, none extra - read at gate time from the
     vendored source, so it cannot drift. The adopted ppy dylibs match that
     list exactly. pins.env's REQUIRED_SYMBOLS sample is checked as well.

  3. Install name - `otool -D` must say @rpath/libSDL3.0.dylib (as built).

  4. Dependencies - every `otool -L` entry must be under /usr/lib/ or
     /System/Library/Frameworks/. Anything from Homebrew, /usr/local or an
     @rpath would make the package demand something be installed. (The
     shipped dylibs list libSystem, libobjc and 21 system frameworks.)

  5. No LC_RPATH.

  6. Deployment target - minos CHECKED against the slice's floor.

  7. The floor is real - zero -Wunguarded-availability warnings in build.log
     (THE MINIMUM macOS VERSION).

  8. Code signature - `codesign -v` must pass after the strip. Apple Silicon
     refuses to load an unsigned arm64 dylib.

  9. dlopen smoke test - ../smoke-test.c, compiled for the slice, loads the
     STAGED dylib (copied beside it and passed by full path, so the shipped
     bytes are what runs and no libSDL3 from Homebrew can be picked up),
     resolves 24 entry points, checks SDL_GetVersion() == 3005000, prints the
     compiled-in video, audio and render drivers, initialises SDL on the DUMMY
     video driver (no window server needed), creates a hidden window and a
     renderer, clears to a known colour, reads a pixel back, and quits.

 10. Revision - SDL_GetRevision() must be SDL-3.5.0-a8591d9.

  On a cross route whose target cannot execute (osx-arm64 on Intel; osx-x64 on
  Apple Silicon without Rosetta), checks 9 and 10 cannot run. That is
  reported as a FAILURE, the script exits 1, and BUILD-INFO.txt is still
  written with "Gate status: INCOMPLETE" so the result can be finished
  elsewhere.


================================================================================
FINISHING A CROSS-BUILT SLICE
================================================================================
Copy ../output/<rid>/libSDL3.dylib and ../smoke-test.c to a Mac that can run
the slice, then:

    cc -std=c11 -O1 -o smoke-test smoke-test.c
    ./smoke-test "$PWD/libSDL3.dylib" 3005000

It must end with "SMOKE TEST PASSED" and print
"SDL_GetRevision  : SDL-3.5.0-a8591d9". Record the result in
../BUILD-PROVENANCE.txt and in BUILD-INFO.txt's "Gate status" line. Better
still, run the script natively on that Mac and adopt the fully gated build.


================================================================================
LC_UUID: NOT BYTE-REPRODUCIBLE, AND WHY THAT IS EXPECTED
================================================================================
Two from-scratch builds of the same source on the same Mac will NOT have the
same sha256. llama-native-tools measured it on 2026-09-15 (and dav1d saw the
same for a different reason): the unstripped dylibs differed only in the
16-byte LC_UUID and two bytes in the symbol-table region; the stripped, signed
files differed in about 112 bytes - the same UUID plus the ad-hoc signature,
which hashes it. ld64 derives the UUID from the pre-strip image, and with -g
that image carries debug-map entries (N_OSO) recording the object files'
modification times - new on every build. Every byte of code and data is
identical.

It is left alone deliberately: -Wl,-no_uuid would make crash reports from the
shipped binary much harder to symbolicate, which is the whole reason the
unstripped twin and the dSYM are kept. So when a rebuild's sha256 differs from
a recorded one, confirm it is only that before concluding anything:

    cmp -l old.dylib new.dylib | wc -l          # expect on the order of 100
    otool -l <dylib> | grep -A2 LC_UUID

BUILD-INFO.txt records the LC_UUID of the stripped file and of its unstripped
twin; they must be EQUAL (strip and codesign do not change the UUID), which
is how anyone later proves the stored twin and dSYM belong to the shipped
file:

    dwarfdump --uuid ../../native_libraries/<rid>/libSDL3.dylib
    dwarfdump --uuid ../unstripped/<rid>/libSDL3.dylib
    dwarfdump --uuid ../unstripped/<rid>/libSDL3.dylib.dSYM

The adopted ppy dylibs' UUIDs are in their provenance files (osx-x64
CBCA0221-A566-33FB-A7AA-65B184E75B6B, osx-arm64
4C79C675-BBFD-38C5-865E-8F77C6EC715A); ppy published no dSYM for them.


================================================================================
TROUBLESHOOTING
================================================================================
"cmake: command not found" after brew install
    Homebrew's bin directory is not on PATH for this shell: /opt/homebrew/bin
    on Apple Silicon, /usr/local/bin on Intel.
        eval "$(/opt/homebrew/bin/brew shellenv)"   (or /usr/local/bin/brew)

"minimum macOS is <version>, expected 11.0 / 10.14"
    The deployment target did not reach the build. The scripts pass it on
    every run and delete the build directory first, so use the scripts rather
    than configuring cmake by hand. Do NOT relax the check.

"N -Wunguarded-availability warning lines in build.log"
    THE MINIMUM macOS VERSION. grep build.log for the warnings; each names the
    API and the version it needs.

"lipo -info: ... (expected a non-fat ... file)"
    Something produced a universal binary: CMAKE_OSX_ARCHITECTURES must be a
    single architecture (the script passes exactly one).

"install name is '...', expected @rpath/libSDL3.0.dylib"
    SDL changed how it names the library. Look at the build tree
    (ls -l /tmp/codebrix-sdl3-build-<rid>/*.dylib); if the new name is
    deliberate upstream, update EXPECTED_INSTALL_NAME in build-common.sh and
    say so in ../BUILD-PROVENANCE.txt.

"non-system dynamic dependencies"
    SDL found a library outside the OS at configure time (Homebrew's, most
    likely) and linked it. Check cmake-summary.txt for the backend that
    pulled it in and switch that backend off in SDL_CMAKE_OPTIONS_MACOS, or
    configure in a shell without Homebrew's prefixes on the search paths.

"codesign -v fails"
    The explicit codesign call failed or something modified the file after
    it. Signing must be the LAST change to the file.

"smoke test NOT RUN" on osx-x64
    Cross route without Rosetta 2: softwareupdate --install-rosetta, re-run.

dsymutil prints warnings
    llama saw a benign "duplicate object name" warning from its static
    archives; SDL is built as one target, so expect none - but a warning
    alone does not fail the gate. Look before ignoring it.

The sha256 does not match a recorded build
    Expected if the only difference is the LC_UUID and the signature. See
    LC_UUID above.


================================================================================
ADOPTING A BUILT BINARY INTO THE PACKAGE
================================================================================
  1. Read ../output/<rid>/BUILD-INFO.txt and satisfy yourself it is the build
     you think it is: SDL commit, toolchain, "Gate status: COMPLETE",
     deployment target, zero unguarded-availability warnings, the smoke-test
     output.

  2. Replace the adopted ppy binary:

       cp ../output/<rid>/libSDL3.dylib     ../../native_libraries/<rid>/
       cp ../output/<rid>/LICENSE-SDL3.txt  ../../native_libraries/<rid>/
       codesign -v ../../native_libraries/<rid>/libSDL3.dylib

     <rid> is osx-arm64 or osx-x64. Keep the name libSDL3.dylib. Re-check the
     signature after the copy - some transports drop it.

  3. Rewrite ../../native_libraries/<rid>/libSDL3.dylib.provenance.txt: it
     then says BUILT HERE (by which script, on which Mac, with which
     toolchain and SDK, hashes, LC_UUID, gate result) instead of ADOPTED FROM
     ppy - copy the values from BUILD-INFO.txt, as the Linux provenance files
     do.

  4. Do NOT put the .dSYM or the unstripped copy in the package. Their home
     is ../unstripped/<rid>/: copy ../output/<rid>/unstripped/libSDL3.dylib
     and the whole ../output/<rid>/libSDL3.dylib.dSYM/ bundle there and
     regenerate ../unstripped/SHA256SUMS, in the SAME change that adopts the
     binary. Check the three UUIDs agree (LC_UUID above).

  5. Update the RID's section of ../BUILD-PROVENANCE.txt and this README's
     status block.

  6. Run the managed test suite before publishing.


================================================================================
FILES
================================================================================
  README.txt                 this document
  build-common.sh            shared machinery: pins, floors, options, the
                             build, collection, the gate, the record
  build-osx-arm64.sh         osx-arm64, native on Apple Silicon or cross on
                             Intel
  build-osx-x64.sh           osx-x64, native on Intel or cross on Apple
                             Silicon
  ../linux/pins.env          the pins shared by every platform: SDL commit,
                             version, revision string, required exports. It
                             lives in the linux folder because the container
                             build sources it; this platform sources the same
                             file
  ../SDL/                    the vendored source (never edited)
  ../smoke-test.c            the load-and-run verification program
  ../output/                 build results (git-ignored)
================================================================================
