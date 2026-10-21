# One-click Windows setup + auto-flash for ESP32 iPhone Agent.
# This script will:
#   1. Download and install arduino-cli if missing
#   2. Install ESP32 core 3.3.x
#   3. Install NimBLE-Arduino 2.5.x
#   4. Run auto_flash.ps1 to detect and flash your board
#
# Usage: .\setup_and_flash.ps1 [-Debug] [-Sta] [-ApTune] [-Monitor]

param(
    [switch]$Debug,
    [switch]$Sta,
    [switch]$ApTune,
    [switch]$Monitor
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$AutoFlash = Join-Path $Root "auto_flash.ps1"

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "Machine")
    # Ensure the local arduino-cli install dir is in PATH for this session even if the
    # registry change has not yet propagated.
    $LocalCliDir = "$env:LOCALAPPDATA\Programs\arduino-cli"
    if ($env:Path -notlike "*$LocalCliDir*") {
        $env:Path = "$env:Path;$LocalCliDir"
    }
}

function Install-ArduinoCli {
    $InstallDir = "$env:LOCALAPPDATA\Programs\arduino-cli"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    Write-Host "Downloading arduino-cli..." -ForegroundColor Cyan
    $Url = "https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Windows_64bit.zip"
    $Zip = "$env:TEMP\arduino-cli.zip"

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Zip -UseBasicParsing
    } catch {
        Write-Host "Failed to download from $Url" -ForegroundColor Red
        Write-Host "Please download manually from:" -ForegroundColor Yellow
        Write-Host "  https://arduino.github.io/arduino-cli/latest/installation/" -ForegroundColor Yellow
        throw
    }

    Write-Host "Extracting arduino-cli..." -ForegroundColor Cyan
    Expand-Archive -Path $Zip -DestinationPath $InstallDir -Force

    Write-Host "Adding arduino-cli to user PATH..." -ForegroundColor Cyan
    $CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($CurrentPath -notlike "*$InstallDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$InstallDir", "User")
    }
    Refresh-Path

    if (-not (Get-Command arduino-cli -ErrorAction SilentlyContinue)) {
        throw "arduino-cli still not found after installation."
    }
    $cmd = Get-Command arduino-cli
    Write-Host "arduino-cli installed at: $($cmd.Source)" -ForegroundColor Green
}

