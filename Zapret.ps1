<#
  Zapret.ps1 - управление обходом блокировок (YouTube / Discord) из CYBERCROC.
  Работает со сборкой, где есть bat-стратегии и winws.exe (bat-режим).

  Действия:  install | on | off | choose | test | autostart-on | autostart-off | status | remove

  Настройки (необязательно) в config.ini:
    ZAPRET_DIR=C:\Zapret
    ZAPRET_URL=            прямая ссылка на zip (если пусто - берётся последний релиз с GitHub)
    ZAPRET_GITHUB=Flowseal/zapret-discord-youtube
    ZAPRET_SHA256=         необязательно, проверка скачанного zip
  ВАЖНО: файл должен быть в кодировке UTF-8 с BOM.
#>
[CmdletBinding()]
param([string]$Action = 'status')

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root    = Split-Path -Parent $PSScriptRoot
$CfgFile = Join-Path $Root 'config.ini'
$LogDir  = Join-Path $Root 'logs'
$LogFile = Join-Path $LogDir 'zapret_log.txt'
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 1MB)) {
    Move-Item -LiteralPath $LogFile -Destination "$LogFile.old" -Force
}

function Log([string]$t, [string]$c = 'Gray') {
    Write-Host $t -ForegroundColor $c
    Add-Content -LiteralPath $LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $t) -Encoding UTF8
}

function Read-Ini([string]$Path) {
    $h = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($raw in Get-Content -LiteralPath $Path -Encoding UTF8) {
            $l = $raw.Trim()
            if (-not $l -or $l -match '^[#;\[]') { continue }
            $i = $l.IndexOf('=')
            if ($i -lt 1) { continue }
            $h[$l.Substring(0, $i).Trim().ToUpper()] = $l.Substring($i + 1).Trim()
        }
    }
    return $h
}

$Cfg   = Read-Ini $CfgFile
$ZDir  = if ($Cfg['ZAPRET_DIR']) { [Environment]::ExpandEnvironmentVariables($Cfg['ZAPRET_DIR']) } else { 'C:\Zapret' }
$ZUrl  = $Cfg['ZAPRET_URL']
$ZRepo = if ($Cfg['ZAPRET_GITHUB']) { $Cfg['ZAPRET_GITHUB'] } else { 'Flowseal/zapret-discord-youtube' }
$ZSha  = $Cfg['ZAPRET_SHA256']
$StateFile = Join-Path $ZDir 'cybercroc_strategy.txt'
$TaskName  = 'CyberCroc-Zapret'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Log '[ОШИБКА] Нужны права администратора. Запустите Master.cmd заново.' 'Red'; exit 1 }

# ---------------------------------------------------------------
function Get-Strategies {
    if (-not (Test-Path -LiteralPath $ZDir)) { return @() }
    $all = @(Get-ChildItem -LiteralPath $ZDir -Filter '*.bat' -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notmatch '^(service|stop|update|check|remove|install|uninstall|cybercroc)' })
    $gen = @($all | Where-Object { $_.Name -match '^general' })
    if ($gen.Count -gt 0) { return @($gen | Sort-Object Name) }
    return @($all | Sort-Object Name)
}

