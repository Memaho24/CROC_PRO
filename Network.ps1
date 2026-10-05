<#
CyberCroc Network - PowerShell 5.1.
Неблокирующий UDP bus для заказов, вызовов, beacon и команд.
Секреты никогда не отправляются по сети и не пишутся в логи.
#>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')

if ($null -eq $script:CcNetworkState) {
    $script:CcNetworkState = @{ Running = $false; Port = 50505; Udp = $null; Peers = @{} }
}

function Get-CcNetworkConfig {
    try {
        $cfg = Get-CcConfig
        $port = 50505
        try { if ($cfg['DISCOVERY_PORT']) { $port = [int]$cfg['DISCOVERY_PORT'] } } catch {}
        $interval = 10
        try { if ($cfg['BEACON_INTERVAL_SEC']) { $interval = [int]$cfg['BEACON_INTERVAL_SEC'] } } catch {}
        if ($interval -lt 2) { $interval = 2 }
        $address = [string]$cfg['BROADCAST_ADDRESS']
        if ([string]::IsNullOrWhiteSpace($address)) { $address = '255.255.255.255' }
        [pscustomobject]@{ Port = $port; BeaconIntervalSec = $interval; BroadcastAddress = $address }
    } catch {
        Write-CcError -FunctionName 'Get-CcNetworkConfig' -Exception $_.Exception
        [pscustomobject]@{ Port = 50505; BeaconIntervalSec = 10; BroadcastAddress = '255.255.255.255' }
    }
}

function Get-CcNodeIdentity {
    try {
        $cfg = Get-CcConfig
        $pcId = [string]$cfg['PC_ID']
        if ([string]::IsNullOrWhiteSpace($pcId)) { $pcId = [Environment]::MachineName }
        $role = [string]$cfg['ROLE']
        if ($role -notin @('client','admin')) { $role = 'client' }
        $zone = [string]$cfg['PC_ZONE']
        if ([string]::IsNullOrWhiteSpace($zone)) { $zone = 'standard' }
        [pscustomobject]@{
            PcId = $pcId; Role = $role; Zone = $zone
            Version = [string](Get-CcVersionText); Host = [Environment]::MachineName
        }
    } catch {
        [pscustomobject]@{ PcId = [Environment]::MachineName; Role = 'client'; Zone = 'standard'; Version = '0.0.0'; Host = [Environment]::MachineName }
    }
}
function Get-CcVersionText {
    try {
        $f = Join-Path $script:CcRoot 'version.txt'
        if (Test-Path -LiteralPath $f) { return (Get-Content -LiteralPath $f -Raw -ErrorAction Stop).Trim() }
    } catch {}
    return '0.0.0'
}
function Start-CcUdpListener {
    try {
        if ($script:CcNetworkState.Running) { return $true }
        $net = Get-CcNetworkConfig
        $udp = New-Object System.Net.Sockets.UdpClient($net.Port)
        $udp.EnableBroadcast = $true
        $udp.Client.ReceiveTimeout = 1
        $script:CcNetworkState.Port = $net.Port
        $script:CcNetworkState.Udp = $udp
        $script:CcNetworkState.Running = $true
        Write-CcLog "UDP listener ready on port $($net.Port)" 'OK' 'Start-CcUdpListener'
        return $true
    } catch {
        Write-CcError -FunctionName 'Start-CcUdpListener' -Exception $_.Exception
        return $false
    }
}
function Stop-CcUdpListener {
    try {
        $script:CcNetworkState.Running = $false
        if ($script:CcNetworkState.Udp) { $script:CcNetworkState.Udp.Close(); $script:CcNetworkState.Udp.Dispose() }
        $script:CcNetworkState.Udp = $null
    } catch {}
}
function Send-CcUdpMessage {
    param([Parameter(Mandatory=$true)][object]$Message,[string]$Address,[int]$Port=0)
    $client = $null
    try {
        $net = Get-CcNetworkConfig
        if ($Port -le 0) { $Port = $net.Port }
        if ([string]::IsNullOrWhiteSpace($Address)) { $Address = $net.BroadcastAddress }
        $json = if ($Message -is [string]) { [string]$Message } else { $Message | ConvertTo-Json -Depth 12 -Compress }
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        if ($bytes.Length -gt 60000) { throw 'UDP packet exceeds 60 KB.' }
        $client = New-Object System.Net.Sockets.UdpClient
        $client.EnableBroadcast = $true
        [void]$client.Send($bytes,$bytes.Length,$Address,$Port)
        return $true
    } catch {
        Write-CcLog "UDP send failed: $($_.Exception.Message)" 'WARN' 'Send-CcUdpMessage'
        return $false
    } finally { if ($client) { $client.Dispose() } }
}
function Get-CcKnownNodes {
    try {
        $now=(Get-Date).ToUniversalTime()
        $out=@()
        foreach($key in @($script:CcNetworkState.Peers.Keys)) {
            $peer=$script:CcNetworkState.Peers[$key]
            $age=($now-$peer.LastSeenUtc).TotalSeconds
            if($age -le 45){$out+=[pscustomobject]@{PcId=$peer.PcId;Role=$peer.Role;Zone=$peer.Zone;Version=$peer.Version;Host=$peer.Host;Address=$peer.Address;LastSeenUtc=$peer.LastSeenUtc;Online=$true}}
            else{$out+=[pscustomobject]@{PcId=$peer.PcId;Role=$peer.Role;Zone=$peer.Zone;Version=$peer.Version;Host=$peer.Host;Address=$peer.Address;LastSeenUtc=$peer.LastSeenUtc;Online=$false}}
        }
        return @($out|Sort-Object Role,Zone,PcId)
    } catch { Write-CcError -FunctionName 'Get-CcKnownNodes' -Exception $_.Exception; return @() }
}

