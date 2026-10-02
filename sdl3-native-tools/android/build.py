#!/usr/bin/env python3
"""Build libSDL3.so for android-arm64 (arm64-v8a) and android-x64 (x86_64) from the vendored SDL source.

Never installs or downloads anything. Requires the pinned NDK (pins.json), cmake and ninja on PATH, and
Python 3.9+. See README.txt for the tools and for the offline container route used for the shipped files.

    python3 build.py --ndk ~/Android/Sdk/ndk/30.0.16248370 [--arch all|arm64|x64] [--jobs N]
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import time

from verify import ARCHITECTURES, PINS, TOOLS, output, sha256, verify


def run(*args, **kwargs):
    print("+", " ".join(str(arg) for arg in args), flush=True)
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def version_tuple(text):
    return tuple(int(part) for part in re.search(r"(\d+(?:\.\d+)+)", text)[1].split("."))


def check_tools(ndk):
    revision = re.search(r"Pkg.Revision\s*=\s*(\S+)", (ndk / "source.properties").read_text())[1]
    if revision != PINS["ndk"]:
        raise SystemExit(f"NDK {PINS['ndk']} is pinned; found {revision} at {ndk}")
    for tool in ("cmake", "ninja"):
        if shutil.which(tool) is None:
            raise SystemExit(f"{tool} is not on PATH - install it (README.txt, TOOLS); this script installs nothing")
    cmake = output("cmake", "--version").splitlines()[0].strip()
    ninja = output("ninja", "--version").strip()
    assert version_tuple(cmake) >= version_tuple(PINS["cmake_minimum"]), f"cmake too old: {cmake}"
    assert version_tuple(ninja) >= version_tuple(PINS["ninja_minimum"]), f"ninja too old: {ninja}"
    return revision, cmake, ninja


def build(arch, ndk, jobs, tools):
    revision, cmake, ninja = tools
    host = {"Linux": "linux-x86_64", "Darwin": "darwin-x86_64"}.get(platform.system())
    if host is None:
        raise SystemExit("Run on Linux or macOS (on Windows, use a Linux build machine or WSL).")
    toolchain = ndk / "toolchains/llvm/prebuilt" / host / "bin"
    cpu, _, abi = ARCHITECTURES[arch]
    api = PINS["api"]
    compiler = toolchain / f"{cpu}-linux-android{api}-clang"
    dest = TOOLS / "output" / ("android-" + arch)
    if dest.exists():
        shutil.rmtree(dest)
    (dest / "unstripped").mkdir(parents=True)
    started = time.monotonic()
    # A FIXED scratch path (not a random temp name), so the recorded flags are the same on every
    # run; the prefix maps below keep it out of the binaries either way.
    scratch = TOOLS / "output" / "build-scratch" / ("android-" + arch)
    if scratch.exists():
        shutil.rmtree(scratch)
    scratch.mkdir(parents=True)
    try:
        source, build_dir = scratch / "SDL", scratch / "build"
        # Keep the vendored upstream snapshot pristine; local patches, if any, apply to this copy.
        shutil.copytree(TOOLS / "SDL", source, symlinks=True)
        patches = sorted((TOOLS / "patches").glob("*.patch"))
        for patch in patches:
            run("patch", "-p1", "--forward", "--batch", "-i", patch, cwd=source)
        # Fixed names for every absolute path the compiler sees, so neither the scratch folder nor
        # the NDK's install location lands in the debug information of the unstripped twin.
        prefix_maps = [f"-ffile-prefix-map={source}=SDL", f"-ffile-prefix-map={build_dir}=build",
                       f"-ffile-prefix-map={ndk}=ndk", "-fdebug-compilation-dir=build"]
        compile_flags = " ".join(["-g", *prefix_maps])
        link_flags = "-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384 -Wl,--build-id=sha1"
        options = ["-G", "Ninja",
                   f"-DCMAKE_TOOLCHAIN_FILE={ndk}/build/cmake/android.toolchain.cmake",
                   f"-DANDROID_ABI={abi}", f"-DANDROID_PLATFORM={api}",
                   "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
                   "-DSDL_SHARED=ON", "-DSDL_STATIC=OFF", "-DSDL_TEST_LIBRARY=OFF", "-DSDL_TESTS=OFF",
                   "-DSDL_EXAMPLES=OFF", "-DSDL_INSTALL=OFF", "-DSDL_ANDROID_JAR=OFF",
                   f"-DSDL_REVISION={PINS['sdl_revision']}"]
        flag_options = [f"-DCMAKE_C_FLAGS={compile_flags}", f"-DCMAKE_CXX_FLAGS={compile_flags}",
                        f"-DCMAKE_SHARED_LINKER_FLAGS={link_flags}"]
        configure = subprocess.run(["cmake", "-S", str(source), "-B", str(build_dir), *options, *flag_options],
                                   text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print(configure.stdout, flush=True)
        if configure.returncode:
            raise SystemExit(f"cmake configure failed for {abi}")
        summary = configure.stdout[configure.stdout.find("SDL3 was configured with the following options:"):]
        summary = "\n".join(line[3:] if line.startswith("-- ") else line for line in summary.splitlines())
        (dest / "cmake-summary.txt").write_text(summary.strip() + "\n")
        run("cmake", "--build", build_dir, "--parallel", jobs)
        library = build_dir / "libSDL3.so"
        assert library.is_file() and not library.is_symlink(), f"Expected {library}"
        shutil.copy2(library, dest / "unstripped/libSDL3.so")
        shutil.copy2(library, dest / "libSDL3.so")
        run(toolchain / "llvm-strip", "--strip-unneeded", dest / "libSDL3.so")
        # The smoke test is cross-compiled for a later device run; it is NOT run here.
        run(compiler, "-std=c11", "-O1", "-Wl,-z,max-page-size=16384", TOOLS / "smoke-test.c",
            "-ldl", "-o", dest / "smoke-test")
        shutil.copy2(source / "LICENSE.txt", dest / "LICENSE-SDL3.txt")
        report = verify(dest / "libSDL3.so", arch, toolchain)
        unstripped = verify(dest / "unstripped/libSDL3.so", arch, toolchain)
        assert report["build_id"] == unstripped["build_id"], "Stripped and unstripped build-ids differ"
        assert report["exports_total"] == unstripped["exports_total"]
        report.update({"built_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
                       "build_seconds": round(time.monotonic() - started),
                       "ndk": revision, "clang": output(compiler, "--version").splitlines()[0],
                       "cmake": cmake, "ninja": ninja, "source_commit": PINS["source_commit"],
                       "sdl_revision": PINS["sdl_revision"], "cmake_options": options + flag_options,
                       "strip": "llvm-strip --strip-unneeded", "patches": [p.name for p in patches],
                       "unstripped_sha256": unstripped["sha256"], "unstripped_bytes": unstripped["bytes"],
                       "static_gates": "passed (verify.py, both twins)",
                       "runtime_tests": "UNRUN - no device or emulator was used"})
        (dest / "BUILD-INFO.json").write_text(json.dumps(report, indent=2) + "\n")
        sums = "".join(f"{sha256(dest / name)}  {name}\n"
                       for name in ("libSDL3.so", "unstripped/libSDL3.so", "LICENSE-SDL3.txt", "smoke-test"))
        (dest / "SHA256SUMS.txt").write_text(sums)
        print(json.dumps(report, indent=2), flush=True)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--arch", choices=["all", *ARCHITECTURES], default="all")
    parser.add_argument("--ndk", type=Path, default=os.environ.get("CODEBRIX_ANDROID_NDK"),
                        required=not os.environ.get("CODEBRIX_ANDROID_NDK"))
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")
    ndk = args.ndk.resolve()
    tools = check_tools(ndk)
    for arch in ARCHITECTURES if args.arch == "all" else [args.arch]:
        build(arch, ndk, args.jobs, tools)
