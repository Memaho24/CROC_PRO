<#
  Apps.ps1 - установка и обновление программ ПРЯМО ИЗ ИНТЕРНЕТА (без папки APL).
  Список программ - файл apps.txt рядом с Master.cmd.
  Формат строки:  Название | Источник | Тип | Файл-проверка | Ключи тихой установки
    Тип winget : Источник = ID в winget            (например Valve.Steam)
    Тип url    : Источник = прямая ссылка на exe/msi
  Ключи тихой установки - необязательно (по умолчанию /S для exe и /qn /norestart для msi).
  Запуск:  Apps.ps1                    - только проверить
           Apps.ps1 -Install           - проверить и поставить недостающее
           Apps.ps1 -Install -Update   - ещё и обновить уже установленные (winget)
           Apps.ps1 -Update            - только обновить уже установленные (winget)
  ВАЖНО: файл должен быть в кодировке UTF-8 с BOM.
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Update,
    [switch]$NoNotify,
    [string]$List = 'apps.txt'
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Root     = Split-Path -Parent $PSScriptRoot
$ListFile = if ([IO.Path]::IsPathRooted($List)) { $List } else { Join-Path $Root $List }
$LogDir   = Join-Path $Root 'logs'
$LogFile  = Join-Path $LogDir 'apps_log.txt'
$Notify   = Join-Path $PSScriptRoot 'Notify.ps1'
$TmpDir   = Join-Path $env:TEMP 'cybercroc-apps'

if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $TmpDir)) { New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null }
if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 1MB)) {
    Move-Item -LiteralPath $LogFile -Destination "$LogFile.old" -Force
}

function Log([string]$t, [string]$c = 'Gray') {
    Write-Host $t -ForegroundColor $c
    Add-Content -LiteralPath $LogFile -Value $t -Encoding UTF8
}

function Expand-Path([string]$p) {
    if (-not $p) { return '' }
    return [Environment]::ExpandEnvironmentVariables($p.Trim().Trim('"'))
}

function Test-Winget {
    try { $null = & winget --version 2>$null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}

function Test-Have($it) {
    if ($it.Check) {
        $full = Expand-Path $it.Check
        if (Test-Path -LiteralPath $full) { return "файл: $full" }
    }
    if ($it.Type -eq 'winget' -and $it.Source -and $script:HasWinget) {
        try {
            $o = & winget list --id $it.Source --exact --source winget --accept-source-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -and $o -match [regex]::Escape($it.Source)) { return "winget: $($it.Source)" }
        } catch {}
    }
    return ''
}

function Install-Winget($it) {
    Log "   [WINGET] $($it.Source)" 'Cyan'
    foreach ($scope in @('', 'machine', 'user')) {
        $wargs = @('install', '--id', $it.Source, '--exact', '--source', 'winget',
                   '--accept-source-agreements', '--accept-package-agreements', '--silent', '--disable-interactivity')
        if ($scope) { $wargs += @('--scope', $scope) }
        Add-Content -LiteralPath $LogFile -Value "winget $($wargs -join ' ')" -Encoding UTF8
        & winget @wargs 2>&1 | ForEach-Object { Add-Content -LiteralPath $LogFile -Value "$_" -Encoding UTF8 }
        $rc = $LASTEXITCODE
        Add-Content -LiteralPath $LogFile -Value "winget code: $rc" -Encoding UTF8
        if ($rc -eq 0 -or $rc -eq -1978335189 -or $rc -eq -1978335135) { return @{ Ok = $true; Code = $rc } }
    }
    return @{ Ok = $false; Code = -1 }
}

function Update-Winget($it) {
    Log "   [UPDATE] $($it.Source)" 'Cyan'
    $wargs = @('upgrade', '--id', $it.Source, '--exact', '--source', 'winget',
               '--accept-source-agreements', '--accept-package-agreements', '--silent', '--disable-interactivity')
    Add-Content -LiteralPath $LogFile -Value "winget $($wargs -join ' ')" -Encoding UTF8
    & winget @wargs 2>&1 | ForEach-Object { Add-Content -LiteralPath $LogFile -Value "$_" -Encoding UTF8 }
    $rc = $LASTEXITCODE
    Add-Content -LiteralPath $LogFile -Value "winget upgrade code: $rc" -Encoding UTF8
    if ($rc -eq 0) { return 'updated' }
    if ($rc -eq -1978335189) { return 'latest' }   # обновлений нет
    return 'fail'
}

