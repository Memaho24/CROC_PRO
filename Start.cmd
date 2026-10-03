@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

:: ============================================================
::  ДЕПЛОЙ WINDOWS 11 — КОМПЬЮТЕРНЫЙ КЛУБ
::  Версия: 6.1 (Финальная + автоустановка APL)
::  Автор: Senior
:: ============================================================

title Deploy Windows 11 (CC)

:: -------------------------------------------------------------------
:: 0.1. ВЫБОР РЕЖИМА (Авто / Отладка) — 3 СЕКУНДЫ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ВЫБЕРИТЕ РЕЖИМ РАБОТЫ:
echo   1 - АВТОМАТИЧЕСКИЙ (без пауз)
echo   2 - ОТЛАДОЧНЫЙ (пауза после каждого шага)
echo.
echo   Если не нажать - через 3 секунды выберется АВТО.
echo ============================================================
choice /c 12 /n /t 3 /d 1 /m "Ваш выбор: "
set "MODE=%errorlevel%"

if "%MODE%"=="2" (
    set "_debug=pause"
    echo [ИНФО] Включён ОТЛАДОЧНЫЙ режим
) else (
    set "_debug="
    echo [ИНФО] Включён АВТОМАТИЧЕСКИЙ режим
)
timeout /t 1 /nobreak >nul

:: -------------------------------------------------------------------
:: 0.2. ПОДГОТОВКА: ПРАВА, КОНСОЛЬ, ПЕРЕМЕННЫЕ
:: -------------------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ИНФО] Запрос прав администратора...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
echo [УСПЕХ] Права администратора

reg add "HKCU\Console" /v "FaceName" /t REG_SZ /d "Lucida Console" /f >nul 2>&1
reg add "HKCU\Console" /v "FontSize" /t REG_DWORD /d 0x00120000 /f >nul 2>&1
echo [УСПЕХ] Консоль настроена

set "SCRIPT_DIR=%~dp0"

:: -------------------------------------------------------------------
:: 0.3. ВВОД НОМЕРА ПК
:: -------------------------------------------------------------------
:input_pc
echo.
echo ============================================================
echo   ВВЕДИТЕ НОМЕР КОМПЬЮТЕРА (1-50)
echo   Пример: 04, 15, 25
echo ============================================================
set /p "PC_NUM=Номер: "

if "%PC_NUM%"=="" (
    echo [ОШИБКА] Вы ничего не ввели!
    goto input_pc
)

set /a "TEST_NUM=%PC_NUM%" 2>nul
if "%TEST_NUM%"=="" (
    echo [ОШИБКА] Введите только цифры!
    goto input_pc
)
if not "%TEST_NUM%"=="%PC_NUM%" (
    echo [ОШИБКА] Введите только цифры!
    goto input_pc
)

set "IS_VALID=0"
for %%i in (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50) do (
    if "%PC_NUM%"=="%%i" set "IS_VALID=1"
)
if "%IS_VALID%"=="0" (
    echo [ОШИБКА] Число должно быть от 1 до 50!
    goto input_pc
)

if %PC_NUM% LSS 10 set "PC_NUM=0%PC_NUM%"
set "PC_NAME=CC%PC_NUM%"
echo [УСПЕХ] Имя ПК будет: %PC_NAME%
timeout /t 2 /nobreak >nul
%_debug%

:: -------------------------------------------------------------------
:: 1. ПРОВЕРКА СРЕДЫ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 1: ПРОВЕРКА СРЕДЫ
echo ============================================================
%_debug%

if not exist "D:\" (
    echo [ОШИБКА] Диск D не найден! Убедитесь, что физический диск подключен.
    pause
    exit /b 1
)
echo [УСПЕХ] Диск D найден
%_debug%

net user ARM >nul 2>&1
if errorlevel 1 (
    echo [ОШИБКА] Пользователь ARM не найден! Создайте и запустите скрипт заново.
    pause
    exit /b 1
)
echo [УСПЕХ] Пользователь ARM найден
%_debug%

