================================================================================
tools/sdl3_binding_generation - regenerating the SDL3 C# bindings
================================================================================

WHAT THIS DOES
--------------
generate_bindings.py runs ClangSharpPInvokeGenerator over the SDL3 public
headers and writes src/CodeBrix.Sdl3/Bindings/ClangSharp/SDL_<header>.g.cs,
one file per header (plus SDL_main.Windows and the per-OS SDL_system.*
variants). Every emitted file is then post-processed into the CodeBrix source
layout - file-scoped `namespace CodeBrix.Sdl3; //was previously: SDL;`, body
dedented, LF, no BOM - so a regeneration reproduces the committed files
exactly. An emitted file with no content is deleted.

It is run BY HAND, only when the vendored SDL source moves to a new commit or
the binding rules change. Nothing in a dotnet build calls it.

FILES
-----
  generate_bindings.py      the script (MIT, from the upstream bindings project;
                            its "Changes for CodeBrix" block lists the edits)
  rsp/*.rsp                 ClangSharp response files, per header (extra
                            defines, excludes, remaps)
  SDL-license-header.txt    the header (SDL zlib notice) ClangSharp writes at
                            the top of every generated file
  include/process.h         empty process.h shim, used on non-Windows hosts when
                            the Windows-specific headers are generated
  .config/dotnet-tools.json pins the ClangSharpPInvokeGenerator local tool
  .gitignore                re-includes *.rsp (the family .gitignore ignores it)

PREREQUISITES (installed by YOU, not by the script)
---------------------------------------------------
  - python3, 3.10 or later
  - the .NET 10 SDK (for `dotnet tool restore` / `dotnet tool run`)
  - the ClangSharpPInvokeGenerator local tool, restored from
    .config/dotnet-tools.json in this folder
  - the libclang and libClangSharp native libraries the tool loads (17.x,
    matching the tool). The upstream bindings project obtained them by adding
    PackageReferences to the libclang and libClangSharp 17.0.4 NuGet packages
    to its library csproj; CodeBrix.Sdl3 deliberately carries no such
    references (the package has no dependencies), so if the tool reports that
    it cannot load libclang / libClangSharp, provide them yourself - for
    example from those packages in a throwaway project, outside this repo -
    and put them on the loader path.
  - the vendored SDL source at ../../sdl3-native-tools/SDL (headers in
    include/, gendynapi.py in src/dynapi/) - already in the repository

STEPS
-----
    cd tools/sdl3_binding_generation
    dotnet tool restore                      # one time; fetches the pinned tool
    python3 generate_bindings.py             # all headers
    python3 generate_bindings.py SDL_audio   # or just one (SDL_audio.h,
                                             # audio, SDL3/SDL_audio.h all work)
    python3 generate_bindings.py --postprocess-only
                                             # re-apply the layout only

The script runs SDL's own src/dynapi/gendynapi.py --dump against a TEMPORARY
COPY of the headers and dynapi folder to learn which functions return strings
(those are emitted as Unsafe_<name> so the source generator can add the
friendly string-returning <name>); the vendored SDL tree is never modified.

"[Warning] Function X not found in generated files" lines name SDL functions
that the generated output does not declare - usually ones a hand-written
partial in src/CodeBrix.Sdl3/Bindings/ provides, or ones excluded in rsp/.

AFTERWARDS
----------
  1. dotnet build CodeBrix.Sdl3.slnx -c Debug and -c Release: 0 warnings.
  2. dotnet test --solution CodeBrix.Sdl3.slnx: green.
  3. Review the git diff of src/CodeBrix.Sdl3/Bindings/ClangSharp - new or
     removed functions, changed signatures - and update the hand-written
     partials where a new header needs typed enums or array overloads.
  4. The native binaries must come from the same SDL commit as the headers:
     rebuild them with sdl3-native-tools/ if the snapshot moved.

STATUS
------
The post-processing step (--postprocess-only, and to_codebrix_layout applied
to the upstream generated files) has been run and reproduces the committed
files byte for byte. A full ClangSharp regeneration has NOT been run in this
repository yet (it needs the ClangSharp tool restored); the committed
Bindings/ClangSharp files are the upstream project's generated output for the
same SDL commit, converted by that same post-processing step.
