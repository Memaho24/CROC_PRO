@echo off
setlocal
chcp 65001 >nul 2>&1
title CyberCroc deployment
set "ROOT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
echo.
echo CyberCroc first-install / redeploy
set /p "ROLE=Role (client/admin) [client]: "
if not defined ROLE set "ROLE=client"
set /p "PCID=PC ID (e.g. PC-07), blank = computer name: "
set /p "ZONE=Zone (standard/VIP/PS5) [standard]: "
if not defined ZONE set "ZONE=standard"
if /i "%ROLE%"=="admin" (
  "%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%install.ps1" -Role admin -PcId "%PCID%" -Zone "%ZONE%"
) else (
  "%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%install.ps1" -Role client -PcId "%PCID%" -Zone "%ZONE%"
)
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (echo [OK] Installed. Restart Windows or sign out/in.) else (echo [ERROR] Installation code %RC%.)
pause
exit /b %RC%
