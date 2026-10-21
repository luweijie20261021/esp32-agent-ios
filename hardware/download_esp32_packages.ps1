#requires -Version 5.1
<#
.SYNOPSIS
    Download missing Windows x86_64 toolchain packages for esp32:esp32@3.3.0.
.DESCRIPTION
    Checks the Arduino CLI staging directory, verifies SHA-256, and downloads
    missing/corrupt packages. The Espressif China mirror is tried first,
    then the official GitHub URL as fallback. Supports resume (curl -C -).
#>
[CmdletBinding()]
param(
    [string]$StagingDir = "$env:LOCALAPPDATA\Arduino15\staging\packages",
    [int]$MaxRetries = 2
)

$ErrorActionPreference = "Stop"
$StagingDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StagingDir)
if (-not (Test-Path $StagingDir)) { New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null }

# Required packages for esp32:esp32@3.3.0 on Windows x86_64 (from package_index.json)
$packages = @(
    @{
        File      = "esp32-3.3.0.zip"
        Size      = 25835747
        SHA256    = "c8525462e47b37b726c211b71afada0fca5859ba748963e4d967131355716ba2"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/espressif/arduino-esp32/releases/download/3.3.0/esp32-3.3.0.zip"
            "https://github.com/espressif/arduino-esp32/releases/download/3.3.0/esp32-3.3.0.zip"
        )
    }
    @{
        File      = "riscv32-esp-elf-14.2.0_20241119-x86_64-w64-mingw32.zip"
        Size      = 677812937
        SHA256    = "24c8407fa467448d394e0639436a5ede31caf1838e35e8435e19df58ebed438c"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/espressif/crosstool-NG/releases/download/esp-14.2.0_20241119/riscv32-esp-elf-14.2.0_20241119-x86_64-w64-mingw32.zip"
            "https://github.com/espressif/crosstool-NG/releases/download/esp-14.2.0_20241119/riscv32-esp-elf-14.2.0_20241119-x86_64-w64-mingw32.zip"
        )
    }
    @{
        File      = "xtensa-esp-elf-14.2.0_20241119-x86_64-w64-mingw32.zip"
        Size      = 386316009
        SHA256    = "62ae704777d73c30689efff6e81178632a1ca44d1a2d60f4621eb997e040e028"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/espressif/crosstool-NG/releases/download/esp-14.2.0_20241119/xtensa-esp-elf-14.2.0_20241119-x86_64-w64-mingw32.zip"
            "https://github.com/espressif/crosstool-NG/releases/download/esp-14.2.0_20241119/xtensa-esp-elf-14.2.0_20241119-x86_64-w64-mingw32.zip"
        )
    }
    @{
        File      = "esp32-arduino-libs-idf-release_v5.5-b66b5448-v1.zip"
        Size      = 430471837
        SHA256    = "a871d945c6bfb685ecff5e30ad759f280c841ea143071466b2e611bd1800f18f"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/espressif/esp32-arduino-lib-builder/releases/download/idf-release_v5.5/esp32-arduino-libs-idf-release_v5.5-b66b5448-v1.zip"
            "https://github.com/espressif/esp32-arduino-lib-builder/releases/download/idf-release_v5.5/esp32-arduino-libs-idf-release_v5.5-b66b5448-v1.zip"
        )
    }
    @{
        File      = "esptool-v5.0.0-windows-amd64.zip"
        Size      = 59105322
        SHA256    = "2294107f66db6f09b886b337728a981173c9e7eab45a030928a8a5a1370611ca"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/espressif/esptool/releases/download/v5.0.0/esptool-v5.0.0-windows-amd64.zip"
            "https://github.com/espressif/esptool/releases/download/v5.0.0/esptool-v5.0.0-windows-amd64.zip"
        )
    }
    @{
        File      = "x86_64-w64-mingw32.mklittlefs-c41e51a.200706.zip"
        Size      = 345132
        SHA256    = "2e319077491f8e832e96eb4f2f7a70dd919333cee4b388c394e0e848d031d542"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/earlephilhower/esp-quick-toolchain/releases/download/3.0.0-gnu12/x86_64-w64-mingw32.mklittlefs-c41e51a.200706.zip"
            "https://github.com/earlephilhower/esp-quick-toolchain/releases/download/3.0.0-gnu12/x86_64-w64-mingw32.mklittlefs-c41e51a.200706.zip"
        )
    }
    @{
        File      = "mkspiffs-0.2.3-arduino-esp32-win32.zip"
        Size      = 249809
        SHA256    = "b647f2c2efe6949819c85ea9404271b55c7c9c25bcb98d3b98a1d0ba771adf56"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/igrr/mkspiffs/releases/download/0.2.3/mkspiffs-0.2.3-arduino-esp32-win32.zip"
            "https://github.com/igrr/mkspiffs/releases/download/0.2.3/mkspiffs-0.2.3-arduino-esp32-win32.zip"
        )
    }
    @{
        File      = "openocd-esp32-win64-0.12.0-esp32-20250422.zip"
        Size      = 2988858
        SHA256    = "e9eae8e1a8d0e030cd81dcb08394a9137cb7338a6211dfabcdbdfb37b58c5a23"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/espressif/openocd-esp32/releases/download/v0.12.0-esp32-20250422/openocd-esp32-win64-0.12.0-esp32-20250422.zip"
            "https://github.com/espressif/openocd-esp32/releases/download/v0.12.0-esp32-20250422/openocd-esp32-win64-0.12.0-esp32-20250422.zip"
        )
    }
    @{
        File      = "riscv32-esp-elf-gdb-16.2_20250324-x86_64-w64-mingw32.zip"
        Size      = 32667353
        SHA256    = "37c79178900c19ca7487c26af4b5ad6b0d3f34683bd0e9c2ddd39038c999e429"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/espressif/binutils-gdb/releases/download/esp-gdb-v16.2_20250324/riscv32-esp-elf-gdb-16.2_20250324-x86_64-w64-mingw32.zip"
            "https://github.com/espressif/binutils-gdb/releases/download/esp-gdb-v16.2_20250324/riscv32-esp-elf-gdb-16.2_20250324-x86_64-w64-mingw32.zip"
        )
    }
    @{
        File      = "xtensa-esp-elf-gdb-16.2_20250324-x86_64-w64-mingw32.zip"
        Size      = 32290997
        SHA256    = "e970fc3ec8a1d0acee2432e91e0a01b348613a0425aacfa981b2fc505fe920cc"
        Urls      = @(
            "https://dl.espressif.cn/github_assets/espressif/binutils-gdb/releases/download/esp-gdb-v16.2_20250324/xtensa-esp-elf-gdb-16.2_20250324-x86_64-w64-mingw32.zip"
            "https://github.com/espressif/binutils-gdb/releases/download/esp-gdb-v16.2_20250324/xtensa-esp-elf-gdb-16.2_20250324-x86_64-w64-mingw32.zip"
        )
    }
)

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -gt 1GB) { "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -gt 1MB) { "{0:N2} MB" -f ($Bytes / 1MB) }
    else { "{0:N2} KB" -f ($Bytes / 1KB) }
}

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Test-PackageOk {
    param([hashtable]$Pkg)
    $dest = Join-Path $StagingDir $Pkg.File
    if (-not (Test-Path $dest)) { return $false }
    $len = (Get-Item $dest).Length
    if ($len -ne $Pkg.Size) { return $false }
    $hash = Get-Sha256 $dest
    return ($hash -eq $Pkg.SHA256)
}

