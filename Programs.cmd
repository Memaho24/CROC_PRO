@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title APL - Auto Check / Install
color 0E

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%.."
set "APL_DIR=%ROOT_DIR%\APL"
set "RECIPES=%ROOT_DIR%\recipes.txt"
set "LOGFILE=%ROOT_DIR%\logs\programs_log.txt"
set "DEBUGLOG=%ROOT_DIR%\logs\programs_debug.log"
set "AUTO_MODE=%~1"

if not exist "%ROOT_DIR%\logs" md "%ROOT_DIR%\logs" >nul 2>&1

>"%DEBUGLOG%" echo Programs.cmd start : %DATE% %TIME%
>>"%DEBUGLOG%" echo AUTO_MODE=[%AUTO_MODE%]  APL=[%APL_DIR%]  RECIPES=[%RECIPES%]

set "MODE=check"
set "SKIP_MENU=0"
if /i "%AUTO_MODE%"=="auto"  ( set "MODE=auto"  & set "SKIP_MENU=1" )
if /i "%AUTO_MODE%"=="force" ( set "MODE=force" & set "SKIP_MENU=1" )
if /i "%AUTO_MODE%"=="check" ( set "MODE=check" & set "SKIP_MENU=1" )

if "%MODE%"=="check" if "%SKIP_MENU%"=="0" (
    cls
    echo.
    echo ============================================================
    echo   APL - AUTO MODE
    echo ============================================================
    echo   Computer: %COMPUTERNAME%
    echo.
    echo   [1] Check only          - scan APL, show status
    echo   [2] Check + INSTALL     - install what is missing
    echo   [3] FORCE install       - install everything from APL
    echo.
    echo   Default in 8 sec: [1]
    echo ============================================================
    choice /c 123 /n /t 8 /d 1 /m "Choice: "
    set "CH=%errorlevel%"
    if "!CH!"=="3" set "MODE=force"
    if "!CH!"=="2" set "MODE=auto"
)

>"%LOGFILE%" echo ============================================================
>>"%LOGFILE%" echo APL AUTO - %DATE% %TIME%
>>"%LOGFILE%" echo Computer: %COMPUTERNAME%   Mode: %MODE%
>>"%LOGFILE%" echo ============================================================

set /a T_TOTAL=0, T_OK=0, T_MISSING=0, T_INSTALLED=0, T_FAILED=0, T_NORECIPE=0, T_SKIPPED=0

if not exist "%APL_DIR%\" (
    echo [ERROR] APL folder not found: %APL_DIR%
    >>"%LOGFILE%" echo [ERROR] APL folder not found
    if "%SKIP_MENU%"=="0" pause
    exit /b 1
)

if "%MODE%"=="force" goto FORCE_INSTALL

if not exist "%RECIPES%" (
    echo [ERROR] recipes.txt not found: %RECIPES%
    echo         Put recipes.txt next to Master.cmd
    >>"%LOGFILE%" echo [ERROR] recipes.txt not found
    if "%SKIP_MENU%"=="0" pause
    exit /b 1
)

echo.
echo ============================================================
echo   SCAN APL  - mode: %MODE%
echo ============================================================
echo.

for %%F in ("%APL_DIR%\*.exe") do call :HandleInstaller "%%~fF" "%%~nF" "%%~xF"
for %%F in ("%APL_DIR%\*.msi") do call :HandleInstaller "%%~fF" "%%~nF" "%%~xF"

echo.
echo ============================================================
echo   RESULTS
echo ============================================================
echo   Found in APL:   %T_TOTAL%
echo   OK:             %T_OK%
echo   Missing:        %T_MISSING%
echo   Installed now:  %T_INSTALLED%
echo   No recipe:      %T_NORECIPE%
echo   Failed:         %T_FAILED%
echo ============================================================
echo.
>>"%LOGFILE%" echo RESULTS: Total=%T_TOTAL% OK=%T_OK% Missing=%T_MISSING% Installed=%T_INSTALLED% NoRecipe=%T_NORECIPE% Failed=%T_FAILED%

if exist "%SCRIPT_DIR%Notify.cmd" (
    call "%SCRIPT_DIR%Notify.cmd" "APL: OK %T_OK%/%T_TOTAL%, inst %T_INSTALLED%, fail %T_FAILED%" 2>nul
)

if "%SKIP_MENU%"=="0" pause
exit /b 0

:: ============================================================
:HandleInstaller
:: %1 full path   %2 name (no ext)   %3 ext
set "IFULL=%~1"
set "INAME=%~2"
set "IEXT=%~3"
set /a T_TOTAL+=1

call :FindRecipe "!INAME!"
if not defined RECIPE_PATH (
    echo [NO RECIPE] !INAME!!IEXT!
    echo   -- add a line to recipes.txt if you want it checked
    >>"%LOGFILE%" echo [NO RECIPE] !INAME!
    set /a T_NORECIPE+=1
    exit /b 0
)

call set "CHK=%RECIPE_PATH%"

if not exist "!CHK!" (
    echo [MISSING]    !INAME!!IEXT!
    echo              ^> !CHK!
    >>"%LOGFILE%" echo [MISSING] !INAME!  target=!CHK!
    set /a T_MISSING+=1
    if "%MODE%"=="auto" call :InstallIt "!IFULL!" "!INAME!" "!IEXT!"
    exit /b 0
)

