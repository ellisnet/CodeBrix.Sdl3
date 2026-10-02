# Copyright (c) ppy Pty Ltd <contact@ppy.sh>. Licensed under the MIT Licence.
# See the LICENCE file in the repository root for full licence text.

# Changes for CodeBrix (CodeBrix.Sdl3):
#   - Paths: headers are read from the vendored SDL snapshot in
#     sdl3-native-tools/SDL/include; generated files are written to
#     src/CodeBrix.Sdl3/Bindings/ClangSharp/; the hand-written partials it reads
#     (for [Constant] and [Typedef] symbols) live in src/CodeBrix.Sdl3/Bindings/;
#     the ClangSharp response files live in rsp/ beside this script and the
#     non-Windows process.h shim in include/.
#   - SDL_image, SDL_ttf and SDL_mixer were dropped (SDL3 core only).
#   - The vendored SDL snapshot is never modified: instead of `git reset --hard`
#     on the SDL source, gendynapi.py --dump runs against a temporary copy.
#   - Every emitted file is post-processed into the CodeBrix layout
#     (to_codebrix_layout below): file-scoped `namespace CodeBrix.Sdl3;` with a
#     `//was previously: SDL;` provenance comment, the body dedented one level,
#     LF line endings, no BOM. An emitted file with no content is deleted.
#     Regeneration therefore reproduces the committed shape exactly.

"""
Generates C# bindings for SDL3 using ClangSharp.

Prerequisites:
- python3 (3.10 or later - the script uses `match`)
- run `dotnet tool restore` in this folder (installs the ClangSharpPInvokeGenerator
  local tool at the version pinned in .config/dotnet-tools.json)
- the vendored SDL source at ../../sdl3-native-tools/SDL

This script should be run manually. See README.txt beside it.

Usage:
- Run the script without any command line parameters to generate all header files.
- Provide header names as command line parameters to generate just those headers.
- `--postprocess-only` re-applies the CodeBrix layout to the already-generated
  files without running ClangSharp (idempotent).

Example:
- python3 generate_bindings.py
- python3 generate_bindings.py SDL3/SDL_audio.h
- python3 generate_bindings.py SDL_audio.h
- python3 generate_bindings.py SDL_audio
- python3 generate_bindings.py audio
- python3 generate_bindings.py SDL_camera.h SDL_init.h
"""

import json
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import tempfile

# Needs to match CodeBrix.Sdl3.SourceGeneration.Helper.UnsafePrefix
unsafe_prefix = "Unsafe_"

tools_root = pathlib.Path(__file__).resolve().parent
repository_root = tools_root.parents[1]

SDL_source_root = repository_root / "sdl3-native-tools" / "SDL"
SDL_lib_include_root = {
    "SDL3": SDL_source_root / "include",
}

SDL3_header_base = "SDL3"  # base folder of header files

library_root = repository_root / "src" / "CodeBrix.Sdl3"
bindings_root = library_root / "Bindings"
generated_root = bindings_root / "ClangSharp"
rsp_root = tools_root / "rsp"

# The namespace ClangSharp emits, and the namespace the CodeBrix layout uses.
generated_namespace = "SDL"
codebrix_namespace = "CodeBrix.Sdl3"


class Header:
    """Represents a SDL header file that is used in ClangSharp generation."""

    def __init__(self, base: str, name: str, output_suffix=None):
        assert base in SDL_lib_include_root
        assert name.startswith("SDL")
        assert not name.endswith(".h")
        self.base = base
        self.name = name
        self.output_suffix = output_suffix

    def __str__(self):
        return f"{self.base}/{self.name}.h"

    def sdl_api_name(self):
        """Header name in sdl.json API dump."""
        return f"{self.name}.h"

    def input_file(self):
        """Absolute path of the input header file."""
        return SDL_lib_include_root[self.base] / self.base / f"{self.name}.h"

    def _stem(self):
        return self.name if self.output_suffix is None else f"{self.name}.{self.output_suffix}"

    def output_file(self):
        """Location of generated C# file."""
        return generated_root / f"{self._stem()}.g.cs"

    def rsp_files(self):
        """Location of ClangSharp response files."""
        yield rsp_root / f"{self.name}.rsp"
        if self.output_suffix is not None:
            yield rsp_root / f"{self.name}.{self.output_suffix}.rsp"

    def cs_file(self):
        """Location of the manually-written C# file that implements some parts of the header."""
        return bindings_root / f"{self._stem()}.cs"


