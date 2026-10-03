@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

rem ============================================================
rem CYBERCROC 0.3.2 - portable controller (fixed)
rem ASCII-only BAT with CRLF line endings. No Cyrillic here.
rem ============================================================
set "ROOT=%~dp0"
set "TOOLS=%ROOT%tools"
set "LOGDIR=%ROOT%logs"
set "LOG=%LOGDIR%\CyberCroc.log"
set "VER=0.3.2"

rem --- administrator rights (most tools need them) ---
fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%LOGDIR%" md "%LOGDIR%" >nul 2>&1
if exist "%LOG%" for %%F in ("%LOG%") do if %%~zF gtr 1048576 move /y "%LOG%" "%LOG%.old" >nul 2>&1
>>"%LOG%" echo ============================================================
>>"%LOG%" echo CYBERCROC %VER% start: %DATE% %TIME%  PC: %COMPUTERNAME%
>>"%LOG%" echo ============================================================

if not exist "%TOOLS%\" (
    echo [ERROR] tools folder was not found: "%TOOLS%"
    call :WriteError "start CyberCroc" "tools folder was not found" "1" "Check that Master.cmd is in the project root" "Restore the tools folder next to Master.cmd"
    pause
    exit /b 1
)

:MENU
cls
title CYBERCROC v%VER%
color 0A
echo.
echo ================================================================
echo                 CYBERCROC v%VER%
echo ================================================================
echo Computer: %COMPUTERNAME%
echo Root:     %ROOT%
if not exist "%ROOT%config.ini" echo WARNING:  config.ini not found - copy config.example.ini to config.ini
echo.
echo [1] PC DEPLOYMENT
echo [2] GAME CHECK
echo [3] PROGRAMS - CHECK
echo [4] PROGRAMS - INSTALL / UPDATE
echo [5] BACKUP
echo [6] CLEANUP
echo [7] OFFICE PROGRAMS
echo [8] ZAPRET
echo [9] RUN MAIN TASKS
echo [A] WINDOWS SETTINGS
echo [B] TELEGRAM TEST
echo [C] OPEN UNIFIED LOG
echo [D] RESET PC
echo [E] PC DIAGNOSTICS
echo [F] OPEN GUI (CyberCroc.ps1)
echo [G] EDIT config.ini
echo [0] EXIT
echo.
choice /c 123456789ABCDEFG0 /n /m "Select: "
set "CH=%ERRORLEVEL%"
if "%CH%"=="17" goto EXIT
if "%CH%"=="16" goto EDITCFG
if "%CH%"=="15" goto GUI
if "%CH%"=="14" goto DIAG
if "%CH%"=="13" goto RESET
if "%CH%"=="12" goto LOGS
if "%CH%"=="11" goto TELEGRAM
if "%CH%"=="10" goto TWEAKS
if "%CH%"=="9" goto ALL
if "%CH%"=="8" goto ZAPRET
if "%CH%"=="7" goto OFFICE
if "%CH%"=="6" goto CLEANUP
if "%CH%"=="5" goto BACKUP
if "%CH%"=="4" goto APPS_INSTALL
if "%CH%"=="3" goto APPS_CHECK
if "%CH%"=="2" goto GAMES
if "%CH%"=="1" goto DEPLOY
goto MENU

:DEPLOY
call :RunCmd Deploy.cmd
goto MENU
:GAMES
call :RunCmd Games.cmd
goto MENU
:APPS_CHECK
call :RunPs Apps.ps1
goto MENU
:APPS_INSTALL
call :RunPs Apps.ps1 -Install -Update
goto MENU
:BACKUP
call :RunCmd Backup.cmd
goto MENU
:CLEANUP
call :RunCmd Cleanup.cmd
goto MENU
:TWEAKS
call :RunCmd WindowsTweaks.cmd
goto MENU
:RESET
call :RunPs FactoryReset.ps1
goto MENU
:TELEGRAM
call :RunPs TelegramTest.ps1
goto MENU
:OFFICE
call :RunPs OfficePrograms.ps1 -Install
goto MENU
:DIAG
call :RunPs Diagnostics.ps1
goto MENU
:ALL
call :RunCmd Games.cmd auto
call :RunPs Apps.ps1 -Install -Update
if exist "%TOOLS%\OfficePrograms.ps1" call :RunPs OfficePrograms.ps1 -Install
call :RunCmd Backup.cmd auto
call :RunCmd Cleanup.cmd auto
goto MENU
:LOGS
if exist "%LOG%" start "CyberCroc Log" notepad.exe "%LOG%"
goto MENU
:GUI
if exist "%ROOT%CyberCroc.ps1" (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%ROOT%CyberCroc.ps1"
) else (
    echo CyberCroc.ps1 was not found.
    pause
)
goto MENU
:EDITCFG
if not exist "%ROOT%config.ini" if exist "%ROOT%config.example.ini" copy /y "%ROOT%config.example.ini" "%ROOT%config.ini" >nul
start "config.ini" notepad.exe "%ROOT%config.ini"
goto MENU