if not exist "%SCRIPT_DIR%ADM\" (
    echo [ОШИБКА] Папка ADM не найдена на флешке!
    pause
    exit /b 1
)
if not exist "%SCRIPT_DIR%APL\" (
    echo [ОШИБКА] Папка APL не найдена на флешке!
    pause
    exit /b 1
)
echo [УСПЕХ] Структура флешки проверена
%_debug%

:: -------------------------------------------------------------------
:: 2. СИСТЕМНЫЕ НАСТРОЙКИ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 2: СИСТЕМНЫЕ НАСТРОЙКИ
echo ============================================================
%_debug%

:: 2.1. Часовой пояс
tzutil /s "Russia Time Zone 3" >nul 2>&1
if errorlevel 1 (
    echo [ОШИБКА] Часовой пояс
) else (
    echo [УСПЕХ] Часовой пояс
)
%_debug%

:: 2.2. Интерфейс
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Тёмная тема

reg add "HKCU\Control Panel\Keyboard" /v "PrintScreenKeyForSnippingEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] PrintScreen для сниппета выключен

reg add "HKCU\Software\Microsoft\Windows\DWM" /v "AccentColor" /t REG_DWORD /d 0xff646464 /f >nul 2>&1
echo [УСПЕХ] Акцентный цвет
%_debug%

:: 2.3. Питание
powercfg /hibernate off >nul 2>&1
echo [УСПЕХ] Гибернация выключена

powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
echo [УСПЕХ] Схема питания: Высокая производительность

powercfg /change disk-timeout-ac 0 >nul 2>&1
echo [УСПЕХ] Отключение дисков: Никогда
%_debug%

:: 2.4. Сеть и общий доступ
netsh advfirewall firewall set rule group="@FirewallAPI.dll,-28502" new enable=Yes >nul 2>&1
echo [УСПЕХ] Общий доступ к файлам и принтерам

powershell -Command "Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue" >nul 2>&1
echo [УСПЕХ] Профиль сети: Частная

sc config fdphost start= auto >nul 2>&1
sc config fdrespub start= auto >nul 2>&1
net start fdphost >nul 2>&1
net start fdrespub >nul 2>&1
echo [УСПЕХ] Службы обнаружения запущены

reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation" /v "AllowInsecureGuestAuth" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "everyoneincludeanonymous" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v "LimitBlankPasswordUse" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Гостевой доступ разрешён. Далее шара диска D: - это долго, если он с файлами.

net share DataD /delete >nul 2>&1
powershell -Command "$Sid = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0'); $Everyone = $Sid.Translate([System.Security.Principal.NTAccount]).Value; New-SmbShare -Name 'DataD' -Path 'D:\' -FullAccess $Everyone -ErrorAction SilentlyContinue" >nul 2>&1
icacls "D:" /grant *S-1-1-0:(OI)(CI)F /T /C /Q >nul 2>&1
echo [УСПЕХ] Шара DataD создана
%_debug%

:: -------------------------------------------------------------------
:: 3. КОПИРОВАНИЕ ADM И СЕРТИФИКАТ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 3: КОПИРОВАНИЕ ADM И СЕРТИФИКАТ
echo ============================================================
%_debug%

:: 3.1. Удаление старого ADM
if exist "C:\ADM" (
    takeown /f "C:\ADM" /r /d y >nul 2>&1
    icacls "C:\ADM" /grant administrators:F /t >nul 2>&1
    rd /s /q "C:\ADM" >nul 2>&1
    if exist "C:\ADM" ren "C:\ADM" "ADM_old" >nul 2>&1
)
echo [УСПЕХ] Старая папка ADM обработана
%_debug%

:: 3.2. Копирование ADM
xcopy "%SCRIPT_DIR%ADM" "C:\ADM\" /E /I /H /Y /Q >nul 2>&1
if errorlevel 1 (
    echo [ОШИБКА] Копирование ADM
) else (
    echo [УСПЕХ] ADM скопирован
)
%_debug%

:: 3.3. Импорт сертификата (без окна подтверждения)
if exist "%SCRIPT_DIR%APL\LAN\Certificate.p12" (
    certutil -importPFX -p bllbFjFj -user "%SCRIPT_DIR%APL\LAN\Certificate.p12" >nul 2>&1
    if errorlevel 1 (
        echo [ОШИБКА] Импорт сертификата
    ) else (
        echo [УСПЕХ] Сертификат импортирован
    )
) else (
    echo [ПРОПУСК] Сертификат не найден
)
%_debug%

