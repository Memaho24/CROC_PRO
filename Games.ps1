<#
  Games.ps1 - проверка игр, автозаход в лаунчеры, автоустановка/обновление игр.
  Источники в games.txt: steam / riot / vk / epic
  Находит лаунчеры автоматически (LauncherFinder.ps1).
  - Steam: статус из appmanifest_*.acf, автоустановка/обновление через steam://install/<AppID>.
  - Riot: установка/обновление через RiotClientServices --launch-product=...
  - VK Play (Warface): запускает клиент, дальше кнопка в клиенте.
  - Автонажимает кнопку "Установить" в диалоге Steam (AUTO_CONFIRM_INSTALL).
  - Ждёт установки перед следующей игрой (WAIT_FOR_INSTALL=start/full/off).
  - Установленные и актуальные игры НЕ перекачиваются.
  ВАЖНО: файл должен быть в кодировке UTF-8 с BOM.
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$NoNotify
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$Root     = Split-Path -Parent $PSScriptRoot
$ListFile = Join-Path $Root 'games.txt'
$CfgFile  = Join-Path $Root 'config.ini'
$LogDir   = Join-Path $Root 'logs'
$LogFile  = Join-Path $LogDir 'games_log.txt'
$Notify   = Join-Path $PSScriptRoot 'Notify.ps1'
$Finder   = Join-Path $PSScriptRoot 'LauncherFinder.ps1'

foreach ($n in 'ListFile', 'CfgFile') {
    $cur = Get-Variable -Name $n -ValueOnly
    if (-not (Test-Path -LiteralPath $cur)) {
        $alt = Join-Path $PSScriptRoot (Split-Path -Leaf $cur)
        if (Test-Path -LiteralPath $alt) { Set-Variable -Name $n -Value $alt }
    }
}

if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 1MB)) {
    Move-Item -LiteralPath $LogFile -Destination "$LogFile.old" -Force
}

function Write-Лог {
    param([string]$Текст, [string]$Цвет = 'Gray')
    Write-Host $Текст -ForegroundColor $Цвет
    Add-Content -LiteralPath $LogFile -Value $Текст -Encoding UTF8
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

function Expand-Path([string]$p) {
    if (-not $p) { return '' }
    return [Environment]::ExpandEnvironmentVariables($p.Trim().Trim('"'))
}

# ---- подключаем модуль поиска лаунчеров ----
if (-not (Test-Path -LiteralPath $Finder)) {
    Write-Host '[ОШИБКА] LauncherFinder.ps1 не найден рядом с Games.ps1' -ForegroundColor Red
    Write-Host "         Ожидался по пути: $Finder" -ForegroundColor Red
    exit 1
}
. $Finder

# ================================================================
#  Win32 helper для автонажатия Enter в диалогах Steam
# ================================================================
if (-not ('CcWin32' -as [type])) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class CcWin32 {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr h, StringBuilder t, int c);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetClassNameW(IntPtr h, StringBuilder t, int c);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] private static extern IntPtr PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr h, int cmd);

    public static List<IntPtr> GetWindowsByPid(uint pid) {
        var r = new List<IntPtr>();
        EnumWindows((h, l) => {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp == pid && IsWindowVisible(h)) {
                var sb = new StringBuilder(512); GetWindowTextW(h, sb, 512);
                if (sb.Length > 0) r.Add(h);
            }
            return true;
        }, IntPtr.Zero);
        return r;
    }
    public static string GetTitle(IntPtr h) {
        var sb = new StringBuilder(512); GetWindowTextW(h, sb, 512); return sb.ToString();
    }
    public static void PressEnter(IntPtr h) {
        PostMessageW(h, 0x0100, (IntPtr)0x0D, IntPtr.Zero);
        PostMessageW(h, 0x0101, (IntPtr)0x0D, IntPtr.Zero);
    }
    public static bool Focus(IntPtr h) { ShowWindow(h, 9); return SetForegroundWindow(h); }
}
"@ -ErrorAction SilentlyContinue
    } catch {}
}

# ================================================================
#  STEAM
# ================================================================
function Get-SteamExe {
    return (Find-Launcher -Kind 'Steam' -ExtraPath $Cfg['STEAM_PATH'])
}

function Get-SteamRoot {
    $exe = Get-SteamExe
    if (-not $exe) { return $null }
    return (Split-Path -Parent $exe)
}

function Get-SteamUserFromRegistry {
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).AutoLoginUser
        if ($v) { return $v }
    } catch {}
    return ''
}

