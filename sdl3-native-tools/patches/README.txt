sdl3-native-tools/patches - local changes to the vendored SDL source
================================================================================
EMPTY as of 2026-10-01: no build on any platform needs a change to ../SDL/.

If one ever does, it goes here as <NN>-<what>.patch (unified diff, -p1 relative
to the SDL/ folder), and every build script applies it, in name order, to a
SCRATCH COPY of ../SDL/ at build time - never to ../SDL/ itself, which stays an
unmodified, verifiable upstream snapshot (see ../SDL/UPSTREAM.txt). A patch that
does not apply cleanly fails the build; patches are never applied best-effort.
Record each patch, and why it exists, in ../BUILD-PROVENANCE.txt.
