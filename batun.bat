@echo off
title alsosar-cli-wingettools - Winget Tools for Windows

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0batun.ps1" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Uninstall completed with errors (check exit code).
)

echo.
pause
