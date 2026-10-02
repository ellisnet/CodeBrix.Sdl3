================================================================================
sdl3-native-tools/linux - building libSDL3.so for linux-x64, linux-arm64 and
                          linux-riscv64
================================================================================

>>> STATUS 2026-10-01: see ../BUILD-PROVENANCE.txt for which slices are built,
    gated and adopted, with their hashes. Written and first run on the x86_64
    LMDE 7 laptop with podman 5.4.2: linux-x64 natively, linux-arm64 and
    linux-riscv64 under qemu-user emulation - the route dav1d-native-tools and
    llama-native-tools took. The two first-run fixes (both in
    container-build.sh's gate, neither in the build itself) are recorded in
    ../BUILD-PROVENANCE.txt. <<<

WHAT THIS IS
--------------------------------------------------------------------------------
Everything needed to build the three Linux SDL3 native libraries this package
ships, from the SDL snapshot vendored in ../SDL/. Each build is verified before
it is allowed to be adopted.

The build reaches nothing outside this repository. It literally cannot: the
compile runs in a container started with `--network none`, and the first thing
container-build.sh prints is the proof that the container has no network
interface but loopback. The source it compiles and the smoke test it runs are
files in this repository.

NOTHING HERE INSTALLS ANYTHING ON YOUR MACHINE. Every script checks what it
needs, and if something is missing it names it, prints the command that installs
it, and stops. Installing is your decision.


================================================================================
PREREQUISITES  (the complete list - one package, two if emulating)
================================================================================
  1. A container engine - podman (preferred) or docker.

       sudo apt install podman

     Verify:       podman --version

  2. ONLY IF building a foreign architecture on this host (arm64 or riscv64 on
     an x86_64 machine): qemu user-mode emulation and its binfmt registrations.

       sudo apt install qemu-user-static binfmt-support

     Verify:       ls /proc/sys/fs/binfmt_misc | grep qemu
     Alternative that installs nothing permanently:
       sudo podman run --rm --privileged \
            docker.io/multiarch/qemu-user-static --reset -p yes

  3. Disk: about 2.5 GB per architecture for the base image plus its derived
     image, and about 600 MB of build tree per run (inside the container's
     /tmp, discarded when it exits).

  NOT REQUIRED ON THE HOST, AND DELIBERATELY SO: cmake, ninja, gcc, the X11 /
  Wayland / audio development headers, any cross-compiler. They live inside the
  container images, at pinned versions, so the build does not vary with
  whatever the workstation happens to have installed this year.


================================================================================
THE IMAGES, AND WHY THEY ARE PINNED BY DIGEST
================================================================================
  RID             base image                           glibc floor  compiler
  --------------  -----------------------------------  -----------  ---------
  linux-x64       quay.io/pypa/manylinux_2_28_x86_64    2.28         gcc 14.2
  linux-arm64     quay.io/pypa/manylinux_2_28_aarch64   2.28         gcc 14.2
  linux-riscv64   quay.io/pypa/manylinux_2_39_riscv64   2.39         gcc 14.3

WHY A CONTAINER, EVEN ON A NATIVE MACHINE. glibc symbol versioning is
forward-only: a binary compiled against the glibc on a current desktop distro
refuses to load on anything older. Building on the workstation would quietly
restrict the package to the newest distributions, and the failure would only
appear on a user's machine. The manylinux images are old userlands with modern
compilers, which is exactly the tool for this. The glibc number in the image
name IS the compatibility floor being chosen.

riscv64 has no older manylinux than 2_39, so its floor is glibc 2.39 - Debian 13
/ Ubuntu 24.04 and newer. In practice every riscv64 distribution anyone runs is
newer than that.

WHY DIGESTS. pins.env records a dated tag AND a sha256 digest for each image,
and the Containerfiles resolve the digest. A tag can be moved; a digest cannot.
The three digests are the same ones CodeBrix.VideoPlayback.Dav1d,
CodeBrix.Ollama and CodeBrix.Audio pin, so every CodeBrix Linux native comes
from one base userland.

THE IMAGES ARE THE "INSTALLED TOOLS" EXCEPTION TO THE RULE. Pulling a base image
and building the derived image are the only things the Linux route fetches from
outside the repository - and they are a compiler and headers, not SDL source.
For the day the images are gone, see THE BARE-HOST ROUTE at the end of this file.


================================================================================
THE DERIVED IMAGE - THE "INSTALL THE TOOLS" STEP
================================================================================
Containerfile.<arch> adds to the base image, and nothing else:
  * cmake and ninja at the versions pinned in pins.env (pip wheels from the
    image's own CPython);
  * file, xz, patch and pkg-config for the gate and the patch step;
  * SDL's backend -devel HEADER packages from the image's own dnf repositories.

    Containerfile.x86_64    -> codebrix-sdl3-build-x86_64
    Containerfile.aarch64   -> codebrix-sdl3-build-aarch64
    Containerfile.riscv64   -> codebrix-sdl3-build-riscv64

WHY HEADERS. SDL is configured with SDL_DEPS_SHARED=ON: it dlopen()s libX11,
libwayland-client, libxkbcommon, libdecor, libasound, libpulse, libpipewire,
libudev, libdbus, libusb and the rest at RUN time on the user's machine, and
links none of them - the gate proves the shipped .so needs nothing beyond
glibc. But CMake can only switch a backend ON if it finds that backend's
headers (and the soname to dlopen) at configure time; a missing -devel package
silently turns the backend off. pins.env splits them into:

  SDL_DEVEL_REQUIRED  X11 + the extensions SDL uses, xkbcommon, Wayland, GL/EGL,
                      ALSA, PulseAudio, D-Bus, udev. A missing one fails the
                      image build.
  SDL_DEVEL_OPTIONAL  XScrnSaver, XTest, wayland-protocols, libdecor, gbm, drm,
                      PipeWire, IBus, libusb, JACK, sndio, fribidi, libthai,
                      liburing. Installed when the image's repositories carry
                      them; which ones were found is written into the image
                      (/usr/local/share/codebrix-sdl3-build/packages.txt) and
                      copied into every BUILD-INFO.txt.

The CMake feature summary in BUILD-INFO.txt ("Enabled backends") is the final
word on what was compiled in; the smoke test then prints the video, audio and
render drivers the built library reports at run time.

KNOWN BACKEND DIFFERENCES BETWEEN THE IMAGES - the AlmaLinux 8 repositories
(x86_64, aarch64) are older than SDL wants for four optional backends:
  * libdecor   - not packaged for EL8 at all. Solved by VENDORING its public
                 header (libdecor 0.2.2, MIT; Jeremy's ruling 2026-10-01):
                 vendored-headers/libdecor-0/ holds libdecor.h, unmodified, a
                 pkg-config stub and UPSTREAM.txt. pins.env
                 SDL_VENDORED_PKGCONFIG_<ARCH> puts it on PKG_CONFIG_PATH for
                 x64 and arm64, and -DDECOR_0_LIB=libdecor-0.so.0 gives SDL the
                 soname to dlopen(). Only the header is used - no libdecor
                 library is linked, and the gate proves libdecor is not in
                 NEEDED. So libdecor is ON for all three Linux RIDs: SDL windows
                 get client-side decorations on GNOME / Weston Wayland whenever
                 the user's machine has libdecor-0.so.0.
  * PipeWire   - EL8 ships libpipewire 0.3.6; SDL requires >= 0.3.44. Left OFF
                 (ruling 2026-10-01): audio on a PipeWire desktop goes through
                 its PulseAudio layer (pipewire-pulse) or ALSA, which every
                 PipeWire desktop provides.
  * sndio      - not packaged (it matters on the BSDs, rarely on Linux). OFF.
  * liburing   - EL8's liburing 1.0.7 has no liburing-ffi; SDL's async I/O
                 then uses its thread-pool implementation.
The Rocky Linux 10 riscv64 image is the other way round: it HAS libdecor
(libdecor-devel 0.2.2 - the same version as the vendored header), PipeWire 1.x
and liburing, but RHEL 10 dropped libXScrnSaver-devel, and SDL treats a
wanted-but-missing X11 extension as a configure ERROR. pins.env therefore
passes -DSDL_X11_XSCRNSAVER=OFF for riscv64 only (SDL_CMAKE_OPTIONS_RISCV64):
on X11, SDL_DisableScreenSaver() then works only through the D-Bus screensaver
inhibit, which current desktops provide. ../BUILD-PROVENANCE.txt records
exactly what each RID got - recorded facts, not silent variation - and gate
check 9 fails a build in which any of the must-have backends went missing.

Each Containerfile ends by PROVING its toolchain: it prints the pkg-config
versions of the core backend modules and compiles and runs a C11 program that
includes the X11 and Wayland client headers.

To force an image rebuild:      FORCE_IMAGE_REBUILD=1 ./build.sh


================================================================================
USAGE
================================================================================
    cd sdl3-native-tools/linux
    ./build.sh                  # all three RIDs
    ./build.sh x64              # or arm64 / riscv64

  Environment variables:
    CONTAINER_ENGINE=docker ./build.sh          force an engine
    FORCE_IMAGE_REBUILD=1 ./build.sh            rebuild the derived image first

  Timings: recorded per RID in ../BUILD-PROVENANCE.txt (2026-10-01, 24-core
  x86_64 laptop). linux-x64 builds in under half a minute; arm64 and riscv64
  under qemu-user emulation take many times longer, and their first image
  build (dnf under emulation) longer still.

  DO NOT RUN TWO COPIES OF build.sh AT ONCE. Both rewrite ../output/SHA256SUMS
  at the end.

  Output, git-ignored (see ../output/README.txt):
    ../output/<rid>/libSDL3.so              stripped - the file the package ships
    ../output/<rid>/unstripped/libSDL3.so   the pre-strip twin (debug info), for
                                            crash triage; never shipped
    ../output/<rid>/LICENSE-SDL3.txt        SDL's LICENSE.txt, verbatim
    ../output/<rid>/BUILD-INFO.txt          toolchain, pins, -devel packages,
                                            enabled backends, sizes, sha256,
                                            build-id, glibc floor, smoke test
    ../output/<rid>/cmake-summary.txt       SDL's own configure summary
    ../output/<rid>/cmake-configure.log     the whole configure log
    ../output/<rid>/smoke-test              the gate program that ran
    ../output/<rid>/SHA256SUMS.txt          that RID's files
    ../output/SHA256SUMS                    every library, one line each


================================================================================
THE BUILD, IN ONE PARAGRAPH
================================================================================
container-build.sh copies ../SDL to scratch, applies any patches from ../patches
(none), and configures SDL's own CMakeLists.txt with the options in pins.env: -G
Ninja, Release, SDL_SHARED=ON, SDL_STATIC=OFF, no test library, tests or
examples, SDL_INSTALL=OFF, SDL_DEPS_SHARED=ON, SDL_RPATH=OFF, and SDL_REVISION
pinned to the string ppy's binaries of this commit carry (the scratch copy has
no .git for SDL to describe), plus the per-architecture SDL_CMAKE_OPTIONS_<ARCH>
(x64 and arm64: -DDECOR_0_LIB=libdecor-0.so.0 with vendored-headers/libdecor-0
on PKG_CONFIG_PATH; riscv64: -DSDL_X11_XSCRNSAVER=OFF). These follow
ppy/SDL3-CS's CI for the same commit (External/build.sh +
.github/workflows/build.yml: -GNinja, Release, SDL_SHARED=ON, SDL_STATIC=OFF);
the additions are the ones a container build and this gate need. CMAKE_C_FLAGS
adds -g (debug info for the unstripped twin; no effect on code generation) and
-ffile-prefix-map for the source, build and /work paths; the link adds
--build-id=sha1. The result, libSDL3.so.0.5.0, is collected as ONE regular file
named libSDL3.so - the unversioned name DllImport("SDL3") probes - with its
SONAME libSDL3.so.0 kept as built, and stripped with --strip-unneeded.


================================================================================
THE VERIFICATION GATE
================================================================================
A build that fails ANY of these exits non-zero and must not be adopted. (The
smoke test is item 8 but runs before item 9; both always run.)

  1. ELF class and machine - ELF64 and x86-64 / AArch64 / RISC-V to match the
     RID (readelf -h). Catches the wrong file under the wrong RID.
  2. SONAME - exactly libSDL3.so.0.
  3. No RPATH or RUNPATH (the library lands in somebody else's application
     folder), and no TEXTREL.
  4. Required exports - the REQUIRED_SYMBOLS in pins.env (SDL_Init,
     SDL_GetVersion, SDL_CreateWindow, SDL_CreateRenderer, SDL_SetHint, ...);
     the total SDL_* export count is recorded.
  5. Dependencies - NEEDED must be a subset of ALLOWED_DEPS in pins.env
     (libc / libm / libpthread / libdl / librt and the dynamic loader). Any
     X11, Wayland, audio or udev library here would mean SDL_DEPS_SHARED did
     not take. `ldd -r` must report no undefined symbols.
  6. glibc floor - the highest GLIBC_x.y symbol version referenced, which IS
     the oldest system the binary loads on, CHECKED against pins.env: <= 2.28
     for x64 and arm64, <= 2.39 for riscv64.
  7. Build-id - the stripped file and its unstripped twin carry the same GNU
     build-id (the link between a crash dump and the twin's symbols).
  8. dlopen smoke test - ../smoke-test.c, compiled in the container, loads the
     STAGED (stripped) library the way .NET does, resolves 24 entry points,
     checks SDL_GetVersion() == 3005000, prints the revision and every compiled-
     in video / audio / render driver, sets SDL_VIDEO_DRIVER=dummy,
     SDL_Init(VIDEO), creates a hidden window and a renderer, clears to a known
     colour and reads a pixel back, then tears everything down and SDL_Quit()s.
     Under qemu this really executes the foreign-architecture code.
  9. Must-have backends - every soname in REQUIRED_DLOPEN_SONAMES (pins.env:
     libX11, libwayland-client, libdecor-0, libxkbcommon, libEGL, libasound,
     libpulse, libudev, libdbus-1) must appear in the binary as a dlopen()
     target. Catches a backend CMake silently switched off because a header
     went missing from an image. The full list of dlopen() sonames is recorded
     in BUILD-INFO.txt.


================================================================================
TROUBLESHOOTING
================================================================================
"neither podman nor docker found"
    Install one (see PREREQUISITES). The script will not install it for you.

"exec format error" / every command in the container dies immediately
    You are building a foreign architecture and the binfmt handler for it is not
    registered. See PREREQUISITES item 2 - or build on the native machine.

Image pull fails / the tag no longer exists
    quay.io/pypa retires old dated tags. Pick a current tag from
    https://quay.io/organization/pypa, put it in pins.env WITH its digest, and
    say in the commit message which glibc floor that changes. If quay.io itself
    is gone, see THE BARE-HOST ROUTE.

cmake configure fails "Couldn't find dependency package for <X>"
    SDL wants a backend whose headers the image lacks, and that backend is one
    SDL refuses to drop silently. Either add the -devel package to the
    Containerfile, or switch the backend off for that architecture in
    SDL_CMAKE_OPTIONS_<ARCH> (pins.env) and record the consequence in
    ../BUILD-PROVENANCE.txt - as was done for riscv64's XSCRNSAVER on the
    first run, 2026-10-01.

The image build fails on a REQUIRED -devel package
    The base image's repositories no longer carry it (or renamed it). Find the
    new name with `dnf provides '*/<header>.h'` in the base image, change
    SDL_DEVEL_REQUIRED in pins.env (and the ARG default in the Containerfiles),
    and record the change in ../BUILD-PROVENANCE.txt.

"readelf: Warning: Gap in build notes detected"
    Harmless: the Red Hat toolchain's annobin plugin leaves build-attribute
    notes, and readelf warns (and exits 1) about them. container-build.sh
    tolerates it; this was the first-run gate fix of 2026-10-01.

The gate fails "missing exports" for every name
    SDL exports through a version script, so nm prints SDL_Init@@SDL3_0.0.0.
    The gate cuts the @-suffix off; if a future binutils prints differently,
    adjust the awk in step 5d. (The second first-run fix of 2026-10-01.)

The gate fails on an unexpected NEEDED library
    A backend was linked instead of dlopen()ed. Check SDL_DEPS_SHARED=ON and the
    matching SDL_<BACKEND>_SHARED line in output/<rid>/cmake-summary.txt.

"pins.env was not found" after a clone
    The repository-root .gitignore has a blanket '*.env' rule, and it also
    ignores directory names that occur inside the vendored SDL tree. Both are
    handled by the "!*" re-include at the top of ../.gitignore - do not delete
    that line. Check with:  git check-ignore -v sdl3-native-tools/linux/pins.env

Podman "permission denied" writing ../output/
    Rootless podman maps your user into the container and the :Z mount flag
    handles SELinux relabelling. On a system with an unusual security policy,
    try --userns=keep-id.


================================================================================
THE BARE-HOST ROUTE (no container - for the day the images are gone)
================================================================================
The rule this folder exists for is that the libraries can be rebuilt from this
repository alone, years from now. The container images are the one input that
comes from outside, so here is how to build WITHOUT them. The cost is the glibc
floor: a bare-host build's floor is the glibc of the machine that built it,
which must then be recorded in ../BUILD-PROVENANCE.txt as the compatibility
floor of that binary.

On a Debian-based machine of the target architecture, install the compiler, the
two build tools and the backend headers (the Debian names of the packages in
pins.env; this is the list ppy's CI uses on Ubuntu):

    sudo apt install build-essential cmake ninja-build pkg-config file \
        libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev \
        libxfixes-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
        wayland-protocols libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev \
        libgles2-mesa-dev libgbm-dev libdrm-dev libasound2-dev libpulse-dev \
        libpipewire-0.3-dev libjack-dev libsndio-dev libdbus-1-dev libudev-dev \
        libibus-1.0-dev libusb-1.0-0-dev libfribidi-dev libthai-dev

then run container-build.sh itself outside a container:

    cd sdl3-native-tools
    . linux/pins.env
    sudo ln -sfn "$PWD" /work        # container-build.sh reads /work
    TARGET_RID=linux-x64 GLIBC_MAX=<this machine's glibc, e.g. 2.41> \
    SDL_DIR=$SDL_DIR SDL_VERSION=$SDL_VERSION SDL_COMMIT=$SDL_COMMIT \
    SDL_COMMIT_SUBJECT="$SDL_COMMIT_SUBJECT" SDL_SONAME=$SDL_SONAME \
    SDL_REVISION_STRING=$SDL_REVISION_STRING SDL_VERSION_NUM=$SDL_VERSION_NUM \
    SDL_CMAKE_OPTIONS="$SDL_CMAKE_OPTIONS" LIB_NAME=$LIB_NAME \
    LICENSE_FILE_NAME=$LICENSE_FILE_NAME CMAKE_VERSION=$CMAKE_VERSION \
    NINJA_VERSION=$NINJA_VERSION ALLOWED_DEPS="$ALLOWED_DEPS" \
    REQUIRED_SYMBOLS="$REQUIRED_SYMBOLS" \
    REQUIRED_DLOPEN_SONAMES="$REQUIRED_DLOPEN_SONAMES" \
    SDL_CMAKE_OPTIONS_ARCH="$SDL_CMAKE_OPTIONS_X64" \
    SDL_VENDORED_PKGCONFIG="" \
    bash linux/container-build.sh

(On Debian the distro's libdecor-0-dev provides libdecor, so the vendored
header is not needed there - leave SDL_VENDORED_PKGCONFIG empty; the
-DDECOR_0_LIB pin in SDL_CMAKE_OPTIONS_<ARCH> is harmless either way.)

(It will warn that the host has network interfaces - the build still fetches
nothing - and the glibc-floor check passes or fails against the GLIBC_MAX you
give it.)

The result is a legitimate build - same source, same options, same gate - whose
only difference from the container route is the glibc floor (and possibly the
set of backends, which BUILD-INFO.txt records), and that is why both must be
written down with it.


================================================================================
ADOPTING A BUILT BINARY INTO THE PACKAGE
================================================================================
  1. Read ../output/<rid>/BUILD-INFO.txt and satisfy yourself the build is the
     one you think it is: SDL commit, image digest, glibc floor, enabled
     backends, the smoke-test lines.

  2. Copy the library and its licence into the package's native tree:

       cp ../output/<rid>/libSDL3.so       ../../native_libraries/<rid>/
       cp ../output/<rid>/LICENSE-SDL3.txt ../../native_libraries/<rid>/

     <rid> is linux-x64, linux-arm64 or linux-riscv64. The file must keep the
     name libSDL3.so - DllImport("SDL3") probes exactly that name. The licence
     copy is not optional: the zlib licence's notice travels with the binary,
     and the package packs it into runtimes/<rid>/native/ beside it.

  3. Update ../../native_libraries/<rid>/libSDL3.so.provenance.txt from
     BUILD-INFO.txt (it is not packed; it is the in-repo record beside the
     binary).

  4. Store the unstripped twin in the SAME change:

       mkdir -p ../unstripped/<rid>
       cp ../output/<rid>/unstripped/libSDL3.so ../unstripped/<rid>/
       ( cd ../unstripped && sha256sum <rid>/libSDL3.so ) # replace that RID's
                                                          # line in SHA256SUMS

     See ../unstripped/README.txt for the rule and the build-id check.

  5. Record the build in ../BUILD-PROVENANCE.txt - copy the values straight out
     of BUILD-INFO.txt.

  6. Run the managed test suite before publishing.


================================================================================
FILES
================================================================================
  README.txt              this document
  pins.env                every version / digest / option / package pin
                          (edit here only)
  build.sh                host entry point: images, emulation check,
                          orchestration
  container-build.sh      the build and the gate; runs inside the container
  Containerfile.x86_64    derived build image for linux-x64
  Containerfile.aarch64   derived build image for linux-arm64
  Containerfile.riscv64   derived build image for linux-riscv64
  vendored-headers/libdecor-0/
                          libdecor 0.2.2's libdecor.h (unmodified, MIT),
                          libdecor-0.pc (our pkg-config stub), UPSTREAM.txt -
                          used by the x64 and arm64 builds only
  ../smoke-test.c         the dlopen verification program, shared by all
                          platforms
  ../output/              build results (git-ignored)
================================================================================