function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)]$Command,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 10
    )
    $OldEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    for ($i = 1; $i -le $MaxAttempts; $i++) {
        Write-Host "Attempt $i of $MaxAttempts..." -ForegroundColor Cyan
        & $Command 2>&1
        if ($LASTEXITCODE -eq 0) {
            $ErrorActionPreference = $OldEap
            return
        }
        if ($i -lt $MaxAttempts) {
            Write-Host "Failed, waiting $DelaySeconds seconds before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    $ErrorActionPreference = $OldEap
    throw "Command failed after $MaxAttempts attempts."
}

function Show-ManualDownloadHelp {
    param($StagingDir, $ErrorMessage = "")
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Yellow
    Write-Host " Network download failed. Manual mode." -ForegroundColor Yellow
    Write-Host "==============================================" -ForegroundColor Yellow
    if ($ErrorMessage) {
        Write-Host "Error: $ErrorMessage" -ForegroundColor Red
        Write-Host ""
    }

    # Check for partial files in staging
    if (Test-Path $StagingDir) {
        $Partial = Get-ChildItem -Path $StagingDir -Filter "*.zip" -ErrorAction SilentlyContinue |
            Select-Object Name, @{N="SizeMB";E={[math]::Round($_.Length/1MB,2)}}
        if ($Partial) {
            Write-Host "Partial files already in staging folder:" -ForegroundColor Cyan
            $Partial | ForEach-Object { Write-Host "  - $($_.Name) ($($_.SizeMB) MB)" -ForegroundColor Cyan }
            Write-Host "If a file is nearly complete, just retry." -ForegroundColor Yellow
            Write-Host ""
        }
    }

    Write-Host "The ESP32 core contains large toolchains hosted on GitHub." -ForegroundColor Yellow
    Write-Host "If GitHub is unstable, download the missing .zip file manually" -ForegroundColor Yellow
    Write-Host "from another device/network, then place it here:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  $StagingDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Files you may need (check the error above for the exact one):" -ForegroundColor Yellow
    Write-Host "  - riscv32-esp-elf-14.2.0_20241119-x86_64-w64-mingw32.zip  (646 MB)" -ForegroundColor Yellow
    Write-Host "  - xtensa-esp-elf-14.2.0_20241119-x86_64-w64-mingw32.zip   (~ 500 MB)" -ForegroundColor Yellow
    Write-Host "  - esp32-3.3.x.zip (the core package)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Download sources:" -ForegroundColor Yellow
    Write-Host "  1. Original: https://github.com/espressif/crosstool-NG/releases" -ForegroundColor Yellow
    Write-Host "  2. Espressif mirror: https://dl.espressif.cn/github_assets/..." -ForegroundColor Yellow
    Write-Host "  3. Search filename on Baidu / Quark / Aliyun cloud drive" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Press any key AFTER you have placed the file(s) in the folder above..." -ForegroundColor Green
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Invoke-CoreInstall {
    $StagingDir = "$env:LOCALAPPDATA\Arduino15\staging\packages"
    $MaxRounds = 5
    for ($r = 1; $r -le $MaxRounds; $r++) {
        Write-Host "Installing ESP32 core 3.3.x (round $r/$MaxRounds)..." -ForegroundColor Cyan
        $OldEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & arduino-cli core install esp32:esp32@3.3.0 2>&1
            $exit = $LASTEXITCODE
        } catch {
            $exit = 1
            $errMsg = $_.Exception.Message
        }
        $ErrorActionPreference = $OldEap
        if ($exit -eq 0) { return }
        Show-ManualDownloadHelp -StagingDir $StagingDir -ErrorMessage $errMsg
    }
    throw "ESP32 core installation failed after $MaxRounds rounds."
}

function Install-Esp32Core {
    Write-Host "Installing ESP32 core 3.3.x..." -ForegroundColor Cyan
    Invoke-WithRetry { arduino-cli core update-index } -MaxAttempts 3 -DelaySeconds 15
    # Pre-stage large packages from Espressif mirror so arduino-cli does not need to download from GitHub.
    $Downloader = Join-Path $Root "download_esp32_packages.ps1"
    if (Test-Path $Downloader) {
        Write-Host "Pre-staging ESP32 packages (mirror fallback)..." -ForegroundColor Cyan
        & $Downloader
        if ($LASTEXITCODE -ne 0) { throw "Package pre-staging failed." }
    }
    Invoke-CoreInstall
    Write-Host "ESP32 core installed." -ForegroundColor Green
}

function Install-NimBle {
    Write-Host "Installing NimBLE-Arduino 2.5.1..." -ForegroundColor Cyan
    Invoke-WithRetry { arduino-cli lib install "NimBLE-Arduino@2.5.1" } -MaxAttempts 3 -DelaySeconds 10
    Write-Host "NimBLE-Arduino installed." -ForegroundColor Green
}

function Test-Esp32CoreInstalled {
    try {
        $json = & arduino-cli core list --format json 2>$null
        if (-not $json) { return $false }
        $cores = $json | ConvertFrom-Json
        if (-not $cores) { return $false }
        foreach ($c in $cores) {
            $id = $c.id
            $ver = $c.installed
            if ($id -like "*esp32*" -and $ver -like "3.3*") {
                return $ver
            }
        }
    } catch {
        Write-Host "Warning: could not check installed cores: $_" -ForegroundColor Yellow
    }
    return $false
}

function Test-NimBleInstalled {
    try {
        $json = & arduino-cli lib list --format json 2>$null
        if (-not $json) { return $false }
        $libs = $json | ConvertFrom-Json
        if (-not $libs) { return $false }
        foreach ($l in $libs) {
            $name = $l.library.name
            $ver = $l.library.version
            if ($name -eq "NimBLE-Arduino") {
                return $ver
            }
        }
    } catch {
        Write-Host "Warning: could not check installed libraries: $_" -ForegroundColor Yellow
    }
    return $false
}

# --- Main ---
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " ESP32 Agent - One-Click Setup + Flash" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# 1. Ensure arduino-cli
Refresh-Path
if (-not (Get-Command arduino-cli -ErrorAction SilentlyContinue)) {
    Install-ArduinoCli
} else {
    $ver = & arduino-cli version
    Write-Host "arduino-cli already installed: $ver" -ForegroundColor Green
}

# 2. Ensure ESP32 core
$hasCore = Test-Esp32CoreInstalled
if (-not $hasCore) {
    Install-Esp32Core
} else {
    Write-Host "ESP32 core $hasCore already installed." -ForegroundColor Green
}

# 3. Ensure NimBLE
$hasNim = Test-NimBleInstalled
if (-not $hasNim) {
    Install-NimBle
} else {
    Write-Host "NimBLE-Arduino $hasNim already installed." -ForegroundColor Green
}

Write-Host ""
Write-Host "Setup complete. Starting auto-flash..." -ForegroundColor Green
Write-Host ""

# 4. Run auto_flash.ps1
$Args = @()
if ($Debug) { $Args += "-Debug" }
if ($Sta) { $Args += "-Sta" }
if ($ApTune) { $Args += "-ApTune" }
if ($Monitor) { $Args += "-Monitor" }

& $AutoFlash @Args