function Get-Current {
    $list = Get-Strategies
    if ($list.Count -eq 0) { return $null }
    if (Test-Path -LiteralPath $StateFile) {
        $n = (Get-Content -LiteralPath $StateFile -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($n) {
            $hit = $list | Where-Object { $_.Name -eq $n.Trim() } | Select-Object -First 1
            if ($hit) { return $hit }
        }
    }
    return $list[0]
}

function Set-Current([string]$name) {
    Set-Content -LiteralPath $StateFile -Value $name -Encoding UTF8
}

function Test-Running { return [bool](Get-Process -Name winws, winws2 -ErrorAction SilentlyContinue) }

function Stop-Zapret {
    Get-Process -Name winws, winws2 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($s in 'zapret', 'WinDivert', 'WinDivert14') {
        if (Get-Service -Name $s -ErrorAction SilentlyContinue) {
            & sc.exe stop $s 2>&1 | Out-Null
        }
    }
    Start-Sleep -Seconds 1
}

function Start-Zapret($bat) {
    Stop-Zapret
    Start-Process -FilePath 'cmd.exe' -ArgumentList @('/d', '/s', '/c', ('"' + '"' + $bat.FullName + '"' + '"')) `
        -WorkingDirectory $ZDir -WindowStyle Hidden
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Running) { return $true }
    }
    return $false
}

function Test-Net {
    # возвращает сколько сайтов открылось из 3
    $urls = @('https://www.youtube.com', 'https://discord.com', 'https://i.ytimg.com')
    $ok = 0
    foreach ($u in $urls) {
        $code = & curl.exe -s -o NUL -m 7 -I -w '%{http_code}' $u 2>$null
        if ($code -and $code -ne '000') { $ok++ }
    }
    return $ok
}

function Need-Installed {
    if ((Get-Strategies).Count -eq 0) {
        Log "[!] Zapret не установлен в $ZDir. Сначала выберите 'Установить'." 'Yellow'
        return $false
    }
    return $true
}

function Set-Autostart($bat) {
    $arg = '/d /s /c "' + '"' + $bat.FullName + '"' + '"'
    $action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument $arg -WorkingDirectory $ZDir
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Autostart-Exists { return [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) }

# ---------------------------------------------------------------
function Do-Install {
    Log '[УСТАНОВКА] Ищу, что скачать...' 'Cyan'
    $url = $ZUrl
    if (-not $url) {
        try {
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$ZRepo/releases/latest" `
                   -Headers @{ 'User-Agent' = 'CyberCroc' } -TimeoutSec 30
            $asset = @($rel.assets | Where-Object { $_.name -match '\.zip$' }) | Select-Object -First 1
            if ($asset) { $url = $asset.browser_download_url; Log "[УСТАНОВКА] Версия: $($rel.tag_name)" 'Gray' }
        } catch {
            Log "[ОШИБКА] GitHub не ответил: $($_.Exception.Message)" 'Red'
        }
    }
    if (-not $url) {
        Log '[ОШИБКА] Не удалось найти ссылку на скачивание.' 'Red'
        Log '         Впишите прямую ссылку на zip в config.ini:  ZAPRET_URL=https://...zip' 'Yellow'
        return 1
    }

    $tmpZip = Join-Path $env:TEMP 'cc_zapret.zip'
    $tmpDir = Join-Path $env:TEMP 'cc_zapret_unpack'
    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    Log "[УСТАНОВКА] Скачиваю: $url" 'Cyan'
    try {
        $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing -TimeoutSec 600 -Headers @{ 'User-Agent' = 'CyberCroc' }
        $ProgressPreference = $old
    } catch {
        Log "[ОШИБКА] Скачать не удалось: $($_.Exception.Message)" 'Red'
        return 1
    }

    if ($ZSha) {
        $h = (Get-FileHash -LiteralPath $tmpZip -Algorithm SHA256).Hash
        if ($h -ine $ZSha) { Log "[ОШИБКА] SHA256 не совпал ($h). Установка остановлена." 'Red'; return 1 }
        Log '[УСТАНОВКА] SHA256 совпал' 'Green'
    }

    $wasRunning = Test-Running
    Stop-Zapret

    try {
        Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
    } catch {
        Log "[ОШИБКА] Не удалось распаковать: $($_.Exception.Message)" 'Red'
        return 1
    }

    # если внутри одна папка и в корне нет bat - берём содержимое папки
    $src = $tmpDir
    $topBat = @(Get-ChildItem -LiteralPath $tmpDir -Filter '*.bat' -File -ErrorAction SilentlyContinue)
    $topDirs = @(Get-ChildItem -LiteralPath $tmpDir -Directory -ErrorAction SilentlyContinue)
    if ($topBat.Count -eq 0 -and $topDirs.Count -eq 1) { $src = $topDirs[0].FullName }

    if (-not (Test-Path -LiteralPath $ZDir)) { New-Item -ItemType Directory -Path $ZDir -Force | Out-Null }
    Copy-Item -Path (Join-Path $src '*') -Destination $ZDir -Recurse -Force

    # антивирус (Defender) часто ругается на WinDivert - добавляем папку в исключения
    try { Add-MpPreference -ExclusionPath $ZDir -ErrorAction Stop; Log '[УСТАНОВКА] Папка добавлена в исключения Defender' 'Gray' } catch {}

    Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    $n = (Get-Strategies).Count
    if ($n -eq 0) {
        Log '[ОШИБКА] В архиве не нашлось bat-стратегий. Проверьте ссылку (ZAPRET_URL).' 'Red'
        return 1
    }
    Log "[ГОТОВО] Установлено в $ZDir. Найдено стратегий: $n" 'Green'

    if ($wasRunning) {
        $cur = Get-Current
        if ($cur) { [void](Start-Zapret $cur); Log '[УСТАНОВКА] Обход снова включён' 'Gray' }
    } else {
        Log 'Дальше: пункт "Тест всех стратегий" найдёт рабочую, потом "ВКЛЮЧИТЬ".' 'Yellow'
    }
    return 0
}

