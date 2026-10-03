[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSScriptRoot
$List = Join-Path $Root 'games.txt'
$LogDir = Join-Path $Root 'logs'
$Log = Join-Path $LogDir 'CyberCroc.log'
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-Status {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    Write-Host $Text -ForegroundColor $Color
    try { Add-Content -LiteralPath $Log -Value $Text -Encoding UTF8 } catch {}
}

if (-not (Test-Path -LiteralPath $List)) {
    Write-Status '[ERROR] games.txt was not found.' Red
    Write-Status ("Expected: {0}" -f $List) Red
    exit 1
}

function Normalize-PathValue {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $p = [Environment]::ExpandEnvironmentVariables($Path).Trim().Trim('"')
        $p = $p -replace '\\\\','\'
        if (-not (Test-Path -LiteralPath $p)) { return $null }
        return [System.IO.Path]::GetFullPath($p).TrimEnd('\')
    } catch { return $null }
}

function Add-UniquePath {
    param([System.Collections.ArrayList]$List, [string]$Path)
    $p = Normalize-PathValue $Path
    if (-not $p) { return }
    foreach ($existing in $List) {
        if ([string]::Equals([string]$existing, $p, [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    [void]$List.Add($p)
}

function Get-InstalledApplications {
    $result = @()
    foreach ($path in @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try { $result += Get-ItemProperty -Path $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } } catch {}
    }
    return @($result)
}
$InstalledApps = Get-InstalledApplications

function Get-RegistrySteamValues {
    $values = @()
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
            $base = $null
            $key = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                $key = $base.OpenSubKey('SOFTWARE\Valve\Steam')
                if ($key) {
                    foreach ($name in @('InstallPath','SteamPath','SteamRoot','SteamExe','BaseInstallFolder_1','BaseInstallFolder_2','BaseInstallFolder_3','BaseInstallFolder_4','BaseInstallFolder_5')) {
                        $v = [string]$key.GetValue($name,$null)
                        if ($v) { $values += $v }
                    }
                }
            } catch {} finally {
                if ($key) { try { $key.Dispose() } catch {} }
                if ($base) { try { $base.Dispose() } catch {} }
            }
        }
    }
    return @($values)
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.ArrayList
    foreach ($value in (Get-RegistrySteamValues)) {
        $v = $value
        if ($v -like '*.exe') { $v = Split-Path -Parent $v }
        Add-UniquePath -List $roots -Path $v
    }

    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $pf = [Environment]::GetEnvironmentVariable('ProgramFiles')
    $known = @(
        'C:\Program Files (x86)\Steam',
        'C:\Program Files\Steam',
        'C:\Steam','D:\Steam','E:\Steam','F:\Steam','G:\Steam','H:\Steam','I:\Steam','J:\Steam',
        'K:\Steam','L:\Steam','M:\Steam','N:\Steam','O:\Steam','P:\Steam','Q:\Steam','R:\Steam',
        'S:\Steam','T:\Steam','U:\Steam','V:\Steam','W:\Steam','X:\Steam','Y:\Steam','Z:\Steam'
    )
    if ($pf86) { $known += (Join-Path $pf86 'Steam') }
    if ($pf) { $known += (Join-Path $pf 'Steam') }
    foreach ($candidate in $known) { Add-UniquePath -List $roots -Path $candidate }

    try {
        Get-CimInstance Win32_Process -Filter "Name='steam.exe'" | ForEach-Object {
            if ($_.ExecutablePath) { Add-UniquePath -List $roots -Path (Split-Path -Parent $_.ExecutablePath) }
        }
    } catch {}
    try {
        foreach ($p in (Get-Process -Name steam -ErrorAction SilentlyContinue)) {
            try { Add-UniquePath -List $roots -Path (Split-Path -Parent $p.Path) } catch {}
            try { Add-UniquePath -List $roots -Path (Split-Path -Parent $p.MainModule.FileName) } catch {}
        }
    } catch {}
    return @($roots)
}

function Get-SteamLibraryData {
    param([string]$SteamRoot)
    $result = @()
    $vdfFiles = @(
        (Join-Path $SteamRoot 'steamapps\libraryfolders.vdf'),
        (Join-Path $SteamRoot 'config\libraryfolders.vdf')
    )
    foreach ($file in $vdfFiles) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        try {
            $lines = Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop
            foreach ($line in $lines) {
                $m = [regex]::Match($line,'^\s*"path"\s*"(?<path>(?:[^"\\]|\\.)*)"')
                if ($m.Success) {
                    $path = $m.Groups['path'].Value -replace '\\\\','\'
                    $normalized = Normalize-PathValue $path
                    if ($normalized) { $result += [pscustomobject]@{ Path=$normalized; Source=$file } }
                }
            }
        } catch {}
    }
    return @($result)
}

