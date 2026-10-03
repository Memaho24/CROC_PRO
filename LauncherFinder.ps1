<#
  LauncherFinder.ps1 - универсальный поиск лаунчеров (Steam / Riot / Epic / Battle.net / VK Play).
  Возвращает полный путь к .exe или $null.

  Использование:
    . "$PSScriptRoot\LauncherFinder.ps1"
    $steam = Find-Launcher -Kind 'Steam'
#>

function _Reg-Candidates {
    param([string[]]$Paths, [string[]]$ValueNames)
    $out = @()
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        foreach ($v in $ValueNames) {
            try {
                $val = (Get-ItemProperty -LiteralPath $p -ErrorAction Stop).$v
                if ($val) { $out += $val }
            } catch {}
        }
    }
    return $out
}

function _Shortcut-Candidates {
    param([string[]]$Names)
    $out = @()
    $dirs = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    if ($dirs.Count -eq 0) { return @() }
    $sh = New-Object -ComObject WScript.Shell
    foreach ($d in $dirs) {
        $lnks = @(Get-ChildItem -LiteralPath $d -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
                  Where-Object { $n = $_.Name; ($Names | Where-Object { $n -like "*$_*" }).Count -gt 0 })
        foreach ($lnk in $lnks) {
            try {
                $t = $sh.CreateShortcut($lnk.FullName).TargetPath
                if ($t -and (Test-Path -LiteralPath $t)) { $out += $t }
            } catch {}
        }
    }
    return $out
}

function _Protocol-Candidates {
    param([string[]]$Protocols)
    # Windows хранит обработчик steam:// в HKCU/HKCR — берём оттуда путь к exe
    $out = @()
    foreach ($proto in $Protocols) {
        $keys = @(
            "Registry::HKEY_CLASSES_ROOT\$proto\shell\open\command",
            "Registry::HKEY_CURRENT_USER\Software\Classes\$proto\shell\open\command",
            "Registry::HKEY_LOCAL_MACHINE\Software\Classes\$proto\shell\open\command"
        )
        foreach ($k in $keys) {
            try {
                $cmd = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).'(default)'
                if ($cmd -match '^\s*"([^"]+)"') { $out += $Matches[1] }
                elseif ($cmd -match '^\s*([^\s"]+)') { $out += $Matches[1] }
            } catch {}
        }
    }
    return $out
}

function _Process-Candidates {
    param([string[]]$ProcessNames)
    $out = @()
    foreach ($pn in $ProcessNames) {
        try {
            $p = Get-CimInstance Win32_Process -Filter "Name='$pn'" -ErrorAction Stop |
                 Select-Object -First 1
            if ($p -and $p.ExecutablePath) { $out += $p.ExecutablePath }
        } catch {}
    }
    return $out
}

function _Uninstall-Candidates {
    param([string[]]$NamePatterns, [string]$ExeName)
    $out = @()
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r)) { continue }
        foreach ($k in Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue) {
            try {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction Stop
                $n = $p.DisplayName
                if (-not $n) { continue }
                if (-not ($NamePatterns | Where-Object { $n -like "*$_*" })) { continue }
                # InstallLocation может не быть, ищем через UninstallString
                if ($p.InstallLocation -and (Test-Path -LiteralPath $p.InstallLocation)) {
                    $cand = Join-Path $p.InstallLocation $ExeName
                    if (Test-Path -LiteralPath $cand) { $out += $cand }
                }
                if ($p.DisplayIcon) {
                    $ic = $p.DisplayIcon -replace ',\d+$','' -replace '^"','' -replace '"$',''
                    if ($ic -and $ic -match '\.exe$' -and (Test-Path -LiteralPath $ic)) {
                        $out += $ic
                    }
                }
            } catch {}
        }
    }
    return $out
}

function _Walk-Drives {
    param([string]$ExeName, [int]$MaxDepth = 3)
    # Обход корней дисков в поисках .exe. Ограничение по глубине чтобы не висело.
    $drives = @(Get-PSDrive -PSProvider FileSystem |
                Where-Object { $_.Free -ne $null -and $_.Root -match '^[A-Z]:\\$' } |
                Select-Object -ExpandProperty Root)
    $found = @()
    foreach ($d in $drives) {
        $queue = @([pscustomobject]@{ Path = $d; Depth = 0 })
        while ($queue.Count -gt 0) {
            $cur = $queue[0]; $queue = $queue[1..($queue.Count-1)]
            try {
                $hit = Join-Path $cur.Path $ExeName
                if (Test-Path -LiteralPath $hit) { $found += $hit; continue }
                if ($cur.Depth -ge $MaxDepth) { continue }
                $dirs = @(Get-ChildItem -LiteralPath $cur.Path -Directory -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -notmatch '^(Windows|ProgramData|\$Recycle\.Bin|System Volume Information|Recovery|PerfLogs|MSOCache)$' })
                foreach ($sd in $dirs) {
                    $queue += [pscustomobject]@{ Path = $sd.FullName; Depth = ($cur.Depth + 1) }
                }
            } catch {}
        }
    }
    return $found
}