:: -------------------------------------------------------------------
:: 4. УСТАНОВКА ПРОГРАММ - ВЫНЕСЕНА (Master.cmd [4] / tools\Apps.ps1)
:: -------------------------------------------------------------------
%_debug%

:: -------------------------------------------------------------------
:: 5. УДАЛЕНИЕ ПРИЛОЖЕНИЙ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 5: УДАЛЕНИЕ ПРЕДУСТАНОВЛЕННЫХ ПРИЛОЖЕНИЙ
echo ============================================================
%_debug%

call :RemoveApp "Microsoft365Copilot"
call :RemoveApp "Clipchamp"
call :RemoveApp "MicrosoftTeams"
call :RemoveApp "Outlook"
call :RemoveApp "Solitaire"
call :RemoveApp "QuickAssist"
call :RemoveApp "Weather"
call :RemoveApp "BingNews"
call :RemoveApp "Xbox"
call :RemoveApp "Maps"
call :RemoveApp "CommunicationsApps"
call :RemoveApp "ZuneMusic"
call :RemoveApp "ZuneVideo"
call :RemoveApp "WindowsCamera"
call :RemoveApp "SoundRecorder"
call :RemoveApp "ScreenSketch"
call :RemoveApp "YourPhone"
call :RemoveApp "Cortana"

%_debug%

:: -------------------------------------------------------------------
:: 6. УДАЛЕНИЕ ONEDRIVE
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 6: УДАЛЕНИЕ ONEDRIVE
echo ============================================================
%_debug%

taskkill /f /im OneDrive.exe >nul 2>&1
echo [УСПЕХ] Процесс OneDrive остановлен

if exist "%SystemRoot%\System32\OneDriveSetup.exe" (
    "%SystemRoot%\System32\OneDriveSetup.exe" /uninstall >nul 2>&1
    echo [УСПЕХ] OneDrive деинсталлирован
) else (
    echo [ПРОПУСК] Деинсталлятор OneDrive не найден
)

rmdir /s /q "%USERPROFILE%\OneDrive" >nul 2>&1
echo [УСПЕХ] Папка OneDrive удалена

powershell -Command "Get-AppxPackage -AllUsers *OneDrive* | Remove-AppxPackage -AllUsers" >nul 2>&1
echo [УСПЕХ] Пакет OneDrive удалён
%_debug%

:: -------------------------------------------------------------------
:: 7. ИНТЕРФЕЙС И ПАНЕЛЬ ЗАДАЧ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 7: ИНТЕРФЕЙС И ПАНЕЛЬ ЗАДАЧ
echo ============================================================
%_debug%

:: 7.1. Скрытие поиска
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" /v "SearchboxTaskbarMode" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Поиск скрыт

:: 7.2. Представление задач OFF
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowTaskViewButton" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Представление задач выключено

:: 7.3. Пуск влево
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarAl" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Кнопка Пуск перемещена влево

:: 7.4. End Task в контекстном меню
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" /v "TaskbarEndTask" /t REG_DWORD /d 1 /f >nul 2>&1
echo [УСПЕХ] End Task включён в меню панели задач

:: 7.5. Открепление ярлыков (кроме Проводника)
powershell -Command "$shell = New-Object -ComObject Shell.Application; $items = $shell.Namespace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items(); foreach ($item in $items) { $n = $item.Name; if ($n -match 'Explorer|Проводник') { } else { foreach ($verb in $item.Verbs()) { if ($verb.Name -match 'Unpin|Открепить') { $verb.DoIt() } } } }" >nul 2>&1
echo [УСПЕХ] Ярлыки откреплены (кроме Проводника)
%_debug%

:: -------------------------------------------------------------------
:: 8. КОРЗИНА, UAC, КОНТЕКСТНОЕ МЕНЮ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 8: КОРЗИНА, UAC, КОНТЕКСТНОЕ МЕНЮ
echo ============================================================
%_debug%