function Do-On {
    if (-not (Need-Installed)) { return 1 }
    $cur = Get-Current
    Log "[ВКЛ] Стратегия: $($cur.Name)" 'Cyan'
    if (Start-Zapret $cur) {
        Log '[ВКЛ] Обход запущен (winws работает)' 'Green'
        $r = Test-Net
        Log "[ВКЛ] Проверка сайтов: открылось $r из 3" $(if ($r -ge 2) { 'Green' } else { 'Yellow' })
        if ($r -lt 2) { Log '      Если не открылось - выберите другую стратегию или сделайте "Тест всех стратегий".' 'Yellow' }
        return 0
    }
    Log '[ОШИБКА] winws не запустился. Возможно, антивирус блокирует. Проверьте исключения.' 'Red'
    return 1
}

function Do-Off {
    Stop-Zapret
    if (Test-Running) { Log '[ОШИБКА] Не удалось остановить winws' 'Red'; return 1 }
    Log '[ВЫКЛ] Обход выключен' 'Green'
    if (Autostart-Exists) { Log '       (Автозапуск включён: после перезагрузки обход включится снова)' 'Yellow' }
    return 0
}

function Do-Choose {
    if (-not (Need-Installed)) { return 1 }
    $list = Get-Strategies
    $cur  = Get-Current
    Write-Host ''
    Write-Host 'Стратегии:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $list.Count; $i++) {
        $mark = if ($list[$i].Name -eq $cur.Name) { '  <-- сейчас' } else { '' }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $list[$i].Name, $mark)
    }
    Write-Host ''
    $a = (Read-Host 'Введите номер (пусто = отмена)').Trim()
    if (-not $a) { return 0 }
    $n = 0
    if (-not [int]::TryParse($a, [ref]$n) -or $n -lt 1 -or $n -gt $list.Count) {
        Log '[!] Нет такого номера' 'Yellow'; return 1
    }
    $pick = $list[$n - 1]
    Set-Current $pick.Name
    Log "[ВЫБОР] Стратегия: $($pick.Name)" 'Green'
    if (Autostart-Exists) { Set-Autostart $pick; Log '[ВЫБОР] Автозапуск обновлён под новую стратегию' 'Gray' }
    if ((Read-Host 'Включить сейчас? Y/N').Trim().ToLower() -in @('y', 'д', 'да', 'yes')) { return (Do-On) }
    return 0
}

function Do-Test {
    if (-not (Need-Installed)) { return 1 }
    $list = Get-Strategies
    Write-Host ''
    Log "[ТЕСТ] Стратегий: $($list.Count). Примерно $([int]($list.Count * 0.3)) мин. Не закрывайте окно." 'Cyan'
    Write-Host ''
    $res = @()
    $k = 0
    foreach ($s in $list) {
        $k++
        Write-Host ("[{0}/{1}] {2} ... " -f $k, $list.Count, $s.Name) -NoNewline
        $started = Start-Zapret $s
        if (-not $started) { Write-Host 'не запустилась' -ForegroundColor Red; $res += [pscustomobject]@{ Name = $s.Name; Score = -1 }; continue }
        Start-Sleep -Seconds 4
        $sc = Test-Net
        $res += [pscustomobject]@{ Name = $s.Name; Score = $sc }
        Write-Host "$sc из 3" -ForegroundColor $(if ($sc -ge 3) { 'Green' } elseif ($sc -ge 1) { 'Yellow' } else { 'Red' })
    }
    Stop-Zapret
    $best = $res | Sort-Object Score -Descending | Select-Object -First 1
    Write-Host ''
    if (-not $best -or $best.Score -lt 1) {
        Log '[ТЕСТ] Ни одна стратегия не открыла сайты. Проверьте интернет и антивирус.' 'Red'
        return 1
    }
    Log "[ТЕСТ] Лучшая: $($best.Name) ($($best.Score) из 3)" 'Green'
    if ((Read-Host 'Сохранить её и включить? Y/N').Trim().ToLower() -in @('y', 'д', 'да', 'yes')) {
        Set-Current $best.Name
        if (Autostart-Exists) { Set-Autostart (Get-Current) }
        return (Do-On)
    }
    return 0
}

