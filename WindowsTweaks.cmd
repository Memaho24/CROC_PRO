@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title CYBERCROC - Настройки Windows
color 0A

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%.."
set "LOGFILE=%ROOT_DIR%\logs\tweaks_log.txt"
set "MODE=%~1"
set "WHAT=%~2"

if not exist "%ROOT_DIR%\logs" md "%ROOT_DIR%\logs" >nul 2>&1

fltmc >nul 2>&1
if errorlevel 1 (
    echo Запрос прав администратора...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%MODE% %WHAT%' -Verb RunAs"
    exit /b
)

>"%LOGFILE%" echo ============================================================
>>"%LOGFILE%" echo WINDOWS TWEAKS - %DATE% %TIME%
>>"%LOGFILE%" echo Computer: %COMPUTERNAME%   Mode: %MODE% %WHAT%
>>"%LOGFILE%" echo ============================================================

if "%MODE%"=="" goto MENU
if /i "%MODE%"=="disable" goto DO_DISABLE
if /i "%MODE%"=="enable"  goto DO_ENABLE
goto MENU

:MENU
cls
echo.
echo ============================================================
echo   НАСТРОЙКИ WINDOWS
echo ============================================================
echo   [1] ОТКЛЮЧИТЬ обновления Windows + все уведомления
echo   [2] ВКЛЮЧИТЬ обновления Windows + уведомления обратно
echo   [3] Отключить ТОЛЬКО обновления Windows
echo   [4] Отключить ТОЛЬКО уведомления
echo   [0] Назад
echo ============================================================
choice /c 12340 /n /m "Ваш выбор: "
set "C=%errorlevel%"
if "%C%"=="5" exit /b 0
if "%C%"=="4" set "MODE=disable" & set "WHAT=notif"   & goto DO_DISABLE
if "%C%"=="3" set "MODE=disable" & set "WHAT=wu"      & goto DO_DISABLE
if "%C%"=="2" set "MODE=enable"  & set "WHAT=all"     & goto DO_ENABLE
if "%C%"=="1" set "MODE=disable" & set "WHAT=all"     & goto DO_DISABLE
goto MENU

:: ============================================================
:DO_DISABLE
cls
echo.
echo ============================================================
echo   ОТКЛЮЧЕНИЕ
echo ============================================================
if "%WHAT%"=="all"    call :DisableWU & call :DisableNotif
if "%WHAT%"=="wu"     call :DisableWU
if "%WHAT%"=="notif"  call :DisableNotif
echo.
echo ============================================================
echo   ГОТОВО. Изменения вступят в силу после перезагрузки.
echo ============================================================
>>"%LOGFILE%" echo DONE: disabled %WHAT%
timeout /t 3 /nobreak >nul
if "%~1"=="" pause
exit /b 0

:: ============================================================
:DO_ENABLE
cls
echo.
echo ============================================================
echo   ВКЛЮЧЕНИЕ ОБРАТНО
echo ============================================================
call :EnableWU
call :EnableNotif
echo.
echo ============================================================
echo   ГОТОВО. Изменения вступят в силу после перезагрузки.
echo ============================================================
>>"%LOGFILE%" echo DONE: enabled all
timeout /t 3 /nobreak >nul
if "%~1"=="" pause
exit /b 0

:: ============================================================
:DisableWU
echo [WU] Отключаю службы и задачи обновлений Windows...
sc stop wuauserv >nul 2>&1
sc config wuauserv start= disabled >nul 2>&1
sc stop UsoSvc >nul 2>&1
sc config UsoSvc start= disabled >nul 2>&1
sc stop BITS >nul 2>&1
sc config BITS start= disabled >nul 2>&1
sc stop dosvc >nul 2>&1
sc config dosvc start= disabled >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\wuauserv"    /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\UsoSvc"      /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\BITS"        /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\dosvc"       /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate"                /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUOptions"                   /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoRebootWithLoggedOnUsers" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"    /v "DisableWindowsUpdateAccess"  /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"    /v "SetDisableUXWUAccess"        /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v "AUOptions" /t REG_DWORD /d 1 /f >nul 2>&1

schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\Scheduled Start"      /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan"   /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Wakeup" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\InstallService\ScanForUpdates"      /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\InstallService\ScanForUpdatesAsUser" /Disable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\WaaSMedic\PerformRemediation"       /Disable >nul 2>&1

net stop wuauserv >nul 2>&1
rd /s /q "C:\Windows\SoftwareDistribution" >nul 2>&1
md "C:\Windows\SoftwareDistribution" >nul 2>&1
echo   [OK] Обновления Windows отключены
>>"%LOGFILE%" echo [OK] Windows Update disabled
exit /b 0

:: ============================================================
:EnableWU
echo [WU] Включаю обновления обратно...
sc config wuauserv start= demand >nul 2>&1
sc config UsoSvc start= auto >nul 2>&1
sc config BITS start= delayed-auto >nul 2>&1
sc config dosvc start= delayed-auto >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v "Start" /t REG_DWORD /d 3 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /t REG_DWORD /d 0 /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "DisableWindowsUpdateAccess" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "SetDisableUXWUAccess"       /f >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\WindowsUpdate\Scheduled Start" /Enable >nul 2>&1
schtasks /Change /TN "\Microsoft\Windows\UpdateOrchestrator\Schedule Scan" /Enable >nul 2>&1
sc start wuauserv >nul 2>&1
echo   [OK] Обновления Windows включены
>>"%LOGFILE%" echo [OK] Windows Update enabled
exit /b 0

:: ============================================================
:DisableNotif
echo [NOTIF] Отключаю все уведомления Windows...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications" /v "ToastEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /v "NOC_GLOBAL_SETTING_TOASTS_ENABLED" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.ActionCenter.SmartOptOut" /v "Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v "DisableNotificationCenter" /t REG_DWORD /d 1 /f >nul 2>&1

:: Советы, подсказки, реклама
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-310093Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338388Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338389Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338393Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-353694Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-353696Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SilentInstalledAppsEnabled"     /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SoftLandingEnabled"             /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SystemPaneSuggestionsEnabled"   /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "OemPreInstalledAppsEnabled"     /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEnabled"        /t REG_DWORD /d 0 /f >nul 2>&1

:: Советы "Что нового" и завершение настройки
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v "ScoobeSystemSettingEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowSyncProviderNotifications" /t REG_DWORD /d 0 /f >nul 2>&1

:: Уведомления Защитника
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance" /v "Enabled" /t REG_DWORD /d 0 /f >nul 2>&1

:: Отключить "предложения" в Центре уведомлений
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /v "NOC_GLOBAL_SETTING_ALLOW_NOTIFICATION_SOUND" /t REG_DWORD /d 0 /f >nul 2>&1

echo   [OK] Уведомления отключены
>>"%LOGFILE%" echo [OK] Notifications disabled
exit /b 0

:: ============================================================
:EnableNotif
echo [NOTIF] Включаю уведомления обратно...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications" /v "ToastEnabled" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /v "NOC_GLOBAL_SETTING_TOASTS_ENABLED" /t REG_DWORD /d 1 /f >nul 2>&1
reg delete "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v "DisableNotificationCenter" /f >nul 2>&1
echo   [OK] Уведомления включены
>>"%LOGFILE%" echo [OK] Notifications enabled
exit /b 0