function Find-Launcher {
    param(
        [Parameter(Mandatory)][ValidateSet('Steam','Riot','Epic','BattleNet','VKPlay')]
        [string]$Kind,
        [string]$ExtraPath   # ручной путь из config.ini (если задан)
    )

    $spec = switch ($Kind) {
        'Steam' {
            @{
                Exe        = 'steam.exe'
                RegPaths   = @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')
                RegValues  = @('SteamPath','InstallPath')
                Shortcut   = @('Steam')
                Protocols  = @('steam')
                Processes  = @('steam.exe')
                Uninstall  = @('Steam')
                StdDirs    = @('D:\Steam','E:\Steam','C:\Steam','C:\Games\Steam','D:\Games\Steam','E:\Games\Steam',
                               'C:\Program Files (x86)\Steam','C:\Program Files\Steam',
                               'D:\Program Files (x86)\Steam','D:\Program Files\Steam')
            }
        }
        'Riot' {
            @{
                Exe        = 'RiotClientServices.exe'
                RegPaths   = @('HKCU:\Software\Riot Games\Riot Client','HKLM:\SOFTWARE\WOW6432Node\Riot Games\Riot Client')
                RegValues  = @('Path','InstallLocation')
                Shortcut   = @('Riot Client','RiotClient')
                Protocols  = @('riotclient')
                Processes  = @('RiotClientServices.exe')
                Uninstall  = @('Riot Client')
                StdDirs    = @('D:\Riot Games\Riot Client','C:\Riot Games\Riot Client',
                               'E:\Riot Games\Riot Client','D:\Games\Riot Games\Riot Client')
            }
        }
        'Epic' {
            @{
                Exe        = 'EpicGamesLauncher.exe'
                RegPaths   = @('HKCU:\Software\Epic Games\EOS','HKLM:\SOFTWARE\WOW6432Node\Epic Games\EOS')
                RegValues  = @('InstallLocation','ModSdkMetadataDir')
                Shortcut   = @('Epic Games','EpicGamesLauncher')
                Protocols  = @('com.epicgames.launcher')
                Processes  = @('EpicGamesLauncher.exe')
                Uninstall  = @('Epic Games Launcher')
                StdDirs    = @('D:\Epic Games\Launcher','C:\Epic Games\Launcher','E:\Epic Games\Launcher',
                               'C:\Program Files (x86)\Epic Games\Launcher','D:\Program Files (x86)\Epic Games\Launcher')
            }
        }
        'BattleNet' {
            @{
                Exe        = 'Battle.net.exe'
                RegPaths   = @('HKCU:\Software\Blizzard Entertainment\Battle.net','HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\Battle.net')
                RegValues  = @('InstallPath')
                Shortcut   = @('Battle.net','Battle.net Launcher')
                Protocols  = @('battlenet')
                Processes  = @('Battle.net.exe')
                Uninstall  = @('Battle.net')
                StdDirs    = @('D:\Battle.net','C:\Battle.net','E:\Battle.net',
                               'C:\Program Files (x86)\Battle.net','D:\Program Files (x86)\Battle.net')
            }
        }
        'VKPlay' {
            # VK Play (бывш. My.Games GameCenter). Если не находится сам - впишите VK_PATH в config.ini
            @{
                Exe        = 'GameCenter.exe'
                RegPaths   = @('HKCU:\Software\VK Play','HKCU:\Software\MY.GAMES')
                RegValues  = @('InstallPath','InstallLocation')
                Shortcut   = @('VK Play','GameCenter')
                Protocols  = @('vkplay')
                Processes  = @('GameCenter.exe')
                Uninstall  = @('VK Play')
                StdDirs    = @("$env:LOCALAPPDATA\GameCenter",'D:\VK Play','C:\VK Play','D:\GameCenter','C:\GameCenter',
                               'D:\Games\VK Play','D:\Games\GameCenter')
            }
        }
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    # 0) ручной путь из config.ini
    if ($ExtraPath) {
        $candidates.Add($ExtraPath) | Out-Null
        $candidates.Add((Join-Path $ExtraPath $spec.Exe)) | Out-Null
        $candidates.Add((Join-Path $ExtraPath 'steam.exe')) | Out-Null
    }

    # 1) реестр
    foreach ($c in _Reg-Candidates -Paths $spec.RegPaths -ValueNames $spec.RegValues) {
        $candidates.Add($c) | Out-Null
        $candidates.Add((Join-Path $c $spec.Exe)) | Out-Null
    }

    # 2) ярлыки
    foreach ($c in _Shortcut-Candidates -Names $spec.Shortcut) { $candidates.Add($c) | Out-Null }

    # 3) протоколы
    foreach ($c in _Protocol-Candidates -Protocols $spec.Protocols) { $candidates.Add($c) | Out-Null }

    # 4) запущенные процессы
    foreach ($c in _Process-Candidates -ProcessNames $spec.Processes) { $candidates.Add($c) | Out-Null }

    # 5) Uninstall в реестре
    foreach ($c in _Uninstall-Candidates -NamePatterns $spec.Uninstall -ExeName $spec.Exe) { $candidates.Add($c) | Out-Null }

    # 6) стандартные каталоги
    foreach ($d in $spec.StdDirs) {
        $candidates.Add((Join-Path $d $spec.Exe)) | Out-Null
        if ($Kind -eq 'Steam') { $candidates.Add((Join-Path $d 'steam.exe')) | Out-Null }
    }

    # -------- проверка --------
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $p = ($c -replace '/','\').TrimEnd('\')
        if ($p -match '\.exe$') {
            if (Test-Path -LiteralPath $p) { return $p }
            # если exe не найден, но папка валидная — пробуем склеить
            $dir = Split-Path -Parent $p
            if ($dir -and (Test-Path -LiteralPath $dir)) {
                $joined = Join-Path $dir $spec.Exe
                if (Test-Path -LiteralPath $joined) { return $joined }
            }
        } else {
            # это папка — ищем exe внутри
            $joined = Join-Path $p $spec.Exe
            if (Test-Path -LiteralPath $joined) { return $joined }
        }
    }

    # 7) обход дисков (последний шанс, медленно, но точно)
    $walked = _Walk-Drives -ExeName $spec.Exe -MaxDepth 4
    if ($walked.Count -gt 0) { return $walked[0] }

    return $null
}
