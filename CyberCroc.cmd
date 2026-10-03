@echo off
rem Launch the CyberCroc GUI (double-click)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CyberCroc.ps1"
exit /b 0
