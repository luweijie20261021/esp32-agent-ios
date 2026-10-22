#requires -Version 5.1
<#
.SYNOPSIS
    Helper to sideload IPhoneAgent.ipa onto an iPhone using Sideloadly on Windows.
.DESCRIPTION
    This script checks prerequisites and then launches Sideloadly with the IPA.
    Sideloadly itself is a GUI tool, so you will still need to enter your Apple ID
    and tap Trust on the iPhone.

    Usage:
        .\sideload_ipa.ps1 -IpaPath C:\path\to\IPhoneAgent-unsigned.ipa

    If -IpaPath is omitted, the script looks in the Downloads folder and the current
    directory for the most recent IPhoneAgent*.ipa file.
#>
[CmdletBinding()]
param(
    [string]$IpaPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "ESP32 Agent iOS sideload helper" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Find Sideloadly
$SideloadlyPaths = @(
    "${env:ProgramFiles}\Sideloadly\Sideloadly.exe"
    "${env:ProgramFiles(x86)}\Sideloadly\Sideloadly.exe"
    "$env:LOCALAPPDATA\Programs\Sideloadly\Sideloadly.exe"
    "$env:LOCALAPPDATA\Sideloadly\sideloadly.exe"
)
$Sideloadly = $SideloadlyPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $Sideloadly) {
    Write-Error @"
Sideloadly not found.
Please run install_sideloadly.ps1 first, or download it manually from https://sideloadly.io/
"@
    exit 1
}
Write-Host "Found Sideloadly: $Sideloadly" -ForegroundColor Green

# 2. Find IPA if not provided
if (-not $IpaPath) {
    $Candidates = @()
    $Candidates += Get-ChildItem -Path "$env:USERPROFILE\Downloads" -Filter "IPhoneAgent*.ipa" -ErrorAction SilentlyContinue
    $Candidates += Get-ChildItem -Path "." -Filter "IPhoneAgent*.ipa" -ErrorAction SilentlyContinue
    $Latest = $Candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($Latest) { $IpaPath = $Latest.FullName }
}

if (-not $IpaPath -or -not (Test-Path $IpaPath)) {
    Write-Error "IPA not found. Please download it from GitHub Actions and pass -IpaPath C:\path\to\IPhoneAgent-unsigned.ipa"
    exit 1
}
Write-Host "Using IPA: $IpaPath" -ForegroundColor Green

# 3. Check iTunes / Apple Devices
$AppleMobileDevice = Get-Command "AppleMobileDeviceService.exe" -ErrorAction SilentlyContinue
$iTunes = Get-ChildItem -Path "${env:ProgramFiles}\iTunes\iTunes.exe", "${env:ProgramFiles(x86)}\iTunes\iTunes.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
$AppleDevices = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\AppleDevices.exe" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $AppleMobileDevice -and -not $iTunes -and -not $AppleDevices) {
    Write-Warning @"
Apple mobile device support does not appear to be installed.
Sideloadly needs either iTunes (Microsoft Store version recommended) or Apple Devices app.
Download: https://support.apple.com/en-us/HT210384
"@
}

# 4. Check connected iOS device
$Device = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*iPhone*" -or $_.Name -like "*iPad*" -or $_.Name -like "*Apple*" } | Select-Object -First 1
if (-not $Device) {
    Write-Warning "No USB iOS device detected. Make sure your iPhone is plugged in and unlocked."
} else {
    Write-Host "Detected USB device: $($Device.Name)" -ForegroundColor Green
}

# 5. Launch Sideloadly with the IPA
Write-Host ""
Write-Host "Launching Sideloadly..." -ForegroundColor Cyan
Write-Host "After it opens, enter your Apple ID, then click Start." -ForegroundColor Yellow
Write-Host "On your iPhone, go to Settings -> General -> VPN & Device Management to trust the app." -ForegroundColor Yellow

& $Sideloadly $IpaPath
