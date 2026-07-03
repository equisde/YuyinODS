# YuyinODS Root Installer (Windows)
# Delegates to yuyinods/installers/windows/install-windows.ps1

param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NonInteractive,
    [string]$Tier = "",
    [switch]$Voice,
    [switch]$Workflows,
    [switch]$Rag,
    [switch]$Recommended,
    [switch]$NoRecommended,
    [switch]$Hermes,
    [switch]$NoHermes,
    [switch]$OpenClaw,
    [switch]$All,
    [switch]$Cloud,
    [switch]$Comfyui,
    [switch]$NoComfyui,
    [switch]$Langfuse,
    [switch]$NoLangfuse,
    [switch]$NoBootstrap,
    [switch]$Lan,
    [string]$InstallDir = "",
    [string]$SummaryJsonPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "YuyinODS Installer" -ForegroundColor Cyan
Write-Host ""

# Delegate to Windows installer
$YuyinODSInstaller = Join-Path (Join-Path (Join-Path $ScriptDir "yuyinods") "installers") "windows" | Join-Path -ChildPath "install-windows.ps1"
if (-not (Test-Path $YuyinODSInstaller)) {
    Write-Host "Error: Windows installer not found" -ForegroundColor Red
    Write-Host "Expected: $YuyinODSInstaller" -ForegroundColor Red
    exit 1
}

# Forward all bound parameters to the real installer.
# A successful PowerShell script can leave a stale $LASTEXITCODE from a handled
# native command, so only use $LASTEXITCODE when the delegated installer fails.
$global:LASTEXITCODE = 0
& $YuyinODSInstaller @PSBoundParameters
$installerSucceeded = $?
$installerExit = if ($null -ne $global:LASTEXITCODE) { [int]$global:LASTEXITCODE } else { 0 }
if ($installerExit -ne 0) {
    exit $installerExit
}
if ($installerSucceeded) {
    exit 0
}
exit 1
