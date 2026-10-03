@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Cleanup
color 0D

set "AUTO_MODE=%~1"
set "SCRIPT_DIR=%~dp0"
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "CONFIG=%ROOT_DIR%\config.ini"
set "LOGDIR=%ROOT_DIR%\logs"
set "LOGFILE=%LOGDIR%\cleanup_log.txt"

:: ---- admin rights (fltmc works even if the Server service is off, unlike "net session") ----
fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%LOGDIR%" md "%LOGDIR%" >nul 2>&1

:: ---- read config (KEY=VALUE, no spaces around "=") ----
set "PATHS="
set "EMPTY_RECYCLE=1"
set "DISM_CLEANUP=0"
set "DISM_RESETBASE=0"
if exist "%CONFIG%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG%") do (
        if /i "%%A"=="PATHS" set "PATHS=%%B"
        if /i "%%A"=="EMPTY_RECYCLE" set "EMPTY_RECYCLE=%%B"
        if /i "%%A"=="DISM_CLEANUP" set "DISM_CLEANUP=%%B"
        if /i "%%A"=="DISM_RESETBASE" set "DISM_RESETBASE=%%B"
    )
)
if not defined PATHS set "PATHS=%TEMP%;%SystemRoot%\Temp"

if exist "%LOGFILE%" for %%F in ("%LOGFILE%") do if %%~zF gtr 1048576 move /y "%LOGFILE%" "%LOGFILE%.old" >nul 2>&1
call :Log "============================================================"
call :Log "CLEANUP - %DATE% %TIME%"
call :Log "Computer: %COMPUTERNAME%"

set "FREE_BEFORE="
for /f %%S in ('powershell -NoProfile -Command "[int]((Get-PSDrive %SystemDrive:~0,1%).Free/1MB)"') do set "FREE_BEFORE=%%S"

set /a C_OK=0, C_SKIP=0

echo.
echo ============================================================
echo   CLEANUP
echo ============================================================
echo.

:: ---- walk through "path;path;..." (paths may contain spaces, %ENV% allowed) ----
set "REST=!PATHS!"
:PATH_LOOP
if not defined REST goto PATHS_DONE
set "ITEM="
set "NEXT="
for /f "tokens=1* delims=;" %%A in ("!REST!") do (
    set "ITEM=%%A"
    set "NEXT=%%B"
)
set "REST=!NEXT!"
if defined ITEM call :CleanPath "!ITEM!"
goto PATH_LOOP

:PATHS_DONE
if "!EMPTY_RECYCLE!"=="1" (
    echo.
    echo [RECYCLE] Emptying...
    powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
    echo    [OK]
    call :Log "[OK] Recycle Bin emptied"
)

echo [DNS] Flushing cache...
ipconfig /flushdns >nul 2>&1
echo    [OK]

if "!DISM_CLEANUP!"=="1" (
    set "DISM_ARGS=/online /cleanup-image /startcomponentcleanup"
    if "!DISM_RESETBASE!"=="1" set "DISM_ARGS=!DISM_ARGS! /resetbase"
    echo [DISM] Cleaning WinSxS, this may take minutes...
    dism !DISM_ARGS! >nul 2>&1
    echo    [OK]
    call :Log "[OK] DISM !DISM_ARGS!"
) else (
    echo [DISM] Skipped ^(DISM_CLEANUP=0^)
)

set "FREE_AFTER="
for /f %%S in ('powershell -NoProfile -Command "[int]((Get-PSDrive %SystemDrive:~0,1%).Free/1MB)"') do set "FREE_AFTER=%%S"
set "FREED_TXT="
if defined FREE_BEFORE if defined FREE_AFTER (
    set /a FREED=FREE_AFTER-FREE_BEFORE
    set "FREED_TXT=   Freed on !SystemDrive!: !FREED! MB"
)

echo.
echo ============================================================
echo   RESULTS
echo ============================================================
echo   Cleaned: !C_OK!
echo   Skipped: !C_SKIP!
if defined FREED_TXT echo !FREED_TXT!
echo ============================================================
echo.
call :Log "RESULTS: Cleaned=!C_OK! Skipped=!C_SKIP!!FREED_TXT!"
echo Log: !LOGFILE!

if /i not "%AUTO_MODE%"=="auto" pause
exit /b 0


:: ============================================================
:CleanPath
set "CUR=%~1"
if "!CUR:~-1!"=="\" set "CUR=!CUR:~0,-1!"
echo [DIR] !CUR!

:: ---- safety: never touch drive roots or system/profile folders ----
set "SAFE=1"
if "!CUR:~3,1!"=="" set "SAFE=0"
for %%X in ("%SystemRoot%" "%SystemRoot%\System32" "%SystemDrive%\Users" "%SystemDrive%\ProgramData" "%SystemDrive%\Program Files" "%SystemDrive%\Program Files (x86)" "%USERPROFILE%") do (
    if /i "!CUR!"=="%%~X" set "SAFE=0"
)
if "!SAFE!"=="0" (
    echo    [REFUSED] Unsafe path, check PATHS in config.ini
    call :Log "[REFUSED] unsafe path: !CUR!"
    set /a C_SKIP+=1
    exit /b 0
)

if not exist "!CUR!\" (
    echo    [SKIP] Not found
    call :Log "[SKIP] not found: !CUR!"
    set /a C_SKIP+=1
    exit /b 0
)

del /s /f /q "!CUR!\*" >nul 2>&1
for /d %%D in ("!CUR!\*") do rd /s /q "%%D" >nul 2>&1
echo    [OK]
call :Log "[OK] !CUR!"
set /a C_OK+=1
exit /b 0


:Log
set "LOGLINE=%~1"
>>"%LOGFILE%" echo(!LOGLINE!
exit /b 0