function Get-SteamUserFromLoginUsers {
    param([string]$SteamRoot)
    $path = Join-Path $SteamRoot 'config\loginusers.vdf'
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    $txt = Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue
    if (-not $txt) { return '' }
    $best = ''
    foreach ($m in [regex]::Matches($txt, '"(\d{17})"\s*\{((?:[^{}]|\{[^{}]*\})*)\}')) {
        $body = $m.Groups[2].Value
        if ($body -match '"MostRecent"\s+"1"' -and $body -match '"AccountName"\s+"([^"]+)"') {
            $best = $Matches[1]; break
        }
    }
    return $best
}

function Get-ActiveSteamUser {
    param([string]$SteamRoot)
    $u = Get-SteamUserFromLoginUsers $SteamRoot
    if ($u) { return $u }
    return (Get-SteamUserFromRegistry)
}

function Запустить-Steam {
    param([string]$User, [string]$Pass)

    $steamExe = Get-SteamExe
    if (-not $steamExe) {
        Write-Лог '[STEAM] Steam не найден на ПК' 'Red'
        return $false
    }
    Write-Лог "[STEAM] Найден: $steamExe" 'Green'
    $steamRoot = Split-Path -Parent $steamExe

    if (-not $User) {
        Write-Лог '[STEAM] STEAM_USER не указан — запускаю как есть' 'Yellow'
        if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath $steamExe | Out-Null
            Start-Sleep -Seconds 20
        }
        return $true
    }

    $running = [bool](Get-Process -Name steam -ErrorAction SilentlyContinue)
    $activeUser = ''
    if ($running) { $activeUser = Get-ActiveSteamUser $steamRoot }

    if ($running -and ($activeUser -ieq $User)) {
        Write-Лог "[STEAM] Уже запущен под аккаунтом $User" 'Green'
        return $true
    }
    if ($running -and (-not $activeUser)) {
        $regUser = Get-SteamUserFromRegistry
        if ($regUser -ieq $User) {
            Write-Лог "[STEAM] Steam запущен, реестр подтверждает '$User'" 'Green'
            return $true
        }
    }
    if ($running) {
        Write-Лог "[STEAM] Запущен под '$activeUser' — перезапускаю под '$User'" 'Yellow'
        Get-Process -Name steam -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 5
    }

    try {
        if (-not (Test-Path 'HKCU:\Software\Valve\Steam')) {
            New-Item -Path 'HKCU:\Software\Valve\Steam' -Force | Out-Null
        }
        Set-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'AutoLoginUser'     -Value $User -Force
        Set-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name 'RememberPassword' -Value 1 -Type DWord -Force
        Write-Лог "[STEAM] Записал AutoLoginUser=$User" 'Cyan'
    } catch {
        Write-Лог "[STEAM] Реестр: $($_.Exception.Message)" 'Yellow'
    }

    try {
        if ($Pass) {
            Write-Лог "[STEAM] Запуск: steam.exe -login $User ****" 'Cyan'
            Start-Process -FilePath $steamExe -ArgumentList @('-login', $User, $Pass) | Out-Null
        } else {
            Write-Лог '[STEAM] Запуск без пароля' 'Cyan'
            Start-Process -FilePath $steamExe | Out-Null
        }
    } catch {
        Write-Лог "[STEAM] Ошибка запуска: $($_.Exception.Message)" 'Red'
        return $false
    }

    $waited = 0
    while ($waited -lt 60) {
        Start-Sleep -Seconds 2; $waited += 2
        if (Get-Process -Name steam -ErrorAction SilentlyContinue) { break }
    }

    $waited = 0
    $loggedIn = $false
    while ($waited -lt 90 -and -not $loggedIn) {
        Start-Sleep -Seconds 3; $waited += 3
        $u = Get-ActiveSteamUser $steamRoot
        if ($u -ieq $User) {
            $loggedIn = $true
            Write-Лог "[STEAM] Вход выполнен за $waited сек" 'Green'
        } elseif ($waited % 15 -eq 0) {
            Write-Host "    ждём логин ($waited сек)" -ForegroundColor DarkGray
        }
    }
    if (-not $loggedIn) {
        $reg = Get-SteamUserFromRegistry
        if ($reg -ieq $User) {
            Write-Лог '[STEAM] loginusers.vdf не обновился, но реестр ок' 'Yellow'
            $loggedIn = $true
        }
    }
    if (-not $loggedIn) {
        Write-Лог '[STEAM] Логин не подтвердился' 'Yellow'
        return $false
    }
    Start-Sleep -Seconds 5
    Write-Лог '[STEAM] Готов принимать steam:// команды' 'Green'
    return $true
}

