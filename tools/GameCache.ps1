<#
CyberCroc LAN game cache.
Compatible with Windows PowerShell 5.1. Uses a normal SMB share, no dedicated server.
Files are verified by SHA-256 before any client-side copy. Existing target files are replaced
only when content differs; unrelated files are never deleted.
#>
Set-StrictMode -Version 2.0

function Get-CcGameCacheShare {
    [CmdletBinding()]
    param([string]$SharePath = '')
    if ([string]::IsNullOrWhiteSpace($SharePath)) {
        $cfg = Get-CcConfig
        $SharePath = [string]$cfg['GAMES_SHARE']
    }
    if ([string]::IsNullOrWhiteSpace($SharePath)) {
        throw 'Не задан GAMES_SHARE. Укажите общую папку SMB, например \\MAIN-PC\CyberCroc_Games.'
    }
    return $SharePath.TrimEnd('\')
}

function Get-CcGameCacheSlug {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GameName)
    $slug = [regex]::Replace($GameName.Trim().ToLowerInvariant(), '[^a-z0-9а-яё._-]+', '-')
    $slug = $slug.Trim('-','.')
    if ([string]::IsNullOrWhiteSpace($slug)) { throw 'Не удалось сформировать имя игры для кэша.' }
    return $slug
}

function Get-CcGameCacheManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GamePath)
    $root = (Resolve-Path -LiteralPath $GamePath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Не папка: $root" }
    $files = New-Object System.Collections.Generic.List[object]
    $totalBytes = [long]0
    foreach ($file in (Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $relative = $file.FullName.Substring($root.TrimEnd('\').Length).TrimStart('\')
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains('..')) { throw "Недопустимый путь в манифесте: $relative" }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $files.Add([pscustomobject]@{ Path = $relative; Length = [long]$file.Length; Sha256 = $hash })
        $totalBytes += [long]$file.Length
    }
    if ($files.Count -eq 0) { throw 'В выбранной папке не найдено файлов.' }
    return [pscustomobject]@{
        SchemaVersion = 1
        GameName = ''
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        FileCount = $files.Count
        TotalBytes = $totalBytes
        Files = @($files.ToArray() | Sort-Object Path)
    }
}

function Publish-CcGameCache {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$GameName,
        [Parameter(Mandatory)][string]$SourcePath,
        [string]$SharePath = ''
    )
    try {
        if ([string]::IsNullOrWhiteSpace($GameName)) { throw 'Название игры обязательно.' }
        $source = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Папка игры не найдена: $source" }
        $share = Get-CcGameCacheShare -SharePath $SharePath
        if (-not (Test-Path -LiteralPath $share -PathType Container)) { throw "Сетевая папка недоступна: $share. Проверьте права SMB." }
        $slug = Get-CcGameCacheSlug -GameName $GameName
        $cacheRoot = Join-Path (Join-Path $share 'cache') $slug
        $stage = Join-Path (Join-Path $share 'cache') ('.stage-' + [guid]::NewGuid().ToString('N'))
        if (-not $PSCmdlet.ShouldProcess($cacheRoot, "Опубликовать кэш игры $GameName")) { return $false }
        New-Item -ItemType Directory -Path $stage -Force -ErrorAction Stop | Out-Null
        try {
            $manifest = Get-CcGameCacheManifest -GamePath $source
            $manifest.GameName = $GameName
            foreach ($entry in $manifest.Files) {
                $dest = Join-Path $stage $entry.Path
                $parent = Split-Path -Parent $dest
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null }
                Copy-Item -LiteralPath (Join-Path $source $entry.Path) -Destination $dest -Force -ErrorAction Stop
                $copiedHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                if ($copiedHash -ne $entry.Sha256) { throw "Проверка SHA-256 не пройдена: $($entry.Path)" }
            }
            $manifestPath = Join-Path $stage 'manifest.json'
            $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -ErrorAction Stop
            if (Test-Path -LiteralPath $cacheRoot) {
                $backup = $cacheRoot + '.previous-' + (Get-Date -Format 'yyyyMMddHHmmss')
                Move-Item -LiteralPath $cacheRoot -Destination $backup -ErrorAction Stop
            }
            Move-Item -LiteralPath $stage -Destination $cacheRoot -ErrorAction Stop
            Write-CcLog "Game cache published: $GameName ($($manifest.FileCount) files)" 'OK' 'Publish-CcGameCache'
            try { Write-CcAudit -Action 'gamecache.publish' -Target $GameName -Result 'success' -Details ("files={0}; bytes={1}" -f $manifest.FileCount,$manifest.TotalBytes) } catch {}
            return [pscustomobject]@{ Success = $true; GameName = $GameName; FileCount = $manifest.FileCount; TotalBytes = $manifest.TotalBytes; Path = $cacheRoot }
        } finally {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-CcError -FunctionName 'Publish-CcGameCache' -Exception $_.Exception
        try { Write-CcAudit -Action 'gamecache.publish' -Target $GameName -Result 'failed' -Details $_.Exception.Message } catch {}
        throw
    }
}

function Sync-CcGameCache {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)][string]$GameName,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string]$SharePath = ''
    )
    try {
        $share = Get-CcGameCacheShare -SharePath $SharePath
        $cacheRoot = Join-Path (Join-Path $share 'cache') (Get-CcGameCacheSlug -GameName $GameName)
        $manifestPath = Join-Path $cacheRoot 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Кэш игры не опубликован или недоступен: $manifestPath" }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([int]$manifest.SchemaVersion -ne 1 -or [string]$manifest.GameName -ne $GameName) { throw 'Манифест кэша не соответствует игре или имеет неподдерживаемую версию.' }
        $destRoot = $DestinationPath.TrimEnd('\')
        if ([string]::IsNullOrWhiteSpace($destRoot)) { throw 'Не указана папка установки на этом ПК.' }
        if (-not (Test-Path -LiteralPath $destRoot -PathType Container)) { New-Item -ItemType Directory -Path $destRoot -Force -ErrorAction Stop | Out-Null }
        $destRoot = (Resolve-Path -LiteralPath $destRoot -ErrorAction Stop).Path
        $needBytes = [long]0
        foreach ($entry in $manifest.Files) {
            $relative = [string]$entry.Path
            if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or $relative.Contains(':')) {
                throw "Небезопасный путь в манифесте: $relative"
            }
            $sourceFile = Join-Path $cacheRoot $relative
            if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "В кэше отсутствует файл: $relative" }
            $actual = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            if ($actual -ne [string]$entry.Sha256) { throw "Кэш повреждён, SHA-256 не совпадает: $relative" }
            $targetFile = Join-Path $destRoot $relative
            $existingHash = ''
            if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
                $existingHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            }
            if ($existingHash -ne $actual) { $needBytes += [long]$entry.Length }
        }
        $driveRoot = [IO.Path]::GetPathRoot($destRoot)
        if ($driveRoot -and $driveRoot -match '^[A-Za-z]:\\$') {
            $drive = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $driveRoot.Substring(0,2)) -ErrorAction SilentlyContinue
            if ($drive -and [long]$drive.FreeSpace -lt $needBytes) { throw ("Недостаточно места: нужно примерно {0:N1} ГБ, доступно {1:N1} ГБ." -f ($needBytes/1GB),($drive.FreeSpace/1GB)) }
        }
        if (-not $PSCmdlet.ShouldProcess($destRoot, "Синхронизировать $($manifest.FileCount) файлов игры $GameName")) { return $false }
        $copied = 0
        foreach ($entry in $manifest.Files) {
            $relative = [string]$entry.Path
            $sourceFile = Join-Path $cacheRoot $relative
            $targetFile = Join-Path $destRoot $relative
            $targetParent = Split-Path -Parent $targetFile
            if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) { New-Item -ItemType Directory -Path $targetParent -Force -ErrorAction Stop | Out-Null }
            $needsCopy = $true
            if (Test-Path -LiteralPath $targetFile -PathType Leaf) {
                $targetHash = (Get-FileHash -LiteralPath $targetFile -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                if ($targetHash -eq [string]$entry.Sha256) { $needsCopy = $false }
            }
            if ($needsCopy) {
                $tempTarget = $targetFile + '.cybercroc-tmp'
                Copy-Item -LiteralPath $sourceFile -Destination $tempTarget -Force -ErrorAction Stop
                $tempHash = (Get-FileHash -LiteralPath $tempTarget -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                if ($tempHash -ne [string]$entry.Sha256) { Remove-Item -LiteralPath $tempTarget -Force -ErrorAction SilentlyContinue; throw "Копирование не прошло проверку: $relative" }
                Move-Item -LiteralPath $tempTarget -Destination $targetFile -Force -ErrorAction Stop
                $copied++
            }
        }
        Write-CcLog "Game cache synced: $GameName; changed=$copied" 'OK' 'Sync-CcGameCache'
        try { Write-CcAudit -Action 'gamecache.sync' -Target $GameName -Result 'success' -Details ("changed={0}; destination={1}" -f $copied,$destRoot) } catch {}
        return [pscustomobject]@{ Success = $true; GameName = $GameName; FileCount = [int]$manifest.FileCount; ChangedFiles = $copied; Destination = $destRoot; TotalBytes = [long]$manifest.TotalBytes }
    } catch {
        Write-CcError -FunctionName 'Sync-CcGameCache' -Exception $_.Exception
        try { Write-CcAudit -Action 'gamecache.sync' -Target $GameName -Result 'failed' -Details $_.Exception.Message } catch {}
        throw
    }
}