:ZAPRET
cls
echo.
echo ================  ZAPRET  ================
echo [1] Status
echo [2] Install / update
echo [3] Start
echo [4] Stop
echo [5] Restart
echo [6] Autostart ON
echo [7] Autostart OFF
echo [8] Choose strategy
echo [9] Test
echo [R] Remove
echo [0] Back
echo.
choice /c 123456789R0 /n /m "Select: "
set "ZC=%ERRORLEVEL%"
if "%ZC%"=="11" goto MENU
if "%ZC%"=="10" call :RunPs Zapret.ps1 remove
if "%ZC%"=="9" call :RunPs Zapret.ps1 test
if "%ZC%"=="8" call :RunPs Zapret.ps1 choose
if "%ZC%"=="7" call :RunPs Zapret.ps1 autostart-off
if "%ZC%"=="6" call :RunPs Zapret.ps1 autostart-on
if "%ZC%"=="5" call :RunPs Zapret.ps1 restart
if "%ZC%"=="4" call :RunPs Zapret.ps1 stop
if "%ZC%"=="3" call :RunPs Zapret.ps1 start
if "%ZC%"=="2" call :RunPs Zapret.ps1 install
if "%ZC%"=="1" call :RunPs Zapret.ps1 status
goto ZAPRET

rem ------------------------------------------------------------
rem  RunCmd <file> [arg1] [arg2] [arg3]   - tool is a .cmd in tools\
rem  (fixed: old code used "shift" + %*, which kept the file name
rem   as the first argument and passed it to the tool)
rem ------------------------------------------------------------
:RunCmd
set "RUN_NAME=%~1"
set "RUN_ARGS=%~2 %~3 %~4"
set "P=%TOOLS%\%RUN_NAME%"
if not exist "%P%" (
    call :WriteError "run %RUN_NAME%" "CMD tool was not found" "1" "Check %P%" "Restore the tools folder"
    echo [ERROR] %P% not found
    pause
    exit /b 1
)
call :Log "Action: run %RUN_NAME% %RUN_ARGS%"
call "%P%" %RUN_ARGS%
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" call :WriteError "run %RUN_NAME% %RUN_ARGS%" "Tool returned an error" "%RC%" "Check the console output and CyberCroc.log" "Repeat the operation after fixing the reported cause"
exit /b %RC%

rem  RunPs <file> [arg1] [arg2] [arg3]   - tool is a .ps1 in tools\
:RunPs
set "RUN_NAME=%~1"
set "RUN_ARGS=%~2 %~3 %~4"
set "P=%TOOLS%\%RUN_NAME%"
if not exist "%P%" (
    call :WriteError "run %RUN_NAME%" "PowerShell file was not found" "1" "Check %P%" "Restore the tools folder"
    echo [ERROR] %P% not found
    pause
    exit /b 1
)
call :Log "Action: run %RUN_NAME% %RUN_ARGS%"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%P%" %RUN_ARGS%
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" call :WriteError "run %RUN_NAME% %RUN_ARGS%" "PowerShell returned an error" "%RC%" "Check the PowerShell output and CyberCroc.log" "Repeat the operation after fixing the reported cause"
echo.
echo Done (code %RC%). Press any key to return to the menu...
pause >nul
exit /b %RC%

:Log
>>"%LOG%" echo [%DATE% %TIME%] %~1
exit /b 0

:WriteError
>>"%LOG%" echo.
>>"%LOG%" echo ------------------------------------------------------------
>>"%LOG%" echo [ERROR]
>>"%LOG%" echo Action: %~1
>>"%LOG%" echo Error: %~2
>>"%LOG%" echo Error code: %~3
>>"%LOG%" echo To fix: 1. %~4  2. %~5
>>"%LOG%" echo ------------------------------------------------------------
exit /b 0

:EXIT
call :Log "Action: exit CyberCroc"
exit /b 0