def make_header_fuzzy(s: str) -> Header:
    match s.split("/"):
        case [name]:  # one part, eg "SDL_audio.h" or "audio"
            base = "SDL3"  # assume a default base
        case [base, name]:  # two parts, eg "SDL3/SDL_audio.h"
            pass
        case _:
            raise ValueError(f"Can't match \"{s}\" to header name.")

    if not name.startswith("SDL_"):
        name = f'SDL_{name}'

    if name.endswith(".h"):
        name = name.replace(".h", "")

    return Header(base, name)


def add(s: str):
    base, name = s.split("/")
    assert s.endswith(".h")
    name = name.replace(".h", "")
    return Header(base, name)


headers = [
    add("SDL3/SDL_atomic.h"),
    add("SDL3/SDL_asyncio.h"),
    add("SDL3/SDL_audio.h"),
    add("SDL3/SDL_blendmode.h"),
    add("SDL3/SDL_camera.h"),
    add("SDL3/SDL_clipboard.h"),
    add("SDL3/SDL_cpuinfo.h"),
    add("SDL3/SDL_dialog.h"),
    add("SDL3/SDL_error.h"),
    add("SDL3/SDL_events.h"),
    add("SDL3/SDL_filesystem.h"),
    add("SDL3/SDL_gamepad.h"),
    add("SDL3/SDL_gpu.h"),
    add("SDL3/SDL_guid.h"),
    add("SDL3/SDL_haptic.h"),
    add("SDL3/SDL_hidapi.h"),
    add("SDL3/SDL_hints.h"),
    add("SDL3/SDL_init.h"),
    add("SDL3/SDL_iostream.h"),
    add("SDL3/SDL_joystick.h"),
    add("SDL3/SDL_keyboard.h"),
    add("SDL3/SDL_keycode.h"),
    add("SDL3/SDL_loadso.h"),
    add("SDL3/SDL_locale.h"),
    add("SDL3/SDL_log.h"),
    add("SDL3/SDL_messagebox.h"),
    add("SDL3/SDL_metal.h"),
    add("SDL3/SDL_misc.h"),
    add("SDL3/SDL_mouse.h"),
    add("SDL3/SDL_mutex.h"),
    add("SDL3/SDL_pen.h"),
    add("SDL3/SDL_pixels.h"),
    add("SDL3/SDL_platform.h"),
    add("SDL3/SDL_power.h"),
    add("SDL3/SDL_process.h"),
    add("SDL3/SDL_properties.h"),
    add("SDL3/SDL_rect.h"),
    add("SDL3/SDL_render.h"),
    add("SDL3/SDL_revision.h"),
    add("SDL3/SDL_scancode.h"),
    add("SDL3/SDL_sensor.h"),
    add("SDL3/SDL_stdinc.h"),
    add("SDL3/SDL_storage.h"),
    add("SDL3/SDL_surface.h"),
    add("SDL3/SDL_thread.h"),
    add("SDL3/SDL_time.h"),
    add("SDL3/SDL_timer.h"),
    add("SDL3/SDL_tray.h"),
    add("SDL3/SDL_touch.h"),
    add("SDL3/SDL_version.h"),
    add("SDL3/SDL_video.h"),
    add("SDL3/SDL_vulkan.h"),
]


# ---------------------------------------------------------------------------
# CodeBrix layout post-processing (also used to port the hand-written files)
# ---------------------------------------------------------------------------

_qualify_system_regex = re.compile(r"(?<![\w.])(U?IntPtr)\b")


def _map_namespace(name: str, namespace_map: dict) -> str:
    for old, new in sorted(namespace_map.items(), key=lambda kv: -len(kv[0])):
        if name == old or name.startswith(old + "."):
            return new + name[len(old):]
    return name


def _qualify_inner_using(line: str, new_namespace: str) -> str:
    """Rewrites a `using` that sat INSIDE the braced namespace so it is valid at the top of the file."""
    m = re.match(r"using static ([\w.]+);$", line)
    if m:
        target = m.group(1)
        return f"using static {new_namespace}.{target};" if "." not in target else line
    m = re.match(r"(using (?:unsafe )?\w+ = )(.*)$", line)
    if m:
        return m.group(1) + _qualify_system_regex.sub(r"System.\1", m.group(2))
    return line


