\xef\xbb\xbf<#
  Diagnostics.ps1 - диагностика ПК: SMART, температура, Event Log, SFC, DISM.
  Запуск:  Diagnostics.ps1            быстрая проверка (sfc /verifyonly, dism /CheckHealth)
           Diagnostics.ps1 -Full      + dism /ScanHealth
           Diagnostics.ps1 -Repair    + sfc /scannow и dism /RestoreHealth
  Код выхода: 0 - всё хорошо, 2 - есть проблемы, 1 - нет прав.
  ВАЖНО: файл должен быть в кодировке UTF-8 с BOM.
#>
[CmdletBinding()]
param([switch]$Full, [switch]$Repair, [switch]$NoNotify)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$Root    = Split-Path -Parent $PSScriptRoot
$LogDir  = Join-Path $Root 'logs'
$LogFile = Join-Path $LogDir 'diag_log.txt'
$Notify  = Join-Path $PSScriptRoot 'Notify.ps1'
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if ((Test-Path -LiteralPath $LogFile) -and ((Get-Item -LiteralPath $LogFile).Length -gt 1MB)) {
    Move-Item -LiteralPath $LogFile -Destination "$LogFile.old" -Force
}

function Log([string]$t, [string]$c = 'Gray') {
    Write-Host $t -ForegroundColor $c
    Add-Content -LiteralPath $LogFile -Value $t -Encoding UTF8
}

$script:problems = New-Object System.Collections.Generic.List[string]
function Bad([string]$m) { $script:problems.Add($m); Log "   [ПРОБЛЕМА] $m" 'Red' }
function Good([string]$m) { Log "   [OK] $m" 'Green' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Log '[ОШИБКА] Нужны права администратора.' 'Red'; exit 1 }

Log ('=' * 60) 'Cyan'
Log "ДИАГНОСТИКА - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  ПК: $env:COMPUTERNAME" 'Cyan'
Log ('=' * 60) 'Cyan'

# ---------------------------------------------------------------- 1. SMART
Log ''
Log '[1/5] Диски (SMART)' 'Cyan'
try {
    $disks = @(Get-PhysicalDisk -ErrorAction Stop)
    foreach ($d in $disks) {
        Log ("   {0} | {1} | {2} ГБ | health={3} | {4}" -f $d.FriendlyName, $d.MediaType, [int]($d.Size / 1GB), $d.HealthStatus, ($d.OperationalStatus -join ','))
        if ("$($d.HealthStatus)" -ne 'Healthy') { Bad "Диск $($d.FriendlyName): состояние $($d.HealthStatus)" }
        $rc = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        if ($rc) {
            if ($null -ne $rc.Wear -and $rc.Wear -ge 90) { Bad "Диск $($d.FriendlyName): износ SSD $($rc.Wear)%" }
            if ($rc.Temperature -and $rc.Temperature -ge 60) { Bad "Диск $($d.FriendlyName): температура $($rc.Temperature) °C" }
            if ($rc.ReadErrorsUncorrected -and $rc.ReadErrorsUncorrected -gt 0) { Bad "Диск $($d.FriendlyName): неисправимых ошибок чтения $($rc.ReadErrorsUncorrected)" }
            if ($rc.PowerOnHours) { Log "      наработка: $($rc.PowerOnHours) ч, температура: $($rc.Temperature) °C" 'DarkGray' }
        }
    }
} catch { Log "   [!] Get-PhysicalDisk: $($_.Exception.Message)" 'Yellow' }
try {
    $pf = @(Get-CimInstance -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop)
    foreach ($p in $pf) { if ($p.PredictFailure) { Bad "SMART прогнозирует отказ диска: $($p.InstanceName)" } }
    if (-not ($pf | Where-Object { $_.PredictFailure })) { Good 'SMART: прогноз отказа отсутствует' }
} catch { Log '   [i] SMART PredictFailure недоступен (NVMe/RAID)' 'DarkGray' }

