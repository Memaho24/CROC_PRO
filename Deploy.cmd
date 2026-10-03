@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Deploy PC
color 0A

set "SCRIPT_DIR=%~dp0"
for %%I in ("%~dp0..") do set "ROOT_DIR=%%~fI"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "LOGDIR=%ROOT_DIR%\logs"
set "LOGFILE=%LOGDIR%\deploy_log.txt"

if not exist "%LOGDIR%" md "%LOGDIR%" >nul 2>&1

:: ---- admin rights (fltmc works even if the Server service is off, unlike "net session") ----
fltmc >nul 2>&1
if errorlevel 1 (
    echo Requesting admin rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if exist "%LOGFILE%" for %%F in ("%LOGFILE%") do if %%~zF gtr 1048576 move /y "%LOGFILE%" "%LOGFILE%.old" >nul 2>&1
call :Log "============================================================"
call :Log "DEPLOY - %DATE% %TIME%"
call :Log "Computer: %COMPUTERNAME%"

:: ============================================================
::  PC NUMBER INPUT  (accepts 4, 04, 15 ... 50; rejects letters, 0, >50)
:: ============================================================
:input_pc
cls
echo.
echo ============================================================
echo   DEPLOY PC
echo ============================================================
echo   Enter PC number 1-50, e.g. 4, 04, 15
echo ============================================================
set "PC_NUM="
set /p "PC_NUM=Number: "

if not defined PC_NUM (
    echo [ERROR] Empty input
    timeout /t 2 >nul
    goto input_pc
)

set "BAD="
for /f "delims=0123456789" %%A in ("0!PC_NUM!") do set "BAD=1"
if defined BAD (
    echo [ERROR] Only digits allowed
    timeout /t 2 >nul
    goto input_pc
)
if not "!PC_NUM:~2,1!"=="" (
    echo [ERROR] Number must be 1-50
    timeout /t 2 >nul
    goto input_pc
)

:: "1" prefix avoids octal parsing of 08 / 09
set "P2=0!PC_NUM!"
set "P2=!P2:~-2!"
set /a "PC_INT=1!P2! - 100"
if !PC_INT! lss 1 (
    echo [ERROR] Number must be 1-50
    timeout /t 2 >nul
    goto input_pc
)
if !PC_INT! gtr 50 (
    echo [ERROR] Number must be 1-50
    timeout /t 2 >nul
    goto input_pc
)

set "PC_NUM=!P2!"
set "PC_NAME=CC!PC_NUM!"
echo.
echo [OK] PC will be renamed to: !PC_NAME!
timeout /t 2 /nobreak >nul

:: ============================================================
::  STEP 1 - ENVIRONMENT CHECK
:: ============================================================
echo.
echo ============================================================
echo   STEP 1: Environment check
echo ============================================================
if not exist "%ROOT_DIR%\ADM\" (
    echo [ERROR] ADM folder not found on flash
    pause
    exit /b 1
)
if not exist "%ROOT_DIR%\tools\Apps.ps1" (
    echo [ERROR] tools\Apps.ps1 not found
    pause
    exit /b 1
)
echo [OK] Flash structure OK

:: ============================================================
::  STEP 2 - COPY ADM
:: ============================================================
echo.
echo ============================================================
echo   STEP 2: Copy ADM to C:\ADM
echo ============================================================
if exist "C:\ADM" (
    takeown /f "C:\ADM" /r /d y >nul 2>&1
    icacls "C:\ADM" /grant administrators:F /t >nul 2>&1
    rd /s /q "C:\ADM" >nul 2>&1
    if exist "C:\ADM" ren "C:\ADM" "ADM_old" >nul 2>&1
)
xcopy "%ROOT_DIR%\ADM" "C:\ADM\" /E /I /H /Y /Q >nul 2>&1
if errorlevel 1 (
    echo [FAIL] Copy ADM
    call :Log "[FAIL] Copy ADM"
) else (
    echo [OK] ADM copied
    call :Log "[OK] ADM copied"
)

:: ============================================================
::  STEP 3 - IMPORT CERTIFICATE
:: ============================================================
echo.
echo ============================================================
echo   STEP 3: Import certificate
echo ============================================================
if exist "%ROOT_DIR%\APL\LAN\Certificate.p12" (
    certutil -importPFX -p bllbFjFj -user "%ROOT_DIR%\APL\LAN\Certificate.p12" >nul 2>&1
    if errorlevel 1 (
        echo [FAIL] Certificate import
        call :Log "[FAIL] Certificate import"
    ) else (
        echo [OK] Certificate imported
        call :Log "[OK] Certificate imported"
    )
) else (
    echo [SKIP] Certificate not found
)

:: ============================================================
::  STEP 4 - INSTALL PROGRAMS FROM THE INTERNET (list: apps.txt)
:: ============================================================
echo.
echo ============================================================
echo   STEP 4: Install programs from the Internet
echo ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\tools\Apps.ps1" -Install
set "APPS_RC=!errorlevel!"
if "!APPS_RC!"=="0" (
    call :Log "[OK] Programs installed"
) else (
    call :Log "[WARN] Programs: code !APPS_RC! - see logs\apps_log.txt"
)

:: ============================================================
::  STEP 5 - FINAL SETTINGS
:: ============================================================
echo.
echo ============================================================
echo   STEP 5: Final settings
echo ============================================================
taskkill /f /im explorer.exe >nul 2>&1
start explorer.exe
echo [OK] Explorer restarted

if /i "%COMPUTERNAME%"=="!PC_NAME!" (
    echo [OK] PC already named !PC_NAME!
) else (
    powershell -NoProfile -Command "Rename-Computer -NewName '!PC_NAME!' -Force -ErrorAction Stop" >nul 2>&1
    if errorlevel 1 (
        echo [FAIL] Rename to !PC_NAME! failed
        call :Log "[FAIL] Rename to !PC_NAME!"
    ) else (
        echo [OK] PC will be renamed to !PC_NAME! after reboot
        call :Log "[OK] Rename to !PC_NAME! after reboot"
    )
)

del /s /f /q "%temp%\*.*" >nul 2>&1
for /d %%i in ("%temp%\*") do rd /s /q "%%i" >nul 2>&1
echo [OK] Temp cleaned

call :Log "SUMMARY: Programs code !APPS_RC!, Name !PC_NAME!"

echo.
echo ============================================================
echo   ALL DONE
echo   PC name:  !PC_NAME!
if "!APPS_RC!"=="0" (
    echo   Programs: all OK
) else (
    echo   Programs: some failed, see logs\apps_log.txt
)
echo ============================================================
echo.
echo   Press R to REBOOT, Q to EXIT without reboot
echo ============================================================
choice /c rq /n /m "Choice: "
if errorlevel 2 (
    echo [CANCEL] Reboot skipped.
    pause
    exit /b 0
)
echo Rebooting...
shutdown /r /t 5
exit /b 0


:Log
set "LOGLINE=%~1"
>>"%LOGFILE%" echo(!LOGLINE!
exit /b 0
