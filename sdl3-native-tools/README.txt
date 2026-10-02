================================================================================
sdl3-native-tools - everything needed to build the SDL3 native libraries
================================================================================

THE RULE THIS FOLDER EXISTS FOR
--------------------------------------------------------------------------------
Jeremy, 2026-09-15 (written for CodeBrix.Ollama's llama-native-tools, and the
rule every CodeBrix native-tools folder is held to):

    "Every single file we need, in order to build these native libraries,
    must be housed in that folder. We must not be pulling from external
    sources during the build process. If, a year from now, I need to redo
    these builds, for some reason - and other source code/repos are not
    available to me - I still need to be able to redo the build. The
    exception is the actual tools like cmake and ninja and those kinds of
    tools - I don't want to vendor a bunch of build tools into this folder.
    But all source code and header files, etc must be in the folder - the
    build process cannot pull from other repos, etc."

Everything below follows from that. The folder is modelled, file for file, on
CodeBrix.VideoPlayback.Dav1d's dav1d-native-tools/ and CodeBrix.Ollama's
llama-native-tools/, which were built to the same rule.


HOW THE RULE IS ENFORCED, NOT JUST STATED
--------------------------------------------------------------------------------
The Linux build runs inside a container started with `--network none`. The first
thing it prints is the proof: the container has no network interface but
loopback. If any step ever tried to fetch a source file or a dependency, it
would fail there instead of quietly working on whichever machine happened to
have a connection. The Windows, macOS and Android scripts fetch nothing either,
but Linux is where the rule is mechanically demonstrated on every run.

SDL's CMake build has no download step at all (no FetchContent, no
ExternalProject, no submodules); see SDL/UPSTREAM.txt.

The things that live outside the folder, by Jeremy's stated exception:
  * the tools installed on each build machine (cmake, ninja, the compilers, a
    container engine, the Android NDK, a JDK) - each platform README lists them
    with versions and install commands;
  * on Linux, the digest-pinned manylinux container images that supply the
    compiler and the glibc floor, and the derived images built on them (cmake
    and ninja wheels, and SDL's backend -devel HEADER packages from the image's
    own repositories). linux/README.txt documents a bare-host route for the day
    those are gone.


FOLDER MAP
--------------------------------------------------------------------------------
  README.txt              this document
  BUILD-PROVENANCE.txt    what was actually built (or adopted), when, by what,
                          with what hashes - one section per runtime identifier
  smoke-test.c            the load-and-run verification program. One file, no
                          SDL headers, no build system; every platform compiles
                          it and runs it against the stripped library as part of
                          its gate (dummy video driver: no display needed)
  .gitignore              re-includes this folder's contents from the root
                          .gitignore (which ignores names that occur inside the
                          vendored source, and *.env) and ignores output/. Its
                          first rule is load-bearing - read the comment before
                          editing it

  SDL/                    THE VENDORED UPSTREAM SOURCE - an unmodified snapshot
                          of SDL at commit a8591d943b7079b17fdd018dc04ec9c71dc94ae4
                          (version header 3.5.0, zlib), including
                          android-project/ (the Java sources of the Android
                          bridge jar) and SDL's own wayland-protocols/.
                          UPSTREAM.txt records the URL, commit, dates, the exact
                          copy command, a tree checksum, and the 14 files that
                          must be committed with `git add -f`. Never edited - if
                          a build ever needs a change it goes in patches/
  patches/                local changes to the vendored source, applied at build
                          time to a scratch copy. EMPTY as of 2026-10-01

  linux/                  linux-x64, linux-arm64, linux-riscv64
                          pins.env, build.sh, container-build.sh,
                          Containerfile.<arch>, README.txt, and
                          vendored-headers/libdecor-0/ (libdecor 0.2.2's public
                          header, MIT, + a pkg-config stub - the AlmaLinux 8
                          images have no libdecor-devel; see its UPSTREAM.txt)
  android/                android-arm64, android-x64 (libSDL3.so, built with
                          the Android NDK, API 33 floor, 16 KB pages) and the
                          SDL3AndroidBridge.jar built with javac from
                          SDL/android-project
                          pins.json, build.py, verify.py, build-jar.sh,
                          README.txt
  windows/                win-x64, win-arm64. build-common.ps1,
                          build-win-x64.ps1, build-win-arm64.ps1 (native on
                          ARM64, or -Route CrossFromX64), README.txt. MSVC +
                          CMake's Visual Studio generator, static CRT - ppy's
                          recipe, from SDL/. Written 2026-10-01, UNRUN: the
                          shipped win-* DLLs are ADOPTED from ppy 2026.722.0
  macos/                  osx-arm64, osx-x64. build-common.sh,
                          build-osx-arm64.sh, build-osx-x64.sh (each native, or
                          cross with the smoke test needing a Mac that runs the
                          slice), README.txt. cmake + ninja + Xcode CLT; floors
                          11.0 (arm64) / 10.14 (x64) as ppy. Written 2026-10-01,
                          UNRUN: the shipped osx-* dylibs are ADOPTED from ppy
                          2026.722.0

  unstripped/             COMMITTED. The pre-strip twin of every native built
                          here, one folder per RID, with SHA256SUMS and a
                          README.txt carrying the rule for keeping them in step
                          with the binaries in ../native_libraries/<rid>/. For
                          crash triage: never shipped, never an input to any
                          build

  output/                 build results (git-ignored except its README.txt).
                          Disposable - the pre-strip copies that are meant to
                          last live in unstripped/, not here


