<#
CyberCroc first-install / mass-deployment helper.
Creates a local client/admin config and registers launcher.vbs for the current Windows user.
#>
[CmdletBinding()]
param(
    [ValidateSet('client','admin')][string]$Role='client',
    [string]$PcId='',
    [string]$Zone='standard',
    [string]$TargetPath='C:\CyberCroc',
    [string]$MasterPassword=''
)
$ErrorActionPreference='Stop'
$SourceRoot=$PSScriptRoot
$TargetPath=[Environment]::ExpandEnvironmentVariables($TargetPath)
if(-not(Test-Path -LiteralPath $TargetPath)){New-Item -ItemType Directory -Path $TargetPath -Force|Out-Null}

# Copy application files; local data/logs/secrets are preserved on re-install.
& robocopy.exe $SourceRoot $TargetPath /E /R:2 /W:1 /COPY:DAT /DCOPY:DAT /NFL /NDL /NJH /NJS /NP /XF 'config.ini' 'accounts.json' 'bar-orders.json' 'bar-stock.json' 'bar-balances.json' /XD 'logs' 'data' 'runtime' | Out-Null
if($LASTEXITCODE -ge 8){throw "Robocopy failed with code $LASTEXITCODE"}
$cfgFile=Join-Path $TargetPath 'config.ini'
$existing=@{}
if(Test-Path -LiteralPath $cfgFile){foreach($line in Get-Content -LiteralPath $cfgFile -Encoding UTF8){$s=$line.Trim();$i=$s.IndexOf('=');if($i-gt 0 -and $s -notmatch '^[#;]'){$existing[$s.Substring(0,$i).Trim().ToUpperInvariant()]=$s.Substring($i+1).Trim()}}}
if(-not$PcId){$PcId=[Environment]::MachineName}
$existing['ROLE']=$Role;$existing['PC_ID']=$PcId;$existing['PC_ZONE']=$Zone;$existing['WATCHDOG_ENABLED']='1';$existing['AUTOSTART']='1'
# Never propagate the legacy plaintext master password to a deployed machine.
$existing.Remove('ADMIN_PASSWORD')
if($Role -eq 'client'){$existing['ADMIN_PASSWORD_PROTECTED']=''}
if($Role -eq 'admin'){
    if([string]::IsNullOrWhiteSpace($MasterPassword)){
        $sec=Read-Host 'Мастер-пароль CyberCroc' -AsSecureString
        $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec);try{$MasterPassword=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
    }
    if([string]::IsNullOrWhiteSpace($MasterPassword)){throw 'Master password is required for admin role.'}
}
# Load Core from the copied installation so the master secret is protected with the current Windows user DPAPI.
$bootstrap=Join-Path $TargetPath 'tools\Core.ps1'
$serialized=($existing.GetEnumerator()|ForEach-Object{('{0}={1}' -f $_.Key,$_.Value)})
Set-Content -LiteralPath $cfgFile -Value $serialized -Encoding UTF8
if($Role -eq 'admin'){
    # Load Core functions in the current installer process and persist the secret without logging it.
    . $bootstrap
    $cfg=Get-CcConfig -Refresh
    Set-CcAdminPassword $MasterPassword|Out-Null
}
# Make the data directory available to the kiosk account while application files remain read-only where ACLs permit.
foreach($dir in @('logs','data','runtime')){New-Item -ItemType Directory -Path (Join-Path $TargetPath $dir) -Force|Out-Null}
if($Role -eq 'client'){
    $policy=Join-Path $TargetPath 'tools\KioskPolicy.ps1'
    if(Test-Path -LiteralPath $policy){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $policy -Disable | Out-Null}
}
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
New-Item -Path $runKey -Force|Out-Null
New-ItemProperty -Path $runKey -Name 'CyberCroc' -Value ("wscript.exe `"$(Join-Path $TargetPath 'launcher.vbs')`"") -PropertyType String -Force|Out-Null
Write-Host "CyberCroc installed: $TargetPath, role=$Role, pc=$PcId"
