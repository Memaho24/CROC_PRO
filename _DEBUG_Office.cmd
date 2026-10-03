@echo off
chcp 65001 >nul 2>&1
title DEBUG OfficePrograms

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%.."
set "DEBUGFILE=%ROOT_DIR%\logs\office_debug.txt"

if not exist "%ROOT_DIR%\logs" md "%ROOT_DIR%\logs" >nul 2>&1

echo ============================================================ > "%DEBUGFILE%"
echo DEBUG OfficePrograms - %DATE% %TIME% >> "%DEBUGFILE%"
echo SCRIPT_DIR = %SCRIPT_DIR% >> "%DEBUGFILE%"
echo ROOT_DIR   = %ROOT_DIR% >> "%DEBUGFILE%"
echo ============================================================ >> "%DEBUGFILE%"

echo.
echo === Проверка окружения ===
echo === Проверка окружения === >> "%DEBUGFILE%"

if exist "%ROOT_DIR%\office.txt" (
    echo [OK] office.txt найден
    echo [OK] office.txt найден >> "%DEBUGFILE%"
) else (
    echo [FAIL] office.txt НЕ найден по пути %ROOT_DIR%\office.txt
    echo [FAIL] office.txt НЕ найден по пути %ROOT_DIR%\office.txt >> "%DEBUGFILE%"
)

echo.
echo === Содержимое корня ===
echo === Содержимое корня === >> "%DEBUGFILE%"
dir /b "%ROOT_DIR%" >> "%DEBUGFILE%" 2>&1

echo.
echo === Содержимое tools ===
echo === Содержимое tools === >> "%DEBUGFILE%"
dir /b "%SCRIPT_DIR%" >> "%DEBUGFILE%" 2>&1

echo.
echo === Запуск OfficePrograms.ps1 ===
echo. >> "%DEBUGFILE%"
echo === ЗАПУСК OfficePrograms.ps1 === >> "%DEBUGFILE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "& { $ErrorActionPreference='Continue'; try { & '%SCRIPT_DIR%OfficePrograms.ps1' *>&1 | Tee-Object -FilePath '%DEBUGFILE%' -Append } catch { Write-Host ('CATCH: ' + $_.Exception.Message); Write-Host ('AT: ' + $_.InvocationInfo.PositionMessage) } }" 2>&1 | Tee-Object -FilePath "%DEBUGFILE%" -Append

echo.
echo ============================================================
echo   Код выхода: %errorlevel%
echo ============================================================
echo. >> "%DEBUGFILE%"
echo === КОД ВЫХОДА: %errorlevel% === >> "%DEBUGFILE%"

echo.
echo Полный лог: %DEBUGFILE%
echo Открой его и пришли мне.
echo.
pause