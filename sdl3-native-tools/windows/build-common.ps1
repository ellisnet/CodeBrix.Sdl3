# =============================================================================================
# build-common.ps1 - shared machinery for the Windows SDL3 builds (win-x64, win-arm64)
# =============================================================================================
#
#   NEVER YET RUN. Written on Linux on 2026-10-01, modelled on CodeBrix.Ollama's
#   llama-native-tools/windows/build-common.ps1 and CodeBrix.VideoPlayback.Dav1d's
#   dav1d-native-tools/windows/build-common.ps1 (whose first-run fixes - the dumpbin export
#   parser, the cl banner capture, choosing the Visual Studio instance by its own filesystem,
#   the PATH trap - are carried over here), and on CodeBrix.Platform.GameEngine's
#   build-sdl2-windows-arm64.ps1 (generator detection, the PE machine-type reader). Expect to
#   fix something on the first real run; fix it IN THE SCRIPT and record it in
#   ..\BUILD-PROVENANCE.txt, then rewrite the status block of README.txt.
#
# Dot-source this from an architecture script; do not run it directly.
#
#     . "$PSScriptRoot\build-common.ps1"
#
# Everything it needs is in this repository: ..\SDL (the vendored, unmodified SDL snapshot),
# ..\patches (empty), ..\smoke-test.c, and ..\linux\pins.env (the version pins shared by every
# platform - see README.txt for why they live in the linux folder). Nothing is downloaded.
# =============================================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------------------------
# Pins. One source of truth for the SDL commit, version, revision string and the required
# exports: ..\linux\pins.env. Only its platform-neutral keys are used here (SDL_DIR,
# SDL_VERSION, SDL_COMMIT, SDL_COMMIT_SUBJECT, SDL_REVISION_STRING, SDL_VERSION_NUM,
# REQUIRED_SYMBOLS, LICENSE_FILE_NAME, CMAKE_VERSION).
# ---------------------------------------------------------------------------------------------
function Read-Pins {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "pins.env was not found at $Path. It is part of the repository - if it is missing after a clone, check the root .gitignore's blanket '*.env' rule (see ..\README.txt and ..\.gitignore)."
    }

    $pins = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $eq = $trimmed.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $trimmed.Substring(0, $eq).Trim()
        $value = $trimmed.Substring($eq + 1).Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $pins[$key] = $value
    }
    foreach ($required in @('SDL_DIR', 'SDL_VERSION', 'SDL_COMMIT', 'SDL_REVISION_STRING', 'SDL_VERSION_NUM', 'REQUIRED_SYMBOLS', 'LICENSE_FILE_NAME')) {
        if (-not $pins.ContainsKey($required)) { throw "pins.env has no $required. The Windows scripts read it from ..\linux\pins.env." }
    }
    return $pins
}

# ---------------------------------------------------------------------------------------------
# The SDL CMake options for Windows. The Linux options live in pins.env; these are the Windows
# equivalent, kept here because three of them only mean something to MSVC. ppy/SDL3-CS
# 2026.722.0 (whose win-x64 / win-arm64 DLLs are the ones currently adopted) passed
#     -A <x64|ARM64> -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded -DCMAKE_BUILD_TYPE=Release
#     -DSDL_SHARED=ON -DSDL_STATIC=OFF
# and these options reproduce that, plus:
#   SDL_TEST_LIBRARY/TESTS/EXAMPLES=OFF  only the library; the gate's smoke test is our own C
#   SDL_INSTALL=OFF                      nothing is installed; the DLL is taken from the build tree
#   SDL_REVISION=<pins>                  the scratch copy has no .git, so SDL cannot `git
#                                        describe`; pinned to the exact string ppy's DLLs carry
#   HAVE_GAMEINPUT_H=OFF                 see README.txt, GAMEINPUT. ppy disabled SDL's
#                                        <gameinput.h> detection with a sed; pre-seeding the
#                                        check's result variable does the same without touching
#                                        the source (CMake skips a check whose variable is
#                                        already defined). Dropped by -GameInput.
#   /Z7 + /DEBUG ... /PDBALTPATH:%_PDB%  a .pdb for crash triage. /Z7 puts the debug info in the
#                                        object files (no shared compiler PDB, so no C1041 under
#                                        a parallel build); /DEBUG makes link.exe write SDL3.pdb
#                                        but would switch /OPT:REF and /OPT:ICF OFF, so both are
#                                        restored explicitly; /PDBALTPATH:%_PDB% records only the
#                                        file name, not this machine's %TEMP% path. Code
#                                        generation is unchanged by any of these.
# CMAKE_C_FLAGS_RELEASE is CMake's own MSVC default ("/O2 /Ob2 /DNDEBUG") plus /Z7.
# ---------------------------------------------------------------------------------------------
function Get-SdlWindowsCmakeOptions {
    param(
        [Parameter(Mandatory)][hashtable] $Pins,
        [switch] $GameInput
    )
    $options = @(
        '-DCMAKE_BUILD_TYPE=Release',
        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded',
        '-DSDL_SHARED=ON', '-DSDL_STATIC=OFF',
        '-DSDL_TEST_LIBRARY=OFF', '-DSDL_TESTS=OFF', '-DSDL_EXAMPLES=OFF',
        '-DSDL_INSTALL=OFF',
        "-DSDL_REVISION=$($Pins['SDL_REVISION_STRING'])",
        '-DCMAKE_C_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /Z7',
        '-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /Z7',
        '-DCMAKE_SHARED_LINKER_FLAGS_RELEASE=/INCREMENTAL:NO /DEBUG /OPT:REF /OPT:ICF /PDBALTPATH:%_PDB%'
    )
    if (-not $GameInput) { $options += '-DHAVE_GAMEINPUT_H=OFF' }
    return $options
}