:: 8.1. Корзина — удалять сразу
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "ConfirmFileDelete" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v "NoRecycleFiles" /t REG_DWORD /d 1 /f >nul 2>&1
echo [УСПЕХ] Корзина настроена

:: 8.2. UAC — никогда не уведомлять
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "EnableLUA" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "ConsentPromptBehaviorAdmin" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v "PromptOnSecureDesktop" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] UAC отключён

:: 8.3. Классическое контекстное меню
reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /ve /t REG_SZ /d "" /f >nul 2>&1
echo [УСПЕХ] Классическое контекстное меню
%_debug%

:: -------------------------------------------------------------------
:: 9. РАБОЧИЙ СТОЛ ARM
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 9: НАСТРОЙКА РАБОЧЕГО СТОЛА ARM
echo ============================================================
%_debug%

:: 9.1. Обои
if exist "C:\ADM\Wallpaper.png" (
    powershell -Command "$code = '[DllImport(\"user32.dll\")] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);'; Add-Type -MemberDefinition $code -Name 'Win32' -Namespace 'JS'; [JS.Win32]::SystemParametersInfo(20, 0, 'C:\ADM\Wallpaper.png', 3)" >nul 2>&1
    echo [УСПЕХ] Обои установлены
) else (
    echo [ПРОПУСК] Wallpaper.png не найден
)
%_debug%

:: 9.2. Очистка рабочего стола
del /s /q "C:\Users\ARM\Desktop\*.*" >nul 2>&1
for /d %%i in ("C:\Users\ARM\Desktop\*") do rd /s /q "%%i" >nul 2>&1
echo [УСПЕХ] Рабочий стол очищен
%_debug%

:: 9.3. Копирование DesktopLayout
if exist "C:\ADM\DesktopLayout" (
    xcopy "C:\ADM\DesktopLayout\*" "C:\Users\ARM\Desktop\" /E /I /H /Y /Q >nul 2>&1
    echo [УСПЕХ] Ярлыки скопированы
) else (
    echo [ПРОПУСК] DesktopLayout не найден
)
%_debug%

:: 9.4. Размер иконок 59
reg add "HKCU\Software\Microsoft\Windows\Shell\Bags\1\Desktop" /v "IconSize" /t REG_DWORD /d 59 /f >nul 2>&1
echo [УСПЕХ] Размер иконок: 59
%_debug%

:: -------------------------------------------------------------------
:: 10. ФИНАЛИЗАЦИЯ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 10: ФИНАЛИЗАЦИЯ
echo ============================================================
%_debug%

:: 10.1. Отключение рекламы
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "Start_IrisRecommendations" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "ShowSyncProviderNotifications" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338388Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338389Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Реклама отключена

:: 10.2. Game Bar и DVR
reg add "HKCU\Software\Microsoft\GameBar" /v "ShowStartupPanel" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\GameBar" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Game Bar и DVR отключены

:: 10.3. Экран блокировки
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v "NoLockScreen" /t REG_DWORD /d 1 /f >nul 2>&1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0 >nul 2>&1
echo [УСПЕХ] Экран блокировки отключён

:: 10.4. Уведомления Защитника
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.SecurityAndMaintenance" /v "Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Уведомления Защитника отключены

:: -------------------------------------------------------------------
:: 10.4.1. ПОЛНОЕ ОТКЛЮЧЕНИЕ УВЕДОМЛЕНИЙ И СОВЕТОВ
:: -------------------------------------------------------------------
echo [ИНФО] Отключение уведомлений и советов...

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications" /v "ToastEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Всплывающие уведомления отключены

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" /v "NOC_GLOBAL_SETTING_TOASTS_ENABLED" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Глобальные уведомления отключены

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.ActionCenter.SmartOptOut" /v "Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Уведомления-предложения отключены

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-310093Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContent-338393Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Советы и подсказки системы отключены

reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v "ScoobeSystemSettingEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo [УСПЕХ] Экран завершения настройки отключён

reg add "HKCU\Software\Policies\Microsoft\Windows\Explorer" /v "DisableNotificationCenter" /t REG_DWORD /d 1 /f >nul 2>&1
echo [УСПЕХ] Центр уведомлений отключён

%_debug%