# ================================================================
#  АВТОНАЖАТИЕ ENTER В ДИАЛОГАХ STEAM
#  Окна современного Steam принадлежат steamwebhelper.exe, а не steam.exe.
# ================================================================
$script:SteamSeenTitles = @{}

function Confirm-SteamDialog {
    $procs = @(Get-Process -Name steam, steamwebhelper -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { return $false }

    # слова в заголовке окна установки (русский и английский Steam)
    $dialogRx = 'Install|Установ'
    $mainRx   = '^(Steam|Friends|Library|Store|Community|Библиотека|Магазин|Сообщество|Друзья|Список друзей)$'

    $target = $null
    foreach ($p in $procs) {
        $wins = @()
        try { $wins = [CcWin32]::GetWindowsByPid([uint32]$p.Id) } catch {}
        foreach ($hwnd in $wins) {
            $title = [CcWin32]::GetTitle($hwnd)
            if ([string]::IsNullOrWhiteSpace($title)) { continue }

            # для отладки: показываем в консоли новые заголовки окон (1 раз)
            if (-not $script:SteamSeenTitles.ContainsKey($title)) {
                $script:SteamSeenTitles[$title] = $true
                Write-Host "    [окно Steam] '$title'" -ForegroundColor DarkGray
            }

            if ($title -match $mainRx) { continue }
            if ($title -match $dialogRx) { $target = [pscustomobject]@{ Hwnd = $hwnd; Title = $title }; break }
        }
        if ($target) { break }
    }

    if (-not $target) { return $false }

    Write-Host "    [STEAM] нашёл диалог '$($target.Title)', жму Enter" -ForegroundColor DarkGray
    try { [void][CcWin32]::Focus($target.Hwnd) } catch {}
    Start-Sleep -Milliseconds 600

    $wsh = New-Object -ComObject wscript.shell
    try { [void]$wsh.AppActivate($target.Title) } catch {}
    Start-Sleep -Milliseconds 400
    try { $wsh.SendKeys('{ENTER}') } catch {}
    Start-Sleep -Milliseconds 500
    try { [CcWin32]::PressEnter($target.Hwnd) } catch {}
    return $true
}

# ================================================================
#  ОЖИДАНИЕ СТАРТА / ЗАВЕРШЕНИЯ УСТАНОВКИ
# ================================================================
$F_UPDATE_REQUIRED = 2
$F_FULLY_INSTALLED = 4
$F_FILES_BAD       = 32 -bor 128
$F_UPDATING        = 256 -bor 1024 -bor 262144 -bor 524288 -bor 1048576 -bor 2097152 -bor 4194304

function Invoke-SteamInstall {
    param(
        [string]$AppId,
        [string]$WaitMode = 'start',    # start | full | off
        [int]$TimeoutMin = 10
    )

    Write-Лог "   [STEAM] steam://install/$AppId" 'Cyan'
    try {
        Start-Process "steam://install/$AppId"
    } catch {
        Write-Лог "   [STEAM] Не удалось открыть URI: $($_.Exception.Message)" 'Red'
        return $false
    }

    if ($WaitMode -eq 'off') {
        Start-Sleep -Seconds 3
        return $true
    }

    $deadline   = (Get-Date).AddMinutes($TimeoutMin)
    $confirmed  = $false
    $lastCheck  = [datetime]::MinValue
    $lastTry    = [datetime]::MinValue
    $tickStart  = (Get-Date)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2

        # 1) пробуем подтвердить диалог, пока не подтверждён
        if ($AutoConfirm -and -not $confirmed -and ((Get-Date) - $lastTry).TotalSeconds -ge 4) {
            $lastTry = Get-Date
            if (Confirm-SteamDialog) {
                $confirmed = $true
                Write-Лог "   [STEAM] Диалог подтверждён" 'Green'
            }
        }

        # 2) раз в 5 сек смотрим состояние через appmanifest
        if (((Get-Date) - $lastCheck).TotalSeconds -ge 5) {
            $lastCheck = Get-Date
            $man = Find-SteamManifest $AppId
            if ($man) {
                $m = Read-Acf $man.File
                $flags = [int64]0
                [void][int64]::TryParse([string]$m['StateFlags'], [ref]$flags)

                $updating       = ($flags -band $F_UPDATING)        -ne 0
                $updateRequired = ($flags -band $F_UPDATE_REQUIRED) -ne 0
                $fullyInstalled = ($flags -band $F_FULLY_INSTALLED) -ne 0

                if ($WaitMode -eq 'full') {
                    if ($fullyInstalled -and -not $updating -and -not $updateRequired) {
                        Write-Лог "   [STEAM] Установка полностью завершена" 'Green'
                        return $true
                    }
                    $elapsed = [int]((Get-Date) - $tickStart).TotalSeconds
                    if ($elapsed % 30 -lt 5) {
                        Write-Host "    ждём установку ($elapsed сек, flags=$flags)" -ForegroundColor DarkGray
                    }
                } else {
                    # start
                    if ($updating -or ($fullyInstalled -and -not $updateRequired)) {
                        Write-Лог "   [STEAM] Загрузка запущена (flags=$flags)" 'Green'
                        return $true
                    }
                }
            }
        }
    }

    if ($WaitMode -eq 'full') {
        Write-Лог "   [STEAM] Таймаут ожидания установки ($TimeoutMin мин)" 'Yellow'
    } else {
        Write-Лог "   [STEAM] Загрузка не началась за $TimeoutMin мин" 'Yellow'
    }
    return $false
}

