# =============================================================================================
# build-win-arm64.ps1 - build SDL3.dll for the win-arm64 runtime identifier
# =============================================================================================
#
#   NEVER YET RUN (either route). Written on Linux on 2026-10-01. Expect to fix something on
#   the first real run; fix it IN THE SCRIPT (or build-common.ps1) and record it in
#   ..\BUILD-PROVENANCE.txt. Then rewrite this header and README.txt's status block.
#
# USAGE (from any PowerShell prompt - the script sets up the compiler environment itself):
#
#     cd sdl3-native-tools\windows
#     .\build-win-arm64.ps1                       # on an ARM64 Windows machine (preferred)
#     .\build-win-arm64.ps1 -Route CrossFromX64   # on an x64 Windows machine (partial gate)
#     ... -GameInput                              # leave GameInput detection to SDL
#
# THE COMPILER IS MSVC (cl), NOT clang-cl. llama and dav1d needed clang-cl on ARM64 for their
# NEON intrinsics and assembly; SDL needs neither - it builds with cl for ARM64 out of the box,
# and that is exactly how ppy built the win-arm64 DLL that is currently adopted (-A ARM64, on an
# x64 runner). So both routes use the same CMake Visual Studio generator with -A ARM64; they
# differ only in the HOST, which decides whether the gate can RUN what it built.
#
# THE TWO ROUTES
#   -Route Native (default) - run on an ARM64 Windows machine. Preferred: the smoke test runs.
#       Developer environment: vcvarsall arm64 (the ARM64-hosted tools).
#   -Route CrossFromX64 - run on an x64 Windows machine. Developer environment: vcvarsall
#       x64_arm64. It produces the DLL and an ARM64 smoke-test.exe and runs the static checks
#       (machine type, exports, dependents), but it CANNOT run the smoke test. That is reported
#       as a FAILURE and the script exits 1 - an unrun check is not a passed check. It still
#       writes BUILD-INFO.txt with "Gate status: INCOMPLETE" and stages win-arm64-gate.zip
#       (DLL + ARM64 smoke-test.exe) so the gate can be finished on ARM64 hardware.
#
# Output: ..\output\win-arm64\
# =============================================================================================

[CmdletBinding()]
param(
    [ValidateSet('Native', 'CrossFromX64')]
    [string] $Route = 'Native',
    [string] $BuildRoot = (Join-Path $env:TEMP 'codebrix-sdl3-build-win-arm64'),
    [switch] $GameInput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\build-common.ps1"

$hostIsArm64 = ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64')
if ($Route -eq 'Native' -and -not $hostIsArm64) {
    throw "-Route Native must run on an ARM64 Windows machine; this host is $env:PROCESSOR_ARCHITECTURE. Use -Route CrossFromX64 here, or run on the ARM64 machine."
}
if ($Route -eq 'CrossFromX64' -and $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw "-Route CrossFromX64 runs on an x64 Windows machine; this host is $env:PROCESSOR_ARCHITECTURE. On ARM64 use the default -Route Native."
}

$vcvarsArch = if ($Route -eq 'Native') { 'arm64' } else { 'x64_arm64' }
$routeText  = if ($Route -eq 'Native') { 'Native (ARM64 host)' } else { 'CrossFromX64 (x64 host, -A ARM64)' }

Invoke-WindowsSdlBuild -Rid 'win-arm64' -Platform 'ARM64' -ExpectedMachine 0xAA64 -VcVarsArch $vcvarsArch `
                       -Route $routeText -CanRun $hostIsArm64 -BuildRoot $BuildRoot `
                       -ScriptName 'build-win-arm64.ps1' -GameInput:$GameInput
