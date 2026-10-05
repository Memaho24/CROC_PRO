@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\KioskPolicy.ps1" -Disable
pause
