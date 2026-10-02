================================================================================
MAINTAINER-README: CodeBrix.Sdl3
Notes for people and agents MAINTAINING this repository - not for package
consumers
================================================================================

If you are CONSUMING the NuGet package, stop reading and open
AGENT-README.txt (repo root) instead. Everything below is about the
repository itself: how it is laid out, how it builds, how it is tested, how it
is packaged, and the conventions the source follows.


PURPOSE AND SCOPE
=================
This repository produces exactly one NuGet package:

    PackageId:  CodeBrix.Sdl3.ZlibLicenseForever
    Assembly:   CodeBrix.Sdl3 (net10.0 and net10.0-android)
    Project:    src/CodeBrix.Sdl3/CodeBrix.Sdl3.csproj
    License:    MIT AND Zlib (repository LICENSE: MIT)
    Consumer documentation: AGENT-README.txt (repo root; packed at the
                            package root)

The package is C# bindings for SDL3 plus the SDL3 native libraries for nine
runtime identifiers (win-x64, win-arm64, osx-x64, osx-arm64, linux-x64,
linux-arm64, linux-riscv64, android-x64, android-arm64) and, on the android
TFM, the SDL Java bridge jar. SDL3 core only: no SDL_image/ttf/mixer/net, no
iOS, no 32-bit targets.


REPOSITORY LAYOUT
=================
    src/CodeBrix.Sdl3/               the library (the only packable project)
      (root)                         SDL3.cs (PtrToStringUTF8), Utf8String,
                                     SDLArray / SDLPointerArray /
                                     SDLOpaquePointerArray /
                                     SDLConstOpaquePointerArray, the four
                                     binding attributes (Constant, Macro,
                                     NativeTypeName, Typedef),
                                     JetBrainsAnnotations.cs,
                                     InternalsVisibleTo.cs
      Bindings/                      the hand-written partials, one per SDL
                                     header (SDL_<header>.cs)
      Bindings/ClangSharp/           the GENERATED bindings (SDL_<header>.g.cs)
                                     - never hand-edit; regenerate (below)
      Transforms/                    .NET-for-Android binding transforms for the
                                     embedded SDL Java bridge (Metadata.xml
                                     removes the members the binding generator
                                     cannot bind and adds the not-null marks
                                     that keep the generated SDLSurface override
                                     warning-free; the other two are empty
                                     templates)
    src/CodeBrix.Sdl3.SourceGeneration/
                                     Roslyn source generator that writes the
                                     friendly Utf8String/string overloads while
                                     CodeBrix.Sdl3 compiles (not packed)
    tests/CodeBrix.Sdl3.Tests/       the xUnit v3 test project
      Internal/Sdl3NativeLibrary.cs  RID detection + the DllImport resolver
    tools/sdl3_binding_generation/   regeneration of Bindings/ClangSharp (see
                                     its README.txt and EXTRAS-README.txt)
    native_libraries/<rid>/          the committed SDL3 binaries, each with
                                     LICENSE-SDL3.txt and a .provenance.txt;
                                     native_libraries/android/ holds
                                     SDL3AndroidBridge.jar (+ provenance)
    sdl3-native-tools/               everything needed to rebuild every native
                                     binary and the jar from the vendored,
                                     unmodified SDL source (see EXTRAS-README.txt
                                     and sdl3-native-tools/README.txt)

    CodeBrix.Sdl3.slnx               the solution; its Solution Items folder
                                     carries .gitignore,
                                     AGENT-README.txt,
                                     EXTRAS-README.txt, global.json,
                                     icon-codebrix-128.png, LICENSE,
                                     MAINTAINER-README.txt, README-INDEX.txt,
                                     README.md and THIRD-PARTY-NOTICES.txt; its
                                     Tests folder carries the test project; it
                                     also lists both src projects
    global.json                      selects the Microsoft.Testing.Platform test
                                     runner. Does NOT pin an SDK version.
    AGENT-README.txt                 the consumer guide (packed at the package
                                     root)