WHICH README TO READ
--------------------------------------------------------------------------------
  Building on Linux    -> linux/README.txt
  Building on Windows  -> windows/README.txt
  Building on a Mac    -> macos/README.txt
  Building for Android -> android/README.txt

Each one lists the tools to install on that machine, with the exact command,
and nothing else is needed.


THE NINE RUNTIME IDENTIFIERS
--------------------------------------------------------------------------------
  RID             built by                                            shipped file
  --------------  --------------------------------------------------- ---------------------
  linux-x64       linux/build.sh x64                                  libSDL3.so
  linux-arm64     linux/build.sh arm64                                libSDL3.so
  linux-riscv64   linux/build.sh riscv64                              libSDL3.so
  win-x64         ADOPTED (ppy); rebuild: windows/build-win-x64.ps1   SDL3.dll
  win-arm64       ADOPTED (ppy); rebuild: windows/build-win-arm64.ps1 SDL3.dll
  osx-x64         ADOPTED (ppy); rebuild: macos/build-osx-x64.sh      libSDL3.dylib
  osx-arm64       ADOPTED (ppy); rebuild: macos/build-osx-arm64.sh    libSDL3.dylib
  android-x64     android/build.py --arch x64                         libSDL3.so
  android-arm64   android/build.py --arch arm64                       libSDL3.so
  (android)       android/build-jar.sh                                SDL3AndroidBridge.jar

The three Linux RIDs, the two Android RIDs and the Android bridge jar are
BUILT HERE from SDL/. For the first published version the Windows and macOS
binaries are ADOPTED from ppy/SDL3-CS 2026.722.0, which built them from this
same SDL commit (Jeremy's ruling, 2026-10-01); the scripts that rebuild them
from SDL/ live in windows/ and macos/ all the same, so every target can be
rebuilt from this repository alone.
BUILD-PROVENANCE.txt says, per RID, which route each shipped binary took.

The shipped binaries live in ../native_libraries/<rid>/, each with a
<file>.provenance.txt beside it; the package packs them into
runtimes/<rid>/native/.

All the names are UNVERSIONED on purpose: DllImport("SDL3") on .NET probes for
exactly libSDL3.so / SDL3.dll / libSDL3.dylib and does not follow sonames. The
Linux SONAME (libSDL3.so.0) lives inside the file, as built, and is recorded in
every BUILD-INFO.txt.

Every RID folder also gets a LICENSE-SDL3.txt - a verbatim copy of SDL's
LICENSE.txt (zlib). The name is package-unique (LICENSE-Dav1d.txt,
LICENSE-LlamaCpp.txt are the family's precedents) because these files land in a
consuming application's OUTPUT FOLDER, where a file named plainly LICENSE
collides with any other package that ships one there.


THE VENDORED COMMIT
--------------------------------------------------------------------------------
  SDL commit a8591d943b7079b17fdd018dc04ec9c71dc94ae4 ("Fix #15985",
  2026-07-19), version header 3.5.0 - a development snapshot, NOT a tagged SDL
  release. zlib.

It is the commit ppy/SDL3-CS 2026.722.0 pins, so the managed bindings in
CodeBrix.Sdl3 (ported from that release), this source and every shipped native
describe one C API. SDL/UPSTREAM.txt explains the choice and records how to
verify the snapshot against upstream.


LICENCES AND NOTICES
--------------------------------------------------------------------------------
../THIRD-PARTY-NOTICES.txt, at the root of this repository, carries SDL's zlib
licence and the notices for everything else the repository incorporates. Read
it before changing what this folder vendors.


A ONE-MINUTE TOUR (on Linux)
--------------------------------------------------------------------------------
    cd linux
    ./build.sh x64              # about half a minute once the image exists
    cat ../output/linux-x64/BUILD-INFO.txt
    cd ../output && sha256sum -c SHA256SUMS
================================================================================