echo [OK]         !INAME!!IEXT!
echo              ^> !CHK!
>>"%LOGFILE%" echo [OK] !INAME!  target=!CHK!
set /a T_OK+=1
exit /b 0

:: ============================================================
:FindRecipe
:: %1 = installer name (no ext). Fills RECIPE_PATH / RECIPE_MIN
set "RECIPE_PATH="
set "RECIPE_MIN="
for /f "usebackq tokens=1,2,3 delims=|" %%A in ("%RECIPES%") do (
    if not defined RECIPE_PATH (
        set "RK=%%A"
        if not "!RK!"=="" if not "!RK:~0,1!"=="#" (
            echo %~1 | findstr /i /c:"!RK!" >nul
            if not errorlevel 1 (
                set "RECIPE_PATH=%%B"
                set "RECIPE_MIN=%%C"
            )
        )
    )
)
exit /b 0

:: ============================================================
:InstallIt
:: %1 full path   %2 name   %3 ext
set "SRC=%~1"
set "NME=%~2"
set "EXT=%~3"

echo              [INSTALL] %NME%%EXT%
>>"%LOGFILE%" echo [INSTALL] %NME%%EXT%

if /i "%EXT%"==".msi" (
    msiexec /i "%SRC%" /qn /norestart
) else (
    start /wait "" "%SRC%" /S /silent /quiet /norestart
)
set "RC=!ERRORLEVEL!"

if "!RC!"=="0" (
    echo              [OK] installed
    >>"%LOGFILE%" echo [OK-INST] %NME%%EXT%
    set /a T_INSTALLED+=1
) else if "!RC!"=="3010" (
    echo              [OK] installed, reboot needed
    >>"%LOGFILE%" echo [OK-INST-REBOOT] %NME%%EXT%
    set /a T_INSTALLED+=1
) else if "!RC!"=="1641" (
    echo              [OK] installed, reboot started
    >>"%LOGFILE%" echo [OK-INST-REBOOT] %NME%%EXT%
    set /a T_INSTALLED+=1
) else (
    echo              [FAIL] exit code !RC!
    >>"%LOGFILE%" echo [FAIL] %NME%%EXT% code=!RC!
    set /a T_FAILED+=1
)
timeout /t 2 /nobreak >nul
exit /b 0

:: ============================================================
:FORCE_INSTALL
echo.
echo ============================================================
echo   FORCE INSTALL - EVERYTHING FROM APL
echo ============================================================
echo.

set /a APL_COUNT=0
for %%F in ("%APL_DIR%\*.exe") do set /a APL_COUNT+=1
for %%F in ("%APL_DIR%\*.msi") do set /a APL_COUNT+=1

if %APL_COUNT%==0 (
    echo [SKIP] No installers in APL
    if "%SKIP_MENU%"=="0" pause
    exit /b 0
)

echo Found: %APL_COUNT%
echo.

for %%F in ("%APL_DIR%\*.exe") do (
    set /a T_TOTAL+=1
    echo ------------------------------------------------------------
    echo [INSTALL] %%~nxF
    echo ------------------------------------------------------------
    start /wait "" "%%~fF" /S /silent /quiet /norestart
    set "RC=!ERRORLEVEL!"
    call :ReportForce "%%~nxF" "!RC!"
    timeout /t 1 /nobreak >nul
)
for %%F in ("%APL_DIR%\*.msi") do (
    set /a T_TOTAL+=1
    echo ------------------------------------------------------------
    echo [INSTALL] %%~nxF
    echo ------------------------------------------------------------
    msiexec /i "%%~fF" /qn /norestart
    set "RC=!ERRORLEVEL!"
    call :ReportForce "%%~nxF" "!RC!"
    timeout /t 1 /nobreak >nul
)

echo.
echo ============================================================
echo   RESULTS
echo ============================================================
echo   Total:      %T_TOTAL%
echo   Installed:  %T_INSTALLED%
echo   Failed:     %T_FAILED%
echo ============================================================
>>"%LOGFILE%" echo FORCE RESULTS: Total=%T_TOTAL% Installed=%T_INSTALLED% Failed=%T_FAILED%

if exist "%SCRIPT_DIR%Notify.cmd" (
    call "%SCRIPT_DIR%Notify.cmd" "APL force: %T_INSTALLED%/%T_TOTAL% ok, fail %T_FAILED%" 2>nul
)
if "%SKIP_MENU%"=="0" pause
exit /b 0

:ReportForce
set "RF=%~1"
set "RR=%~2"
if "%RR%"=="0" (
    echo   [OK] installed
    >>"%LOGFILE%" echo [OK] %RF%
    set /a T_INSTALLED+=1
) else if "%RR%"=="3010" (
    echo   [OK] installed, reboot needed
    >>"%LOGFILE%" echo [OK-REBOOT] %RF%
    set /a T_INSTALLED+=1
) else if "%RR%"=="1641" (
    echo   [OK] installed, reboot started
    >>"%LOGFILE%" echo [OK-REBOOT] %RF%
    set /a T_INSTALLED+=1
) else (
    echo   [FAIL] code %RR%
    >>"%LOGFILE%" echo [FAIL] %RF% code=%RR%
    set /a T_FAILED+=1
)
exit /b 0