function Get-CcNetworkMessages {
    $items=@()
    try {
        if (-not $script:CcNetworkState.Running) { Start-CcUdpListener | Out-Null }
        $udp=$script:CcNetworkState.Udp
        if ($null -eq $udp) { return @() }
        while ($udp.Available -gt 0) {
            $remote=New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any,0)
            try { $data=$udp.Receive([ref]$remote) } catch { break }
            if($data.Length -le 0 -or $data.Length -gt 60000){continue}
            $json=[Text.Encoding]::UTF8.GetString($data)
            try {
                $message=$json|ConvertFrom-Json
                if($message.type -eq 'beacon' -and -not [string]::IsNullOrWhiteSpace([string]$message.pc_id)) {
                    $pc=[string]$message.pc_id
                    $hostName=[string]$(if($message.host){$message.host}else{$pc})
                    $script:CcNetworkState.Peers[$pc]=[pscustomobject]@{PcId=$pc;Role=[string]$message.role;Zone=[string]$message.zone;Version=[string]$message.version;Host=$hostName;Address=$remote.Address.ToString();LastSeenUtc=(Get-Date).ToUniversalTime()}
                }
                $items += [pscustomobject]@{ Message=$message; RemoteAddress=$remote.Address.ToString(); RemotePort=$remote.Port; ReceivedUtc=(Get-Date).ToUniversalTime().ToString('o') }
            } catch { Write-CcLog 'Invalid UDP JSON packet ignored.' 'WARN' 'Get-CcNetworkMessages' }
        }
    } catch { Write-CcError -FunctionName 'Get-CcNetworkMessages' -Exception $_.Exception }
    return @($items)
}
function Send-CcBeacon {
    try {
        $id=Get-CcNodeIdentity
        Send-CcUdpMessage ([pscustomobject]@{type='beacon';pc_id=$id.PcId;role=$id.Role;zone=$id.Zone;version=$id.Version;host=$id.Host;client_pc=$id.PcId;timestamp=(Get-Date).ToUniversalTime().ToString('o')}) | Out-Null
    } catch { Write-CcError -FunctionName 'Send-CcBeacon' -Exception $_.Exception }
}
Start-CcUdpListener | Out-Null
