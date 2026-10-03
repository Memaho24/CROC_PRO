@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Backup Data
color 0E

set "AUTO_MODE=%~1"
set "SCRIPT_DIR=%~dp0"
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "CONFIG=%ROOT_DIR%\config.ini"
set "BACKUP_DIR=%ROOT_DIR%\BACKUP"
set "LOGDIR=%ROOT_DIR%\logs"
set "LOGFILE=%LOGDIR%\backup_log.txt"

if not exist "%LOGDIR%" md "%LOGDIR%" >nul 2>&1
if not exist "%BACKUP_DIR%" md "%BACKUP_DIR%" >nul 2>&1

if not exist "%CONFIG%" (
    echo [ERROR] config.ini not found
    if /i not "%AUTO_MODE%"=="auto" pause
    exit /b 1
)

:: ---- read config (KEY=VALUE, no spaces around "=") ----
set "ITEMS="
set "KEEP=5"
for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG%") do (
    if /i "%%A"=="ITEMS" set "ITEMS=%%B"
    if /i "%%A"=="KEEP_BACKUPS" set "KEEP=%%B"
)
if not defined ITEMS (
    echo [ERROR] ITEMS not set in config.ini
    if /i not "%AUTO_MODE%"=="auto" pause
    exit /b 1
)
set "KEEP_N=5"
set /a "KEEP_N=KEEP" 2>nul
if !KEEP_N! lss 1 set "KEEP_N=5"

:: ---- timestamp independent of Windows regional settings ----
set "STAMP="
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set "STAMP=%%T"
if not defined STAMP (
    echo [ERROR] Could not get date from PowerShell
    if /i not "%AUTO_MODE%"=="auto" pause
    exit /b 1
)

:: ---- log rotation (>1 MB) and header ----
if exist "%LOGFILE%" for %%F in ("%LOGFILE%") do if %%~zF gtr 1048576 move /y "%LOGFILE%" "%LOGFILE%.old" >nul 2>&1
call :Log "============================================================"
call :Log "BACKUP - %DATE% %TIME%"
call :Log "Computer: %COMPUTERNAME%   Keep last: !KEEP_N!"

set /a B_TOTAL=0, B_OK=0, B_FAIL=0
set "FAILED="

echo.
echo ============================================================
echo   BACKUP DATA
echo ============================================================
echo   Target: !BACKUP_DIR!
echo   Stamp:  !STAMP!
echo   Keep:   !KEEP_N! newest copies per item
echo ============================================================
echo.

:: ---- walk through "Name|Path;Name|Path;..." (paths may contain spaces) ----
set "REST=!ITEMS!"
:ITEM_LOOP
if not defined REST goto ITEMS_DONE
set "ITEM="
set "NEXT="
for /f "tokens=1* delims=;" %%A in ("!REST!") do (
    set "ITEM=%%A"
    set "NEXT=%%B"
)
set "REST=!NEXT!"
if defined ITEM call :ProcessItem "!ITEM!"
goto ITEM_LOOP

:ITEMS_DONE
echo.
echo ============================================================
echo   RESULTS
echo ============================================================
echo   Total:  !B_TOTAL!
echo   OK:     !B_OK!
echo   Failed: !B_FAIL!
echo ============================================================
echo.
call :Log "RESULTS: Total=!B_TOTAL! OK=!B_OK! Fail=!B_FAIL!"
echo Log: !LOGFILE!

if !B_FAIL! gtr 0 call "%SCRIPT_DIR%Notify.cmd" "Backup problems: OK !B_OK! of !B_TOTAL!, failed:!FAILED!"

if /i not "%AUTO_MODE%"=="auto" pause
if !B_FAIL! gtr 0 exit /b 1
exit /b 0


:: ============================================================
:ProcessItem
set "B_NAME="
set "B_PATH="
for /f "tokens=1,2 delims=|" %%P in ("%~1") do (
    set "B_NAME=%%P"
    set "B_PATH=%%Q"
)
set /a B_TOTAL+=1
if not defined B_PATH (
    echo [SKIP] Bad item format, expected Name^|Path
    call :Log "[FAIL] bad item format: %~1"
    set /a B_FAIL+=1
    set "FAILED=!FAILED! ?"
    exit /b 0
)

:: robocopy hates a trailing backslash before the closing quote
if "!B_PATH:~-1!"=="\" (
    if "!B_PATH:~3,1!"=="" (set "B_PATH=!B_PATH!.") else set "B_PATH=!B_PATH:~0,-1!"
)

set "B_OUT=!BACKUP_DIR!\!B_NAME!_!STAMP!"
echo ------------------------------------------------------------
echo [BACKUP] !B_NAME!
echo    From: !B_PATH!

if not exist "!B_PATH!" (
    echo    [SKIP] Path not found
    call :Log "[FAIL] !B_NAME! - path not found: !B_PATH!"
    set /a B_FAIL+=1
    set "FAILED=!FAILED! !B_NAME!"
    exit /b 0
)

robocopy "!B_PATH!" "!B_OUT!" /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS /NP >nul 2>&1
set "RC=!errorlevel!"
if !RC! geq 8 (
    echo    [FAIL] robocopy code !RC!
    call :Log "[FAIL] !B_NAME! - robocopy code !RC!"
    set /a B_FAIL+=1
    set "FAILED=!FAILED! !B_NAME!"
    exit /b 0
)
echo    [OK] saved to !B_OUT!
call :Log "[OK] !B_NAME! saved to !B_OUT!"
set /a B_OK+=1
call :Prune "!B_NAME!"
exit /b 0


:: ---- keep only the newest KEEP_N copies of one item ----
:Prune
for /f "skip=%KEEP_N% delims=" %%D in ('dir /b /ad /o-n "%BACKUP_DIR%\%~1_????????_????" 2^>nul') do (
    rd /s /q "%BACKUP_DIR%\%%D" >nul 2>&1
    echo    [PRUNE] removed old copy %%D
    call :Log "[PRUNE] removed old copy %%D"
)
exit /b 0


:: ---- append a line to the log (safe for | & < > in the text) ----
:Log
set "LOGLINE=%~1"
>>"%LOGFILE%" echo(!LOGLINE!
exit /b 0