function Do-AutoOn {
    if (-not (Need-Installed)) { return 1 }
    $cur = Get-Current
    Set-Autostart $cur
    Log "[АВТОЗАПУСК] Включён. Стратегия: $($cur.Name)" 'Green'
    if (-not (Test-Running)) { [void](Start-Zapret $cur) }
    return 0
}

function Do-AutoOff {
    if (Autostart-Exists) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Log '[АВТОЗАПУСК] Выключен' 'Green'
    } else { Log '[АВТОЗАПУСК] И так был выключен' 'Gray' }
    return 0
}

function Do-Status {
    Write-Host ''
    Write-Host '=== СТАТУС ZAPRET ===' -ForegroundColor Cyan
    $n = (Get-Strategies).Count
    Write-Host ("Папка:        {0}  ({1})" -f $ZDir, $(if ($n -gt 0) { "установлен, стратегий: $n" } else { 'НЕ установлен' }))
    $cur = Get-Current
    Write-Host ("Стратегия:    {0}" -f $(if ($cur) { $cur.Name } else { '-' }))
    Write-Host ("Обход:        {0}" -f $(if (Test-Running) { 'ВКЛЮЧЁН' } else { 'выключен' })) -ForegroundColor $(if (Test-Running) { 'Green' } else { 'Yellow' })
    Write-Host ("Автозапуск:   {0}" -f $(if (Autostart-Exists) { 'ВКЛ' } else { 'выкл' }))
    if (Test-Running) {
        $r = Test-Net
        Write-Host ("Сайты:        открылось {0} из 3 (YouTube, Discord, картинки YouTube)" -f $r)
    }
    Write-Host ''
    return 0
}

function Do-Remove {
    $a = (Read-Host "Удалить Zapret полностью ($ZDir)? Y/N").Trim().ToLower()
    if ($a -notin @('y', 'д', 'да', 'yes')) { Log '[ОТМЕНА] Не удаляю' 'Gray'; return 0 }
    Stop-Zapret
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    foreach ($s in 'zapret', 'WinDivert', 'WinDivert14') {
        if (Get-Service -Name $s -ErrorAction SilentlyContinue) { & sc.exe delete $s 2>&1 | Out-Null }
    }
    try { Remove-MpPreference -ExclusionPath $ZDir -ErrorAction SilentlyContinue } catch {}
    Remove-Item -LiteralPath $ZDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $ZDir) { Log '[!] Часть файлов не удалилась (перезагрузите ПК и повторите)' 'Yellow'; return 1 }
    Log '[ГОТОВО] Zapret удалён' 'Green'
    return 0
}

# ---------------------------------------------------------------
$rc = 0
switch ($Action.ToLower()) {
    'install'       { $rc = Do-Install }
    'update'        { $rc = Do-Install }
    'on'            { $rc = Do-On }
    'start'         { $rc = Do-On }
    'restart'       { [void](Do-Off); $rc = Do-On }
    'off'           { $rc = Do-Off }
    'stop'          { $rc = Do-Off }
    'choose'        { $rc = Do-Choose }
    'test'          { $rc = Do-Test }
    'autostart-on'  { $rc = Do-AutoOn }
    'autostart'     { $rc = Do-AutoOn }
    'autostart-off' { $rc = Do-AutoOff }
    'status'        { $rc = Do-Status }
    'remove'        { $rc = Do-Remove }
    default         { Log "[!] Неизвестное действие: $Action" 'Yellow'; $rc = 1 }
}
exit $rc
