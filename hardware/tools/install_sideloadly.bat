@echo off
chcp 65001 >nul
title Install Sideloadly
echo ======================================
echo  Install Sideloadly (Windows IPA sideloading)
echo ======================================
echo.
echo This will download and install Sideloadly from sideloadly.io.
echo Sideloadly is needed to install the ESP32 Agent app on your iPhone.
echo.
set "SCRIPTDIR=%~dp0"
powershell -ExecutionPolicy Bypass -Command "& '%SCRIPTDIR%install_sideloadly.ps1' -Resume"
echo.
echo Press any key to exit...
pause >nul
