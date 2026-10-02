================================================================================
EXTRAS-README: CodeBrix.Sdl3
Samples, tools and other content in this repository that is not part of a NuGet
package
================================================================================

This repository ships no sample applications or demos. Exactly one project is
packable - src/CodeBrix.Sdl3 - and everything else listed below exists to
build, regenerate, test or document it. None of it is included in the
CodeBrix.Sdl3.ZlibLicenseForever package except the committed native binaries
(and LICENSE-SDL3.txt beside each), which the package redistributes.

For runnable, compilable usage of the library, read the test project: the
"WORKING EXAMPLES ON GITHUB" section of AGENT-README.txt maps
each feature area to the test file that exercises it.


TEST PROJECT
============
    tests/CodeBrix.Sdl3.Tests/

xUnit v3; run it as described in MAINTAINER-README.txt (TESTING). It copies the
committed natives into its output in the package layout and skips, with the
reason, the tests whose native library for the current RID is not present.


SOURCE GENERATOR
================
    src/CodeBrix.Sdl3.SourceGeneration/

A Roslyn source generator consumed by the library as an analyzer while it
compiles. It writes the friendly overloads (Utf8String for `const char *`
parameters, string? for `char *` results). Not packed - its output is part of
CodeBrix.Sdl3.dll. See MAINTAINER-README.txt (BUILDING).


BINDING GENERATION TOOL
=======================
    tools/sdl3_binding_generation/

Regenerates src/CodeBrix.Sdl3/Bindings/ClangSharp/*.g.cs from the SDL3 headers
in sdl3-native-tools/SDL/include, using the ClangSharpPInvokeGenerator dotnet
tool at the version pinned in .config/dotnet-tools.json, the ClangSharp
response files in rsp/, the SDL licence header in SDL-license-header.txt and
the non-Windows process.h shim in include/. The script post-processes every
emitted file into the family source layout, so a regeneration reproduces the
committed shape. Run by hand only; nothing in a dotnet build calls it.
README.txt in that folder has the prerequisites and the exact steps.


NATIVE LIBRARIES
================
    native_libraries/<rid>/          SDL3.dll | libSDL3.dylib | libSDL3.so,
                                     LICENSE-SDL3.txt (SDL's LICENSE.txt,
                                     verbatim) and <binary>.provenance.txt
    native_libraries/android/        SDL3AndroidBridge.jar + its provenance

The committed binaries the library csproj packs under runtimes/<rid>/native/
(the jar becomes an EmbeddedJar of the net10.0-android build). The nine RIDs:
win-x64, win-arm64, osx-x64, osx-arm64, linux-x64, linux-arm64, linux-riscv64,
android-x64, android-arm64. Each .provenance.txt records how that file was
produced (built here from the vendored SDL source, or adopted from a recorded
upstream build of the same SDL commit), with its SHA-256 and size. The
provenance files are not packed.


SDL3 NATIVE BUILD TOOLS
=======================
    sdl3-native-tools/

Everything needed to rebuild every native library and the Java bridge from
source, without any other repository:
  SDL/            the vendored, UNMODIFIED SDL source snapshot at the commit
                  the bindings were generated from (UPSTREAM.txt records the
                  URL, commit, copy command and licence)
  linux/          container builds (podman, --network none, manylinux images)
                  of linux-x64, linux-arm64 and linux-riscv64, with verification
                  (ELF class, SONAME, NEEDED, glibc floor, exports, smoke test)
  android/        the NDK build of android-x64 / android-arm64 and the javac
                  build of SDL3AndroidBridge.jar from SDL's android-project
  windows/        win-x64 / win-arm64 build scripts (MSVC, static CRT)
  macos/          osx-arm64 / osx-x64 build scripts
  patches/        build patches, if any (empty means unmodified source)
  unstripped/     the pre-strip twins of the Linux binaries + SHA256SUMS
  BUILD-PROVENANCE.txt   the full per-RID build record
  README.txt      the folder map, prerequisites and the rebuild policy

Build tools (cmake, ninja, compilers, podman, the Android NDK, MSVC, Xcode) are
NOT vendored; each platform README names them with versions. sdl3-native-tools/
README.txt and the per-platform READMEs are authoritative for that folder.