# ---------------------------------------------------------------- 2. Температура
Log ''
Log '[2/5] Температура' 'Cyan'
try {
    $tz = @(Get-CimInstance -Namespace 'root\wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)
    foreach ($z in $tz) {
        $c = [math]::Round($z.CurrentTemperature / 10 - 273.15, 1)
        Log "   Зона $($z.InstanceName): $c °C"
        if ($c -ge 85) { Bad "Перегрев: $c °C ($($z.InstanceName))" }
    }
} catch { Log '   [i] Датчики температуры через WMI недоступны на этом ПК' 'DarkGray' }

# ---------------------------------------------------------------- 3. Event Log
Log ''
Log '[3/5] Event Log (System, 7 дней)' 'Cyan'
$prov = @('disk', 'Ntfs', 'volmgr', 'stornvme', 'storahci', 'Microsoft-Windows-WHEA-Logger',
          'Microsoft-Windows-Kernel-Power', 'BugCheck', 'Display', 'nvlddmkm', 'atikmpag', 'amdkmdag')
$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } -ErrorAction SilentlyContinue)
$hits = @($ev | Where-Object { $_.ProviderName -in $prov -or $_.LevelDisplayName -eq 'Critical' })
if ($hits.Count -eq 0) {
    Good "Критических ошибок диска/питания/GPU нет (всего error+critical: $($ev.Count))"
} else {
    $grp = $hits | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 10
    foreach ($g in $grp) {
        $sample = ($g.Group | Select-Object -First 1).Message
        if ($sample) { $sample = ($sample -split "`r?`n")[0] }
        Bad ("{0} x{1}: {2}" -f $g.Name, $g.Count, $sample)
    }
}

# ---------------------------------------------------------------- 4. SFC
Log ''
Log "[4/5] SFC ($(if ($Repair) { '/scannow' } else { '/verifyonly' })), это может занять несколько минут..." 'Cyan'
$mode = if ($Repair) { '/scannow' } else { '/verifyonly' }
$o = ((& sfc.exe $mode 2>&1 | Out-String) -replace "`0", '')
Add-Content -LiteralPath $LogFile -Value $o -Encoding UTF8
if     ($o -match 'не обнаружила нарушений|did not find any integrity violations') { Good 'Системные файлы целы' }
elseif ($o -match 'успешно их восстановила|successfully repaired')                { Good 'Повреждённые файлы восстановлены (SFC)' }
elseif ($o -match 'не может восстановить|unable to fix')                          { Bad 'SFC: есть повреждённые файлы, которые не удалось восстановить (см. CBS.log)' }
elseif ($o -match 'обнаружила|found integrity violations|found corrupt')          { Bad 'SFC: найдены нарушения целостности (запустите с -Repair)' }
else                                                                               { Log '   [?] SFC: результат не распознан, см. diag_log.txt' 'Yellow' }

# ---------------------------------------------------------------- 5. DISM
Log ''
$sub = if ($Full -or $Repair) { '/ScanHealth' } else { '/CheckHealth' }
Log "[5/5] DISM $sub" 'Cyan'
$o = ((& dism.exe /Online /Cleanup-Image $sub 2>&1 | Out-String) -replace "`0", '')
$rc = $LASTEXITCODE
Add-Content -LiteralPath $LogFile -Value $o -Encoding UTF8
if ($o -match 'не обнаружено|No component store corruption detected') {
    Good 'Хранилище компонентов в порядке'
} else {
    Bad "DISM: хранилище компонентов повреждено или проверка не прошла (код $rc)"
    if ($Repair) {
        Log '   Запускаю DISM /RestoreHealth...' 'Cyan'
        $o2 = ((& dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String) -replace "`0", '')
        Add-Content -LiteralPath $LogFile -Value $o2 -Encoding UTF8
        if ($LASTEXITCODE -eq 0) { Good 'DISM RestoreHealth выполнен' } else { Bad "DISM RestoreHealth не удался (код $LASTEXITCODE)" }
    }
}

# ---------------------------------------------------------------- итог
Log ''
Log ('=' * 60) 'Cyan'
Log "ИТОГ: проблем = $($script:problems.Count)" $(if ($script:problems.Count -gt 0) { 'Red' } else { 'Green' })
Log ('=' * 60) 'Cyan'

if (-not $NoNotify -and $script:problems.Count -gt 0 -and (Test-Path -LiteralPath $Notify)) {
    $msg = "Диагностика: проблем $($script:problems.Count)`n" + (($script:problems | ForEach-Object { "• $_" }) -join "`n")
    & $Notify -Message $msg | Out-Null
}
if ($script:problems.Count -gt 0) { exit 2 } else { exit 0 }
