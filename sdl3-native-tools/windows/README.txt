================================================================================
sdl3-native-tools/windows - building SDL3.dll for win-x64 and win-arm64
================================================================================

>>> STATUS: NEVER YET RUN. These scripts were written on Linux on 2026-10-01,
    modelled on CodeBrix.Ollama's llama-native-tools/windows/ and
    CodeBrix.VideoPlayback.Dav1d's dav1d-native-tools/windows/ (both of which
    have run for real on Windows 11 with Visual Studio 2026, and whose
    first-run fixes are carried over here), and on the recipe ppy/SDL3-CS used
    for the DLLs that are shipped today. Expect to fix something on the first
    real run - dav1d's Windows scripts needed four fixes, llama's five. Fix it
    IN THE SCRIPT and commit that; then rewrite this status block and the
    win-* sections of ../BUILD-PROVENANCE.txt with what the run established.

    WHAT SHIPS TODAY: the win-x64 and win-arm64 SDL3.dll in
    ../../native_libraries/<rid>/ were NOT built by these scripts. They are
    ADOPTED from the ppy.SDL3-CS 2026.722.0 NuGet package, which built them from
    the same SDL commit (Jeremy's ruling, 2026-10-01); each has a
    SDL3.dll.provenance.txt beside it. These scripts exist so that both RIDs
    can be rebuilt from this repository alone. Run them when convenient; adopt
    a result only if its gate passes. <<<

WHAT THIS IS
--------------------------------------------------------------------------------
Everything needed to build the two Windows SDL3 libraries this package ships,
from the SDL snapshot vendored in ..\SDL\. Nothing is downloaded: not the
source, not a dependency, not a test asset. The only things that come from
outside are the tools you install on the build machine, and every one of them
is listed below with the command that installs it.

  win-x64     built with MSVC (cl) on an x64 Windows machine
  win-arm64   built with MSVC (cl) for ARM64, either natively on an ARM64
              Windows machine (preferred) or cross-compiled from an x64
              machine (see THE TWO ARM64 ROUTES)

Jeremy has both an x64 and an ARM64 Windows 11 machine, so the plan is one
native build on each.


================================================================================
PREREQUISITES
================================================================================
  1. Visual Studio 2022 or newer, or the standalone Build Tools, with:

       - Workload:  "Desktop development with C++"
                    (brings cl, link, dumpbin and the Windows SDK)
       - Component: "MSVC v143 - VS 2022 C++ ARM64/ARM64EC build tools"
                    (win-arm64 only; on newer Visual Studio the equivalent
                    "MSVC Build Tools for ARM64/ARM64EC" works - the script
                    checks the filesystem for an ARM64-targeting cl.exe, not a
                    component name)

     Install through the Visual Studio Installer, or:
       winget install Microsoft.VisualStudio.2022.BuildTools

     NO clang-cl is needed (unlike llama and dav1d): SDL builds with cl for
     ARM64 as it is, and that is how the shipped DLL was built.

     THE COMPONENTS MUST BE IN THE INSTANCE THE BUILD ACTUALLY USES. The
     scripts select an instance with `vswhere -latest`, check THAT instance's
     filesystem, and hand the same instance to CMake
     (CMAKE_GENERATOR_INSTANCE). If you have several Visual Studios, adding the
     ARM64 tools to the wrong one changes nothing - see TROUBLESHOOTING.

  2. cmake, new enough to know your Visual Studio's generator:

       winget install Kitware.CMake

     Verify: cmake --version. SDL itself needs cmake >= 3.16; Visual Studio
     2026 (major version 18) needs a cmake that lists "Visual Studio 18 2026"
     in `cmake --help` [ASSUMED: 4.2 or newer - the script asks cmake rather
     than trusting this number, and stops with the list it found if there is
     no match]. The Linux build pins cmake 4.4.3 (../linux/pins.env); using
     the same version here is sensible but not required - BUILD-INFO.txt
     records what was used.

     Visual Studio's own "C++ CMake tools for Windows" component also bundles
     a cmake. Whichever is first on PATH after vcvarsall is used, and the
     script prints its path and version.

  3. PowerShell 5.1 (in the box) or PowerShell 7+.

  NOT required: ninja (the Visual Studio generator drives MSBuild, as ppy's
  build did), Python, Perl, nasm, MSYS2, git-bash. git is needed only if
  ..\patches\ ever holds a patch (it does not).


================================================================================
USAGE
================================================================================
    cd sdl3-native-tools\windows
    .\build-win-x64.ps1                         # on the x64 machine

    .\build-win-arm64.ps1                       # on the ARM64 machine
    .\build-win-arm64.ps1 -Route CrossFromX64   # on the x64 machine (partial gate)

  Each script imports its own developer environment (vcvarsall x64, arm64 or
  x64_arm64), so no special command prompt is needed. Each deletes and
  recreates its scratch and build directories under %TEMP% on every run, so
  re-running is always safe.

  If PowerShell refuses to run the scripts ("running scripts is disabled on
  this system"), allow local scripts for this session only:
       Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

  EXIT CODES. 0 means every check ran and passed. Non-zero means it did not -
  and for  -Route CrossFromX64  a non-zero exit is the NORMAL, EXPECTED result,
  because the smoke test cannot run on an x64 host. Read the summary the
  script prints at the end rather than the exit code alone.

  Timings: unknown until the first run (SDL is a 1,300-function C library with
  no assembly; expect a minute or two cold).

  Output, git-ignored:
    ..\output\<rid>\SDL3.dll            the file the package ships
    ..\output\<rid>\SDL3.pdb            debug symbols - the Windows equivalent
                                        of the unstripped copy. NOT shipped;
                                        goes to ..\unstripped\<rid>\
    ..\output\<rid>\LICENSE-SDL3.txt    SDL's LICENSE.txt (zlib), verbatim
    ..\output\<rid>\BUILD-INFO.txt      toolchain, options, enabled backends,
                                        size, sha256, smoke-test output
    ..\output\<rid>\cmake-summary.txt   SDL's own end-of-configure summary
    ..\output\<rid>\SHA256SUMS.txt      the DLL's, the .pdb's and the
                                        licence's hashes (LF endings, so
                                        `sha256sum -c` works on Linux too)
    ..\output\staging\<rid>\SDL3-<rid>.zip
                                        DLL + pdb + licence + BUILD-INFO for
                                        moving to whichever machine assembles
                                        the package (.zip because
                                        Compress-Archive is in the box)
    ..\output\staging\win-arm64\win-arm64-gate.zip
                                        CROSS ROUTE ONLY - the DLL plus the
                                        ARM64 smoke-test.exe, to finish the
                                        gate on ARM64 hardware


================================================================================
THE BUILD, IN ONE PARAGRAPH
================================================================================
The script copies ..\SDL to %TEMP%, applies any patches from ..\patches (none),
and configures that copy with CMake's Visual Studio generator for the selected
instance, -A x64 or -A ARM64, with the options in build-common.ps1
(Get-SdlWindowsCmakeOptions): Release, SDL_SHARED=ON, SDL_STATIC=OFF, tests,
test library and examples OFF, SDL_INSTALL=OFF, CMAKE_MSVC_RUNTIME_LIBRARY=
MultiThreaded (the STATIC CRT, so no Visual C++ Redistributable is needed on a
user's machine), SDL_REVISION pinned to the string in ../linux/pins.env (the
scratch copy has no .git for SDL to describe), HAVE_GAMEINPUT_H=OFF (see
GAMEINPUT), and debug information for a .pdb (see THE .pdb). It builds the
Release configuration, compiles ..\smoke-test.c with cl for the same target,
collects SDL3.dll, SDL3.pdb and the licence into ..\output\<rid>\, and runs
the gate on the collected file.


================================================================================
HOW THIS COMPARES WITH THE SHIPPED (ppy) DLLs
================================================================================
ppy/SDL3-CS 2026.722.0's CI built the shipped DLLs from the same SDL commit
with (.github/workflows/build.yml + External/build.sh, for SDL):

    sed -i 's/#include <gameinput.h>/#_include <gameinput.h>/g' CMakeLists.txt
    cmake -B build -A <x64|ARM64> -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
          -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF
    cmake --build build/ --config Release

These scripts reproduce that, and differ ONLY in:
  * GameInput is disabled by pre-seeding HAVE_GAMEINPUT_H=OFF instead of by a
    sed on the source - same result, vendored source untouched (GAMEINPUT);
  * the test library, tests and examples are not built (they are not shipped);
  * SDL_REVISION is passed explicitly (ppy's came from git describe; both
    give SDL-3.5.0-a8591d9);
  * /Z7 + /DEBUG /OPT:REF /OPT:ICF /PDBALTPATH:%_PDB% produce a .pdb (THE .pdb).
None of these changes the generated code. A rebuild will still not be
byte-identical to ppy's file: link.exe stamps a timestamp, the debug directory
gains a CodeView record, and the toolset version will differ. Compare the
BUILD-INFO.txt facts (exports, dependents, enabled backends) instead.

What the shipped DLLs look like (read from their PE headers on 2026-10-01; the
gate checks a rebuild against the same facts):
  - machine 0x8664 (x64) / 0xAA64 (ARM64); linker 14.51
  - exactly the 1303 names in ..\SDL\src\dynapi\SDL_dynapi.sym exported
    (1302 SDL_* + JNI_OnLoad)
  - imports ADVAPI32 GDI32 HID IMM32 KERNEL32 OLEAUT32 SETUPAPI SHELL32 USER32
    VERSION WINMM ole32 - and nothing from the Visual C++ runtime
  - no GameInput backend


================================================================================
GAMEINPUT
================================================================================
SDL's CMakeLists.txt (lines ~2356-2390 at this commit) enables a GameInput
joystick backend when the Windows SDK has <gameinput.h>, and links
gameinput.lib if it finds one. ppy's build script turns that detection off on
Windows with a sed that breaks the check's #include; ppy added it on
2025-01-02 with the note "SDL does not build on Github Actions with GameInput".

Is it still needed at this SDL commit? Probably not [INFERRED, not tested -
there is no Windows SDK on the machine these scripts were written on]: SDL's
GameInput code is now version-aware (SDL_gameinput.h maps
GAMEINPUT_API_VERSION > 0 onto the GameInput::v<N> namespace) and loads
gameinputredist.dll / gameinput.dll at run time. What IS certain: the shipped
ppy DLLs contain no GameInput backend (no gameinput.dll, gameinputredist.dll or
GameInputCreate strings, no SDL_JOYSTICK_GAMEINPUT hint name).

So the default build matches the shipped DLLs WITHOUT patching anything: it
passes -DHAVE_GAMEINPUT_H=OFF, which pre-seeds the result of SDL's own check
(CMake never runs a check whose result variable is already defined), and
..\patches\ stays empty. No sed runs at build time, ever.

To try GameInput, pass -GameInput: SDL then detects <gameinput.h> itself. If
it also finds gameinput.lib it LINKS it, and the dependents check will fail on
the new import - that is the gate doing its job. Decide deliberately (and
record it in ..\BUILD-PROVENANCE.txt) before shipping a DLL built that way.


================================================================================
THE .pdb
================================================================================
CMake's Release configuration asks MSVC for no debug information, so ppy
published no .pdb, and a crash inside the shipped DLL can only be resolved to
an export-relative address. These builds keep one, as the Linux builds keep an
unstripped twin:

  /Z7 (in CMAKE_C_FLAGS_RELEASE / CMAKE_CXX_FLAGS_RELEASE, appended to CMake's
      default "/O2 /Ob2 /DNDEBUG") puts debug info in the object files - no
      shared compiler .pdb, so no C1041 contention under a parallel build;
  /DEBUG makes link.exe write SDL3.pdb. It also switches /OPT:REF and
      /OPT:ICF OFF by default, so both are passed explicitly to keep the code
      identical to a build without /DEBUG;
  /PDBALTPATH:%_PDB% records only "SDL3.pdb" in the DLL, not this machine's
      %TEMP% path.

The .pdb is NOT shipped. On adoption it goes to ..\unstripped\<rid>\SDL3.pdb.
A debugger matches it to the DLL by the GUID+age in the DLL's CodeView record
(`dumpbin /headers SDL3.dll` shows it under "Debug Directories").


================================================================================
THE TWO ARM64 ROUTES
================================================================================
  -Route Native (default) - run on an ARM64 Windows machine.
      Preferred, because the gate can RUN what it built. vcvarsall arm64 (the
      ARM64-hosted tools); CMake -A ARM64.

  -Route CrossFromX64 - run on an x64 Windows machine.
      vcvarsall x64_arm64; CMake -A ARM64 - the route ppy's CI took. It
      produces the DLL and an ARM64 smoke-test.exe and runs the static checks
      (machine type, exports, dependents), but it CANNOT run the smoke test.
      The script reports that as a FAILURE rather than skipping it quietly,
      exits non-zero, still writes BUILD-INFO.txt with "Gate status:
      INCOMPLETE" at the top, and stages win-arm64-gate.zip.

  Unlike llama and dav1d there is no compiler difference between the routes:
  cl targets ARM64 from either host. The route decides only whether the
  smoke test can run.


================================================================================
THE VERIFICATION GATE
================================================================================
The same gate as the Linux build, expressed with the tools Windows has. A
build that fails any check that could run exits non-zero, records nothing,
and must not be adopted.

  1. Machine type - read straight from the PE header by the script (0x8664 /
     0xAA64), and cross-checked with dumpbin /headers.

  2. Exports - dumpbin /exports must list EXACTLY the names in
     ..\SDL\src\dynapi\SDL_dynapi.sym (1303 at this commit), none missing,
     none extra. The list is read at gate time from the vendored source, so it
     cannot drift. The REQUIRED_SYMBOLS sample in ../linux/pins.env (SDL_Init,
     SDL_GetVersion, ...) is checked as well. (With the .pdb beside the DLL,
     dumpbin prints "name = name"; the parser takes the first token after the
     RVA, and parsing zero names is itself a failure - llama's first run.)

  3. Dependents - dumpbin /dependents may list only the twelve operating-
     system DLLs the shipped ppy DLLs import (build-common.ps1,
     $AllowedDependents). NOTHING from the Visual C++ runtime:
     VCRUNTIME140.dll, MSVCP140.dll, ucrtbase.dll or any api-ms-win-crt-*.dll
     there means the static CRT did not take, and every user would need a
     redistributable.

  4. LoadLibrary smoke test - ..\smoke-test.c (one file, no SDL headers),
     compiled with cl for the target and the static CRT, loads the STAGED DLL
     by full path the way .NET does, resolves 24 entry points, checks
     SDL_GetVersion() == 3005000 (pins.env SDL_VERSION_NUM), prints every
     compiled-in video, audio and render driver, initialises SDL on the DUMMY
     video driver (no display needed), creates a hidden window and a
     renderer, clears to a known colour, reads a pixel back, and quits.

  5. Revision - the smoke test's SDL_GetRevision() line must be
     SDL-3.5.0-a8591d9 (pins.env SDL_REVISION_STRING).

  THE PATH TRAP. The staged DLL is copied beside smoke-test.exe and passed by
  full path, so the exact file the package ships is what loads. dav1d's first
  Windows run loaded GStreamer's dav1d.dll from PATH instead of the one under
  test; SDL3.dll is a far commoner name (games, emulators, SDKs), so the copy
  matters even more here.

  There is no glibc-floor equivalent on Windows: the static CRT removes the
  redistributable question, which check 3 covers. The DLLs' OS version fields
  (6.0 for x64, 6.2 for ARM64 in the shipped files) are recorded, not gated.


================================================================================
FINISHING A CROSS-BUILT win-arm64 ON ARM64 HARDWARE
================================================================================
A cross-built win-arm64 has passed the static checks. The smoke test must be
run on an ARM64 Windows machine before the binary is adopted.

  A. VERIFY THE ACTUAL ARTEFACT

     Copy ..\output\staging\win-arm64\win-arm64-gate.zip to the ARM64 machine,
     unpack it into one folder, and in that folder:

       .\smoke-test.exe "$PWD\SDL3.dll" 3005000

     It must end with "SMOKE TEST PASSED" and print
     "SDL_GetRevision  : SDL-3.5.0-a8591d9". Then record the result in
     ..\BUILD-PROVENANCE.txt and replace the "Gate status" line in
     output\win-arm64\BUILD-INFO.txt.

  B. REBUILD NATIVELY (the stronger check)

       .\build-win-arm64.ps1

     This runs the whole gate end to end and exits 0 if everything passes. If
     it passes, prefer the natively built binary.


================================================================================
TROUBLESHOOTING
================================================================================
"vswhere.exe was not found"
    No Visual Studio 2017-or-newer installer is present. See PREREQUISITES 1.

"The ARM64 C++ build tools are not installed in THIS Visual Studio instance"
    Exactly what it says - note the word THIS. To see which instance is used:
        & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath

"This cmake offers no generator for Visual Studio major version NN"
    The cmake on PATH is older than your Visual Studio. Install a newer one
    (winget install Kitware.CMake) or put Visual Studio's bundled cmake first.

vcvarsall.bat arm64 fails on the ARM64 machine (Route Native)
    The ARM64-HOSTED tools are missing from that instance. Install them, or as
    a stop-gap edit $vcvarsArch in build-win-arm64.ps1 to 'x64_arm64' (the
    x64-hosted cross tools, run under emulation) - and record that you did.

"smoke-test.exe was compiled for machine 0x8664, not 0xAA64"
    The developer environment imported was not the ARM64 one; check the
    "developer environment: vcvarsall.bat ..." line near the top of the log.

dumpbin /dependents lists VCRUNTIME140.dll or api-ms-win-crt-*.dll
    The static CRT did not take. CMAKE_MSVC_RUNTIME_LIBRARY needs CMake policy
    CMP0091 NEW, which SDL's cmake_minimum_required(3.16) gives. Check
    configure.log for the -D reaching cmake; delete the build directory and
    re-run (the script always does).

The dependents check fails on GameInput.dll (or another DLL)
    See GAMEINPUT. Without -GameInput this should not happen; if it does,
    SDL's detection changed - look at cmake-summary.txt and configure.log.

The exports check reports missing or extra names
    Missing: something was compiled out that SDL's export list expects - see
    cmake-summary.txt. Extra: the export list and the dllexport set
    disagree, which would be an SDL change; compare with the vendored
    SDL_dynapi.sym. Either way, do not edit the list to make it pass.

The smoke test fails at "SDL_CreateRenderer" or the read-back
    The dummy video driver renders through SDL's software renderer; a failure
    there is a real defect of the build. Read the SDL_GetError text it prints.

cmake or the build prints errors mentioning gameinput
    You passed -GameInput and the Windows SDK's GameInput header is one SDL
    cannot build against - the situation ppy's sed was written for. Drop
    -GameInput.

PowerShell stops at the first cmake warning
    Native commands run through Invoke-Native, which relaxes
    $ErrorActionPreference for the call because Windows PowerShell 5.1 turns
    redirected stderr lines into errors. If a native call was added without
    it, route it through Invoke-Native.

The sha256 differs from a previous build of the same source
    Expected: link.exe stamps a timestamp into the image (dav1d saw exactly
    four bytes differ between two builds of identical source), and the .pdb
    GUID differs too. Compare size, exports, dependents and the gate result.
    /Brepro would make it reproducible and is deliberately not passed, as in
    llama and dav1d.


================================================================================
ADOPTING A BUILT BINARY INTO THE PACKAGE
================================================================================
  1. Read ..\output\<rid>\BUILD-INFO.txt and satisfy yourself it is the build
     you think it is: SDL commit, toolchain, "Gate status: COMPLETE", the
     enabled backends, the smoke-test output.

  2. Replace the adopted ppy binary:

       copy ..\output\<rid>\SDL3.dll           ..\..\native_libraries\<rid>\
       copy ..\output\<rid>\LICENSE-SDL3.txt   ..\..\native_libraries\<rid>\

     <rid> is win-x64 or win-arm64. Keep the name SDL3.dll -
     DllImport("SDL3") probes exactly that.

  3. Rewrite ..\..\native_libraries\<rid>\SDL3.dll.provenance.txt: it then
     says BUILT HERE (by which script, on which machine, with which
     toolchain, hashes, gate result) instead of ADOPTED FROM ppy - copy the
     values from BUILD-INFO.txt, as the Linux provenance files do.

  4. The .pdb: copy ..\output\<rid>\SDL3.pdb to ..\unstripped\<rid>\ and
     extend ..\unstripped\SHA256SUMS, in the SAME change that adopts the DLL.

  5. Update the RID's section of ..\BUILD-PROVENANCE.txt and this README's
     status block.

  6. Run the managed test suite before publishing.


================================================================================
FILES
================================================================================
  README.txt                 this document
  build-common.ps1           shared machinery: pins, VS discovery, the build,
                             the gate, the record
  build-win-x64.ps1          win-x64
  build-win-arm64.ps1        win-arm64, native or cross
  ..\linux\pins.env          the pins shared by every platform: SDL commit,
                             version, revision string, required exports. It
                             lives in the linux folder because the container
                             build sources it as a shell script; this platform
                             parses the same file
  ..\SDL\                    the vendored source (never edited)
  ..\smoke-test.c            the load-and-run verification program, shared by
                             every platform
  ..\output\                 build results (git-ignored)
================================================================================
