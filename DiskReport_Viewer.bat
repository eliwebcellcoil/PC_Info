@echo off
chcp 65001 >nul
title Disk Report Viewer v1.5.0

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Set-Location -LiteralPath '%~dp0'; & '&' '%~dp0DiskReport_Viewer.ps1'"

exit /b %ERRORLEVEL%