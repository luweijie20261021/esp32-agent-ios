#requires -Version 5.1
<#
.SYNOPSIS
    Download and install Sideloadly for Windows.
.DESCRIPTION
    Sideloadly is used to install the unsigned IPhoneAgent.ipa onto an iPhone
    from Windows without a Mac. This script downloads the official installer and
    runs it. Administrator rights are required for installation.

    On a slow network, use -Resume to keep retrying until the download finishes.
#>
[CmdletBinding()]
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\Sideloadly",
    [switch]$NoInstall,
    [switch]$Resume
)

$ErrorActionPreference = "Stop"

$Is64Bit = [Environment]::Is64BitOperatingSystem
if ($Is64Bit) {
    $DownloadUrl = "https://sideloadly.io/SideloadlySetup64.exe"
    $InstallerName = "SideloadlySetup64.exe"
} else {
    $DownloadUrl = "https://sideloadly.io/SideloadlySetup32.exe"
    $InstallerName = "SideloadlySetup32.exe"
}

$TempDir = "$env:TEMP\sideloadly-install"
$InstallerPath = "$TempDir\$InstallerName"

function Test-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RemoteFileSize {
    param([string]$Url)
    try {
        $resp = Invoke-WebRequest -Uri $Url -Method HEAD -UseBasicParsing -TimeoutSec 15
        $len = $resp.Headers['Content-Length']
        if ($len) { return [long]$len }
    } catch {}
    return $null
}

if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Sideloadly downloader / installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Determine expected size
$ExpectedSize = Get-RemoteFileSize $DownloadUrl
if ($ExpectedSize) {
    Write-Host "Installer size: $([math]::Round($ExpectedSize/1MB,2)) MB" -ForegroundColor DarkGray
}

# Check existing file
$CurrentSize = 0
if (Test-Path $InstallerPath) {
    $CurrentSize = (Get-Item $InstallerPath).Length
    Write-Host "Existing file: $InstallerPath ($([math]::Round($CurrentSize/1MB,2)) MB)" -ForegroundColor Yellow
}

$NeedDownload = $true
if ($ExpectedSize -and $CurrentSize -ge $ExpectedSize) {
    $NeedDownload = $false
    Write-Host "Installer already complete." -ForegroundColor Green
}

if ($NeedDownload) {
    if (-not $Resume -and $CurrentSize -gt 0) {
        Write-Warning "Partial download exists. Use -Resume to continue, or delete $InstallerPath and rerun."
        exit 1
    }

    Write-Host "Downloading Sideloadly from $DownloadUrl ..." -ForegroundColor Cyan
    Write-Host "On a slow connection this can take a long time. Leave this window open." -ForegroundColor DarkGray

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        do {
            & curl.exe -C - -L --fail --ssl-no-revoke -o $InstallerPath $DownloadUrl
            $exit = $LASTEXITCODE
            if ($exit -ne 0) {
                Write-Warning "curl returned $exit. Will retry in 5 seconds..."
                Start-Sleep -Seconds 5
            }
        } while ($Resume -and $exit -ne 0)
        if ($exit -ne 0) { throw "curl download failed with exit code $exit" }
    } else {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $InstallerPath -UseBasicParsing
    }

    # Verify
    $FinalSize = (Get-Item $InstallerPath).Length
    if ($ExpectedSize -and $FinalSize -lt $ExpectedSize) {
        throw "Download incomplete: $FinalSize / $ExpectedSize bytes. Use -Resume to continue."
    }
    Write-Host "Download complete ($([math]::Round($FinalSize/1MB,2)) MB)." -ForegroundColor Green
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
