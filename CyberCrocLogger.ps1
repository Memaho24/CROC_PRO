<# CyberCroc2 unified logger. PowerShell 5.1 compatible. #>
[CmdletBinding()]
param(
    [ValidateSet('init','append','error')][string]$Mode,
    [string]$Text,
    [string]$Action,
    [string]$ErrorText,
    [int]$Code = 0,
    [string[]]$Fix
)

$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root 'logs'
$LogFile = Join-Path $LogDir 'CyberCroc.log'

function Ensure-CcLog {
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
}
function Write-CcRaw([string]$Line) {
    Ensure-CcLog
    Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8
}
function Start-CcLog {
    param([string]$Action = 'Запуск CyberCroc')
    Ensure-CcLog
    Set-Content -LiteralPath $LogFile -Value @(
        '============================================================',
        'CYBERCROC — ЖУРНАЛ ОПЕРАЦИИ',
        '============================================================',
        "Дата:      $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Компьютер: $env:COMPUTERNAME",
        "Версия ОС: $([Environment]::OSVersion.VersionString)",
        '',
        '[НАЧАЛО ОПЕРАЦИИ]',
        "Я делал: $Action",
        ''
    ) -Encoding UTF8
}
function Write-CcLog {
    param([Parameter(Mandatory=$true)][string]$Text,[string]$Level='INFO')
    $prefix = switch ($Level.ToUpper()) {
        'OK' { '[УСПЕХ]' }
        'WARN' { '[ПРЕДУПРЕЖДЕНИЕ]' }
        'ERROR' { '[ОШИБКА]' }
        default { '[ИНФО]' }
    }
    Write-CcRaw "[$(Get-Date -Format 'HH:mm:ss')] $prefix $Text"
}
function Write-CcError {
    param([Parameter(Mandatory=$true)][string]$Action,[Parameter(Mandatory=$true)][string]$ErrorText,[int]$Code=1,[string[]]$Fix)
    if (-not $Fix -or $Fix.Count -eq 0) { $Fix = @('Проверь указанные выше условия.','Повтори операцию.') }
    Write-CcRaw ''
    Write-CcRaw '------------------------------------------------------------'
    Write-CcRaw '[ОШИБКА ОПЕРАЦИИ]'
    Write-CcRaw "Я делал: $Action"
    Write-CcRaw "Произошла ошибка: $ErrorText"
    Write-CcRaw "Код ошибки: $Code"
    Write-CcRaw ''
    Write-CcRaw 'Чтобы это исправить, сделай следующее:'
    $n=1
    foreach ($item in $Fix) { Write-CcRaw "$n. $item"; $n++ }
    Write-CcRaw '------------------------------------------------------------'
}

if ($Mode) {
    switch ($Mode) {
        'init' {
            if ([string]::IsNullOrWhiteSpace($Action)) { $Action = 'Запуск CyberCroc' }
            Start-CcLog -Action $Action
        }
        'append' { if ($null -ne $Text) { Write-CcLog -Text $Text } }
        'error' { Write-CcError -Action $Action -ErrorText $ErrorText -Code $Code -Fix $Fix }
    }
}