:: 10.5. Службы обновлений браузеров
sc stop gupdate >nul 2>&1
sc config gupdate start= disabled >nul 2>&1
sc stop edgeupdate >nul 2>&1
sc config edgeupdate start= disabled >nul 2>&1
sc stop edgeupdatem >nul 2>&1
sc config edgeupdatem start= disabled >nul 2>&1
sc stop MicrosoftEdgeElevationService >nul 2>&1
sc config MicrosoftEdgeElevationService start= disabled >nul 2>&1
echo [УСПЕХ] Службы обновлений браузеров отключены

:: 10.6. Полное отключение брандмауэра
netsh advfirewall set allprofiles state off >nul 2>&1
echo [УСПЕХ] Брандмауэр полностью отключён

:: 10.7. Отключение обновлений Windows
sc stop wuauserv >nul 2>&1
sc config wuauserv start= disabled >nul 2>&1
sc stop UsoSvc >nul 2>&1
sc config UsoSvc start= disabled >nul 2>&1
sc stop BITS >nul 2>&1
sc config BITS start= disabled >nul 2>&1
sc stop dosvc >nul 2>&1
sc config dosvc start= disabled >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "NoAutoUpdate" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v "AUOptions" /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update" /v "AUOptions" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "DisableWindowsUpdateAccess" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v "SetDisableUXWUAccess" /t REG_DWORD /d 1 /f >nul 2>&1
net stop wuauserv >nul 2>&1
rd /s /q "C:\Windows\SoftwareDistribution" >nul 2>&1
md "C:\Windows\SoftwareDistribution" >nul 2>&1
echo [УСПЕХ] Обновления Windows отключены

:: 10.8. Автовход ARM
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon" /t REG_SZ /d "1" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultUserName" /t REG_SZ /d "ARM" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultPassword" /t REG_SZ /d "" /f >nul 2>&1
echo [УСПЕХ] Автовход ARM настроен
%_debug%

:: -------------------------------------------------------------------
:: 11. ЗАВЕРШЕНИЕ
:: -------------------------------------------------------------------
echo.
echo ============================================================
echo   ЭТАП 11: ЗАВЕРШЕНИЕ
echo ============================================================
%_debug%

:: 11.1. Перезапуск Explorer
taskkill /f /im explorer.exe >nul 2>&1
start explorer.exe
echo [УСПЕХ] Проводник перезапущен

:: 11.2. Переименование ПК
powershell -Command "Rename-Computer -NewName '%PC_NAME%' -Force" >nul 2>&1
echo [УСПЕХ] ПК будет переименован в %PC_NAME% после перезагрузки

:: 11.3. Очистка TEMP
del /s /f /q "%temp%\*.*" >nul 2>&1
for /d %%i in ("%temp%\*") do rd /s /q "%%i" >nul 2>&1
echo [УСПЕХ] Временные файлы очищены

:: 11.4. Финальное сообщение
echo.
echo ============================================================
echo   ВСЕ НАСТРОЙКИ ЗАВЕРШЕНЫ!
echo   Имя компьютера: %PC_NAME%
echo.
echo   Нажмите "R" для ПЕРЕЗАГРУЗКИ компьютера.
echo   Нажмите любую другую клавишу для ВЫХОДА.
echo ============================================================
choice /c r /n /m "Ваш выбор: "
if errorlevel 2 (
    echo [ОТМЕНА] Перезагрузка отменена. Перезагрузите ПК вручную.
    pause
    exit /b 0
) else (
    echo [ПРОЦЕСС] Перезагрузка...
    shutdown /r /t 0
)

:: ===================================================================
:: ФУНКЦИИ
:: ===================================================================

:RemoveApp
set "APP_NAME=%~1"
powershell -Command "$n='%APP_NAME%'; $p=Get-AppxPackage -AllUsers *$n*; if($p){$p|Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue; if(Get-AppxPackage -AllUsers *$n*){Write-Host '[ОШИБКА] %APP_NAME%' -ForegroundColor Red}else{Write-Host '[УСПЕХ] %APP_NAME%' -ForegroundColor Green}}else{Write-Host '[ПРОПУСК] %APP_NAME% не найден' -ForegroundColor Yellow}"
exit /b 0