# Every DLL the shipped SDL3.dll may import. This is EXACTLY the import list of the ppy
# 2026.722.0 DLLs adopted for both Windows RIDs (read from their PE import tables on
# 2026-10-01; x64 and ARM64 identical): operating-system DLLs only. NOTHING from the Visual C++
# runtime - VCRUNTIME140.dll, MSVCP140.dll, ucrtbase.dll or api-ms-win-crt-*.dll there means
# the static CRT did not take and every user would need a redistributable. If a rebuild needs
# another in-box DLL (GameInput.dll with -GameInput and a linkable gameinput.lib, say), the gate
# fails; add it here only with a note in ..\BUILD-PROVENANCE.txt saying what needs it.
# The comparison is case-insensitive (PE import names are; ppy's DLL lists "HID.DLL").
$script:AllowedDependents = @(
    'ADVAPI32.dll', 'GDI32.dll', 'HID.DLL', 'IMM32.dll', 'KERNEL32.dll', 'OLEAUT32.dll',
    'SETUPAPI.dll', 'SHELL32.dll', 'USER32.dll', 'VERSION.dll', 'WINMM.dll', 'ole32.dll'
)

# ---------------------------------------------------------------------------------------------
# Native commands. Windows PowerShell 5.1 turns every STDERR line of a native command into an
# ErrorRecord when it is redirected with 2>&1, and with $ErrorActionPreference = 'Stop' the
# first one - cmake prints its warnings on stderr - would abort the script. So native tools are
# always run through this helper, which relaxes the preference for the call only, returns the
# merged output as plain strings, and leaves the exit code in $LASTEXITCODE for the caller.
# ---------------------------------------------------------------------------------------------
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $Command,
        [string[]] $Arguments = @()
    )
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $Command @Arguments 2>&1 | ForEach-Object { "$_" }
    }
    finally { $ErrorActionPreference = $saved }
    return $output
}

# ---------------------------------------------------------------------------------------------
# Visual Studio discovery.
#
# IMPORTANT: component checks read the filesystem of the SELECTED installation, never
# `vswhere -requires`. A machine often has more than one VS instance, and -requires searches
# ALL of them: it will report the ARM64 compiler present because some OTHER instance has it.
# The selected instance is also handed to CMake (CMAKE_GENERATOR_INSTANCE), so the compiler
# CMake drives and the dumpbin/cl the gate uses come from the same installation.
# ---------------------------------------------------------------------------------------------
function Find-VisualStudio {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw @"
vswhere.exe was not found at
    $vswhere
which means no Visual Studio 2017-or-newer installer is present. Install Visual Studio 2022 or
newer (or the Build Tools) with the "Desktop development with C++" workload - see README.txt,
PREREQUISITES.
"@
    }

    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1
    if (-not $installPath) {
        throw 'No Visual Studio installation with the C++ toolset was found. Install the "Desktop development with C++" workload - see README.txt, PREREQUISITES.'
    }
    $version = & $vswhere -path $installPath -property installationVersion | Select-Object -First 1
    $display = & $vswhere -path $installPath -property catalog_productDisplayVersion | Select-Object -First 1
    $name    = & $vswhere -path $installPath -property displayName | Select-Object -First 1
    return [pscustomobject]@{
        Path           = $installPath
        Version        = $version
        Major          = [int](($version -split '\.')[0])
        DisplayVersion = $display
        DisplayName    = $name
    }
}

function Get-VcVarsAllPath {
    param([Parameter(Mandatory)][string] $VsInstallPath)

    $vcvarsall = Join-Path $VsInstallPath 'VC\Auxiliary\Build\vcvarsall.bat'
    if (-not (Test-Path -LiteralPath $vcvarsall)) {
        throw "vcvarsall.bat was not found in $VsInstallPath. The C++ workload is not installed in THIS instance."
    }
    return $vcvarsall
}

# Does the SELECTED installation actually have an ARM64-targeting cl.exe? Checked on disk.
function Test-Arm64ToolsPresent {
    param([Parameter(Mandatory)][string] $VsInstallPath)

    $msvcRoot = Join-Path $VsInstallPath 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $msvcRoot)) { return $false }
    foreach ($toolset in Get-ChildItem -LiteralPath $msvcRoot -Directory) {
        foreach ($hostDir in @('Hostx64', 'Hostarm64')) {
            if (Test-Path -LiteralPath (Join-Path $toolset.FullName "bin\$hostDir\arm64\cl.exe")) { return $true }
        }
    }
    return $false
}

# The CMake "Visual Studio NN YYYY" generator for the selected instance, found by asking CMake
# which generators it offers rather than by a name table that goes stale with every Visual
# Studio release (the GameEngine.Sdl2 build script's approach). Visual Studio 2026 (major 18)
# needs a CMake new enough to know it.
function Get-VsGenerator {
    param([Parameter(Mandatory)][int] $VsMajor)

    $help = Invoke-Native 'cmake' @('--help')
    $generators = foreach ($line in $help) {
        if ($line -match '^\s*\*?\s*(Visual Studio (\d+) \d{4})(\s|=|$)') {
            [pscustomobject]@{ Name = $Matches[1].Trim(); Major = [int]$Matches[2] }
        }
    }
    $match = @($generators | Where-Object { $_.Major -eq $VsMajor } | Select-Object -First 1)
    if ($match.Count -eq 0) {
        $known = ($generators | ForEach-Object { $_.Name }) -join ', '
        throw "This cmake offers no generator for Visual Studio major version $VsMajor (it offers: $known). Install a newer cmake - see README.txt, PREREQUISITES."
    }
    return $match[0].Name
}

