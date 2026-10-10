Set-StrictMode -Version Latest

function Get-CcAuditPath {
    [CmdletBinding()]
    param()
    $directory = Join-Path $PSScriptRoot '..\logs'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -Path $directory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    return Join-Path $directory 'audit.jsonl'
}

function Write-CcAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Action,
        [string]$Target = '',
        [ValidateSet('success','failed','requested','info')][string]$Result = 'success',
        [string]$Details = ''
    )
    try {
        $record = [ordered]@{
            timestamp = [DateTime]::UtcNow.ToString('o')
            actor = [Environment]::UserName
            role = [string]$script:CcRole
            pc_id = [string]$script:CcPcId
            action = $Action
            target = $Target
            result = $Result
            details = $Details
        }
        $json = $record | ConvertTo-Json -Compress -Depth 4
        Add-Content -LiteralPath (Get-CcAuditPath) -Value $json -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        try { Write-CcLog ("Audit write failed: {0}" -f $_.Exception.Message) 'ERROR' 'Audit' } catch {}
    }
}

function Get-CcAuditEvents {
    [CmdletBinding()]
    param([ValidateRange(1,100000)][int]$Limit = 1000)
    $path = Get-CcAuditPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    $events = [System.Collections.Generic.List[object]]::new()
    foreach ($line in (Get-Content -LiteralPath $path -Tail $Limit -ErrorAction Stop)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $event = ConvertFrom-Json -InputObject $line -ErrorAction Stop
            $events.Add($event)
        }
        catch {
            try { Write-CcLog 'Skipped malformed audit record.' 'WARN' 'Audit' } catch {}
        }
    }
    return @($events.ToArray() | Sort-Object timestamp -Descending)
}