function Remove-IfExists {
    param([string]$Path)
    if (Test-Path $Path) { Remove-Item -Path $Path -Force }
}

function Invoke-ResumeDownload {
    param(
        [string]$Url,
        [string]$OutFile
    )
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        Write-Warning "curl.exe not found, falling back to Invoke-WebRequest (no resume)"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        return
    }

    $tmp = "$OutFile.tmp"
    $args = @("-C", "-", "-L", "--fail", "--connect-timeout", "10", "--max-time", "300", "--retry", "1", "--ssl-no-revoke", "-o", $tmp, $Url)
    & curl.exe @args
    if ($LASTEXITCODE -ne 0) { throw "curl exited with code $LASTEXITCODE" }
    if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
    Move-Item $tmp $OutFile -Force
}

function Install-Package {
    param([hashtable]$Pkg)
    $dest = Join-Path $StagingDir $Pkg.File

    if (Test-PackageOk $Pkg) {
        Write-Host ("[OK] {0} ({1})" -f $Pkg.File, (Format-Size $Pkg.Size)) -ForegroundColor Green
        return $true
    }

    Remove-IfExists $dest
    Remove-IfExists "$dest.tmp"

    foreach ($url in $Pkg.Urls) {
        for ($i = 1; $i -le $MaxRetries; $i++) {
            try {
                Write-Host ("[DL] {0} from {1} (attempt {2}/{3})" -f $Pkg.File, $url, $i, $MaxRetries) -ForegroundColor Cyan
                Invoke-ResumeDownload -Url $url -OutFile $dest

                if (Test-PackageOk $Pkg) {
                    Write-Host ("[OK] {0} downloaded and verified" -f $Pkg.File) -ForegroundColor Green
                    return $true
                }
                else {
                    Write-Warning ("{0} hash mismatch, will retry" -f $Pkg.File)
                    Remove-IfExists $dest
                    Remove-IfExists "$dest.tmp"
                }
            }
            catch {
                Write-Warning ("{0} download error: {1}" -f $Pkg.File, $_.Exception.Message)
                Start-Sleep -Seconds 3
            }
        }
    }
    return $false
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "ESP32 core 3.3.0 package downloader" -ForegroundColor Yellow
Write-Host "Staging dir: $StagingDir" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow

$missing = 0
$ok = 0
foreach ($pkg in $packages) {
    if (Install-Package $pkg) { $ok++ } else { $missing++ }
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host ("Result: {0}/{1} packages ready" -f $ok, $packages.Count) -ForegroundColor $(if ($missing -eq 0) { 'Green' } else { 'Red' })
if ($missing -gt 0) {
    Write-Host "$missing package(s) still missing. Check network and rerun this script." -ForegroundColor Red
    exit 1
}

Write-Host "All packages ready. Re-run:" -ForegroundColor Green
Write-Host "    arduino-cli core install esp32:esp32@3.3.0" -ForegroundColor White

