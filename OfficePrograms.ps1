<#
  OfficePrograms.ps1 - установка офисных программ из office.txt.
  Проверяет что уже стоит, не переустанавливает.
  Типы: winget / apl / url
  ВАЖНО: файл должен быть в кодировке UTF-8 с BOM.
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Json,
    [switch]$NoNotify
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$Root     = Split-Path -Parent $PSScriptRoot
$ListFile = Join-Path $Root 'office.txt'
$CfgFile  = Join-Path $Root 'config.ini'
$AplDir   = Join-Path $Root 'APL'
$LogDir   = Join-Path $Root 'logs'
$LogFile  = Join-Path $LogDir 'office_log.txt'
$Notify   = Join-Path $PSScriptRoot 'Notify.ps1'
$TmpDir   = Join-Path $env:TEMP 'cybercroc-office'

if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $TmpDir)) { New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null }
if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 1MB)) {
    Move-Item -LiteralPath $LogFile -Destination "$LogFile.old" -Force
}

function Write-Log {
    param([string]$Text, [string]$Color = 'Gray')
    if (-not $Json) { Write-Host $Text -ForegroundColor $Color }
    Add-Content -LiteralPath $LogFile -Value $Text -Encoding UTF8
}

function Write-LogError {
    param([string]$Text)
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Red
    Write-Host '  ОШИБКА' -ForegroundColor Red
    Write-Host '============================================================' -ForegroundColor Red
    Write-Host "  $Text" -ForegroundColor Yellow
    Write-Host ''
    Add-Content -LiteralPath $LogFile -Value "[ERROR] $Text" -Encoding UTF8
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

function Test-AlreadyInstalled {
    param([string]$CheckPath, [string]$WingetId, [string]$Type)

    if ($CheckPath) {
        $full = Expand-Path $CheckPath
        if (Test-Path -LiteralPath $full) {
            return @{ Installed = $true; How = "file: $full" }
        }
    }
    if ($Type -eq 'winget' -and $WingetId) {
        try {
            $out = & winget list --id $WingetId --exact --source winget --accept-source-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -and $out -match [regex]::Escape($WingetId)) {
                return @{ Installed = $true; How = "winget: $WingetId" }
            }
        } catch {}
    }
    return @{ Installed = $false; How = '' }
}

