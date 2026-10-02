# =============================================================================================
# build-win-x64.ps1 - build SDL3.dll for the win-x64 runtime identifier
# =============================================================================================
#
#   NEVER YET RUN. Written on Linux on 2026-10-01. Expect to fix something on the first real
#   run; fix it IN THE SCRIPT (or build-common.ps1) and record it in ..\BUILD-PROVENANCE.txt.
#   Then rewrite this header and README.txt's status block with what the run established.
#
# USAGE (from any PowerShell prompt - the script sets up the compiler environment itself):
#
#     cd sdl3-native-tools\windows
#     .\build-win-x64.ps1
#     .\build-win-x64.ps1 -GameInput     # leave GameInput detection to SDL (README.txt, GAMEINPUT)
#
# Built with MSVC (cl) through CMake's Visual Studio generator, -A x64, static CRT - the recipe
# ppy/SDL3-CS 2026.722.0 used for the DLL that is currently adopted (README.txt says how the two
# differ: a .pdb, and nothing else that changes code). Output: ..\output\win-x64\
# It installs nothing. Anything missing is named, with the command that installs it, and the
# script stops.
# =============================================================================================

[CmdletBinding()]
param(
    # Where cmake builds and the gate runs. Kept out of the repository so the vendored source
    # and the output tree stay clean.
    [string] $BuildRoot = (Join-Path $env:TEMP 'codebrix-sdl3-build-win-x64'),
    [switch] $GameInput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\build-common.ps1"

if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    # An ARM64 Windows machine can run x64 code under emulation, but the x64-hosted compiler
    # and a native-x64 gate are what this recipe assumes. Build win-x64 on an x64 machine.
    throw "build-win-x64.ps1 runs on an x64 Windows machine; this host is $env:PROCESSOR_ARCHITECTURE."
}

Invoke-WindowsSdlBuild -Rid 'win-x64' -Platform 'x64' -ExpectedMachine 0x8664 -VcVarsArch 'x64' `
                       -Route 'native (x64 host)' -CanRun $true -BuildRoot $BuildRoot `
                       -ScriptName 'build-win-x64.ps1' -GameInput:$GameInput
