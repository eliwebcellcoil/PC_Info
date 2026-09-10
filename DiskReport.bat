@echo off
chcp 65001 >nul
title Disk Report v1.5.2
color 0A
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DiskReport.ps1"
exit