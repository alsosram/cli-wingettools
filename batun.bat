@echo off
title asosar-cli-batun - Interactive Batch Uninstaller

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0batun.ps1" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Uninstall completed with errors (check exit code).
)

echo.
pause
