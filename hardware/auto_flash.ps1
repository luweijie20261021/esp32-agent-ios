# Auto-detect ESP32-S3 board and flash it (Windows PowerShell).
# Run this script once, then plug in the board. It will wait for the port
# to appear, compile, and upload the firmware automatically.
#
# Usage: .\auto_flash.ps1 [-Debug] [-Sta] [-ApTune] [-Monitor]
#   -Debug    enable DEBUG_SERIAL in firmware and start serial monitor after flash
#   -Sta      use station mode (needs hid_bridge/secrets.h)
#   -ApTune   A/B build with tuned hotspot timing
#   -Monitor  open serial monitor after flash (even without -Debug)

param(
    [switch]$Debug,
    [switch]$Sta,
    [switch]$ApTune,
    [switch]$Monitor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$FlashScript = Join-Path $Root "flash.ps1"
if (-not (Test-Path $FlashScript)) {
    Write-Error "flash.ps1 not found in $Root. Please keep both scripts together."
    exit 1
}

# Ensure local arduino-cli is on PATH even when run directly in a fresh session.
$LocalCliDir = "$env:LOCALAPPDATA\Programs\arduino-cli"
if ($env:Path -notlike "*$LocalCliDir*") {
    $env:Path = "$env:Path;$LocalCliDir"
}

function Test-Toolchain {
    Write-Host "Checking toolchain..." -ForegroundColor Cyan
    $Ok = $true

    if (-not (Get-Command arduino-cli -ErrorAction SilentlyContinue)) {
        Write-Host "  [X] arduino-cli not found. Install it first:" -ForegroundColor Red
        Write-Host "        winget install Arduino.arduino-cli" -ForegroundColor Yellow
        $Ok = $false
    } else {
        Write-Host "  [OK] arduino-cli installed" -ForegroundColor Green
    }

    try {
        $Cores = & arduino-cli core list --format json 2>$null | ConvertFrom-Json
        $HasCore = $Cores | Where-Object { $_.ID -like "*esp32*" -and $_.Installed -like "3.3*" }
        if (-not $HasCore) {
            Write-Host "  [X] ESP32 core 3.3.x not installed. Run:" -ForegroundColor Red
            Write-Host "        arduino-cli core install esp32:esp32@3.3.0" -ForegroundColor Yellow
            $Ok = $false
        } else {
            Write-Host "  [OK] ESP32 core $($HasCore.Installed)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [!] Could not check ESP32 core" -ForegroundColor Yellow
    }

    try {
        $Libs = & arduino-cli lib list --format json 2>$null | ConvertFrom-Json
        $HasNim = $Libs | Where-Object { $_.library.Name -eq "NimBLE-Arduino" }
        if (-not $HasNim) {
            Write-Host "  [X] NimBLE-Arduino not installed. Run:" -ForegroundColor Red
            Write-Host "        arduino-cli lib install `"NimBLE-Arduino@2.5.1`"" -ForegroundColor Yellow
            $Ok = $false
        } else {
            Write-Host "  [OK] NimBLE-Arduino $($HasNim.library.Version)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [!] Could not check NimBLE library" -ForegroundColor Yellow
    }

    if (-not $Ok) {
        Write-Host ""
        Write-Host "Please install the missing items and run this script again." -ForegroundColor Yellow
        exit 1
    }
}

function Get-UsbSnapshot {
    return Get-PnpDevice -Class USB | Select-Object Name, InstanceId, Status, Present
}

function Find-Esp32S3Port {
    try {
        $Boards = & arduino-cli board list --format json 2>$null | ConvertFrom-Json
        $Candidate = $Boards | Where-Object {
            $_.matching_boards -and ($_.matching_boards.fqbn -like "*esp32s3*" -or
                                     $_.boards -like "*esp32s3*")
        } | Select-Object -First 1
        if ($Candidate) { return $Candidate.port.address }
    } catch {}

    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
    if ($ports.Count -eq 1) { return $ports[0] }
    return $null
}

function Show-Diagnosis {
    param($BaselineUsb, $CurrentUsb)

    Write-Host ""
    Write-Host "Diagnosis:" -ForegroundColor Cyan

    # New USB devices that appeared
    $NewUsb = $CurrentUsb | Where-Object {
        $Before = $BaselineUsb | Where-Object { $_.InstanceId -eq $_.InstanceId }
        -not $Before -and $_.Present -eq $true
    }

    if ($NewUsb) {
        Write-Host "  New USB device(s) detected:" -ForegroundColor Yellow
        $NewUsb | ForEach-Object { Write-Host "    - $($_.Name) [$($_.Status)]" -ForegroundColor Yellow }

        $HasError = $NewUsb | Where-Object { $_.Status -ne 'OK' }
        if ($HasError) {
            Write-Host ""
            Write-Host "  [!] At least one new device has a problem status." -ForegroundColor Red
            Write-Host "      This usually means a missing driver. Try:" -ForegroundColor Yellow
            Write-Host "        1. Right-click the device in Device Manager" -ForegroundColor Yellow
            Write-Host "        2. Choose 'Update driver' -> 'Search automatically'" -ForegroundColor Yellow
        } else {
            Write-Host ""
            Write-Host "  [!] USB device is visible but no COM port appeared." -ForegroundColor Red
            Write-Host "      Common causes and fixes:" -ForegroundColor Yellow
            Write-Host "        1. USB cable is charge-only -> try a data cable" -ForegroundColor Yellow
            Write-Host "        2. Board has two USB ports -> use the one labeled 'USB', not 'UART'" -ForegroundColor Yellow
            Write-Host "        3. Need download mode -> hold BOOT button while plugging in" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No new USB device detected at all." -ForegroundColor Red
        Write-Host "  This strongly suggests the cable or USB port is power-only." -ForegroundColor Yellow
        Write-Host "  Try:" -ForegroundColor Yellow
        Write-Host "    1. Use a different USB-C cable (one that can transfer data)" -ForegroundColor Yellow
        Write-Host "    2. Try a rear USB port on your PC" -ForegroundColor Yellow
        Write-Host "    3. Try holding BOOT while plugging in" -ForegroundColor Yellow
    }

    # Check for any ESP32-related devices regardless
    $EspDevices = $CurrentUsb | Where-Object { $_.Name -like "*ESP32*" -or $_.Name -like "*USB JTAG*" -or $_.Name -like "*TinyUSB*" }
    if ($EspDevices) {
        Write-Host ""
        Write-Host "  Found these ESP32-related devices:" -ForegroundColor Green
        $EspDevices | ForEach-Object { Write-Host "    - $($_.Name) [$($_.Status)]" -ForegroundColor Green }
    }
}

# --- Main ---
Write-Host "======================================" -ForegroundColor Cyan
Write-Host " ESP32 Agent Auto-Flash (Windows)" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

Test-Toolchain

Write-Host "Please plug in your ESP32-S3 board now." -ForegroundColor Cyan
Write-Host "Waiting for it to appear as a COM port..." -ForegroundColor Cyan
Write-Host ""

$BaselinePorts = [System.IO.Ports.SerialPort]::GetPortNames()
$BaselineUsb = Get-UsbSnapshot

$Port = $null
$Attempts = 0
$MaxAttempts = 120   # 2 minutes

while (-not $Port -and $Attempts -lt $MaxAttempts) {
    Start-Sleep -Milliseconds 500
    $Attempts++

    $Port = Find-Esp32S3Port
    if (-not $Port) {
        $CurrentPorts = [System.IO.Ports.SerialPort]::GetPortNames()
        $NewPort = $CurrentPorts | Where-Object { $BaselinePorts -notcontains $_ }
        if ($NewPort) { $Port = $NewPort | Select-Object -First 1 }
    }

    if ($Attempts % 8 -eq 0) {
        Write-Host "Still waiting... ($([math]::Round($Attempts/2,1)) s)" -ForegroundColor DarkGray
    }
}

if (-not $Port) {
    $CurrentUsb = Get-UsbSnapshot
    Show-Diagnosis -BaselineUsb $BaselineUsb -CurrentUsb $CurrentUsb
    Write-Host ""
    Write-Error "No ESP32-S3 COM port detected within 2 minutes."
    exit 1
}

Write-Host ""
Write-Host "Detected board on $Port" -ForegroundColor Green
Write-Host "Starting flash in 3 seconds... (unplug now to cancel)" -ForegroundColor Cyan
Start-Sleep -Seconds 3

$Args = @($Port)
if ($Debug) { $Args += "-Debug" }
if ($Sta) { $Args += "-Sta" }
if ($ApTune) { $Args += "-ApTune" }

& $FlashScript @Args

if ($LASTEXITCODE -ne 0) {
    Write-Error "Flash failed."
    exit 1
}

Write-Host ""
Write-Host "Flash completed successfully." -ForegroundColor Green

if ($Debug -or $Monitor) {
    Write-Host "Opening serial monitor on $Port (115200 baud)... Press Ctrl+C to stop." -ForegroundColor Cyan
    & arduino-cli monitor -p $Port -c baudrate=115200
}
