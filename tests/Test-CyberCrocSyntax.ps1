$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'CyberCroc.ps1',
    'tools\Core.ps1',
    'tools\Network.ps1',
    'tools\Accounts.ps1',
    'tools\Updater.ps1',
    'tools\GameCache.ps1',
    'tools\Audit.ps1',
    'version.txt',
    'config.ini'
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf) })
if ($missing.Count) { throw ('Missing required project files: ' + ($missing -join ', ')) }

$parseFailures = New-Object System.Collections.Generic.List[string]
$files = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.ps1' | Where-Object {
    $_.FullName -notmatch '[\\/](\.git|BACKUP|logs|runtime)[\\/]'
})
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($errorItem in @($errors)) {
        $parseFailures.Add(('{0}:{1}:{2}: {3}' -f $file.FullName, $errorItem.Extent.StartLineNumber, $errorItem.Extent.StartColumnNumber, $errorItem.Message))
    }
}
if ($parseFailures.Count) {
    $parseFailures | ForEach-Object { Write-Error $_ }
    throw ("PowerShell syntax validation failed for {0} error(s)." -f $parseFailures.Count)
}

$config = @{}
foreach ($line in (Get-Content -LiteralPath (Join-Path $repoRoot 'config.ini') -Encoding UTF8)) {
    $trimmed = $line.Trim()
    $index = $trimmed.IndexOf('=')
    if ($index -gt 0 -and $trimmed -notmatch '^[#;]') {
        $config[$trimmed.Substring(0, $index).Trim().ToUpperInvariant()] = $trimmed.Substring($index + 1).Trim()
    }
}
if ($config['GITHUB_BRANCH'] -ne 'fix/0.5.1-launcher-updater') { throw 'Expected the current 0.5.1 release branch for updates.' }
if ($config['GITHUB_UPDATE_ENABLED'] -notin @('0','1')) { throw 'GITHUB_UPDATE_ENABLED must be 0 or 1.' }

Write-Host ('PowerShell syntax passed for {0} scripts.' -f $files.Count)
Write-Host 'Required files and updater configuration checks passed.'
