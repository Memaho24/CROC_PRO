<#
CyberCroc fleet configuration helpers.
Common settings are distributed over SMB while ROLE, PC_ID and DPAPI secrets stay local.
#>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'Network.ps1')

function Get-CcFleetTargets {
    try { return @(Get-CcKnownNodes | Where-Object { $_.Role -eq 'client' -and $_.Online -and $_.Host }) }
    catch { Write-CcError -FunctionName 'Get-CcFleetTargets' -Exception $_.Exception; return @() }
}
function Save-CcFleetTemplate([string]$Path='') {
    try {
        $cfg=Get-CcConfig
        if([string]::IsNullOrWhiteSpace($Path)){$Path=Join-Path $script:CcRoot 'config.template.ini'}
        $copy=@{};foreach($k in $cfg.Keys){if($k -notin @('ADMIN_PASSWORD','ADMIN_PASSWORD_PROTECTED','PC_ID','GOOGLE_SERVICE_ACCOUNT_JSON')){$copy[$k]=$cfg[$k]}}
        $lines=@();foreach($key in $copy.Keys|Sort-Object){$lines+=('{0}={1}' -f $key,$copy[$key])};Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
        return (Test-Path -LiteralPath $Path)
    } catch { Write-CcError -FunctionName 'Save-CcFleetTemplate' -Exception $_.Exception; return $false }
}
function Sync-CcProductsCacheToPc([string]$HostName) {
    try {
        $source=Join-Path $script:CcRoot 'data\products-cache.json'
        if(-not(Test-Path -LiteralPath $source)){return $true}
        $remoteData="\\$HostName\C$\CyberCroc\data"
        if(-not(Test-Path -LiteralPath $remoteData)){New-Item -ItemType Directory -Path $remoteData -Force|Out-Null}
        Copy-Item -LiteralPath $source -Destination (Join-Path $remoteData 'products-cache.json') -Force -ErrorAction Stop
        return $true
    } catch { Write-CcError -FunctionName 'Sync-CcProductsCacheToPc' -Exception $_.Exception; return $false }
}

function Sync-CcConfigToPc([string]$HostName,[string]$TemplatePath='') {
    try {
        if([string]::IsNullOrWhiteSpace($HostName)){throw 'Имя ПК не задано.'}
        if([string]::IsNullOrWhiteSpace($TemplatePath)){$TemplatePath=Join-Path $script:CcRoot 'config.template.ini'}
        if(-not(Test-Path -LiteralPath $TemplatePath)){if(-not(Save-CcFleetTemplate $TemplatePath)){throw 'Не удалось создать config.template.ini.'}}
        $remoteRoot="\\$HostName\C$\CyberCroc"
        $remoteConfig=Join-Path $remoteRoot 'config.ini'
        if(-not(Test-Path -LiteralPath $remoteRoot)){throw "Недоступен SMB: $remoteRoot"}
        $remote=@{}
        if(Test-Path -LiteralPath $remoteConfig){foreach($line in Get-Content -LiteralPath $remoteConfig -Encoding UTF8){$s=$line.Trim();$i=$s.IndexOf('=');if($i-gt 0 -and $s -notmatch '^[#;]'){$remote[$s.Substring(0,$i).Trim().ToUpperInvariant()]=$s.Substring($i+1).Trim()}}}
        $remote.Remove('ADMIN_PASSWORD')
        $template=@{}
        foreach($line in Get-Content -LiteralPath $TemplatePath -Encoding UTF8){$s=$line.Trim();$i=$s.IndexOf('=');if($i-gt 0 -and $s -notmatch '^[#;]'){$template[$s.Substring(0,$i).Trim().ToUpperInvariant()]=$s.Substring($i+1).Trim()}}
        foreach($key in $template.Keys){if($key -notin @('ROLE','PC_ID','ADMIN_PASSWORD','ADMIN_PASSWORD_PROTECTED','GOOGLE_SERVICE_ACCOUNT_JSON')){$remote[$key]=$template[$key]}}
        Set-Content -LiteralPath $remoteConfig -Value ($remote.Keys|Sort-Object|ForEach-Object { '{0}={1}' -f $_,$remote[$_] }) -Encoding UTF8
        Write-CcLog "Fleet config synced to $HostName" 'OK' 'Sync-CcConfigToPc'
        return $true
    } catch { Write-CcError -FunctionName 'Sync-CcConfigToPc' -Exception $_.Exception; return $false }
}
function Sync-CcConfigToFleet {
    try {
        [void](Save-CcFleetTemplate)
        $targets=@(Get-CcFleetTargets)
        if($targets.Count -eq 0){return [pscustomobject]@{Total=0;Success=0;Failed=0;Targets=@()}}
        $ok=0;$bad=0;$result=@()
        foreach($t in $targets){$configOk=Sync-CcConfigToPc ([string]$t.Host);$cacheOk=Sync-CcProductsCacheToPc ([string]$t.Host);$success=($configOk -and $cacheOk);if($success){$ok++}else{$bad++};$result+=[pscustomobject]@{PcId=$t.PcId;Host=$t.Host;Config=$configOk;ProductsCache=$cacheOk;Success=$success}}
        [pscustomobject]@{Total=$targets.Count;Success=$ok;Failed=$bad;Targets=$result}
    } catch { Write-CcError -FunctionName 'Sync-CcConfigToFleet' -Exception $_.Exception; return [pscustomobject]@{Total=0;Success=0;Failed=0;Targets=@()} }
}
