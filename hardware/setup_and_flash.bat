@echo off
chcp 65001 >nul
title ESP32 Agent - One-Click Setup and Flash
echo ======================================
echo  ESP32 Agent - One-Click Setup + Flash
echo ======================================
echo.
echo This will install the required tools and flash your ESP32-S3 board.
echo A log file will be saved next to this batch file.
echo.
echo Please plug in your board when the PowerShell window asks for it.
echo.
pause
echo.

set "SCRIPTDIR=%~dp0"
set "LOGFILE=%SCRIPTDIR%setup_and_flash_log_%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%.txt"
set "LOGFILE=%LOGFILE: =0%"

powershell -NoExit -ExecutionPolicy Bypass -Command "& '%SCRIPTDIR%setup_and_flash.ps1' *>&1 | Tee-Object -FilePath '%LOGFILE%'"