$SteamRoots = @(Get-SteamRoots)
$SteamLibrariesList = New-Object System.Collections.ArrayList
foreach ($rootPath in $SteamRoots) {
    Add-UniquePath -List $SteamLibrariesList -Path $rootPath
    foreach ($data in (Get-SteamLibraryData -SteamRoot $rootPath)) {
        Add-UniquePath -List $SteamLibrariesList -Path $data.Path
    }
}

function Get-FileSystemRoots {
    $roots = New-Object System.Collections.ArrayList
    try { Get-PSDrive -PSProvider FileSystem | ForEach-Object { Add-UniquePath -List $roots -Path $_.Root } } catch {}
    foreach ($letter in 'C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z') {
        Add-UniquePath -List $roots -Path ($letter + ':\')
    }
    return @($roots)
}

# Targeted discovery only. No recursive scan of complete drives.
foreach ($driveRoot in (Get-FileSystemRoots)) {
    foreach ($candidate in @(
        (Join-Path $driveRoot 'Steam'),
        (Join-Path $driveRoot 'SteamLibrary'),
        (Join-Path $driveRoot 'Games\Steam'),
        (Join-Path $driveRoot 'Games\SteamLibrary'),
        (Join-Path $driveRoot 'Program Files\Steam'),
        (Join-Path $driveRoot 'Program Files (x86)\Steam')
    )) {
        if (Test-Path -LiteralPath $candidate) {
            foreach ($data in (Get-SteamLibraryData -SteamRoot $candidate)) {
                Add-UniquePath -List $SteamLibrariesList -Path $data.Path
            }
            Add-UniquePath -List $SteamLibrariesList -Path $candidate
        }
    }
}
$SteamLibraries = @($SteamLibrariesList)

function Read-SteamManifestStatus {
    param([string]$Manifest)
    if (-not (Test-Path -LiteralPath $Manifest)) { return $null }
    try { $text = Get-Content -LiteralPath $Manifest -Raw -ErrorAction Stop } catch { return 'INSTALLED - MANIFEST UNREADABLE' }
    $build = ''
    $bytes = [int64]0
    $state = 0
    if ($text -match '"buildid"\s+"([^"]+)"') { $build = $Matches[1] }
    if ($text -match '"BytesToDownload"\s+"(\d+)"') { $bytes = [int64]$Matches[1] }
    if ($text -match '"StateFlags"\s+"(\d+)"') { $state = [int]$Matches[1] }
    if ($bytes -gt 0 -or (($state -band 2) -ne 0)) { return "INSTALLED - UPDATE PENDING (build: $build)" }
    return "INSTALLED - CURRENT (build: $build)"
}

function Get-CommonGamePath {
    param([string]$AppId, [string]$Name)
    $folders = @{}
    $folders['730'] = @('Counter-Strike Global Offensive','Counter-Strike 2')
    $folders['570'] = @('dota 2 beta','Dota 2')
    $folders['578080'] = @('PUBG','PUBG: BATTLEGROUNDS')
    if ($folders.ContainsKey($AppId)) {
        foreach ($library in $SteamLibraries) {
            foreach ($folder in $folders[$AppId]) {
                $candidate = Join-Path $library ('steamapps\common\' + $folder)
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
        }
    }
    return $null
}

function Get-SteamStatus {
    param([string]$AppId, [string]$PathCheck, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($AppId)) { return 'NOT CONFIRMED - APPID MISSING' }
    foreach ($library in $SteamLibraries) {
        foreach ($manifest in @(
            (Join-Path $library "steamapps\appmanifest_$AppId.acf"),
            (Join-Path $library "appmanifest_$AppId.acf")
        )) {
            $status = Read-SteamManifestStatus -Manifest $manifest
            if ($status) { return $status }
        }
    }
    $common = Get-CommonGamePath -AppId $AppId -Name $Name
    if ($common) { return 'INSTALLED - PATH FOUND (MANIFEST MISSING)' }
    if ($PathCheck) {
        $expanded = [Environment]::ExpandEnvironmentVariables($PathCheck)
        if (Test-Path -LiteralPath $expanded) { return 'INSTALLED - PATH FOUND (MANIFEST MISSING)' }
    }
    if ($SteamLibraries.Count -eq 0) { return 'NOT CONFIRMED - STEAM LIBRARY NOT FOUND' }
    return 'NOT INSTALLED'
}

function Get-NonSteamStatus {
    param([string]$Name, [string]$PathCheck, [string]$Launcher)
    foreach ($path in @($PathCheck,$Launcher)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $expanded = [Environment]::ExpandEnvironmentVariables($path)
            if (Test-Path -LiteralPath $expanded) { return 'INSTALLED - PATH FOUND' }
        }
    }
    $match = $InstalledApps | Where-Object { $_.DisplayName -and ($_.DisplayName -like "*$Name*") } | Select-Object -First 1
    if ($match) { return "INSTALLED - REGISTRY ($($match.DisplayName))" }
    if ($Name -eq 'League of Legends') {
        foreach ($drive in 'C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z') {
            $candidate = $drive + ':\Riot Games\League of Legends\LeagueClient.exe'
            if (Test-Path -LiteralPath $candidate) { return 'INSTALLED - PATH FOUND' }
        }
    }
    return 'NOT CONFIRMED - LAUNCHER CHECK REQUIRED'
}

$rows = @()
foreach ($rawLine in (Get-Content -LiteralPath $List -Encoding UTF8)) {
    $line = $rawLine.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
    $parts = $line -split '\|',6
    if ($parts.Count -ge 6) {
        $name=$parts[0].Trim(); $pathCheck=$parts[1].Trim(); $platform=$parts[2].Trim().ToLowerInvariant(); $launcher=$parts[3].Trim(); $appId=$parts[4].Trim()
    } elseif ($parts.Count -ge 3) {
        $platform=$parts[0].Trim().ToLowerInvariant(); $appId=$parts[1].Trim(); $name=$parts[2].Trim(); $pathCheck=''; $launcher=''
    } else {
        Write-Status ("[SKIP] Invalid games.txt line: {0}" -f $line) Yellow
        continue
    }
    if ($platform -eq 'steam') { $status=Get-SteamStatus -AppId $appId -PathCheck $pathCheck -Name $name } else { $status=Get-NonSteamStatus -Name $name -PathCheck $pathCheck -Launcher $launcher }
    $rows += [pscustomobject]@{Platform=$platform.ToUpperInvariant();Name=$name;Status=$status}
}

Write-Status ''
Write-Status '============================================================' Cyan
Write-Status 'CYBERCROC GAME CHECK - RESULT' Cyan
Write-Status '============================================================' Cyan
Write-Status ("[STEAM DIAGNOSTIC] Roots detected: {0}; Libraries detected: {1}" -f $SteamRoots.Count,$SteamLibraries.Count) DarkCyan
foreach ($r in $SteamRoots) { Write-Status ("  Root: {0}" -f $r) DarkCyan }
foreach ($l in $SteamLibraries) { Write-Status ("  Library: {0}" -f $l) DarkCyan }
foreach ($row in $rows) {
    $color=[ConsoleColor]::Yellow
    if ($row.Status -like 'INSTALLED*') { $color=[ConsoleColor]::Green }
    elseif ($row.Status -like '*UPDATE PENDING*') { $color=[ConsoleColor]::Yellow }
    elseif ($row.Status -like 'NOT INSTALLED*') { $color=[ConsoleColor]::Red }
    Write-Status ("[{0}] {1} - {2}" -f $row.Platform,$row.Name,$row.Status) $color
}
Write-Status '============================================================' Cyan
exit 0