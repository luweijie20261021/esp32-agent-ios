#requires -Version 5.1
<#
.SYNOPSIS
    Download and install Sideloadly for Windows.
.DESCRIPTION
    Sideloadly is used to install the unsigned IPhoneAgent.ipa onto an iPhone
    from Windows without a Mac. This script downloads the official installer and
    runs it. Administrator rights are required for installation.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\Sideloadly",
    [switch]$NoInstall
)

$ErrorActionPreference = "Stop"

$DownloadUrl = "https://sideloadly.io/SideloadlySetup32.exe"
$InstallerName = "SideloadlySetup32.exe"
$TempDir = "$env:TEMP\sideloadly-install"
$InstallerPath = "$TempDir\$InstallerName"

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Sideloadly downloader / installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Download
if (Test-Path $InstallerPath) {
    Write-Host "Installer already exists: $InstallerPath" -ForegroundColor Green
} else {
    Write-Host "Downloading Sideloadly from $DownloadUrl ..." -ForegroundColor Cyan
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -C - -L --fail --ssl-no-revoke -o $InstallerPath $DownloadUrl
        if ($LASTEXITCODE -ne 0) { throw "curl download failed with exit code $LASTEXITCODE" }
    } else {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    }
    Write-Host "Download complete." -ForegroundColor Green
}

if ($NoInstall) {
    Write-Host "Downloaded to: $InstallerPath" -ForegroundColor Yellow
    Write-Host "Run it manually to install." -ForegroundColor Yellow
    exit 0
}

# Install silently if possible. Sideloadly uses NSIS; /S is the standard silent flag.
Write-Host "Installing Sideloadly..." -ForegroundColor Cyan
if (-not (Test-Admin)) {
    Write-Warning "Not running as Administrator. Sideloadly installer may prompt for UAC."
}

try {
    $proc = Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -PassThru -Verb RunAs
    if ($proc.ExitCode -ne 0) {
        Write-Warning "Installer exited with code $($proc.ExitCode). You may need to run it manually."
    } else {
        Write-Host "Sideloadly installed successfully." -ForegroundColor Green
    }
} catch {
    Write-Warning "Silent install failed: $($_.Exception.Message)"
    Write-Host "Please run the installer manually: $InstallerPath" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next step: use sideload_ipa.ps1 to install the IPA, or run Sideloadly from Start Menu." -ForegroundColor Cyan
