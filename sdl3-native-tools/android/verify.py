#!/usr/bin/env python3
"""Static gates for an Android libSDL3.so (no device needed; nothing is loaded on the build host).

    python3 verify.py <libSDL3.so> --arch arm64|x64 --toolchain <NDK>/toolchains/llvm/prebuilt/<host>/bin

Checks: ELF64 little-endian shared object for the right machine; Android ABI note == the pinned API
(33); every PT_LOAD aligned to >= 16 KB with offset/address congruent; no writable+executable segment;
SONAME exactly libSDL3.so; NEEDED only Android system libraries (pins.json "allowed_needed"); no
GLIBC_ version requirement; no TEXTREL / RPATH / RUNPATH; the required SDL exports plus JNI_OnLoad;
every `native` method declared by the Java bridge sources (../SDL/android-project) is named in the
library's JNI registration tables; a GNU build-id is present.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

if not __debug__:
    raise SystemExit("Run the Android build/verification tools without Python -O; their gates must stay enabled.")

TOOLS = Path(__file__).resolve().parents[1]
PINS = json.loads((TOOLS / "android/pins.json").read_text())
# arch -> (NDK triple cpu, ELF e_machine, Android ABI name)
ARCHITECTURES = {"arm64": ("aarch64", 183, "arm64-v8a"), "x64": ("x86_64", 62, "x86_64")}
JAVA_SOURCES = TOOLS / "SDL/android-project/app/src/main/java/org/libsdl/app"


def output(*args):
    return subprocess.check_output([str(arg) for arg in args], text=True)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def java_native_methods():
    """Names of every `native` method the bridge's Java sources declare."""
    names = set()
    for source in sorted(JAVA_SOURCES.glob("*.java")):
        text = re.sub(r"/\*.*?\*/|//[^\n]*", "", source.read_text(encoding="utf-8"), flags=re.S)
        names.update(re.findall(r"\bnative\b[^;{()=]*?\b(\w+)\s*\(", text))
    return names


def verify(library, arch, toolchain, expected_api=None):
    expected_api = PINS["api"] if expected_api is None else expected_api
    library = Path(library)
    data = library.read_bytes()
    assert data[:6] == b"\x7fELF\x02\x01", "Expected little-endian ELF64"
    assert struct.unpack_from("<H", data, 16)[0] == 3, "Expected a shared object (ET_DYN)"
    assert struct.unpack_from("<H", data, 18)[0] == ARCHITECTURES[arch][1], "Wrong architecture"
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phsize, phnum = struct.unpack_from("<HH", data, 54)
    alignments = []
    android_api = None
    ndk_note = None
    for index in range(phnum):
        kind, flags, offset, address, _, size, _, alignment = struct.unpack_from(
            "<IIQQQQQQ", data, phoff + index * phsize)
        if kind == 1:  # PT_LOAD
            assert alignment >= 16384 and alignment & (alignment - 1) == 0, f"Not 16 KB aligned: {alignment}"
            assert offset % 16384 == address % 16384, "Invalid load alignment"
            assert flags & 3 != 3, "Writable executable segment"
            alignments.append(alignment)
        if kind == 4:  # PT_NOTE
            cursor = offset
            while cursor + 12 <= offset + size:
                namesz, descsz, note_type = struct.unpack_from("<III", data, cursor)
                cursor += 12
                name = data[cursor:cursor + namesz].rstrip(b"\0")
                cursor += (namesz + 3) & ~3
                if name == b"Android" and note_type == 1 and descsz >= 4:
                    android_api = struct.unpack_from("<I", data, cursor)[0]
                    if descsz >= 4 + 64 + 64:
                        ndk_note = data[cursor + 4:cursor + 4 + 64].rstrip(b"\0").decode() + " / " + \
                            data[cursor + 68:cursor + 68 + 64].rstrip(b"\0").decode()
                cursor += (descsz + 3) & ~3
    assert alignments, "No load segments"
    assert android_api == expected_api, f"Expected API {expected_api}, got {android_api}"
    readelf = toolchain / "llvm-readelf"
    dynamic = output(readelf, "--dynamic", library)
    dependencies = re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic)
    assert dependencies and set(dependencies) <= set(PINS["allowed_needed"]), \
        f"Unexpected NEEDED: {sorted(set(dependencies) - set(PINS['allowed_needed']))}"
    assert "GLIBC_" not in output(readelf, "--version-info", library), "Desktop glibc dependency"
    assert not re.search(r"\((TEXTREL|RPATH|RUNPATH)\)", dynamic), "Text relocations or build-host paths"
    assert not re.search(r"\(FLAGS\).*TEXTREL", dynamic), "DF_TEXTREL set"
    assert re.search(r"\(SONAME\).*?\[libSDL3\.so\]", dynamic), "Wrong Android SONAME (want libSDL3.so)"
    nm = output(toolchain / "llvm-nm", "-D", "--defined-only", library)
    exports = set()
    for line in nm.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[1] in "TtWwVvDdBbRrIi":
            exports.add(parts[2].split("@")[0])
    required = set(PINS["required_exports"])
    assert required <= exports, f"Missing exports: {sorted(required - exports)}"
    sdl_exports = sorted(name for name in exports if name.startswith("SDL_"))
    natives = java_native_methods()
    assert natives, "No native methods found in the Java bridge sources"
    strings = set(re.findall(rb"[A-Za-z_][A-Za-z0-9_]{2,}", data))
    unregistered = sorted(name for name in natives if name.encode() not in strings)
    assert not unregistered, f"Java native methods with no JNI registration string: {unregistered}"
    notes = output(readelf, "--notes", library)
    build_id = re.search(r"Build ID: (\w+)", notes)
    assert build_id, "Missing build ID"
    return {"rid": "android-" + arch, "abi": ARCHITECTURES[arch][2], "file": library.name,
            "api": android_api, "ndk_note": ndk_note, "load_alignments": alignments,
            "soname": "libSDL3.so", "dependencies": dependencies,
            "exports_total": len(exports), "exports_sdl": len(sdl_exports),
            "required_exports": sorted(required), "java_native_methods_registered": len(natives),
            "build_id": build_id[1], "sha256": sha256(library), "bytes": len(data)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("library", type=Path)
    parser.add_argument("--arch", required=True, choices=ARCHITECTURES)
    parser.add_argument("--toolchain", type=Path, required=True, help="NDK prebuilt bin directory")
    parser.add_argument("--expect-api", type=int, default=None,
                        help="only for inspecting someone else's build (e.g. 21); the default is the pinned API")
    args = parser.parse_args()
    print(json.dumps(verify(args.library, args.arch, args.toolchain, args.expect_api), indent=2))
