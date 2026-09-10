@echo off
chcp 65001 >nul
title Disk Report Viewer v1.5.0

REM UNC-safe: pushd maps \\server\share to a temporary drive letter
pushd "%~dp0" 2>nul
if errorlevel 1 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DiskReport_Viewer.ps1"
    exit /b %ERRORLEVEL%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DiskReport_Viewer.ps1"
set ERR=%ERRORLEVEL%
popd
exit /b %ERR%