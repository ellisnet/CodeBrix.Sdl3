================================================================================
sdl3-native-tools/unstripped - the durable home for pre-strip binaries
================================================================================

UNLIKE output/, THIS FOLDER IS COMMITTED. It exists so the unstripped mate of
every SDL3 binary BUILT HERE and shipped in the package survives the machine it
was built on (../output/ is git-ignored and disposable). These files are needed
for crash triage: a stripped release binary in a crash dump can only be
symbolised from its unstripped twin. Nothing here is shipped, and nothing here
is an input to any build or pack step.

One folder per runtime identifier, mirroring ../../native_libraries/<rid>/:

  <rid>/libSDL3.so        the pre-strip ELF (Linux, Android), with DWARF debug
                          info (both builds compile with -g; strip removes it)

The twins are stored RAW, not compressed: the Linux ones are 20-25 MB and the
Android ones about 11 MB, well under GitHub's per-file limit.

Verify any file two ways:

  1. sha256 - `sha256sum -c SHA256SUMS` from this folder; the same value is the
     "SHA256 unstripped" line of that RID's entry in ../BUILD-PROVENANCE.txt and
     of ../../native_libraries/<rid>/libSDL3.so.provenance.txt.
  2. the GNU build-id equals the shipped binary's -
        readelf -n <rid>/libSDL3.so | grep 'Build ID'
        readelf -n ../../native_libraries/<rid>/libSDL3.so | grep 'Build ID'
     (readelf may also print "Gap in build notes" and exit 1 - harmless, see
     ../linux/README.txt, TROUBLESHOOTING. For Android, the NDK's
     llvm-readelf -n works as well as binutils readelf -n.)

STORED SO FAR (build-ids, each verified equal to its shipped twin's):

  linux-x64      b98b1577d53a87c9867e387c5ef1fdd2cf649dca   (verified 2026-10-01)
  linux-arm64    8e0ff562538a3f04b099d941e9edf13b69606509   (verified 2026-10-01)
  linux-riscv64  38ffc84a8bb11b9cabdae4206bd1a4abafd25baa   (verified 2026-10-01)
  android-arm64  434b17e6da9f987669cccb1f19de059b8b4b4add   (verified 2026-10-01)
  android-x64    c06c705695b78f6fc75122bbaa758b4a7b39445d   (verified 2026-10-01)

(linux-x64 and linux-arm64 were rebuilt the same day with the vendored libdecor
header; the twins and ids above are those rebuilds.)

ADOPTED, NOT BUILT HERE - nothing to store
--------------------------------------------------------------------------------
For the first published version the win-* and osx-* binaries are adopted from
ppy/SDL3-CS 2026.722.0 (see ../BUILD-PROVENANCE.txt). Their pre-strip twins
were never published, so there is nothing to keep here. When those RIDs are
rebuilt from ../SDL with the scripts in ../windows and ../macos, their twins
(.pdb, .dSYM) land here under the same rule.

THE RULE
--------------------------------------------------------------------------------
Whenever a newly built binary is adopted into native_libraries/<rid>/, its
unstripped mate from the same build lands here in the same change, and
SHA256SUMS is updated. A binary here that no longer matches the shipped one's
build-id is stale and must be replaced, never kept alongside.
================================================================================
