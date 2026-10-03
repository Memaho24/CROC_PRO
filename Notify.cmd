@echo off
setlocal
chcp 65001 >nul 2>&1

:: Usage:  Notify.cmd "message text"
::         Notify.cmd /f "C:\path\message.txt"
:: Avoid " and % inside the text; for anything complex use /f.

set "SCRIPT_DIR=%~dp0"

if /i "%~1"=="/f" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Notify.ps1" -TextFile "%~2"
    exit /b %errorlevel%
)

set "MSG=%~1"
if not defined MSG set "MSG=Notification"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Notify.ps1" -Message "%MSG%"
exit /b %errorlevel%
