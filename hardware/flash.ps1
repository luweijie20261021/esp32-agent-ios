# Windows flash script for ESP32 iPhone Agent
# Equivalent to hardware/flash.sh, but works in PowerShell.
# Usage: .\flash.ps1 [COMn] [-Debug] [-Sta] [-BuildOnly] [-ApTune]
#   -Debug      log commands and the AirPlay handshake on USB serial
#   -Sta        join the Wi-Fi in hid_bridge/secrets.h instead of opening a hotspot
#   -BuildOnly  compile only, do not upload
#   -ApTune     A/B build: hotspot on a 20 MHz channel with 300 TU beacons
#
# Prerequisites:
#   arduino-cli + esp32:esp32 core 3.3.x + NimBLE-Arduino 2.5.x
#   Install: arduino-cli core install esp32:esp32@3.3.0
#            arduino-cli lib install "NimBLE-Arduino@2.5.1"

param(
    [string]$Port = "",
    [switch]$Debug,
    [switch]$Sta,
    [switch]$BuildOnly,
    [switch]$ApTune
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$FQBN = "esp32:esp32:esp32s3:USBMode=default,CDCOnBoot=cdc,FlashSize=8M,PSRAM=opi,PartitionScheme=default_8MB"

# Ensure local arduino-cli is on PATH when this script is run directly.
$LocalCliDir = "$env:LOCALAPPDATA\Programs\arduino-cli"
if ($env:Path -notlike "*$LocalCliDir*") {
    $env:Path = "$env:Path;$LocalCliDir"
}

# Resolve project root relative to this script
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bridge = Join-Path $Root "hid_bridge"

$Defs = @()
$Defs += "-include `"$Bridge\nimble_cfg.h`""

if ($Debug) { $Defs += "-DDEBUG_SERIAL=1" }
if ($Sta) {
    $Secrets = Join-Path $Bridge "secrets.h"
    if (-not (Test-Path $Secrets)) {
        Write-Error "-Sta needs hid_bridge/secrets.h (copy from secrets.example.h and fill in Wi-Fi)."
        exit 1
    }
    $Defs += "-DSTA_FROM_SECRETS=1"
}
if ($ApTune) { $Defs += "-DAP_TUNE=1" }

# Build properties for arduino-cli
$CppFlags = "compiler.cpp.extra_flags=$($Defs -join ' ')"
$CFlags = "compiler.c.extra_flags=$($Defs -join ' ')"

Write-Host "FQBN: $FQBN"
Write-Host "Extra flags: $($Defs -join ' ')"

# Compile
& arduino-cli compile -b $FQBN `
    --build-property $CppFlags `
    --build-property $CFlags `
    --output-dir build `
    $Bridge

if ($LASTEXITCODE -ne 0) {
    Write-Error "Compile failed."
    exit 1
}

if ($BuildOnly) {
    Write-Host "Build-only requested, done."
    exit 0
}

# Find port if not given
if (-not $Port) {
    Write-Host "Looking for ESP32-S3 serial port..."
    $Boards = & arduino-cli board list --format json | ConvertFrom-Json
    $Candidate = $Boards | Where-Object {
        $_.matching_boards -and $_.matching_boards.fqbn -like "*esp32s3*"
    } | Select-Object -First 1
    if ($Candidate) {
        $Port = $Candidate.port.address
        Write-Host "Found $Port"
    }
    if (-not $Port) {
        # Fallback: list common COM ports
        $ComPorts = [System.IO.Ports.SerialPort]::GetPortNames()
        if ($ComPorts.Count -eq 1) {
            $Port = $ComPorts[0]
            Write-Host "Using only available serial port $Port"
        } else {
            Write-Error "No ESP32-S3 port found automatically. Please run 'arduino-cli board list' and pass the COM port: .\flash.ps1 COM3"
            exit 1
        }
    }
}

Write-Host "Uploading to $Port ..."
& arduino-cli upload -b $FQBN -p $Port --input-dir build $Bridge

if ($LASTEXITCODE -ne 0) {
    Write-Error "Upload failed."
    exit 1
}

Write-Host "Done. Board flashed."
