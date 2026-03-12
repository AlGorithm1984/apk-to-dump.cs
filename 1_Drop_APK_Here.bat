@echo off
setlocal
title Portable APK to dump.cs Automator

:: Check if a file was dropped
set "APK_PATH=%~1"
if "%APK_PATH%"=="" (
    echo [!] ERROR: No APK file provided.
    echo Please drag and drop an .apk file directly onto this batch script.
    echo.
    pause
    exit /b
)

:: Ensure the file exists
if not exist "%APK_PATH%" (
    echo [!] ERROR: The file "%APK_PATH%" does not exist.
    pause
    exit /b
)

echo [*] Initializing Portable APK Dumper...
echo [*] Target APK: "%APK_PATH%"
echo.

:: Launch the PowerShell automation script and pass the APK path
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0core\ApkToDump.ps1" -ApkPath "%APK_PATH%"

echo.
pause