def _using_sort_key(line: str):
    name = line[len("using "):].rstrip(";").strip()
    return (0 if name == "System" or name.startswith("System.") else 1, name)


def to_codebrix_layout(text: str, namespace_map: dict | None = None):
    """
    Converts one C# file from the upstream shape (optional header comment, usings,
    braced `namespace X { ... }`) to the CodeBrix layout:

        <preserved header>
        <blank>
        <usings: System.* first, then others, alphabetical; using static / aliases last>
        <blank>
        namespace <New>; //was previously: <Old>;
        <blank>
        <body, dedented one level>

    Returns None for a file with no content. Idempotent: a file already in the
    CodeBrix layout is returned unchanged.
    """
    if namespace_map is None:
        namespace_map = {generated_namespace: codebrix_namespace}

    text = text.lstrip("﻿").replace("\r\n", "\n")
    if not text.strip():
        return None

    lines = text.split("\n")
    i = 0

    header = []
    while i < len(lines):
        line = lines[i]
        if line.startswith("//"):
            header.append(line)
            i += 1
        elif line.startswith("/*"):
            while True:
                header.append(lines[i])
                i += 1
                if header[-1].rstrip().endswith("*/"):
                    break
        else:
            break

    usings = []
    pre_namespace_comments = []
    while i < len(lines) and not lines[i].startswith("namespace "):
        line = lines[i]
        if line.startswith("using "):
            usings.append(line.rstrip())
        elif line.startswith("//"):
            pre_namespace_comments.append(line.rstrip())
        elif line.strip():
            raise ValueError(f"Unexpected line before the namespace: {line!r}")
        i += 1

    if i >= len(lines):
        raise ValueError("No namespace declaration found.")

    namespace_line = lines[i].strip()
    if namespace_line.endswith(";"):
        return text if text.endswith("\n") else text + "\n"  # already file-scoped

    old_namespace = namespace_line[len("namespace "):].strip()
    new_namespace = _map_namespace(old_namespace, namespace_map)
    i += 1
    if lines[i].strip() != "{":
        raise ValueError(f"Expected '{{' after the namespace line, found {lines[i]!r}")
    i += 1

    j = len(lines) - 1
    while not lines[j].strip():
        j -= 1
    if lines[j] != "}":
        raise ValueError(f"Expected the file to end with the namespace's '}}', found {lines[j]!r}")

    body = []
    for line in lines[i:j]:
        line = line.rstrip()
        if line.startswith("    "):
            line = line[4:]
        body.append(line)

    # Lift `using` directives that sat inside the braced namespace to the top block.
    inner_usings = []
    k = 0
    while k < len(body):
        line = body[k]
        if line.startswith("using "):
            inner_usings.append(_qualify_inner_using(line, new_namespace))
            k += 1
        elif not line.strip():
            k += 1
        elif line.startswith("//"):
            n = k
            while n < len(body) and body[n].startswith("//"):
                n += 1
            if n < len(body) and body[n].startswith("using "):
                inner_usings.extend(body[k:n])
                k = n
            else:
                break
        else:
            break
    body = body[k:]
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()

    plain = sorted({u for u in usings if not u.startswith("using static ") and "=" not in u}, key=_using_sort_key)
    statics = [u for u in usings if u.startswith("using static ")]
    aliases = [u for u in usings if "=" in u and not u.startswith("using static ")]
    inner_statics = [u for u in inner_usings if u.startswith("using static ")]
    inner_rest = [u for u in inner_usings if not u.startswith("using static ")]
    using_block = plain + statics + inner_statics + aliases + inner_rest

    if new_namespace != old_namespace:
        namespace_decl = f"namespace {new_namespace}; //was previously: {old_namespace};"
    else:
        namespace_decl = f"namespace {new_namespace};"

    out = []
    if header:
        out.extend(header)
        out.append("")
    if using_block:
        out.extend(using_block)
        out.append("")
    out.append(namespace_decl)
    out.append("")
    if pre_namespace_comments:
        out.extend(pre_namespace_comments)
    out.extend(body)
    return "\n".join(out) + "\n"


def postprocess_file(path: pathlib.Path):
    """Applies to_codebrix_layout to one generated file in place (deleting it when empty)."""
    if not path.is_file():
        return
    with open(path, "r", encoding="utf-8-sig") as f:
        text = f.read()
    result = to_codebrix_layout(text)
    if result is None:
        path.unlink()
        print(f"[CodeBrix] removed empty generated file {path.name}")
        return
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(result)