NAMESPACES: every file under src/CodeBrix.Sdl3 - including Bindings/ and
Bindings/ClangSharp/ - declares the plain CodeBrix.Sdl3 namespace (NOT
CodeBrix.Sdl3.Bindings). The static class SDL3 is `partial` across all of
them, and consumers write `using static CodeBrix.Sdl3.SDL3;`. The folders are
for organization only; do not "fix" this with folder-derived namespaces.
JetBrainsAnnotations.cs deliberately keeps namespace JetBrains.Annotations
(internal attributes, recognized by JetBrains tooling by that name).


BUILDING
========
    dotnet restore CodeBrix.Sdl3.slnx
    dotnet build   CodeBrix.Sdl3.slnx --configuration Release

Both configurations, both library TFMs, must build with 0 warnings and 0
errors. Building the net10.0-android TFM needs the .NET android workload.

NOTHING in a dotnet build reaches outside this repository: no download, no
native compile, no file outside the repo tree. The natives are committed
binaries; the build only copies and packs them.

Situational exceptions to the family csproj shape (each documented in the
csproj):
  - <TargetFrameworks>net10.0;net10.0-android</TargetFrameworks> with
    SupportedOSPlatformVersion 33.0 on the android TFM (ruling D10, the
    CodeBrix.Audio.MidiConnect shape incl. its None Remove/Include of the
    root AGENT-README.txt pack item for the multi-target outer build). The
    android TFM exists to carry the Java bridge as an <EmbeddedJar>.
  - <Nullable>enable</Nullable> on the library: the ported binding surface uses
    `?` annotations (string? returns etc.) in its public signatures.
  - <NoWarn>$(NoWarn);CS1591</NoWarn> on the library and the generator (ruling
    D5, 2026-10-01): the public surface is overwhelmingly machine-generated and
    regenerated by script, so hand-written XML docs are not possible there.
    GenerateDocumentationFile stays true. This is the ONLY permitted NoWarn -
    every other warning is fixed at source.
  - <AllowUnsafeBlocks>true</AllowUnsafeBlocks>: pointer-based P/Invoke.
  - <DefineConstants>...;JETBRAINS_ANNOTATIONS</DefineConstants>: keeps the
    JetBrains annotation attributes meaningful, as upstream.
  - The source generator project (the CodeBrix.VideoProcessing.OpenCV5.Analyzers
    pattern): netstandard2.0, LangVersion 12 pinned, Nullable enable,
    IsRoslynComponent, EnforceExtendedAnalyzerRules, IsPackable=false,
    AssemblyVersion 1.0.0.0 pinned. It is referenced with
    OutputItemType="Analyzer" ReferenceOutputAssembly="false"
    SetTargetFramework="TargetFramework=netstandard2.0" and is NOT packed: it
    runs only while CodeBrix.Sdl3 compiles, and its output is compiled into
    CodeBrix.Sdl3.dll.
  - Generator packages: Microsoft.CodeAnalysis.CSharp and
    Microsoft.CodeAnalysis.Analyzers are kept at the LATEST stable pair on
    nuget.org. The generator is an IIncrementalGenerator (upstream's classic
    ISourceGenerator + ISyntaxReceiver was ported, because Analyzers 3.11.0+
    rejects that API with RS1035/RS1042 errors under
    EnforceExtendedAnalyzerRules), so nothing holds the references back. The
    one limit: the compiler that runs the generator (the .NET SDK's Roslyn)
    must be at least the referenced Microsoft.CodeAnalysis.CSharp version, or
    the build reports CS9057 and the friendly overloads go missing - so bump
    only to a version the SDK in use already ships. Both references are
    PrivateAssets="all" and the generator is never packed, so neither it nor
    Microsoft.CodeAnalysis is ever a dependency of the package.
  - Changing the generator: its output must stay byte-identical unless the
    change is meant to alter the bindings. Check by building
    src/CodeBrix.Sdl3 once per TFM (-f net10.0, -f net10.0-android) with
    -p:EmitCompilerGeneratedFiles=true
    -p:CompilerGeneratedFilesOutputPath=<a scratch folder per TFM> before and
    after the change, and diff the two trees.

The Helper.UnsafePrefix constant ("Unsafe_") in the generator must match
unsafe_prefix in tools/sdl3_binding_generation/generate_bindings.py: the
script renames every string-returning function to Unsafe_<name> and the
generator writes the friendly <name> overload that returns string?.


TESTING
=======
    dotnet test --solution CodeBrix.Sdl3.slnx

THE TEST RUNNER IS Microsoft.Testing.Platform (MTP), selected by global.json
at the repo root:

    { "test": { "runner": "Microsoft.Testing.Platform" } }

That file does NOT pin an SDK version; it exists solely to select the runner.
Keep it committed - without it `dotnet test` falls back to the VSTest bridge,
which fails on the .NET 10 SDK. MTP output ends in a "Test run summary:"
block. If `dotnet test --solution` ever reports zero tests, run the test
assembly directly and read ITS counts:

    dotnet tests/CodeBrix.Sdl3.Tests/bin/Debug/net10.0/CodeBrix.Sdl3.Tests.dll

The test project is xUnit v3 + SilverAssertions (no coverage collector) and
targets net10.0 only. It runs serially
([assembly: Parallelization(Mode = ParallelMode.None)]) because SDL state is
process-global.

Native layout: the test csproj copies native_libraries/<rid>/ (minus
provenance files and the Android material) into its output as
runtimes/<rid>/native/ - the package layout - and Internal/Sdl3NativeLibrary.cs
installs a DllImport resolver for the CodeBrix.Sdl3 assembly that loads
runtimes/<current rid>/native/ (a ProjectReference produces no deps.json
native entries). Tests that need the native library call
Assert.SkipUnless(...) and SKIP with a reason naming the missing file when the
binary for the current RID is not committed. The host-free tests
(Utf8String, SDLBool equality, version constants, RID shape) always run.

The dummy-video-driver smoke tests (DummyVideoDriverSmoke.cs) need no display:
they set SDL_HINT_VIDEO_DRIVER to "dummy".


PACKAGING AND PUBLISHING
========================
GeneratePackageOnBuild is true, so every build of the library emits a fresh
.nupkg under src/CodeBrix.Sdl3/bin/<Configuration>/.

Versioning is the CodeBrix date-stamped scheme, computed in the csproj from
System.DateTime.UtcNow as 1.<years-since-2026>.<day-of-year>.<minute-of-day>.
It is NOT SemVer. Two builds inside the same UTC minute produce the SAME
version - never publish two packages from one minute. Do not replace the
version block with a literal <Version>.

What ships inside the nupkg:
    lib/net10.0/CodeBrix.Sdl3.dll + .xml
    lib/net10.0-android36.0/CodeBrix.Sdl3.dll + .xml (+ the embedded jar; the
      platform version in the folder name is the SDK default)
    runtimes/<rid>/native/<SDL3 binary> + LICENSE-SDL3.txt, for each of the
      nine RIDs
    icon-codebrix-128.png, README.md, AGENT-README.txt,
      THIRD-PARTY-NOTICES.txt (all four from the repo root)
NOT packed: the .provenance.txt files, the generator (no analyzers/ folder),
MAINTAINER-README.txt, EXTRAS-README.txt, README-INDEX.txt, tools/,
sdl3-native-tools/.

Every native pack item is conditional on its file existing, so the project
builds while natives are still being produced. A RELEASE package must carry
all nine binaries and the jar: before publishing, unzip the .nupkg and check
that runtimes/ holds nine <rid>/native/ folders, each with its binary and
LICENSE-SDL3.txt, and that a lib/net10.0-android*/ folder is present. The
PackagePath values use forward slashes and no trailing separator (an empty
path segment can stop NuGet selecting the native).

PackageLicenseExpression is "MIT AND Zlib", PackageRequireLicenseAcceptance is
true. Jeremy publishes.


CODING CONVENTIONS
==================
  - File layout: preserved upstream header (the ppy MIT header on hand-written
    files, SDL's zlib header with <auto-generated/> on generated files), one
    blank line, the using block (System.* first, using static and aliases
    last), one blank line, `namespace CodeBrix.Sdl3; //was previously: SDL;`,
    one blank line, the body. File-scoped namespaces only; no global usings;
    no #nullable directives in hand-written code (the generator emits
    `#nullable enable` into its generated text, which is acceptable).
  - LF line endings, no BOM.
  - Bindings/ClangSharp/*.g.cs are never edited by hand. Change the headers'
    translation through generate_bindings.py, the rsp/ response files or a
    hand-written partial in Bindings/ (constants a partial defines with
    [Constant] and enums marked [Typedef] are excluded from generation
    automatically).
  - New-in-family files carry no header and no "//was previously:" comment.
  - Tests: xUnit v3 + SilverAssertions, <Class>Tests.cs naming (scenario files
    named descriptively, e.g. DummyVideoDriverSmoke.cs), methods in
    Member_snake_case or snake_case, //Arrange //Act //Assert in
    multi-statement tests, TestContext.Current.CancellationToken to any
    cancellable call.


PROVENANCE / VENDORED SOURCES
=============================
  - Managed bindings, generator, binding-generation tooling and four test
    files: ported from ppy/SDL3-CS at tag 2026.722.0 (MIT). Namespace mapping:
        SDL                   -> CodeBrix.Sdl3
        SDL.SourceGeneration  -> CodeBrix.Sdl3.SourceGeneration
        SDL.Tests             -> CodeBrix.Sdl3.Tests
    THIRD-PARTY-NOTICES.txt notice 1 lists every file and every change.
  - SDL3 itself: generated bindings derive from its headers; native binaries
    and the Java bridge are built from (or, for some RIDs, adopted from builds
    of) SDL commit a8591d943b7079b17fdd018dc04ec9c71dc94ae4, vendored
    unmodified in sdl3-native-tools/SDL. Per-binary provenance:
    native_libraries/<rid>/*.provenance.txt; the full record and the build
    recipes: sdl3-native-tools/BUILD-PROVENANCE.txt.
  - JetBrainsAnnotations.cs: JetBrains Annotations (MIT), notice 3.


REGENERATING THE BINDINGS
=========================
See tools/sdl3_binding_generation/README.txt. In short: `dotnet tool restore`
in that folder, then `python3 generate_bindings.py` (all headers) or
`python3 generate_bindings.py SDL_audio` (one). The script post-processes
every emitted file into the layout above. After regenerating, rebuild both
configurations, run the tests, and review the diff of Bindings/ClangSharp.
Regenerate whenever sdl3-native-tools/SDL moves to a new SDL commit, so the
bindings and the binaries always come from the same headers.


NOTES
=====
  - The DllImport library name is "SDL3" everywhere; the shipped file names
    (SDL3.dll, libSDL3.dylib, libSDL3.so) are what that name resolves to under
    runtimes/<rid>/native. Do not rename them.
  - The C-variadic entry points (__arglist) work only on Windows .NET; this is
    a runtime limitation documented for consumers in AGENT-README.txt.
  - The AI-agent pointer stubs at the repo root (AGENTS.md, CLAUDE.md,
    .clinerules, .cursorrules, .cursor/rules/agent-readme.mdc, .windsurfrules,
    .github/copilot-instructions.md, .junie/guidelines.md) are byte-exact
    copies of the CodeBrix.SkiaSvg canonical; never edit them per repo.
  - tools/sdl3_binding_generation/.gitignore re-includes *.rsp, which the
    family .gitignore ignores.


================================================================================
END OF MAINTAINER-README
================================================================================