# ---------------------------------------------------------------------------------------------
# Import a developer environment into THIS PowerShell process, for the gate's cl and dumpbin.
# $ArchArgument is what vcvarsall takes: x64, arm64, or x64_arm64 (cross from an x64 host).
# (CMake's Visual Studio generator finds the compiler on its own; the environment is for the
# smoke test and dumpbin, so they come from the same toolset.)
# ---------------------------------------------------------------------------------------------
function Import-DeveloperEnvironment {
    param(
        [Parameter(Mandatory)][string] $VcVarsAll,
        [Parameter(Mandatory)][string] $ArchArgument
    )

    Write-Host "  developer environment: vcvarsall.bat $ArchArgument"
    # This exact invocation is llama-native-tools' - it has run for real (2026-09-15); keep it.
    $output = & "$env:COMSPEC" /s /c "`"$VcVarsAll`" $ArchArgument >nul 2>&1 && set"
    if ($LASTEXITCODE -ne 0) {
        throw "vcvarsall.bat $ArchArgument failed (exit $LASTEXITCODE). The toolset for that target is probably not installed in this Visual Studio instance."
    }
    foreach ($line in $output) {
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        Set-Item -Path "Env:$($line.Substring(0, $eq))" -Value $line.Substring($eq + 1)
    }
}

# cl.exe with no arguments prints its "Microsoft (R) C/C++ Optimizing Compiler Version ..."
# banner on STDERR and the usage line on STDOUT; pick the banner by content (llama's first
# win-x64 run recorded "usage: cl [ option... ]" by taking the first line).
function Get-ClVersionLine {
    $line = Invoke-Native 'cl' | Where-Object { $_ -match 'Compiler Version' } | Select-Object -First 1
    if (-not $line) { return 'cl (version banner not recognised)' }
    return $line.Trim()
}

function Assert-OnPath {
    param(
        [Parameter(Mandatory)][string] $Tool,
        [Parameter(Mandatory)][string] $InstallHint
    )
    $found = Get-Command $Tool -ErrorAction SilentlyContinue
    if (-not $found) {
        throw @"
$Tool is not on PATH.

$InstallHint

This script does not install anything for you. See README.txt, PREREQUISITES.
"@
    }
    return $found.Source
}

# ---------------------------------------------------------------------------------------------
# Source: copied to scratch and built there, so ..\SDL stays an unmodified, verifiable snapshot.
# Patches (none today - see ..\patches\README.txt) are applied to the copy, in name order.
# ---------------------------------------------------------------------------------------------
function Copy-SourceToScratch {
    param(
        [Parameter(Mandatory)][string] $SourceDir,
        [Parameter(Mandatory)][string] $ScratchDir,
        [Parameter(Mandatory)][string] $PatchDir
    )

    if (Test-Path -LiteralPath $ScratchDir) { Remove-Item -LiteralPath $ScratchDir -Recurse -Force }
    Copy-Item -LiteralPath $SourceDir -Destination $ScratchDir -Recurse
    Write-Host "  copied $SourceDir -> $ScratchDir"

    $applied = @()
    if (Test-Path -LiteralPath $PatchDir) {
        foreach ($patch in Get-ChildItem -LiteralPath $PatchDir -Filter '*.patch' | Sort-Object Name) {
            $git = Get-Command git -ErrorAction SilentlyContinue
            if (-not $git) {
                throw "patches\$($patch.Name) needs applying and git is not available. Install Git for Windows (winget install Git.Git)."
            }
            Write-Host "  applying $($patch.Name)"
            Invoke-Native 'git' @('-C', $ScratchDir, 'apply', '-p1', $patch.FullName) | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) {
                throw "patch $($patch.Name) did not apply. Fix it; patches are never applied best-effort."
            }
            $applied += $patch.Name
        }
    }
    if ($applied.Count -eq 0) { return 'none' }
    return ($applied -join ' ')
}

# ---------------------------------------------------------------------------------------------
# Configure + build SDL with CMake's Visual Studio generator, exactly as ppy's CI did (-A x64 /
# -A ARM64). Writes configure.log, build.log and cmake-summary.txt (SDL's own end-of-configure
# summary - the authoritative list of what was compiled in) into the build directory.
# Returns the full path of the built SDL3.dll.
# ---------------------------------------------------------------------------------------------
function Invoke-SdlBuild {
    param(
        [Parameter(Mandatory)][string]   $ScratchDir,
        [Parameter(Mandatory)][string]   $BuildDir,
        [Parameter(Mandatory)][string]   $Generator,
        [Parameter(Mandatory)][string]   $Platform,           # x64 | ARM64  (the -A value)
        [Parameter(Mandatory)][string]   $VsInstallPath,
        [Parameter(Mandatory)][string[]] $CmakeOptions
    )

    if (Test-Path -LiteralPath $BuildDir) { Remove-Item -LiteralPath $BuildDir -Recurse -Force }
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

    $arguments = @('-S', $ScratchDir, '-B', $BuildDir, '-G', $Generator, '-A', $Platform,
                   "-DCMAKE_GENERATOR_INSTANCE=$VsInstallPath") + $CmakeOptions
    Write-Host "  cmake $($arguments -join ' ')"
    $configure = Invoke-Native 'cmake' $arguments
    $configureExit = $LASTEXITCODE
    $configure | Set-Content -LiteralPath (Join-Path $BuildDir 'configure.log') -Encoding UTF8
    if ($configureExit -ne 0) {
        $configure | Select-Object -Last 30 | ForEach-Object { Write-Host "    $_" }
        throw "cmake configure failed (exit $configureExit) - see $BuildDir\configure.log"
    }

    # SDL prints "-- SDL3 was configured with the following options:" and then the summary to
    # the end of the configure output.
    $start = -1
    for ($i = 0; $i -lt $configure.Count; $i++) {
        if ($configure[$i] -match 'SDL3 was configured with the following options:') { $start = $i; break }
    }
    if ($start -ge 0) {
        $summary = $configure[$start..($configure.Count - 1)] | ForEach-Object { $_ -replace '^-- ', '' }
        $summary | Set-Content -LiteralPath (Join-Path $BuildDir 'cmake-summary.txt') -Encoding UTF8
        $summary | Where-Object { $_ -match '^\s*(Video drivers|Render drivers|GPU drivers|Audio drivers|Joystick drivers|Camera drivers|Platform|Revision):' } |
            ForEach-Object { Write-Host "    $_" }
    }
    else {
        Write-Host '  [warn] SDL''s configure summary was not found in the cmake output; cmake-summary.txt not written.'
    }
    $configure | Where-Object { $_ -match 'CMake Warning|CMake Error' } | ForEach-Object { Write-Host "  $_" }

    Write-Host "  building Release (log: $BuildDir\build.log) ..."
    $build = Invoke-Native 'cmake' @('--build', $BuildDir, '--config', 'Release', '--parallel')
    $buildExit = $LASTEXITCODE
    $build | Set-Content -LiteralPath (Join-Path $BuildDir 'build.log') -Encoding UTF8
    if ($buildExit -ne 0) {
        $build | Select-String -Pattern 'error|FAILED' -Context 2, 8 | Select-Object -First 5 | ForEach-Object { Write-Host $_ }
        throw "build failed (exit $buildExit) - see $BuildDir\build.log"
    }
    $warnings = @($build | Where-Object { $_ -match ': warning [A-Z]+\d+' })
    Write-Host "  built ($($warnings.Count) compiler/linker warning lines in build.log)"

    $dll = Join-Path $BuildDir 'Release\SDL3.dll'
    if (-not (Test-Path -LiteralPath $dll)) {
        # Fall back to searching, in case SDL changes its output layout.
        $found = Get-ChildItem -LiteralPath $BuildDir -Filter 'SDL3.dll' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) { throw "The build reported success but no SDL3.dll exists under $BuildDir." }
        $dll = $found.FullName
        Write-Host "  [note] SDL3.dll found at a non-default location: $dll"
    }
    return $dll
}

# ---------------------------------------------------------------------------------------------
# Helpers for the gate.
# ---------------------------------------------------------------------------------------------

# Every name SDL exports, from SDL's own export list (the version script SDL uses on ELF
# platforms; the dllexport set on Windows is the same set - ppy's DLLs export exactly these
# 1303 names). Read at gate time, so it cannot drift from the vendored commit.
function Get-SdlExportList {
    param([Parameter(Mandatory)][string] $SymPath)
    $names = foreach ($line in Get-Content -LiteralPath $SymPath) {
        if ($line -match '^\s+([A-Za-z_][A-Za-z0-9_]*);\s*$') { $Matches[1] }
    }
    # -CaseSensitive matters: SDL exports both SDL_Log and SDL_log, and a case-insensitive
    # -Unique would fold them into one name.
    return @($names | Sort-Object -Unique -CaseSensitive)
}

# PE machine type, read straight from the header (no tool involved): 0x8664 x64, 0xAA64 ARM64.
function Get-PeMachine {
    param([Parameter(Mandatory)][string] $Path)
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $fs.Position = $br.ReadInt32()
        if ($br.ReadUInt32() -ne 0x00004550) { throw "$Path is not a PE image." }
        return [int]$br.ReadUInt16()
    }
    finally { $fs.Dispose() }
}

$script:GateFailures = New-Object System.Collections.Generic.List[string]
function Add-GatePass { param([string] $Message) Write-Host "  [ok] $Message" }
function Add-GateFail { param([string] $Message) Write-Host "  [FAIL] $Message"; $script:GateFailures.Add($Message) }

function Invoke-Dumpbin {
    param([Parameter(Mandatory)][string[]] $Arguments)
    $output = Invoke-Native 'dumpbin' $Arguments
    if ($LASTEXITCODE -ne 0) { throw "dumpbin $($Arguments -join ' ') failed (exit $LASTEXITCODE)." }
    return $output
}

# Compile ..\smoke-test.c with the cl of the imported developer environment (so for the
# target architecture), static CRT (/MT) so the .exe also runs on a clean ARM64 machine when a
# cross-built gate is finished there.
function Build-SmokeTest {
    param(
        [Parameter(Mandatory)][string] $SourceFile,
        [Parameter(Mandatory)][string] $GateDir
    )
    New-Item -ItemType Directory -Path $GateDir -Force | Out-Null
    Push-Location $GateDir
    try {
        $out = Invoke-Native 'cl' @('/nologo', '/O1', '/MT', '/W3', $SourceFile, '/Fe:smoke-test.exe')
        $exit = $LASTEXITCODE
    }
    finally { Pop-Location }
    $out | Set-Content -LiteralPath (Join-Path $GateDir 'smoke-test-build.log') -Encoding UTF8
    if ($exit -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $GateDir 'smoke-test.exe'))) {
        $out | ForEach-Object { Write-Host "    $_" }
        throw "the smoke test did not compile (exit $exit) - see $GateDir\smoke-test-build.log"
    }
    return (Join-Path $GateDir 'smoke-test.exe')
}

# ---------------------------------------------------------------------------------------------
# THE GATE. The same checks as the Linux build, expressed with the tools Windows has.
# Returns the smoke test's output lines (for BUILD-INFO.txt).
# ---------------------------------------------------------------------------------------------
function Test-Sdl3Dll {
    param(
        [Parameter(Mandatory)][string]    $DllPath,             # the STAGED dll (the file that ships)
        [Parameter(Mandatory)][int]       $ExpectedMachine,     # 0x8664 | 0xAA64
        [Parameter(Mandatory)][string]    $ExpectedMachineName, # x64 | ARM64 (as dumpbin prints it)
        [Parameter(Mandatory)][string]    $SymPath,             # SDL\src\dynapi\SDL_dynapi.sym
        [Parameter(Mandatory)][hashtable] $Pins,
        [Parameter(Mandatory)][string]    $GateDir,             # holds smoke-test.exe
        [bool] $CanRunTargetBinaries = $true
    )

    # --- 1. machine type, two ways ---------------------------------------------------------------
    $machine = Get-PeMachine $DllPath
    if ($machine -eq $ExpectedMachine) {
        Add-GatePass ('PE machine type 0x{0:X4} ({1})' -f $machine, $ExpectedMachineName)
    }
    else {
        Add-GateFail ('PE machine type is 0x{0:X4}, expected 0x{1:X4} ({2}) - the -A platform did not take effect' -f $machine, $ExpectedMachine, $ExpectedMachineName)
    }
    $machineLine = Invoke-Dumpbin @('/nologo', '/headers', $DllPath) | Where-Object { $_ -match 'machine \(' } | Select-Object -First 1
    if ($machineLine -and $machineLine -match [regex]::Escape($ExpectedMachineName)) {
        Add-GatePass "dumpbin agrees: $($machineLine.Trim())"
    }
    else {
        Add-GateFail "dumpbin /headers machine line is '$machineLine', expected $ExpectedMachineName"
    }

    # --- 2. exports: exactly SDL's export list ---------------------------------------------------
    # dumpbin prints "ordinal hint RVA name"; with the .pdb beside the DLL it appends
    # " = name (undecorated)" to each line, so the name is the FIRST token after the RVA.
    # (llama's first win-x64 run anchored at end-of-line and parsed zero names.)
    $exports = @()
    foreach ($line in Invoke-Dumpbin @('/nologo', '/exports', $DllPath)) {
        if ($line -match '^\s*\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)') { $exports += $Matches[1] }
    }
    if ($exports.Count -eq 0) {
        Add-GateFail 'no exports could be parsed from dumpbin /exports - run it on the DLL by hand and compare the line format with the parser in Test-Sdl3Dll'
    }
    $expected = Get-SdlExportList $SymPath
    $missing = @($expected | Where-Object { $exports -cnotcontains $_ })
    $extra   = @($exports  | Where-Object { $expected -cnotcontains $_ })
    if ($missing.Count -gt 0) { Add-GateFail "missing exports ($($missing.Count)): $(($missing | Select-Object -First 10) -join ' ')" }
    if ($extra.Count -gt 0)   { Add-GateFail "unexpected exports ($($extra.Count)): $(($extra | Select-Object -First 10) -join ' ')" }
    if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $exports.Count -gt 0) {
        Add-GatePass "exports are exactly the $($expected.Count) names in SDL_dynapi.sym"
    }
    $sample = @($Pins['REQUIRED_SYMBOLS'] -split '\s+' | Where-Object { $_ -ne '' -and $exports -cnotcontains $_ })
    if ($sample.Count -gt 0) { Add-GateFail "pins.env REQUIRED_SYMBOLS not exported: $($sample -join ' ')" }
    else { Add-GatePass 'pins.env REQUIRED_SYMBOLS (SDL_Init, SDL_GetVersion, ...) all exported' }

    # --- 3. dependents: operating-system DLLs only, no VC runtime --------------------------------
    $dependents = @()
    $inList = $false
    foreach ($line in Invoke-Dumpbin @('/nologo', '/dependents', $DllPath)) {
        $text = $line.Trim()
        if ($text -like 'Image has the following dependencies*') { $inList = $true; continue }
        if ($text -like 'Image has the following delay load dependencies*') { $inList = $true; continue }
        if ($inList) {
            if ($text -eq '') { continue }
            if ($text -like 'Summary*') { break }
            $dependents += $text
        }
    }
    $crt = @($dependents | Where-Object { $_ -match '^(vcruntime|msvcp|msvcr|ucrtbase|api-ms-win-crt)' })
    $unexpected = @($dependents | Where-Object { $script:AllowedDependents -notcontains $_ })
    if ($crt.Count -gt 0) {
        Add-GateFail "the DLL imports the Visual C++ runtime ($($crt -join ' ')) - CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded did not take; every user would need a redistributable"
    }
    if ($unexpected.Count -gt 0) {
        Add-GateFail "unexpected dependencies: $($unexpected -join ' ') (allowed: $($script:AllowedDependents -join ' '))"
    }
    if ($crt.Count -eq 0 -and $unexpected.Count -eq 0) {
        Add-GatePass "dependencies are operating-system DLLs only, no VC runtime: $($dependents -join ' ')"
    }

    if (-not $CanRunTargetBinaries) {
        Add-GateFail 'smoke test NOT RUN - this machine cannot execute the target architecture. (Reported as a failure on purpose: an unrun check is not a passed check.)'
        return @('  not run: this machine cannot execute the target architecture')
    }

    # --- 4. LoadLibrary smoke test ---------------------------------------------------------------
    # THE PATH TRAP. The staged DLL is copied beside smoke-test.exe and passed by full path, so
    # the exact bytes that ship are what loads - never an SDL3.dll found on PATH. (dav1d's first
    # Windows run loaded GStreamer's dav1d.dll from PATH; SDL3.dll is an even commoner name.)
    $gateDll = Join-Path $GateDir 'SDL3.dll'
    Copy-Item -LiteralPath $DllPath -Destination $gateDll -Force
    Write-Host '  --- LoadLibrary smoke test (dummy video driver) ---'
    Push-Location $GateDir
    try {
        $smoke = Invoke-Native (Join-Path $GateDir 'smoke-test.exe') @($gateDll, $Pins['SDL_VERSION_NUM'])
        $smokeExit = $LASTEXITCODE
    }
    finally { Pop-Location }
    $smoke | ForEach-Object { Write-Host "    $_" }
    if ($smokeExit -eq 0) { Add-GatePass "smoke test (SDL_GetVersion == $($Pins['SDL_VERSION_NUM']), init, window, renderer, draw + read-back, quit)" }
    else { Add-GateFail "smoke test exited $smokeExit" }

    # --- 5. the revision string the managed side reports -----------------------------------------
    $revisionLine = $smoke | Where-Object { $_ -match '^SDL_GetRevision' } | Select-Object -First 1
    if ($revisionLine -and $revisionLine -match [regex]::Escape($Pins['SDL_REVISION_STRING'])) {
        Add-GatePass "SDL_GetRevision() = $($Pins['SDL_REVISION_STRING'])"
    }
    else {
        Add-GateFail "SDL_GetRevision() line is '$revisionLine', expected $($Pins['SDL_REVISION_STRING'])"
    }
    return $smoke
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# ---------------------------------------------------------------------------------------------
# Collect, record and stage - shared by both architecture scripts.
# ---------------------------------------------------------------------------------------------
function Copy-BuildToOutput {
    param(
        [Parameter(Mandatory)][string]    $BuiltDll,
        [Parameter(Mandatory)][string]    $BuildDir,
        [Parameter(Mandatory)][string]    $OutDir,
        [Parameter(Mandatory)][string]    $SourceDir,
        [Parameter(Mandatory)][hashtable] $Pins
    )
    if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    Copy-Item -LiteralPath $BuiltDll -Destination (Join-Path $OutDir 'SDL3.dll')
    $pdb = [System.IO.Path]::ChangeExtension($BuiltDll, '.pdb')
    if (Test-Path -LiteralPath $pdb) {
        Copy-Item -LiteralPath $pdb -Destination (Join-Path $OutDir 'SDL3.pdb')
        Write-Host '  SDL3.pdb kept beside the DLL (crash triage; NOT shipped - goes to ..\unstripped\<rid>\ on adoption)'
    }
    else {
        Write-Host '  [warn] no SDL3.pdb was produced - the options ask for /Z7 and /DEBUG; check build.log.'
    }
    Copy-Item -LiteralPath (Join-Path $SourceDir 'LICENSE.txt') -Destination (Join-Path $OutDir $Pins['LICENSE_FILE_NAME'])
    Write-Host "  $($Pins['LICENSE_FILE_NAME']) : SDL's LICENSE.txt (zlib), verbatim"
    $summary = Join-Path $BuildDir 'cmake-summary.txt'
    if (Test-Path -LiteralPath $summary) { Copy-Item -LiteralPath $summary -Destination (Join-Path $OutDir 'cmake-summary.txt') }
}

function Write-Sha256Sums {
    param([Parameter(Mandatory)][string] $OutDir)
    $lines = foreach ($name in @('SDL3.dll', 'SDL3.pdb', 'LICENSE-SDL3.txt')) {
        $p = Join-Path $OutDir $name
        if (Test-Path -LiteralPath $p) { "$(Get-Sha256 $p)  $name" }
    }
    # LF line endings and no BOM, so `sha256sum -c` on Linux or macOS can check the file as is.
    [System.IO.File]::WriteAllText((Join-Path $OutDir 'SHA256SUMS.txt'), (($lines -join "`n") + "`n"))
}

function Get-EnabledBackends {
    param([Parameter(Mandatory)][string] $OutDir)
    $summary = Join-Path $OutDir 'cmake-summary.txt'
    if (-not (Test-Path -LiteralPath $summary)) { return '                    (cmake-summary.txt missing)' }
    $lines = Get-Content -LiteralPath $summary | Where-Object { $_ -match '^\s*(Video drivers|Render drivers|GPU drivers|Audio drivers|Joystick drivers|Camera drivers):' }
    return (($lines | ForEach-Object { '                    ' + $_.Trim() }) -join "`n")
}

