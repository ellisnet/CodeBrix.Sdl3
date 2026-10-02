================================================================================
Android SDL3 - libSDL3.so for ARM64 and x64 (Android 13/API 33 minimum),
and SDL3AndroidBridge.jar
================================================================================

The source is ../SDL, the same unmodified vendored snapshot as every other build
(SDL commit a8591d943b7079b17fdd018dc04ec9c71dc94ae4, version header 3.5.0,
zlib). No patches are required. Nothing is downloaded during a build, and
nothing in a dotnet build invokes these scripts.

  pins.json      NDK revision, API floor, cmake/ninja minimums, SDL commit, the
                 allowed NEEDED list, the required exports, and the jar pins
  build.py       builds both ABIs (or one) and runs the gates
  verify.py      the static gates, also usable on its own against any libSDL3.so
  build-jar.sh   builds SDL3AndroidBridge.jar from ../SDL/android-project

OUTPUT
------
  android-arm64 -> ABI arm64-v8a, aarch64-linux-android33-clang
  android-x64   -> ABI x86_64,    x86_64-linux-android33-clang
  (android)     -> SDL3AndroidBridge.jar, the org.libsdl.app Java classes

Both libraries are ELF64 libSDL3.so with SONAME libSDL3.so (unversioned - the
name DllImport("SDL3") probes) and API 33 in their Android ELF note. They NEED
only Android system libraries (libm libdl liblog libandroid libOpenSLES
libGLESv1_CM libGLESv2 libc); AAudio, Vulkan, EGL, Camera2, MediaNDK and the
OpenXR loader are dlopen()ed at run time. libc++ is linked statically (the NDK
default c++_static; SDL's only C++ file is hidapi's Android backend), so there
is no libc++_shared.so to ship.