# ================================================================
#  WORKSHOP BLOCK (BLOCK_WORKSHOP=1 в config.ini)
# ================================================================
function Block-SteamWorkshop {
    param([string]$SteamRoot, [string[]]$AppIds)
    if (-not $SteamRoot) { return }
    $ud = Join-Path $SteamRoot 'userdata'
    if (-not (Test-Path -LiteralPath $ud)) {
        Write-Лог '[STEAM] userdata не найден — пропускаю Workshop' 'Yellow'
        return
    }
    $steamIdDirs = @(Get-ChildItem -LiteralPath $ud -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '^\d{17}$' })
    if ($steamIdDirs.Count -eq 0) {
        Write-Лог '[STEAM] Нет userdata\<steamid> — пропускаю Workshop' 'Yellow'
        return
    }
    foreach ($dir in $steamIdDirs) {
        $cfg = Join-Path $dir.FullName 'config\localconfig.vdf'
        if (-not (Test-Path -LiteralPath $cfg)) { continue }
        $txt = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8
        if (-not $txt) { continue }

        $changed = $false
        foreach ($appId in $AppIds) {
            if (-not $appId) { continue }
            $rx = '"' + [regex]::Escape($appId) + '"\s*\{(?<body>[^{}]*)\}'
            if ($txt -match $rx) {
                $body = $Matches['body']
                if ($body -match '"WorkshopItemsDisabledLocally"') {
                    $newBody = $body -replace '"WorkshopItemsDisabledLocally"\s+"\d+"', '"WorkshopItemsDisabledLocally" "1"'
                } else {
                    $newBody = "`r`n`t`t`t`t`t`t`t`t`t`"WorkshopItemsDisabledLocally`" `"1`"$body"
                }
                if ($newBody -ne $body) {
                    $txt = $txt -replace $rx, ('"' + $appId + '" { ' + $newBody + ' }')
                    $changed = $true
                }
            }
        }
        if ($changed) {
            try {
                Copy-Item -LiteralPath $cfg -Destination "$cfg.cybercroc.bak" -Force -ErrorAction SilentlyContinue
                Set-Content -LiteralPath $cfg -Value $txt -Encoding UTF8 -NoNewline
                Write-Лог "[STEAM] localconfig.vdf обновлён: $($dir.Name)" 'Green'
            } catch {
                Write-Лог "[STEAM] localconfig.vdf: $($_.Exception.Message)" 'Yellow'
            }
        }
    }
}

function Get-SteamLibraries {
    $libs = New-Object System.Collections.Generic.List[string]
    $steam = Get-SteamRoot
    if (-not $steam) { return @() }
    $libs.Add($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $txt = Get-Content -LiteralPath $vdf -Raw
        $found = @()
        foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) { $found += $m.Groups[1].Value }
        foreach ($m in [regex]::Matches($txt, '^\s*"\d+"\s+"([A-Za-z]:[^"]+)"', 'Multiline')) { $found += $m.Groups[1].Value }
        foreach ($f in $found) {
            $p = ($f -replace '\\\\', '\')
            $exists = $false
            foreach ($l in $libs) { if ($l -ieq $p) { $exists = $true } }
            if (-not $exists) { $libs.Add($p) }
        }
    }
    return @($libs)
}