# ---------------------------------------------------------------------------------------------
# THE WHOLE BUILD, for one RID. The two architecture scripts decide the route and call this;
# keeping one copy of the sequence means the two RIDs cannot drift apart.
#   -VcVarsArch   x64 | arm64 | x64_arm64     (vcvarsall argument, for the gate's cl/dumpbin)
#   -Platform     x64 | ARM64                 (CMake -A value)
#   -CanRun       can this host execute the target's code (false only for the arm64 cross route)
# Exit code: 0 = every check ran and passed. 1 = a check failed OR could not run.
# ---------------------------------------------------------------------------------------------
function Invoke-WindowsSdlBuild {
    param(
        [Parameter(Mandatory)][string] $Rid,
        [Parameter(Mandatory)][string] $Platform,
        [Parameter(Mandatory)][int]    $ExpectedMachine,
        [Parameter(Mandatory)][string] $VcVarsArch,
        [Parameter(Mandatory)][string] $Route,
        [Parameter(Mandatory)][bool]   $CanRun,
        [Parameter(Mandatory)][string] $BuildRoot,
        [Parameter(Mandatory)][string] $ScriptName,
        [switch] $GameInput
    )

    $toolsDir   = Split-Path -Parent $PSScriptRoot          # sdl3-native-tools\
    $pins       = Read-Pins (Join-Path $toolsDir 'linux\pins.env')
    $sourceDir  = Join-Path $toolsDir $pins['SDL_DIR']
    $patchDir   = Join-Path $toolsDir 'patches'
    $smokeSrc   = Join-Path $toolsDir 'smoke-test.c'
    $symPath    = Join-Path $sourceDir 'src\dynapi\SDL_dynapi.sym'
    $scratchDir = Join-Path $env:TEMP "codebrix-sdl3-src-$Rid"
    $buildDir   = Join-Path $BuildRoot 'build'
    $gateDir    = Join-Path $BuildRoot 'gate'
    $outDir     = Join-Path $toolsDir "output\$Rid"
    $startedAt  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
    $stopwatch  = [System.Diagnostics.Stopwatch]::StartNew()
    $osCaption  = (Get-CimInstance Win32_OperatingSystem).Caption
    $osVersion  = [System.Environment]::OSVersion.Version.ToString()

    Write-Host '=============================================================================='
    Write-Host " SDL $($pins['SDL_VERSION']) ($($pins['SDL_COMMIT'].Substring(0, 7))) - $Rid"
    Write-Host '=============================================================================='
    Write-Host "  started  : $startedAt"
    Write-Host "  host     : $env:PROCESSOR_ARCHITECTURE, $osCaption $osVersion"
    Write-Host "  route    : $Route"
    Write-Host "  source   : $sourceDir  (vendored - nothing is downloaded)"
    Write-Host ''

    # --- 1. prerequisites, all of them, before anything is compiled ------------------------------
    Write-Host '--- prerequisites ---'
    $vs = Find-VisualStudio
    Write-Host "  Visual Studio: $($vs.DisplayName) $($vs.DisplayVersion) [$($vs.Version)] at $($vs.Path)"
    $vcvarsall = Get-VcVarsAllPath $vs.Path
    if ($Platform -eq 'ARM64' -and -not (Test-Arm64ToolsPresent $vs.Path)) {
        throw @"
The ARM64 C++ build tools are not installed in THIS Visual Studio instance ($($vs.Path)).
Add the component "MSVC v143 - VS 2022 C++ ARM64/ARM64EC build tools (Latest)" - or the
equivalent "MSVC Build Tools for ARM64/ARM64EC" in newer Visual Studio - to that instance:
see README.txt, PREREQUISITES. (The check reads this instance's filesystem on purpose.)
"@
    }
    Import-DeveloperEnvironment -VcVarsAll $vcvarsall -ArchArgument $VcVarsArch

    $clPath    = Assert-OnPath 'cl'      'cl ships with the "Desktop development with C++" workload; it should be on PATH inside the developer environment.'
    $dumpbin   = Assert-OnPath 'dumpbin' 'dumpbin ships with the C++ toolset; it should be on PATH inside the developer environment.'
    $cmakePath = Assert-OnPath 'cmake'   "Install it: winget install Kitware.CMake   (pinned for Linux: $($pins['CMAKE_VERSION']); SDL needs >= 3.16, Visual Studio 2026 needs a cmake that knows the 'Visual Studio 18 2026' generator)"
    $cmakeVersion = (Invoke-Native 'cmake' @('--version') | Select-Object -First 1)
    $generator = Get-VsGenerator -VsMajor $vs.Major
    $clVersion = Get-ClVersionLine
    $sdkVersion = if ($env:WindowsSDKVersion) { $env:WindowsSDKVersion.TrimEnd('\') } else { 'unknown' }

    Write-Host "  cl       : $clVersion  [$clPath]"
    Write-Host "  dumpbin  : $dumpbin"
    Write-Host "  cmake    : $cmakeVersion  [$cmakePath]"
    Write-Host "  generator: $generator -A $Platform"
    Write-Host "  Win SDK  : $sdkVersion"
    if ($CanRun) { Write-Host '  execute  : this host runs the target architecture - the full gate will be applied' }
    else { Write-Host '  execute  : this host CANNOT run the target architecture - the smoke test cannot run and will be reported as a failure' }

    foreach ($required in @((Join-Path $sourceDir 'CMakeLists.txt'), $symPath, $smokeSrc, (Join-Path $sourceDir 'LICENSE.txt'))) {
        if (-not (Test-Path -LiteralPath $required)) { throw "$required is missing. It is part of the repository; restore it from git." }
    }
    Write-Host ''

    # --- 2. source + build -------------------------------------------------------------------------
    Write-Host '--- source ---'
    $patchesApplied = Copy-SourceToScratch -SourceDir $sourceDir -ScratchDir $scratchDir -PatchDir $patchDir
    Write-Host "  patches applied: $patchesApplied"
    Write-Host ''

    Write-Host '--- building ---'
    $options = Get-SdlWindowsCmakeOptions -Pins $pins -GameInput:$GameInput
    $builtDll = Invoke-SdlBuild -ScratchDir $scratchDir -BuildDir $buildDir -Generator $generator -Platform $Platform `
                                -VsInstallPath $vs.Path -CmakeOptions $options
    Write-Host ''

    Write-Host '--- smoke test program ---'
    $smokeExe = Build-SmokeTest -SourceFile $smokeSrc -GateDir $gateDir
    $smokeMachine = Get-PeMachine $smokeExe
    if ($smokeMachine -ne $ExpectedMachine) {
        throw ('smoke-test.exe was compiled for machine 0x{0:X4}, not 0x{1:X4}: the developer environment ({2}) is not the target''s.' -f $smokeMachine, $ExpectedMachine, $VcVarsArch)
    }
    Write-Host "  $smokeExe (machine 0x$('{0:X4}' -f $smokeMachine))"
    Write-Host ''

    # --- 3. collect ---------------------------------------------------------------------------------
    Write-Host '--- collecting ---'
    Copy-BuildToOutput -BuiltDll $builtDll -BuildDir $buildDir -OutDir $outDir -SourceDir $sourceDir -Pins $pins
    Write-Host ''

    # --- 4. the gate --------------------------------------------------------------------------------
    Write-Host '--- verifying ---'
    $dllPath = Join-Path $outDir 'SDL3.dll'
    $machineName = if ($ExpectedMachine -eq 0xAA64) { 'ARM64' } else { 'x64' }
    $smokeOutput = Test-Sdl3Dll -DllPath $dllPath -ExpectedMachine $ExpectedMachine -ExpectedMachineName $machineName `
                                -SymPath $symPath -Pins $pins -GateDir $gateDir -CanRunTargetBinaries $CanRun

    $complete = ($script:GateFailures.Count -eq 0)
    $gateStatus = if ($complete) { 'COMPLETE - every check ran and passed' }
                  elseif (-not $CanRun) { 'INCOMPLETE - cross-built; the static checks are above, the smoke test is UNRUN. Finish it on ARM64 hardware (README.txt).' }
                  else { 'FAILED' }

    # A build that FAILED a check that could run records nothing and must not be adopted. A
    # cross build records its result even though it exits 1: its output travels to another
    # machine to be finished and needs the paper trail.
    if (-not $complete -and $CanRun) {
        Write-Host ''
        Write-Host "VERIFICATION FAILED for $Rid. $outDir is left for inspection, but this build must"
        Write-Host 'not be adopted into the package.'
        exit 1
    }
    $staticFailures = @($script:GateFailures | Where-Object { $_ -notlike 'smoke test NOT RUN*' })
    if ($staticFailures.Count -gt 0) {
        Write-Host ''
        Write-Host "VERIFICATION FAILED for $Rid (a check that did run failed). Not recorded; must not be adopted."
        exit 1
    }

    # --- 5. record + stage ----------------------------------------------------------------------------
    Write-Sha256Sums -OutDir $outDir
    $sha = Get-Sha256 $dllPath
    $size = (Get-Item -LiteralPath $dllPath).Length
    $pdbPath = Join-Path $outDir 'SDL3.pdb'
    $pdbLine = if (Test-Path -LiteralPath $pdbPath) { "SDL3.pdb, $((Get-Item -LiteralPath $pdbPath).Length) bytes, sha256 $(Get-Sha256 $pdbPath) (not shipped)" } else { 'none produced' }
    $stopwatch.Stop()

    $buildInfoText = @"
SDL3 native library - build information
==============================================================================
RID              : $Rid
Gate status      : $gateStatus
Built            : $startedAt
Build duration   : $([int]$stopwatch.Elapsed.TotalSeconds)s
Built by         : sdl3-native-tools\windows\$ScriptName  (route: $Route)

Build machine
------------------------------------------------------------------------------
OS               : $osCaption $osVersion ($env:PROCESSOR_ARCHITECTURE)
Visual Studio    : $($vs.DisplayName) $($vs.DisplayVersion) [$($vs.Version)]
                   $($vs.Path)
cl               : $clVersion
Windows SDK      : $sdkVersion
cmake            : $cmakeVersion
generator        : $generator -A $Platform (CMAKE_GENERATOR_INSTANCE = the instance above)

Source (vendored in-repo; nothing fetched at build time)
------------------------------------------------------------------------------
SDL              : $($pins['SDL_VERSION']), commit $($pins['SDL_COMMIT']) ("$($pins['SDL_COMMIT_SUBJECT'])")
Vendored at      : sdl3-native-tools\SDL\ (see UPSTREAM.txt)
Patches applied  : $patchesApplied

Configuration
------------------------------------------------------------------------------
cmake options    : $($options -join "`n                   ")
CRT              : static (MultiThreaded) - no Visual C++ Redistributable needed
GameInput        : $(if ($GameInput) { 'left to SDL''s own detection (-GameInput)' } else { 'OFF (HAVE_GAMEINPUT_H pre-seeded OFF, as ppy''s sed did) - see README.txt, GAMEINPUT' })

Enabled backends (SDL's own CMake summary; the full summary is cmake-summary.txt)
------------------------------------------------------------------------------
$(Get-EnabledBackends -OutDir $outDir)

Result
------------------------------------------------------------------------------
File             : SDL3.dll  (DllImport("SDL3") probes this name)
Size             : $size bytes
SHA256           : $sha
Debug symbols    : $pdbLine
Licence beside it: $($pins['LICENSE_FILE_NAME']) (SDL's LICENSE.txt, zlib, verbatim)

Smoke test ($(if ($CanRun) { 'ran on this machine' } else { 'NOT RUN - cross build' }))
------------------------------------------------------------------------------
$(($smokeOutput | ForEach-Object { "  $_" }) -join "`n")
"@
    Set-Content -LiteralPath (Join-Path $outDir 'BUILD-INFO.txt') -Value $buildInfoText -Encoding UTF8

    # Staging: a compressed copy for moving the binary to whichever machine assembles the package.
    # .zip because Compress-Archive is in the box on Windows (Linux stages .xz, macOS .gz).
    $stagingDir = Join-Path $toolsDir "output\staging\$Rid"
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
    $stageFiles = @($dllPath, (Join-Path $outDir 'BUILD-INFO.txt'), (Join-Path $outDir 'SHA256SUMS.txt'), (Join-Path $outDir $pins['LICENSE_FILE_NAME']))
    if (Test-Path -LiteralPath $pdbPath) { $stageFiles += $pdbPath }
    Compress-Archive -Path $stageFiles -DestinationPath (Join-Path $stagingDir "SDL3-$Rid.zip") -Force
    if (-not $CanRun) {
        # The DLL plus the target-architecture smoke test, to finish the gate on real hardware.
        Compress-Archive -Path @($dllPath, $smokeExe) -DestinationPath (Join-Path $stagingDir "$Rid-gate.zip") -Force
        Write-Host "  staged $stagingDir\$Rid-gate.zip (SDL3.dll + the $machineName smoke-test.exe)"
    }

    Write-Host ''
    Write-Host '--- done ---'
    Write-Host "  $dllPath"
    Write-Host "  sha256 $sha"
    Write-Host "  staged $stagingDir\SDL3-$Rid.zip"
    Write-Host "  $([int]$stopwatch.Elapsed.TotalSeconds)s"
    Write-Host ''
    if (-not $complete) {
        Write-Host "GATE INCOMPLETE: this DLL was cross-built and has NOT been executed. Finish the gate on an"
        Write-Host 'ARM64 Windows machine before adopting it - README.txt, "FINISHING A CROSS-BUILT win-arm64".'
        exit 1
    }
    Write-Host 'To adopt this binary into the package, follow ADOPTING A BUILT BINARY in README.txt.'
    exit 0
}
