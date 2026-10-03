@echo off
setlocal
cd /d "%~dp0"

rem CyberCroc GUI bootstrap.
rem The actual application is started by launcher.vbs.
set "LAUNCHER=%~dp0launcher.vbs"

if not exist "%LAUNCHER%" (
    echo [CyberCroc] ERROR: launcher.vbs not found.
    echo Expected: "%LAUNCHER%"
    exit /b 1
)

rem Start the GUI launcher independently so this legacy CMD window can close immediately.
start "" wscript.exe "%LAUNCHER%"
exit /b 0