Enabled backends (SDL's CMake summary, both ABIs):
  Video: android dummy offscreen      Render: gpu ogl_es ogl_es2 vulkan
  GPU:   openxr vulkan                Audio:  aaudio disk dummy opensles
  Joystick: android hidapi virtual    Camera: android dummy

Both link with -z max-page-size=16384 and -z common-page-size=16384, so they
load on 4 KB and 16 KB page-size devices; the application's other native
libraries and its APK packaging must also support the device's page size. See:
  https://developer.android.com/guide/practices/page-sizes

THE JAVA BRIDGE
---------------
On Android SDL is half native, half Java: SDLActivity, SDLSurface,
SDLAudioManager, SDLControllerManager, HIDDeviceManager and friends live in
../SDL/android-project/app/src/main/java/org/libsdl/app/, and libSDL3.so's
JNI_OnLoad registers the native methods they declare. The jar and both .so
files MUST come from the same SDL commit; verify.py checks that every `native`
method in those Java sources (66 of them) is named in the library's JNI
registration tables, so a mismatched pair fails the gate.

build-jar.sh is ppy/SDL3-CS's five-line recipe made reproducible:
  javac --release 11 -encoding utf8 -classpath <android.jar> org/libsdl/app/*.java
  jar --create --date=2026-07-19T00:00:00Z <sorted class list>
--release 11 gives class file version 55, what SDL's own Gradle project targets.
-DSDL_ANDROID_JAR=OFF keeps SDL's CMake from trying to build its own jar.

TOOLS (install separately, before the offline build)
----------------------------------------------------
Linux x64 (or macOS) with the Android NDK host toolchain. The shipped files were
built on Linux x64 (LMDE 7 / Debian 13).

  * Python 3.9+; Python 3.13 was used.
  * NDK 30.0.16248370 (r30), pinned in pins.json. Install the Android SDK
    command-line tools, then (adjust the sdkmanager path to the SDK install):
      sdkmanager --install 'ndk;30.0.16248370'
    Accept the SDK/NDK licences during tool installation. build.py never
    installs anything and refuses any other NDK revision.
  * cmake >= 3.16 (SDL's cmake_minimum_required) and ninja >= 1.10. cmake 4.4.3
    and ninja 1.13.2 were used (from the container image, below). On Debian:
      sudo apt-get install cmake ninja-build
    or in a Python venv:
      python3 -m venv ~/.venvs/codebrix-sdl3-android
      ~/.venvs/codebrix-sdl3-android/bin/python -m pip install cmake==4.4.3 ninja==1.13.2
      export PATH="$HOME/.venvs/codebrix-sdl3-android/bin:$PATH"
  * patch, only if ../patches ever holds *.patch files.
  * For the jar: a JDK with javac and jar, 19 or newer (`jar --date` needs 19;
    javac --release 11 needs 11). JDK 25 is pinned for byte-identical output
    (pins.json jar.jdk_major); another JDK prints a NOTE and still works. Debian:
      sudo apt-get install openjdk-25-jdk-headless
  * An Android SDK platform for android.jar. pins.json names android-37.2 (the
    highest installed when the shipped jar was built); any of android-36,
    android-37.0 and android-37.2 was proven to give the identical jar:
      sdkmanager --install 'platforms;android-37.2'
    Or pass a path: ./build-jar.sh /path/to/android.jar
  * adb from Android SDK platform-tools, only for the device run (below).

BUILD (from the repository root)
--------------------------------
  python3 sdl3-native-tools/android/build.py \
    --ndk "$HOME/Android/Sdk/ndk/30.0.16248370"
  sdl3-native-tools/android/build-jar.sh

Use --arch arm64 or --arch x64 to build just one, --jobs to control parallel
compilation (default: all cores). CODEBRIX_ANDROID_NDK can supply the NDK path
instead of --ndk. Do not use Python -O: assertions implement the gates, and
optimized Python is explicitly rejected.

build.py copies ../SDL to ../output/build-scratch/android-<arch> (a FIXED path,
removed afterwards), applies ../patches, configures with the NDK's
android.toolchain.cmake and these options:

  -G Ninja -DANDROID_ABI=<abi> -DANDROID_PLATFORM=33
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF
  -DSDL_EXAMPLES=OFF -DSDL_INSTALL=OFF -DSDL_ANDROID_JAR=OFF
  -DSDL_REVISION=SDL-3.5.0-a8591d9
  C/C++ flags : -g, -ffile-prefix-map for the scratch source, build and NDK
                folders, -fdebug-compilation-dir=build (no build path in the
                binaries or their debug info)
  link flags  : -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384
                -Wl,--build-id=sha1

then strips with llvm-strip --strip-unneeded and cross-compiles ../smoke-test.c
for the ABI. The API floor is 33, NOT the 21 that SDL's Gradle project and ppy's
CI use: 33 is the CodeBrix Android floor (dav1d, Audio.Android, and the
package's net10.0-android SupportedOSPlatformVersion).

Each ../output/android-<arch>/ gets libSDL3.so, unstripped/libSDL3.so (with
DWARF), LICENSE-SDL3.txt (SDL's LICENSE.txt verbatim), smoke-test,
cmake-summary.txt, BUILD-INFO.json (hashes, build-id, tool versions, flags, gate
results) and SHA256SUMS.txt. build-jar.sh writes ../output/android/ with
SDL3AndroidBridge.jar, classes.txt, LICENSE-SDL3.txt and BUILD-INFO.txt.

WHAT THE GATES CHECK (verify.py, run on BOTH twins by build.py)
--------------------------------------------------------------
  * ELF64 little-endian shared object, right machine (AArch64 / x86-64)
  * Android ELF note API == 33
  * every PT_LOAD aligned to >= 16 KB, offset/address congruent; no
    writable+executable segment
  * SONAME exactly libSDL3.so
  * NEEDED only libraries in pins.json "allowed_needed" (NDK system libs)
  * no GLIBC_ version requirement; no TEXTREL, RPATH or RUNPATH
  * the required exports (SDL_Init, SDL_GetVersion, SDL_CreateWindow and 13
    more, plus JNI_OnLoad)
  * every Java `native` method of the bridge sources is registered
  * a GNU build-id, equal in the stripped and unstripped twins

To inspect another build (for example a reference library built for API 21):
  python3 verify.py <libSDL3.so> --arch arm64 \
    --toolchain "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin" --expect-api 21

RUNTIME TESTS: UNRUN
--------------------
No Android device or emulator was used for the shipped files. The gates are
static. smoke-test is cross-compiled so it can be pushed and run by hand:
  adb -s SERIAL push output/android-arm64/libSDL3.so output/android-arm64/smoke-test /data/local/tmp/
  adb -s SERIAL shell 'cd /data/local/tmp && ./smoke-test ./libSDL3.so'
SDL_GetVersion, the revision and the driver lists should work (not yet tried
on a device). SDL's video
subsystem on Android normally runs inside an SDLActivity (JNI), so a bare
executable's dummy-driver window step may not be representative - the real
test is an app that uses the jar and the library together.

OFFLINE CONTAINER ROUTE USED FOR THE SHIPPED LIBRARIES
------------------------------------------------------
The host that built them had no ninja, so the libraries were built in the Linux
tool image (../linux/Containerfile.x86_64 on the digest-pinned manylinux base in
../linux/pins.env; it supplies cmake 4.4.3, ninja 1.13.2 and Python 3.13).
Build that image once as described in ../linux/README.txt. With it cached:

  podman run --rm --network none \
    -v "$PWD:/repo:Z" \
    -v "$HOME/Android/Sdk/ndk/30.0.16248370:/ndk:ro" \
    localhost/codebrix-sdl3-build-x86_64:latest \
    /opt/python/cp313-cp313/bin/python /repo/sdl3-native-tools/android/build.py --ndk /ndk

(run from the repository root). The compiler and sysroot are still the NDK's;
the container only provides cmake, ninja and Python, and --network none proves
nothing is fetched. The jar was built directly on the host (javac + jar only).

REPRODUCIBILITY
---------------
Both libraries were built three times from scratch (with two different scratch
paths) and came out byte-identical, stripped and unstripped. The jar was built
five times with JDK 25 against three different android.jar files: one sha256.
A different JDK gives the same class set but different bytes. Hashes, sizes and
tool versions: ../BUILD-PROVENANCE.txt and the .provenance.txt beside each
shipped file in ../../native_libraries/.

ADOPTION
--------
After the gates pass, copy each output library and LICENSE-SDL3.txt to
../../native_libraries/android-<arch>/, the jar to
../../native_libraries/android/, and each unstripped twin to
../unstripped/android-<arch>/. Update ../unstripped/SHA256SUMS, the
.provenance.txt files and ../BUILD-PROVENANCE.txt in the same change. Never
commit a library without its unstripped twin from the SAME build.
================================================================================