# ---------------------------------------------------------------------------
# Generation (upstream logic)
# ---------------------------------------------------------------------------

def get_sdl_api_dump():
    """Runs SDL's gendynapi.py --dump against a TEMPORARY COPY of the vendored SDL tree."""
    with tempfile.TemporaryDirectory(prefix="codebrix-sdl3-gendynapi-") as tmp:
        sdl_copy = pathlib.Path(tmp) / "SDL"
        shutil.copytree(SDL_source_root / "include", sdl_copy / "include")
        shutil.copytree(SDL_source_root / "src" / "dynapi", sdl_copy / "src" / "dynapi")
        json_path = pathlib.Path(tmp) / "sdl.json"
        subprocess.run([
            sys.executable,
            sdl_copy / "src" / "dynapi" / "gendynapi.py",
            "--dump", json_path,
        ], cwd=tmp, check=True)

        with open(json_path, "r", encoding="utf-8") as f:
            return json.load(f)


def all_funcs_from_header(sdl_api, header):
    for f in sdl_api:
        if f["header"] == header.sdl_api_name():
            yield f


def get_text(file_paths):
    text = ""
    for path in file_paths:
        if pathlib.Path(path).is_file():
            with open(path, "r", encoding="utf-8") as f:
                text += f.read()

    return text


def check_generated_functions(sdl_api, header, generated_file_paths):
    """Checks that the generated C# files contain the expected function definitions."""
    all_files_text = get_text(generated_file_paths)

    for func in all_funcs_from_header(sdl_api, header):
        name = func["name"]
        found = f"{name}(" in all_files_text

        if not found:
            print(f"[Warning] Function {name} not found in generated files:", *generated_file_paths)


defined_constant_regex = re.compile(r"\[Constant]\s*public (const|static readonly) \w+ (\w+_\w+) = ", re.MULTILINE)


def get_manually_written_symbols(header):
    """Returns symbols names whose definitions are manually written in C#."""
    cs_file = header.cs_file()
    if cs_file.is_file():
        with open(cs_file, "r", encoding="utf-8") as f:
            text = f.read()
            for match in defined_constant_regex.finditer(text):
                m = match.group(2)
                yield m


typedef_enum_regex = re.compile(r"\[Typedef]\s*public enum (\w+_\w+)", re.MULTILINE)


def get_typedefs():
    for header in headers:
        cs_file = header.cs_file()
        if cs_file.is_file():
            with open(cs_file, "r", encoding="utf-8") as f:
                for match in typedef_enum_regex.finditer(f.read()):
                    yield match.group(1)


def typedef(t):
    return f"{t}={t}"


base_command = [
    "dotnet", "tool", "run", "ClangSharpPInvokeGenerator",
    "--headerFile", tools_root / "SDL-license-header.txt",

    "--config",
    "latest-codegen",
    "windows-types",
    "generate-macro-bindings",

    "--file-directory", SDL_lib_include_root["SDL3"],
    "--include-directory", SDL_lib_include_root["SDL3"],
    "--namespace", generated_namespace,

    "--remap",
    "void*=IntPtr",
    "char=byte",
    "wchar_t *=IntPtr",  # wchar_t has a platform-defined size
    "bool=SDLBool",  # treat bool as C# helper type
    "__va_list=byte*",
    "__va_list_tag=byte",
    "Sint64=long",
    "Uint64=ulong",

    "--with-type",
    "*=int",  # all enum types should be ints by default

    "--nativeTypeNamesToStrip",
    "unsigned int",

    "--define-macro",
    "SDL_FUNCTION_POINTER_IS_VOID_POINTER",
    "SDL_SINT64_C(c)=c ## LL",
    "SDL_UINT64_C(c)=c ## ULL",
    "SDL_DECLSPEC=",  # Not supported by llvm

    # Undefine platform-specific macros - these will be defined on a per-case basis later.
    "--additional",
    "--undefine-macro=_WIN32",
    "--undefine-macro=linux",
    "--undefine-macro=__linux",
    "--undefine-macro=__linux__",
    "--undefine-macro=unix",
    "--undefine-macro=__unix",
    "--undefine-macro=__unix__",
    "--undefine-macro=__APPLE__",
]