function Find-SteamManifest([string]$AppId) {
    foreach ($lib in $script:SteamLibs) {
        $f = Join-Path $lib "steamapps\appmanifest_$AppId.acf"
        if (Test-Path -LiteralPath $f) { return @{ File = $f; Lib = $lib } }
    }
    return $null
}

function Read-Acf([string]$File) {
    $t = Get-Content -LiteralPath $File -Raw
    $o = @{}
    foreach ($k in 'appid', 'name', 'StateFlags', 'installdir', 'buildid', 'TargetBuildID') {
        $rx = '"' + $k + '"\s+"([^"]*)"'
        if ($t -match $rx) { $o[$k] = $Matches[1] }
    }
    return $o
}

# ================================================================
#  RIOT / EPIC / BATTLENET / VK PLAY
# ================================================================
function Запустить-Riot {
    param([string]$User, [string]$Pass)
    $exe = Find-Launcher -Kind 'Riot' -ExtraPath $Cfg['RIOT_PATH']
    if (-not $exe) { Write-Лог '[RIOT] Riot Client не найден' 'Yellow'; return $false }
    Write-Лог "[RIOT] Найден: $exe" 'Green'
    if (Get-Process -Name 'RiotClientServices' -ErrorAction SilentlyContinue) {
        Write-Лог '[RIOT] Клиент уже запущен' 'Green'; return $true
    }
    Write-Лог '[RIOT] Запускаю Riot Client' 'Cyan'
    try { Start-Process -FilePath $exe | Out-Null; Start-Sleep -Seconds 15 }
    catch { Write-Лог "[RIOT] $($_.Exception.Message)" 'Red'; return $false }
    return [bool](Get-Process -Name 'RiotClientServices' -ErrorAction SilentlyContinue)
}

function Запустить-Epic {
    param([string]$User, [string]$Pass)
    $exe = Find-Launcher -Kind 'Epic' -ExtraPath $Cfg['EPIC_PATH']
    if (-not $exe) { Write-Лог '[EPIC] Epic Launcher не найден' 'Yellow'; return $false }
    Write-Лог "[EPIC] Найден: $exe" 'Green'
    if (Get-Process -Name 'EpicGamesLauncher' -ErrorAction SilentlyContinue) {
        Write-Лог '[EPIC] Launcher уже запущен' 'Green'; return $true
    }
    Write-Лог '[EPIC] Запускаю Epic Games Launcher' 'Cyan'
    try { Start-Process -FilePath $exe | Out-Null; Start-Sleep -Seconds 15 }
    catch { Write-Лог "[EPIC] $($_.Exception.Message)" 'Red'; return $false }
    return [bool](Get-Process -Name 'EpicGamesLauncher' -ErrorAction SilentlyContinue)
}

function Запустить-Батлнет {
    param([string]$User, [string]$Pass)
    $exe = Find-Launcher -Kind 'BattleNet' -ExtraPath $Cfg['BNET_PATH']
    if (-not $exe) { Write-Лог '[BNET] Battle.net не найден' 'Yellow'; return $false }
    Write-Лог "[BNET] Найден: $exe" 'Green'
    if (Get-Process -Name 'Battle.net' -ErrorAction SilentlyContinue) {
        Write-Лог '[BNET] Battle.net уже запущен' 'Green'; return $true
    }
    Write-Лог '[BNET] Запускаю Battle.net' 'Cyan'
    try {
        if ($User -and $Pass) {
            Start-Process -FilePath $exe -ArgumentList @("-login", $User, $Pass) | Out-Null
        } else {
            Start-Process -FilePath $exe | Out-Null
        }
        Start-Sleep -Seconds 15
    } catch { Write-Лог "[BNET] $($_.Exception.Message)" 'Red'; return $false }
    return [bool](Get-Process -Name 'Battle.net' -ErrorAction SilentlyContinue)
}

