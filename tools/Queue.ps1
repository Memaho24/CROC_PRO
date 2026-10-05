<# CyberCroc persistent offline queue. #>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')

$script:CcQueueDir = Join-Path $script:CcRoot 'data'
$script:CcQueueFile = Join-Path $script:CcQueueDir 'queue.json'
if ($null -eq $script:CcQueueMutex) { $script:CcQueueMutex = New-Object System.Threading.Mutex($false, 'CyberCroc.Queue') }

function Initialize-CcQueue {
    try {
        if (-not (Test-Path -LiteralPath $script:CcQueueDir)) { New-Item -ItemType Directory -Path $script:CcQueueDir -Force | Out-Null }
        if (-not (Test-Path -LiteralPath $script:CcQueueFile)) { Write-CcJsonAtomic -Path $script:CcQueueFile -Object @() | Out-Null }
    } catch { Write-CcError -FunctionName 'Initialize-CcQueue' -Exception $_.Exception }
}
function Get-CcQueueItems {
    Initialize-CcQueue
    try {
        $raw = Get-Content -LiteralPath $script:CcQueueFile -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $x = $raw | ConvertFrom-Json
        return @($x)
    } catch { Write-CcError -FunctionName 'Get-CcQueueItems' -Exception $_.Exception; return @() }
}
function Save-CcQueueItems([object[]]$Items) {
    $taken = $false
    try {
        $taken = $script:CcQueueMutex.WaitOne(3000)
        if (-not $taken) { throw 'Queue is busy.' }
        Write-CcJsonAtomic -Path $script:CcQueueFile -Object @($Items) | Out-Null
        return $true
    } catch { Write-CcError -FunctionName 'Save-CcQueueItems' -Exception $_.Exception; return $false }
    finally { if ($taken) { $script:CcQueueMutex.ReleaseMutex() | Out-Null } }
}
function Enqueue-CcOperation {
    param([Parameter(Mandatory=$true)][string]$Type,[Parameter(Mandatory=$true)][object]$Payload,[string]$ReferenceId='')
    try {
        $items=@(Get-CcQueueItems)
        $item=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Type=$Type;ReferenceId=$ReferenceId;CreatedUtc=(Get-Date).ToUniversalTime().ToString('o');Attempts=0;LastError='';Payload=$Payload}
        $items += $item
        if (-not (Save-CcQueueItems $items)) { throw 'Cannot persist offline queue.' }
        Write-CcLog "Queued operation: $Type ref=$ReferenceId" 'WARN' 'Enqueue-CcOperation'
        return $item
    } catch { Write-CcError -FunctionName 'Enqueue-CcOperation' -Exception $_.Exception; return $null }
}
function Complete-CcQueuedOperation([string]$Type,[string]$ReferenceId) {
    try {
        $items=@(Get-CcQueueItems)
        $new=@($items|Where-Object{!( [string]::Equals([string]$_.Type,$Type,[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$_.ReferenceId,$ReferenceId,[StringComparison]::OrdinalIgnoreCase) )})
        if($new.Count -ne $items.Count){Save-CcQueueItems $new|Out-Null;Write-CcLog "Queued operation completed: $Type ref=$ReferenceId" 'OK' 'Complete-CcQueuedOperation'}
        return $true
    } catch { Write-CcError -FunctionName 'Complete-CcQueuedOperation' -Exception $_.Exception; return $false }
}
function Touch-CcQueueFailure([string]$Id,[string]$ErrorText) {
    try {
        $items=@(Get-CcQueueItems);$item=$items|Where-Object Id -eq $Id|Select-Object -First 1
        if($item){$item.Attempts=[int]$item.Attempts+1;$item.LastError=($ErrorText -replace '[\r\n]+',' ');Save-CcQueueItems $items|Out-Null}
    } catch { Write-CcError -FunctionName 'Touch-CcQueueFailure' -Exception $_.Exception }
}
Initialize-CcQueue
