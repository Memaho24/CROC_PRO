@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul 2>&1

rem ============================================================
rem CYBERCROC 0.3.1 Alfa - GAME CHECK LAUNCHER
rem ASCII-only BAT. Do not put Cyrillic text in this file.
rem ============================================================
set "TOOLS_DIR=%~dp0"
set "ROOT_DIR=%TOOLS_DIR%.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"
set "PS1=%TOOLS_DIR%Games.ps1"
set "REPORT=%TOOLS_DIR%GameStatus.ps1"
set "LIST=%ROOT_DIR%games.txt"
set "LOG_DIR=%ROOT_DIR%logs"
set "LOG=%LOG_DIR%\CyberCroc.log"
set "AUTO=%~1"

if not exist "%LOG_DIR%" md "%LOG_DIR%" >nul 2>&1
if not exist "%LIST%" (
    >"%LIST%" echo # CyberCroc games list
    >>"%LIST%" echo # Format: Name^|PathCheck^|Source^|Launcher^|AppID^|MinVersion
)
if not exist "%REPORT%" (
    echo [ERROR] GameStatus.ps1 was not found: "%REPORT%"
    >>"%LOG%" echo [ERROR] Action: game check
    >>"%LOG%" echo [ERROR] GameStatus.ps1 was not found: %REPORT%
    exit /b 1
)

if /i "%AUTO%"=="auto" goto INSTALL

cls
echo ============================================================
echo   CYBERCROC - GAME CHECK
echo ============================================================
echo   [1] CHECK ONLY
echo   [2] CHECK AND INSTALL MISSING GAMES
echo.
echo   CHECK ONLY reports installed, missing and update status.
echo ============================================================
choice /c 12 /n /t 10 /d 1 /m "SELECT: "
if errorlevel 2 goto INSTALL

:CHECK
rem Check-only mode uses GameStatus.ps1 only.
rem Do not run the legacy installation engine here.
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%REPORT%"
set "RC=%ERRORLEVEL%"
goto FINISH

:INSTALL
if not exist "%PS1%" (
    echo [ERROR] Games.ps1 was not found: "%PS1%"
    >>"%LOG%" echo [ERROR] Action: game install/update
    >>"%LOG%" echo [ERROR] Games.ps1 was not found: %PS1%
    set "RC=1"
    goto FINISH
)
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%REPORT%"
set "REPORT_RC=%ERRORLEVEL%"
if not "%REPORT_RC%"=="0" (
    echo [ERROR] GameStatus.ps1 failed with code %REPORT_RC%.
    >>"%LOG%" echo [ERROR] GameStatus.ps1 failed with code %REPORT_RC%
    set "RC=%REPORT_RC%"
    goto FINISH
)
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS1%" -Install
set "RC=%ERRORLEVEL%"

:FINISH
if "%RC%"=="0" (
    >>"%LOG%" echo [GAMES] Game operation completed successfully.
) else (
    echo.
    echo [ERROR] Game operation failed with code %RC%.
    >>"%LOG%" echo [ERROR] Action: game operation
    >>"%LOG%" echo [ERROR] Error code: %RC%
    >>"%LOG%" echo [ERROR] Fix: check games.txt, launchers and CyberCroc.log.
)
if /i not "%AUTO%"=="auto" pause
exit /b %RC%