function Install-Url($it) {
    $url = $it.Source
    if (-not $url -or $url -notmatch '^https?://') { Log '   [ОШИБКА] нужна ссылка http(s)' 'Red'; return @{ Ok = $false; Code = -1 } }
    $fn = ''
    try { $fn = [IO.Path]::GetFileName(([Uri]$url).AbsolutePath) } catch {}
    if (-not $fn -or $fn -notmatch '\.(exe|msi)$') { $fn = ($it.Name -replace '[^\w]', '') + '.exe' }
    $target = Join-Path $TmpDir $fn
    Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue

    $downloaded = $false
    for ($try = 1; $try -le 2 -and -not $downloaded; $try++) {
        Log "   [СКАЧИВАНИЕ] $url (попытка $try)" 'Cyan'
        try {
            $old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing -TimeoutSec 600 -Headers @{ 'User-Agent' = 'Mozilla/5.0 CyberCroc' }
            $ProgressPreference = $old
            if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Length -gt 0)) { $downloaded = $true }
        } catch { Log "   [!] $($_.Exception.Message)" 'DarkYellow' }
    }
    if (-not $downloaded) { Log '   [ОШИБКА] скачать не удалось' 'Red'; return @{ Ok = $false; Code = -2 } }

    Log "   [УСТАНОВКА] $fn" 'Cyan'
    if ($fn -match '\.msi$') {
        $a = if ($it.Args) { $it.Args } else { '/qn /norestart' }
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList ("/i `"$target`" $a") -Wait -PassThru
    } else {
        $a = if ($it.Args) { $it.Args } else { '/S' }
        $p = Start-Process -FilePath $target -ArgumentList $a -Wait -PassThru
    }
    $rc = $p.ExitCode
    Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if ($rc -in @(0, 3010, 1641)) { return @{ Ok = $true; Code = $rc } }
    return @{ Ok = $false; Code = $rc }
}

# ================================================================
try {
    if (-not (Test-Path -LiteralPath $ListFile)) {
        Log "[ОШИБКА] Не найден файл со списком программ: $ListFile" 'Red'
        Log '         Создайте apps.txt рядом с Master.cmd (пример смотрите в apps.txt из архива).' 'Yellow'
        exit 1
    }

    $script:HasWinget = Test-Winget
    if (-not $script:HasWinget) { Log '[!] winget не найден - строки типа winget будут пропущены' 'Yellow' }

    $items = @()
    foreach ($raw in Get-Content -LiteralPath $ListFile -Encoding UTF8) {
        $line = $raw.Trim()
        if (-not $line -or $line -match '^[#;]') { continue }
        $c = @($line -split '\|' | ForEach-Object { $_.Trim() })
        while ($c.Count -lt 5) { $c += '' }
        if (-not $c[0]) { continue }
        $items += [pscustomobject]@{ Name = $c[0]; Source = $c[1]; Type = $c[2].ToLower(); Check = $c[3]; Args = $c[4] }
    }
    if ($items.Count -eq 0) { Log '[ОШИБКА] В apps.txt нет ни одной программы' 'Red'; exit 1 }

    $modeTxt = @()
    if ($Install) { $modeTxt += 'УСТАНОВКА' }
    if ($Update)  { $modeTxt += 'ОБНОВЛЕНИЕ' }
    if ($modeTxt.Count -eq 0) { $modeTxt += 'проверка' }

    Log ('=' * 60) 'Cyan'
    Log "ПРОГРАММЫ ИЗ ИНТЕРНЕТА - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 'Cyan'
    Log "Компьютер: $env:COMPUTERNAME   Режим: $($modeTxt -join ' + ')   В списке: $($items.Count)" 'Cyan'
    Log ('=' * 60) 'Cyan'

    $already = 0; $installed = 0; $updated = 0; $missing = 0; $failed = @(); $skipped = 0
    foreach ($it in $items) {
        Log ''
        Log "[$($it.Type.ToUpper())] $($it.Name)" 'White'
        $have = Test-Have $it
        if ($have) {
            Log "   [УЖЕ ЕСТЬ] $have" 'DarkGreen'; $already++
            if ($Update -and $it.Type -eq 'winget' -and $script:HasWinget) {
                switch (Update-Winget $it) {
                    'updated' { Log '   [ОБНОВЛЕНО]' 'Green'; $updated++ }
                    'latest'  { Log '   [АКТУАЛЬНА] обновлений нет' 'DarkGreen' }
                    default   { Log '   [ОШИБКА] обновление не удалось (см. logs\apps_log.txt)' 'Red'; $failed += "$($it.Name) (обновление)" }
                }
            }
            continue
        }
        if (-not $Install) { Log '   [НЕТ] не установлено' 'Yellow'; $missing++; continue }

        $r = $null
        if ($it.Type -eq 'winget') {
            if (-not $script:HasWinget) { Log '   [ПРОПУСК] нет winget' 'Yellow'; $skipped++; continue }
            $r = Install-Winget $it
        } elseif ($it.Type -eq 'url') {
            $r = Install-Url $it
        } else {
            Log "   [ПРОПУСК] неизвестный тип: $($it.Type)" 'Yellow'; $skipped++; continue
        }
        if ($r.Ok) { Log '   [OK] установлено' 'Green'; $installed++ }
        else { Log "   [ОШИБКА] не установилось (код $($r.Code))" 'Red'; $failed += $it.Name }
    }

    Log ''
    Log ('=' * 60) 'Cyan'
    Log "ИТОГИ: уже было=$already  установлено=$installed  обновлено=$updated  нет=$missing  ошибок=$($failed.Count)  пропущено=$skipped" 'Cyan'
    Log ('=' * 60) 'Cyan'

    if (-not $NoNotify -and $failed.Count -gt 0 -and (Test-Path -LiteralPath $Notify)) {
        $msg = "Программы: ошибки ($($failed.Count)):`n" + (($failed | ForEach-Object { "• $_" }) -join "`n")
        & $Notify -Message $msg | Out-Null
    }
    if ($failed.Count -gt 0) { exit 2 } else { exit 0 }
}
catch {
    Log "[ОШИБКА] $($_.Exception.Message)" 'Red'
    exit 3
}
