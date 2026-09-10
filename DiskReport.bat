@echo off
title Disk Report Viewer v1.5.1

REM Running from a network share (\\Nas02\...) makes CMD print a UNC warning.
REM That warning is harmless. Do not CD / PUSHD — it causes a second error.
REM Launch PowerShell with a full path so the script still runs.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0DiskReport_Viewer.ps1"
exit /b %ERRORLEVEL%