function Запустить-VK {
    $exe = Find-Launcher -Kind 'VKPlay' -ExtraPath $Cfg['VK_PATH']
    if (-not $exe) { Write-Лог '[VK] VK Play не найден (можно задать VK_PATH в config.ini)' 'Yellow'; return $false }
    Write-Лог "[VK] Найден: $exe" 'Green'
    if (Get-Process -Name 'GameCenter' -ErrorAction SilentlyContinue) {
        Write-Лог '[VK] VK Play уже запущен' 'Green'; return $true
    }
    Write-Лог '[VK] Запускаю VK Play' 'Cyan'
    try { Start-Process -FilePath $exe | Out-Null; Start-Sleep -Seconds 15 }
    catch { Write-Лог "[VK] $($_.Exception.Message)" 'Red'; return $false }
    return [bool](Get-Process -Name 'GameCenter' -ErrorAction SilentlyContinue)
}

# ================================================================
#  ПРОВЕРКА ИГР
# ================================================================
function Проверить-Игру($g) {
    $r = [pscustomobject]@{ Name = $g.Name; Status = 'OK'; Version = ''; Detail = ''; Game = $g }
    $path = Expand-Path $g.Path

    if ($g.AppId) {
        if ($script:SteamLibs.Count -eq 0) {
            $r.Status = 'НЕТ STEAM'; $r.Detail = 'Steam не найден'; return $r
        }
        $man = Find-SteamManifest $g.AppId
        if (-not $man) {
            if ($path -and (Test-Path -LiteralPath $path)) { $r.Detail = 'папка есть, манифест потерян' }
            else { $r.Status = 'НЕ УСТАНОВЛЕНА'; $r.Detail = 'нет appmanifest в Steam' }
            return $r
        }
        $m = Read-Acf $man.File
        $flags = [int64]0
        [void][int64]::TryParse([string]$m['StateFlags'], [ref]$flags)
        $build  = [string]$m['buildid']
        $target = [string]$m['TargetBuildID']
        if ($build) { $r.Version = "сборка $build" }
        $dir = ''
        if ($m['installdir']) { $dir = Join-Path $man.Lib ('steamapps\common\' + $m['installdir']) }

        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            $r.Status = 'НЕ УСТАНОВЛЕНА'; $r.Detail = 'папка игры удалена'
        } elseif ($flags -band $F_FILES_BAD) {
            $r.Status = 'ПОВРЕЖДЕНА'; $r.Detail = 'файлы повреждены'
        } elseif (($flags -band $F_UPDATE_REQUIRED) -or ($target -and $target -ne '0' -and $target -ne $build)) {
            $r.Status = 'ОБНОВЛЕНИЕ'
            if ($target -and $target -ne '0' -and $target -ne $build) { $r.Detail = "сборка $build -> $target" }
            else { $r.Detail = 'вышло обновление' }
        } elseif ($flags -band $F_UPDATING) {
            $r.Status = 'ОБНОВЛЕНИЕ'; $r.Detail = 'обновление идёт'
        } elseif (-not ($flags -band $F_FULLY_INSTALLED)) {
            $r.Status = 'НЕ ГОТОВА'; $r.Detail = 'установка не завершена'
        }
        return $r
    }
    if (-not $path) { $r.Status = 'НЕТ ПУТИ'; return $r }
    if (-not (Test-Path -LiteralPath $path)) { $r.Status = 'НЕ УСТАНОВЛЕНА'; return $r }
    return $r
}

# ================================================================
#  ГЛАВНАЯ
# ================================================================
try {
    $Cfg = Read-Ini $CfgFile
    $BlockWorkshop  = ($Cfg['BLOCK_WORKSHOP'] -eq '1')
    $AutoConfirm    = ($Cfg['AUTO_CONFIRM_INSTALL'] -ne '0')     # по умолчанию ВКЛ
    $WaitMode       = if ($Cfg['WAIT_FOR_INSTALL']) { $Cfg['WAIT_FOR_INSTALL'].ToLower() } else { 'start' }
    if ($WaitMode -notin @('start','full','off')) { $WaitMode = 'start' }
    $WaitTimeoutMin = 10
    if ($Cfg['WAIT_TIMEOUT_MIN'] -match '^\d+$') { $WaitTimeoutMin = [int]$Cfg['WAIT_TIMEOUT_MIN'] }

    if (-not (Test-Path -LiteralPath $ListFile)) {
        Write-Лог "[ОШИБКА] games.txt не найден: $ListFile" 'Red'
        Write-Лог '         Скопируйте games.example.txt в games.txt и поправьте пути.' 'Yellow'
        exit 1
    }

    $games = @()
    foreach ($raw in Get-Content -LiteralPath $ListFile -Encoding UTF8) {
        $line = $raw.Trim()
        if (-not $line -or $line -match '^[#;]') { continue }
        $c = @($line -split '\|' | ForEach-Object { $_.Trim() })
        while ($c.Count -lt 6) { $c += '' }
        if (-not $c[0]) { continue }
        $appId = $c[4]
        if ($appId -and $appId -notmatch '^\d+$') { $appId = '' }
        $games += [pscustomobject]@{
            Name = $c[0]; Path = $c[1]; Source = $c[2].ToLower(); Launch = $c[3]; AppId = $appId; MinVer = $c[5]
        }
    }

    Write-Лог ('=' * 60)
    Write-Лог "ПРОВЕРКА ИГР - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Лог "Компьютер: $env:COMPUTERNAME   Автоустановка: $(if ($Install) { 'ВКЛ' } else { 'выкл' })"
    Write-Лог "Блокировка Workshop: $(if ($BlockWorkshop) { 'ВКЛ' } else { 'выкл' })"
    Write-Лог "Автоподтверждение: $(if ($AutoConfirm) { 'ВКЛ' } else { 'выкл' })   Ожидание: $WaitMode"
    Write-Лог ('=' * 60)

    $steamRootPre = Get-SteamRoot
    if ($steamRootPre) { $script:SteamLibs = @(Get-SteamLibraries) } else { $script:SteamLibs = @() }

    $steamReady = $false
    $needSteam  = @($games | Where-Object { $_.Source -eq 'steam' }).Count -gt 0
    $needRiot   = @($games | Where-Object { $_.Source -eq 'riot' }).Count -gt 0
    $needEpic   = @($games | Where-Object { $_.Source -eq 'epic' }).Count -gt 0
    $needVk     = @($games | Where-Object { $_.Source -eq 'vk' }).Count -gt 0

    if ($Install) {
        if ($needSteam) {
            Write-Лог ''
            Write-Лог '[STEAM] Подготовка...' 'Cyan'
            if ($BlockWorkshop) {
                if (Get-Process -Name steam -ErrorAction SilentlyContinue) {
                    Write-Лог '[STEAM] Останавливаю Steam для правки localconfig.vdf...' 'Cyan'
                    Get-Process -Name steam -ErrorAction SilentlyContinue | Stop-Process -Force
                    Start-Sleep -Seconds 6
                }
                $appIds = @($games | Where-Object { $_.AppId } | ForEach-Object { $_.AppId })
                Block-SteamWorkshop -SteamRoot (Get-SteamRoot) -AppIds $appIds
            }
            $steamReady = Запустить-Steam -User $Cfg['STEAM_USER'] -Pass $Cfg['STEAM_PASS']
            if ($steamReady) { $script:SteamLibs = @(Get-SteamLibraries) }
        }
        if ($needRiot) {
            Write-Лог ''; Write-Лог '[RIOT] Подготовка...' 'Cyan'
            Запустить-Riot -User $Cfg['RIOT_USER'] -Pass $Cfg['RIOT_PASS'] | Out-Null
        }
        if ($needEpic) {
            Write-Лог ''; Write-Лог '[EPIC] Подготовка...' 'Cyan'
            Запустить-Epic -User $Cfg['EPIC_USER'] -Pass $Cfg['EPIC_PASS'] | Out-Null
        }
        if ($needVk) {
            Write-Лог ''; Write-Лог '[VK] Подготовка...' 'Cyan'
            Запустить-VK | Out-Null
        }
    } else {
        Write-Лог '[РЕЖИМ] Только проверка, лаунчеры не запускаю' 'DarkGray'
    }
    Write-Лог ''

    $results   = @()
    $triggered = 0
    foreach ($g in $games) {
        $r = Проверить-Игру $g
        $tag = "[$($r.Status)]"
        $txt = '{0,-18} {1}' -f $tag, $r.Name
        if ($r.Version) { $txt += "  ($($r.Version))" }
        if ($r.Detail)  { $txt += "  — $($r.Detail)" }
        $color = switch ($r.Status) {
            'OK'              { 'Green' }
            'НЕТ ПУТИ'        { 'DarkYellow' }
            'НЕ УСТАНОВЛЕНА'  { 'Red' }
            'НЕТ STEAM'       { 'Red' }
            default           { 'Yellow' }
        }
        Write-Лог $txt $color

        $needsAction = ($r.Status -in @('НЕ УСТАНОВЛЕНА','ОБНОВЛЕНИЕ','ПОВРЕЖДЕНА','НЕ ГОТОВА'))
        if ($Install -and $needsAction) {
            if ($g.AppId -and $steamReady) {
                $ok = Invoke-SteamInstall -AppId $g.AppId -WaitMode $WaitMode -TimeoutMin $WaitTimeoutMin
                if ($ok) { $triggered++ }
            } elseif ($g.AppId -and -not $steamReady) {
                Write-Лог '   [ПРОПУСК] Steam не готов' 'DarkYellow'
            } elseif ($g.Source -eq 'riot') {
                $rx   = Find-Launcher -Kind 'Riot' -ExtraPath $Cfg['RIOT_PATH']
                $prod = ''
                if ($g.Name -match 'valorant')            { $prod = 'valorant' }
                elseif ($g.Name -match 'league|lol')      { $prod = 'league_of_legends' }
                if ($rx -and $prod) {
                    Start-Process -FilePath $rx -ArgumentList @("--launch-product=$prod", '--launch-patchline=live')
                    Write-Лог "   [RIOT] Установка/обновление '$prod' запущено в клиенте" 'Cyan'
                    $triggered++
                    Start-Sleep -Seconds 8
                } else {
                    Write-Лог '   [РУЧНАЯ] Riot: продукт не определён по названию, установите через клиент' 'DarkYellow'
                }
            } elseif ($g.Source -eq 'vk') {
                [void](Запустить-VK)
                Write-Лог '   [РУЧНАЯ] VK Play: нажмите "Установить/Обновить" в клиенте' 'DarkYellow'
            } elseif ($g.Source -eq 'epic') {
                if ($g.Launch) {
                    $l = Expand-Path $g.Launch
                    if (Test-Path -LiteralPath $l) {
                        $procName = [IO.Path]::GetFileNameWithoutExtension($l)
                        if (-not (Get-Process -Name $procName -ErrorAction SilentlyContinue)) {
                            Start-Process -FilePath $l
                            Write-Лог "   [ЛАУНЧЕР] Запущен $l" 'Cyan'
                            Start-Sleep -Seconds 6
                        }
                    }
                }
                Write-Лог '   [РУЧНАЯ] Установи игру через клиент' 'DarkYellow'
            }
        }
        $results += $r
    }

    $total      = $results.Count
    $ok         = @($results | Where-Object { $_.Status -eq 'OK' })
    $missing    = @($results | Where-Object { $_.Status -eq 'НЕ УСТАНОВЛЕНА' })
    $updates    = @($results | Where-Object { $_.Status -eq 'ОБНОВЛЕНИЕ' })
    $broken     = @($results | Where-Object { $_.Status -eq 'ПОВРЕЖДЕНА' })
    $incomplete = @($results | Where-Object { $_.Status -eq 'НЕ ГОТОВА' })
    $problems   = $missing.Count + $updates.Count + $broken.Count + $incomplete.Count

    Write-Лог ''
    Write-Лог ('=' * 60)
    Write-Лог "ИТОГИ: Всего=$total ОК=$($ok.Count) НеУст=$($missing.Count) Обновл=$($updates.Count) Повреждено=$($broken.Count) НеГотово=$($incomplete.Count) Запущено=$triggered"
    Write-Лог ('=' * 60)

    $notifyOk = ($Cfg['NOTIFY_ON_OK'] -eq '1')
    if (-not $NoNotify -and ($problems -gt 0 -or $notifyOk)) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("Проверка игр: в порядке $($ok.Count) из $total")
        function Add-Секция([string]$title, $items) {
            if (@($items).Count -eq 0) { return }
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("$title ($(@($items).Count)):")
            foreach ($i in $items) {
                $line = "• $($i.Name)"
                if ($i.Detail) { $line += " — $($i.Detail)" }
                [void]$sb.AppendLine($line)
            }
        }
        Add-Секция 'Не установлены'         $missing
        Add-Секция 'Вышли обновления'       $updates
        Add-Секция 'Повреждены'             $broken
        Add-Секция 'Установка не завершена' $incomplete
        if ($triggered -gt 0) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("Запущена автоустановка/обновление: $triggered")
        }
        if (Test-Path -LiteralPath $Notify) { & $Notify -Message $sb.ToString().TrimEnd() }
    }

    if ($problems -gt 0) { exit 2 } else { exit 0 }
}
catch {
    Write-Лог "[ОШИБКА] $($_.Exception.Message)" 'Red'
    Write-Лог $_.ScriptStackTrace 'DarkGray'
    exit 1
}
