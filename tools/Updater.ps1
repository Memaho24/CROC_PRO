<#
CyberCroc SMB updater. Runs hidden and never requires a server.
#>
[CmdletBinding()]
param([switch]$Check,[switch]$Apply,[string]$Source,[int]$WaitPid=0)

. (Join-Path $PSScriptRoot 'Core.ps1')

function Get-CcVersion([string]$Root){
    try{$v=(Get-Content -LiteralPath (Join-Path $Root 'version.txt') -Raw -ErrorAction Stop).Trim();if($v){return $v}}catch{Write-CcError -FunctionName 'Get-CcVersion' -Exception $_.Exception}
    return '0.0.0'
}
function Test-CcShare([string]$Path){
    try{return [bool](Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop)}catch{Write-CcError -FunctionName 'Test-CcShare' -Exception $_.Exception;return $false}
}
function Get-CcUpdateInfo([string]$Root,[string]$Share){
    try{
        if(-not(Test-CcShare $Share)){return [pscustomobject]@{Available=$false;Reason='SMB share unavailable';Local=Get-CcVersion $Root;Remote=''}}
        $remote=Get-CcVersion $Share;$local=Get-CcVersion $Root
        $cmp=Compare-CcVersion $remote $local
        [pscustomobject]@{Available=($cmp -gt 0);Reason=if($cmp -gt 0){'New version available'}else{'Already current'};Local=$local;Remote=$remote}
    }catch{Write-CcError -FunctionName 'Get-CcUpdateInfo' -Exception $_.Exception;return [pscustomobject]@{Available=$false;Reason=$_.Exception.Message;Local='';Remote=''}}
}
function Invoke-CcApplyUpdate([string]$Root,[string]$Share){
    try{
        if(-not(Test-CcShare $Share)){throw "SMB share unavailable: $Share"}
        $info=Get-CcUpdateInfo $Root $Share
        if(-not $info.Available){Write-CcLog "Update skipped: $($info.Reason) local=$($info.Local) remote=$($info.Remote)" 'INFO' 'Invoke-CcApplyUpdate';return $false}
        if($WaitPid -gt 0){try{Wait-Process -Id $WaitPid -Timeout 120 -ErrorAction SilentlyContinue|Out-Null}catch{}}
        $stage=Join-Path $env:TEMP ('CyberCrocUpdate_'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force|Out-Null
        & robocopy.exe $Share $stage /E /R:2 /W:2 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP /XF 'config.ini' 'accounts.json' /XD 'logs' 'BACKUP' $null 2>&1|Out-Null
        $rc=$LASTEXITCODE
        if($rc -ge 8){throw "Staging failed, robocopy code $rc"}
        & robocopy.exe $stage $Root /E /R:2 /W:2 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP /XF 'config.ini' 'accounts.json' /XD 'logs' 'BACKUP' $null 2>&1|Out-Null
        $rc=$LASTEXITCODE
        if($rc -ge 8){throw "Install failed, robocopy code $rc"}
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        Write-CcLog "Updated CyberCroc $($info.Local) -> $($info.Remote) from $Share" 'OK' 'Invoke-CcApplyUpdate'
        $launcher=Join-Path $Root 'launcher.vbs'
        if(Test-Path $launcher){Start-Process wscript.exe -ArgumentList @('//B','//Nologo',$launcher) -WindowStyle Hidden}
        return $true
    }catch{Write-CcError -FunctionName 'Invoke-CcApplyUpdate' -Exception $_.Exception;return $false}
}
$root=$script:CcRoot
if(-not $Source){$cfg=Get-CcConfig;$Source=[string]$cfg['UPDATE_SHARE']}
if([string]::IsNullOrWhiteSpace($Source)){Write-CcLog 'UPDATE_SHARE is empty' 'WARN' 'Updater';exit 0}
if($Check){$i=Get-CcUpdateInfo $root $Source;Write-Output ($i|ConvertTo-Json -Compress);exit 0}
if($Apply){[void](Invoke-CcApplyUpdate $root $Source);exit 0}
