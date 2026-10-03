<#
  FactoryReset.ps1 - сброс ПК до заводских настроек (чистая Windows).
  Перед действием несколько раз переспрашивает.
  Проверка без сброса:  powershell -File FactoryReset.ps1 -DryRun
  ВАЖНО: файл должен быть в кодировке UTF-8 с BOM.
#>
[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$Root    = Split-Path -Parent $PSScriptRoot
$LogDir  = Join-Path $Root 'logs'
$LogFile = Join-Path $LogDir 'factory_reset_log.txt'
$Notify  = Join-Path $PSScriptRoot 'Notify.ps1'
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Log([string]$t, [string]$c = 'Gray') {
    Write-Host $t -ForegroundColor $c
    Add-Content -LiteralPath $LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $t) -Encoding UTF8
}

function Ask-Yes([string]$q) {
    $a = (Read-Host $q).Trim().ToLower()
    return ($a -in @('y', 'yes', 'д', 'да'))
}

# ---- права администратора ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Log '[ОШИБКА] Нужны права администратора. Запустите Master.cmd заново.' 'Red'
    exit 1
}

Clear-Host
Write-Host ''
Write-Host '============================================================' -ForegroundColor Red
Write-Host '   СБРОС ПК ДО ЗАВОДСКИХ НАСТРОЕК' -ForegroundColor Red
Write-Host '============================================================' -ForegroundColor Red
Write-Host "   Компьютер: $env:COMPUTERNAME" -ForegroundColor Yellow
if ($DryRun) { Write-Host '   РЕЖИМ ПРОВЕРКИ: сброса НЕ будет' -ForegroundColor Cyan }
Write-Host ''
Write-Host '   Будет удалено ВСЁ на диске C:' -ForegroundColor Yellow
Write-Host '     - все программы и игры'
Write-Host '     - все файлы, пользователи и настройки'
Write-Host '     - Windows будет установлена заново (чистая)'
Write-Host ''
Write-Host '   Вернуть данные будет НЕЛЬЗЯ.' -ForegroundColor Red
Write-Host '============================================================' -ForegroundColor Red
Write-Host ''

# ---- вопрос 1 ----
if (-not (Ask-Yes 'Вы точно уверены? Введите Y (или Д) чтобы продолжить, любое другое - отмена')) {
    Log '[ОТМЕНА] Сброс отменён (вопрос 1)' 'Green'
    exit 0
}

# ---- вопрос 2: ввод имени ПК ----
Write-Host ''
Write-Host "Для подтверждения впишите имя этого ПК: $env:COMPUTERNAME" -ForegroundColor Yellow
$typed = (Read-Host 'Имя ПК').Trim()
if ($typed -ine $env:COMPUTERNAME) {
    Log '[ОТМЕНА] Имя не совпало, сброс отменён (вопрос 2)' 'Green'
    exit 0
}

# ---- вопрос 3: диск D ----
$wipeOther = $false
$sysDrive  = $env:SystemDrive.TrimEnd(':')
$scriptDrv = (Split-Path -Qualifier $PSScriptRoot).TrimEnd(':')
$others = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
            Where-Object { $_.DeviceID.TrimEnd(':') -ne $sysDrive -and $_.DeviceID.TrimEnd(':') -ne $scriptDrv })
if ($others.Count -gt 0) {
    $names = ($others | ForEach-Object { $_.DeviceID }) -join ', '
    Write-Host ''
    Write-Host "Найдены другие диски: $names" -ForegroundColor Yellow
    Write-Host 'Обычный сброс Windows их может НЕ тронуть.' -ForegroundColor Yellow
    if (Ask-Yes "Очистить эти диски тоже (удалить все файлы)? Y/N, по умолчанию N") {
        if (Ask-Yes "ТОЧНО удалить все файлы на $names ? Y/N") { $wipeOther = $true }
    }
}

# ---- обратный отсчёт ----
Write-Host ''
Write-Host 'Последний шанс. Закройте это окно или нажмите Ctrl+C, чтобы ОТМЕНИТЬ.' -ForegroundColor Red
for ($i = 15; $i -ge 1; $i--) {
    Write-Host ("  Сброс начнётся через {0} сек...   " -f $i) -NoNewline -ForegroundColor Red
    Start-Sleep -Seconds 1
    Write-Host "`r" -NoNewline
}
Write-Host ''

