@echo off
chcp 65001 >nul
title Sideload ESP32 Agent IPA
echo ======================================
echo  Sideload ESP32 Agent IPA to iPhone
echo ======================================
echo.
echo This will launch Sideloadly with the IPA file.
echo Make sure your iPhone is connected via USB.
echo.
set "SCRIPTDIR=%~dp0"
powershell -ExecutionPolicy Bypass -Command "& '%SCRIPTDIR%sideload_ipa.ps1'"
echo.
echo Press any key to exit...
pause >nul