function Test-Winget {
    try {
        $null = & winget --version 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Install-ByWinget {
    param([string]$Id, [string]$Name)
    Write-Log "   [WINGET] $Name  ($Id)" 'Cyan'

    # Сначала без указания scope, потом machine, потом user
    foreach ($scope in @('', 'machine', 'user')) {
        $wargs = @(
            'install', '--id', $Id, '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements',
            '--silent', '--disable-interactivity'
        )
        if ($scope) { $wargs += @('--scope', $scope) }

        $label = if ($scope) { $scope } else { 'auto' }
        Add-Content -LiteralPath $LogFile -Value "winget $($wargs -join ' ')" -Encoding UTF8
        & winget @wargs 2>&1 | ForEach-Object { Add-Content -LiteralPath $LogFile -Value "$_" -Encoding UTF8 }
        $rc = $LASTEXITCODE
        Add-Content -LiteralPath $LogFile -Value "winget exit code: $rc" -Encoding UTF8

        if ($rc -eq 0) {
            Write-Log "   [OK] установлено ($label)" 'Green'
            return @{ Status = 'ok'; Code = $rc }
        }
        if ($rc -eq -1978335189 -or $rc -eq -1978335135) {
            Write-Log "   [OK] уже установлено" 'Green'
            return @{ Status = 'ok'; Code = $rc }
        }
        Write-Log "   [..] попытка ($label) не удалась, код $rc" 'DarkYellow'
    }
    Write-Log "   [ОШИБКА] winget не смог установить (подробности в logs\office_log.txt)" 'Red'
    return @{ Status = 'fail'; Code = -1 }
}

function Install-FromApl {
    param([string]$FileName, [string]$Name)
    $path = Join-Path $AplDir $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Log "   [ОШИБКА] Установщик не найден: $path" 'Red'
        return @{ Status='fail'; Code=-1 }
    }
    Write-Log "   [APL] $path" 'Cyan'
    if ($FileName -match '\.msi$') {
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i',"`"$path`"",'/qn','/norestart') -Wait -PassThru
    } else {
        $p = Start-Process -FilePath $path -ArgumentList @('/S','/silent','/quiet','/norestart') -Wait -PassThru
    }
    $rc = $p.ExitCode
    switch ($rc) {
        0    { Write-Log "   [OK] установлено" 'Green'; return @{ Status='ok'; Code=$rc } }
        3010 { Write-Log "   [OK] установлено (нужна перезагрузка)" 'Green'; return @{ Status='ok'; Code=$rc } }
        1641 { Write-Log "   [OK] установлено (перезагрузка запущена)" 'Green'; return @{ Status='ok'; Code=$rc } }
        default {
            Write-Log "   [ОШИБКА] код $rc" 'Red'
            return @{ Status='fail'; Code=$rc }
        }
    }
}

function Install-ByUrl {
    param([string]$Url, [string]$Name)
    if (-not $Url) { Write-Log "   [ОШИБКА] пустой URL" 'Red'; return @{ Status='fail'; Code=-1 } }
    $fileName = [IO.Path]::GetFileName(([Uri]$Url).AbsolutePath)
    if (-not $fileName -or $fileName -notmatch '\.(exe|msi|zip)$') {
        $fileName = ($Name -replace '[^\w]','') + '.exe'
    }
    $target = Join-Path $TmpDir $fileName
    Write-Log "   [Скачивание] $Url" 'Cyan'
    try {
        $oldPref = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $target -UseBasicParsing -TimeoutSec 300
        $ProgressPreference = $oldPref
    } catch {
        Write-Log "   [ОШИБКА] скачать не удалось: $($_.Exception.Message)" 'Red'
        return @{ Status='fail'; Code=-2 }
    }
    Write-Log "   [Установка] $target" 'Cyan'
    if ($fileName -match '\.msi$') {
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i',"`"$target`"",'/qn','/norestart') -Wait -PassThru
    } else {
        $p = Start-Process -FilePath $target -ArgumentList @('/S','/silent','/quiet','/norestart') -Wait -PassThru
    }
    $rc = $p.ExitCode
    switch ($rc) {
        0    { Write-Log "   [OK] установлено" 'Green'; return @{ Status='ok'; Code=$rc } }
        3010 { Write-Log "   [OK] установлено (нужна перезагрузка)" 'Green'; return @{ Status='ok'; Code=$rc } }
        1641 { Write-Log "   [OK] установлено (перезагрузка запущена)" 'Green'; return @{ Status='ok'; Code=$rc } }
        default {
            Write-Log "   [ОШИБКА] код $rc" 'Red'
            return @{ Status='fail'; Code=$rc }
        }
    }
}

# ================================================================
#  ГЛАВНАЯ
# ================================================================
try {
    $Cfg = Read-Ini $CfgFile
    $JsonMode = [bool]$Json

    if (-not (Test-Path -LiteralPath $ListFile)) {
        Write-LogError "Файл office.txt не найден: $ListFile"
        Write-Host '  Что делать:' -ForegroundColor Yellow
        Write-Host '    1. Создай файл office.txt в корне флешки (рядом с Master.cmd)' -ForegroundColor Yellow
        Write-Host '    2. Запусти снова' -ForegroundColor Yellow
        Write-Host ''
        if ($JsonMode) { '{"status":"fail","error":"office.txt not found"}' | Write-Output }
        exit 1
    }

    if (-not (Test-Path -LiteralPath $AplDir)) {
        Write-Log "[!] Папка APL не найдена: $AplDir" 'Yellow'
        Write-Log "    Программы с типом 'apl' будут пропущены" 'Yellow'
    }

    $hasWinget = Test-Winget
    if (-not $hasWinget -and -not $JsonMode) {
        Write-Log '[!] winget не найден - программы winget будут пропущены' 'Yellow'
        Write-Log '    Windows 10: поставь App Installer из Microsoft Store' 'Yellow'
        Write-Log '    Windows 11: должен быть из коробки' 'Yellow'
    }

    $items = @()
    foreach ($raw in Get-Content -LiteralPath $ListFile -Encoding UTF8) {
        $line = $raw.Trim()
        if (-not $line -or $line -match '^[#;]') { continue }
        $c = @($line -split '\|' | ForEach-Object { $_.Trim() })
        while ($c.Count -lt 4) { $c += '' }
        if (-not $c[0]) { continue }
        $items += [pscustomobject]@{
            Name = $c[0]; Source = $c[1]; Type = $c[2].ToLower(); CheckPath = $c[3]
        }
    }

    if ($items.Count -eq 0) {
        Write-LogError 'В office.txt нет ни одной рабочей строки.'
        Write-Host '  Проверь:' -ForegroundColor Yellow
        Write-Host '    - строки не должны начинаться с #' -ForegroundColor Yellow
        Write-Host '    - должно быть 3-4 колонки через |' -ForegroundColor Yellow
        Write-Host ''
        if ($JsonMode) { '{"status":"fail","error":"office.txt empty"}' | Write-Output }
        exit 1
    }

    if (-not $JsonMode) {
        Write-Log ('=' * 60) 'Cyan'
        Write-Log "ОФИСНЫЕ ПРОГРАММЫ - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'Cyan'
        Write-Log "Компьютер: $env:COMPUTERNAME   Режим: $(if ($Install) { 'УСТАНОВКА' } else { 'проверка' })" 'Cyan'
        Write-Log "В списке: $($items.Count) программ" 'Cyan'
        Write-Log ('=' * 60) 'Cyan'
        Write-Log ''
    }

    $results     = @()
    $installed   = 0
    $alreadyHad  = 0
    $missing     = 0
    $failCount   = 0
    $skipCount   = 0

    foreach ($it in $items) {
        $res = [pscustomobject]@{
            Name = $it.Name; Type = $it.Type; Status = 'skip'; Code = 0; Message = ''
        }

        Write-Log "[$($it.Type.ToUpper())] $($it.Name)" 'White'

        $check = Test-AlreadyInstalled -CheckPath $it.CheckPath -WingetId $it.Source -Type $it.Type
        if ($check.Installed) {
            Write-Log "   [УЖЕ ЕСТЬ] $($check.How)" 'DarkGreen'
            $res.Status = 'already'; $res.Message = $check.How
            $alreadyHad++
            $results += $res
            Write-Log ''
            continue
        }

        if (-not $Install) {
            Write-Log '   [НЕТ] не установлено' 'Yellow'
            $res.Status = 'missing'
            $missing++
            $results += $res
            Write-Log ''
            continue
        }

        if ($it.Type -eq 'winget') {
            if (-not $hasWinget) {
                $res.Status = 'skip'; $res.Message = 'winget not found'; $skipCount++
            } else {
                $r = Install-ByWinget -Id $it.Source -Name $it.Name
                $res.Status = $r.Status; $res.Code = $r.Code
                if ($r.Status -eq 'ok') { $installed++ } else { $failCount++ }
            }
        }
        elseif ($it.Type -eq 'apl') {
            $r = Install-FromApl -FileName $it.Source -Name $it.Name
            $res.Status = $r.Status; $res.Code = $r.Code
            if ($r.Status -eq 'ok') { $installed++ } else { $failCount++ }
        }
        elseif ($it.Type -eq 'url') {
            $r = Install-ByUrl -Url $it.Source -Name $it.Name
            $res.Status = $r.Status; $res.Code = $r.Code
            if ($r.Status -eq 'ok') { $installed++ } else { $failCount++ }
        }
        else {
            Write-Log "   [ПРОПУСК] неизвестный тип: $($it.Type)" 'Yellow'
            $res.Status = 'skip'; $res.Message = 'unknown type'; $skipCount++
        }

        $results += $res
        Write-Log ''
    }

    Write-Log ('=' * 60) 'Cyan'
    Write-Log "ИТОГИ: Уже было=$alreadyHad  Установлено=$installed  Нет=$missing  Ошибок=$failCount  Пропущено=$skipCount" 'Cyan'
    Write-Log ('=' * 60) 'Cyan'

    if (-not $NoNotify -and ($failCount -gt 0) -and (Test-Path -LiteralPath $Notify)) {
        $msg = "Офисные программы: уже было $alreadyHad, установлено $installed, ошибок $failCount"
        $failed = @($results | Where-Object { $_.Status -eq 'fail' } | ForEach-Object { "  * $($_.Name) - код $($_.Code)" })
        $msg += "`n`nНе установлены:`n" + ($failed -join "`n")
        & $Notify -Message $msg
    }

    if ($JsonMode) {
        $json = [pscustomobject]@{
            status    = if ($failCount -gt 0) { 'problems' } else { 'ok' }
            total     = $items.Count
            already   = $alreadyHad
            installed = $installed
            missing   = $missing
            fail      = $failCount
            items     = $results
            log_file  = $LogFile
        } | ConvertTo-Json -Depth 6
        Write-Output $json
    }

    if ($failCount -gt 0) { exit 2 } else { exit 0 }
}
catch {
    Write-LogError "$($_.Exception.Message)"
    Write-Host "  Строка: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Yellow
    Write-Host "  Файл:   $($_.InvocationInfo.PositionMessage)" -ForegroundColor Yellow
    Write-Host ''
    if ($Json) {
        $m = ($_.Exception.Message -replace '"', "'")
        "{`"status`":`"error`",`"message`":`"$m`"}" | Write-Output
    }
    exit 3
}
