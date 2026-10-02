sdl3-native-tools/output - build results (git-ignored, except this file)
================================================================================
Every build script in sdl3-native-tools writes here, one folder per runtime
identifier:

  <rid>/libSDL3.so | SDL3.dll | libSDL3.dylib   the stripped library - the file
                                                the package ships
  <rid>/unstripped/                             the pre-strip twin of the same build
  <rid>/LICENSE-SDL3.txt                        SDL's LICENSE.txt (zlib), verbatim
  <rid>/BUILD-INFO.txt                          toolchain, pins, enabled backends,
                                                sizes, sha256, build-id, floors,
                                                smoke-test output
  <rid>/cmake-summary.txt                       SDL's own end-of-configure summary
  <rid>/smoke-test                              the gate program that was run
  <rid>/SHA256SUMS.txt                          checksums of that RID's files
  SHA256SUMS                                    every built library, one line each

Everything here is DISPOSABLE. Nothing in it is committed, and nothing here is
an input to any build or pack step. The copies that are meant to last are the
ones adopted into ../../native_libraries/<rid>/ and the unstripped twins in
../unstripped/<rid>/ - see ../README.txt.