def run_clangsharp(command, header: Header):
    cmd = command + [
        "--file", header.input_file(),
        "--output", header.output_file(),
        "--libraryPath", header.base,
        "--methodClassName", header.base,
    ]

    for rsp in header.rsp_files():
        if rsp.is_file():
            cmd.append(f"@{rsp}")

    to_exclude = list(get_manually_written_symbols(header))
    if to_exclude:
        cmd.append("--exclude")
        cmd.extend(to_exclude)

    subprocess.run(cmd, cwd=tools_root)
    output = header.output_file()
    postprocess_file(output)
    return output


# regex for ClangSharp-generated SDL functions and enums
generated_symbol_regex = re.compile(rf"public (enum|static extern \w+\**) (?:{unsafe_prefix})?(SDL_\w+)")


def get_generated_symbols(file):
    if not pathlib.Path(file).is_file():
        return
    with open(file, "r", encoding="utf-8") as f:
        for match in generated_symbol_regex.finditer(f.read()):
            yield match.group(2)


def generate_platform_specific_headers(sdl_api, header: Header, platforms):
    all_functions = list(all_funcs_from_header(sdl_api, header))

    print(f"* {header} platform agnostic")
    platform_agnostic_cs = run_clangsharp(base_command, header)
    platform_agnostic_symbols = list(get_generated_symbols(platform_agnostic_cs))
    output_files = [platform_agnostic_cs]

    for (defines, suffix, platform_name) in platforms:
        command = base_command + ["--define-macro"] + defines

        if platform_agnostic_symbols:
            command.append("--exclude")
            command.extend(platform_agnostic_symbols)

        if all_functions:
            command.append("--with-attribute")
            for f in all_functions:
                command.append(f'{f["name"]}=SupportedOSPlatform("{platform_name}")')

        print(f"* {header} for {suffix}")
        header.output_suffix = suffix
        output_files.append(run_clangsharp(command, header))

    check_generated_functions(sdl_api, header, output_files)


def get_string_returning_functions(sdl_api):
    for f in sdl_api:
        if f["retval"] in ("const char*", "char*"):
            yield f["name"]


def should_skip(solo_headers: list[Header], header: Header):
    if len(solo_headers) == 0:
        return False

    return not any(header.input_file() == h.input_file() for h in solo_headers)


def postprocess_all():
    for path in sorted(generated_root.glob("*.g.cs")):
        postprocess_file(path)


def main():
    if "--postprocess-only" in sys.argv[1:]:
        postprocess_all()
        return

    solo_headers = [make_header_fuzzy(header_name) for header_name in sys.argv[1:]]

    if platform.system() != "Windows":
        base_command.extend([
            "--include-directory", tools_root / "include"
        ])

    sdl_api = get_sdl_api_dump()

    # typedefs are added globally as their types appear outside of the defining header
    typedefs = list(get_typedefs())
    if typedefs:
        base_command.append("--remap")
        for type_name in typedefs:
            base_command.append(typedef(type_name))

    str_ret_funcs = list(get_string_returning_functions(sdl_api))
    if str_ret_funcs:
        base_command.append("--remap")
        for name in str_ret_funcs:
            # add unsafe prefix to `const char *` functions so that the source generator can make friendly overloads with the unprefixed name.
            base_command.append(f"{name}={unsafe_prefix}{name}")

    for header in headers:
        if should_skip(solo_headers, header):
            continue

        output_file = run_clangsharp(base_command, header)
        check_generated_functions(sdl_api, header, [output_file])

    main_header = add("SDL3/SDL_main.h")
    if not should_skip(solo_headers, main_header):
        generate_platform_specific_headers(sdl_api, main_header, [
            (["SDL_PLATFORM_WINDOWS"], "Windows", "Windows"),
        ])

    system_header = add("SDL3/SDL_system.h")
    if not should_skip(solo_headers, system_header):
        generate_platform_specific_headers(sdl_api, system_header, [
            # define macro, output_suffix, [SupportedOSPlatform]
            (["SDL_PLATFORM_ANDROID"], "Android", "Android"),
            (["SDL_PLATFORM_IOS"], "iOS", "iOS"),
            (["SDL_PLATFORM_LINUX"], "Linux", "Linux"),
            (["SDL_PLATFORM_WINDOWS", "SDL_PLATFORM_WIN32"], "Windows", "Windows"),
            (["SDL_PLATFORM_GDK"], "GDK", "Windows"),
        ])


if __name__ == "__main__":
    main()