Log "[СТАРТ] Сброс ПК $env:COMPUTERNAME. Очистка других дисков: $wipeOther. DryRun: $DryRun" 'Yellow'

if ($DryRun) {
    Log '[ПРОВЕРКА] Всё прошло по плану. В режиме проверки ничего не удалено.' 'Cyan'
    exit 0
}

# ---- уведомление в Telegram (если настроено) ----
if (Test-Path -LiteralPath $Notify) {
    try { & $Notify -Message 'ВНИМАНИЕ: ПК сбрасывается до заводских настроек' | Out-Null } catch {}
}

# ---- очистка других дисков ----
if ($wipeOther) {
    foreach ($d in $others) {
        $root = $d.DeviceID + '\'
        Log "[ОЧИСТКА] $root" 'Yellow'
        Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin @('System Volume Information', '$RECYCLE.BIN') } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- сброс Windows (способ 1: автоматически, от имени SYSTEM) ----
Log '[СБРОС] Запускаю автоматический сброс Windows...' 'Cyan'
& reagentc /enable 2>&1 | Out-Null

$tmp        = Join-Path $env:windir 'Temp'
$wipeScript = Join-Path $tmp 'cc_wipe.ps1'
$resultFile = Join-Path $tmp 'cc_wipe_result.txt'
Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue

$code = @'
$out = Join-Path $env:windir 'Temp\cc_wipe_result.txt'
try {
    $ns  = 'root\cimv2\mdm\dmmap'
    $cls = 'MDM_RemoteWipe'
    $session = New-CimSession
    $inst = Get-CimInstance -Namespace $ns -ClassName $cls -Filter "ParentID='./Vendor/MSFT' and InstanceID='RemoteWipe'" -ErrorAction Stop
    $p = New-Object Microsoft.Management.Infrastructure.CimMethodParametersCollection
    $p.Add([Microsoft.Management.Infrastructure.CimMethodParameter]::Create('param', '', 'String', 'In'))
    $r = $session.InvokeMethod($ns, $inst, 'doWipeMethod', $p)
    "OK ReturnValue=$($r.ReturnValue)" | Out-File -FilePath $out -Encoding ASCII
} catch {
    "ERR $($_.Exception.Message)" | Out-File -FilePath $out -Encoding ASCII
}
'@
Set-Content -LiteralPath $wipeScript -Value $code -Encoding UTF8

$taskName = 'CC_FactoryReset'
$ok = $false
try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wipeScript`""
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path -LiteralPath $resultFile) { break }
    }
    if (Test-Path -LiteralPath $resultFile) {
        $res = (Get-Content -LiteralPath $resultFile -Raw).Trim()
        Log "[СБРОС] Ответ Windows: $res" 'Gray'
        if ($res -like 'OK*') { $ok = $true }
    } else {
        Log '[СБРОС] Нет ответа от Windows за 60 секунд' 'Yellow'
    }
} catch {
    Log "[СБРОС] Ошибка: $($_.Exception.Message)" 'Yellow'
} finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $wipeScript -Force -ErrorAction SilentlyContinue
}

if ($ok) {
    Log '[СБРОС] Windows приняла команду. ПК сейчас перезагрузится и начнёт сброс. Не выключайте ПК!' 'Green'
    Start-Sleep -Seconds 20
    exit 0
}

# ---- способ 2: стандартное окно Windows ----
Log '[СБРОС] Автоматический способ не сработал. Открываю стандартное окно сброса Windows.' 'Yellow'
Write-Host ''
Write-Host 'В открывшемся окне выберите: "Удалить всё" -> "Локальная переустановка" -> "Сброс".' -ForegroundColor Yellow
try {
    Start-Process -FilePath "$env:windir\System32\systemreset.exe" -ArgumentList '-factoryreset'
    exit 0
} catch {
    Log "[ОШИБКА] Не удалось открыть окно сброса: $($_.Exception.Message)" 'Red'
    Write-Host 'Сделайте вручную: Параметры -> Система -> Восстановление -> Вернуть компьютер в исходное состояние.' -ForegroundColor Yellow
    exit 1
}
