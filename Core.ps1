<#
CyberCroc Core - PowerShell 5.1
Configuration, DPAPI secrets, atomic JSON storage, logging and common helpers.
#>
Set-StrictMode -Version 2.0

$script:CcRoot = Split-Path -Parent $PSScriptRoot
$script:CcLogDir = Join-Path $script:CcRoot 'logs'
$script:CcLogFile = Join-Path $script:CcLogDir 'CyberCroc.log'
$script:CcErrorFile = Join-Path $script:CcLogDir 'errors.log'
$script:CcConfigCache = $null
$script:CcConfigPath = Join-Path $script:CcRoot 'config.ini'
$script:CcLastLogRotateUtc = [datetime]::MinValue

function Initialize-CcCore {
    try {
        if (-not (Test-Path -LiteralPath $script:CcLogDir)) { New-Item -ItemType Directory -Path $script:CcLogDir -Force | Out-Null }
        $data=Join-Path $script:CcRoot 'data'
        if (-not (Test-Path -LiteralPath $data)) { New-Item -ItemType Directory -Path $data -Force | Out-Null }
    } catch {}
}
function Invoke-CcLogRotate {
    param([string]$FilePath)
    try {
        $now=(Get-Date).ToUniversalTime()
        if (($now-$script:CcLastLogRotateUtc).TotalMinutes -lt 5) { return }
        $script:CcLastLogRotateUtc=$now
        if (-not (Test-Path -LiteralPath $FilePath)) { return }
        $file=Get-Item -LiteralPath $FilePath -ErrorAction Stop
        $ageDays=($now.ToUniversalTime()-$file.LastWriteTimeUtc).TotalDays
        $sizeLimit=10MB
        $rotate=($file.Length -ge $sizeLimit -or $ageDays -ge 7)
        if (-not $rotate) { return }
        $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
        $archive="$FilePath.$stamp.zip"
        if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
            Compress-Archive -LiteralPath $FilePath -DestinationPath $archive -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $archive) { Set-Content -LiteralPath $FilePath -Value '' -Encoding UTF8 }
        } else {
            Move-Item -LiteralPath $FilePath -Destination "$FilePath.$stamp" -Force -ErrorAction SilentlyContinue
            Set-Content -LiteralPath $FilePath -Value '' -Encoding UTF8
        }
        $pattern=[IO.Path]::GetFileName($FilePath)+'.*.zip'
        Get-ChildItem -LiteralPath $script:CcLogDir -Filter $pattern -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -Skip 14 | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}
}
function Write-CcLog {
    param([string]$Message,[ValidateSet('INFO','OK','WARN','ERROR')][string]$Level='INFO',[string]$FunctionName='')
    try {
        Initialize-CcCore
        Invoke-CcLogRotate -FilePath $script:CcLogFile
        $line='[{0}] [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$FunctionName,($Message -replace '[\r\n]+',' ')
        Add-Content -LiteralPath $script:CcLogFile -Value $line -Encoding UTF8
    } catch {}
}
function Write-CcError {
    param([string]$FunctionName,[System.Exception]$Exception,[string]$Message='')
    try {
        Initialize-CcCore
        Invoke-CcLogRotate -FilePath $script:CcErrorFile
        $msg=if($Message){$Message}elseif($Exception){$Exception.Message}else{'Unknown error'}
        # Do not serialize exception objects or secret values into the log.
        $line='[{0}] [ERROR] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$FunctionName,($msg -replace '[\r\n]+',' ')
        Add-Content -LiteralPath $script:CcErrorFile -Value $line -Encoding UTF8
        Add-Content -LiteralPath $script:CcLogFile -Value $line -Encoding UTF8
    } catch {}
}
function Invoke-CcSafe {
    param([Parameter(Mandatory=$true)][string]$FunctionName,[Parameter(Mandatory=$true)][scriptblock]$Script)
    try { & $Script } catch { Write-CcError -FunctionName $FunctionName -Exception $_.Exception; return $null }
}
function Read-CcIni {
    param([string]$Path)
    $h=@{}
    try {
        if(Test-Path -LiteralPath $Path){
            foreach($raw in Get-Content -LiteralPath $Path -Encoding UTF8){
                $l=$raw.Trim();if(!$l -or $l -match '^[#;]'){continue}
                $i=$l.IndexOf('=');if($i -lt 1){continue}
                $h[$l.Substring(0,$i).Trim().ToUpperInvariant()]=$l.Substring($i+1).Trim()
            }
        }
    }catch{Write-CcError -FunctionName 'Read-CcIni' -Exception $_.Exception}
    return $h
}
function Save-CcConfig {
    param([hashtable]$Config,[string]$Path=$script:CcConfigPath)
    try {
        $lines=@();foreach($key in $Config.Keys|Sort-Object){$lines+=('{0}={1}' -f $key,$Config[$key])}
        $tmp="$Path.tmp";Set-Content -LiteralPath $tmp -Value $lines -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $Path -Force
        $script:CcConfigCache=$Config;return $true
    }catch{Write-CcError -FunctionName 'Save-CcConfig' -Exception $_.Exception;return $false}
}
function Get-CcConfig {
    param([string]$Path=$script:CcConfigPath,[switch]$Refresh)
    try {
        if($script:CcConfigCache -and -not$Refresh){return $script:CcConfigCache}
        if(-not(Test-Path -LiteralPath $Path)){
            $example=Join-Path $script:CcRoot 'config.example.ini';if(Test-Path -LiteralPath $example){Copy-Item $example $Path -Force}
        }
        $script:CcConfigPath=$Path;$script:CcConfigCache=Read-CcIni -Path $Path
        $defaults=@{
            'THEME'='dark';'GAMES_SHARE'='';'BAR_SHEET_ID'='1l-p_ck7hS1PmrqJDYAQcni6_boxFK3Pl5BFGqKoMRWM';'BAR_SHEET_URL'='https://docs.google.com/spreadsheets/d/1l-p_ck7hS1PmrqJDYAQcni6_boxFK3Pl5BFGqKoMRWM/edit?gid=490076928#gid=490076928';'BAR_SHARE'='';'GAMES_SOURCE_URL'='';
            'ROLE'='client';'PC_ID'='';'PC_ZONE'='standard';'DISCOVERY_PORT'='50505';'BEACON_INTERVAL_SEC'='10';
            'BROADCAST_ADDRESS'='255.255.255.255';'EXPECTED_PCS'='50';'PRODUCT_SHEET_RANGE'='A:G';'PRODUCT_SHEET_URL'='https://docs.google.com/spreadsheets/d/1l-p_ck7hS1PmrqJDYAQcni6_boxFK3Pl5BFGqKoMRWM/edit?gid=490076928#gid=490076928';'PRODUCT_SHEET_ID'='1l-p_ck7hS1PmrqJDYAQcni6_boxFK3Pl5BFGqKoMRWM';
            'GOOGLE_SERVICE_ACCOUNT_JSON'='';'UPDATE_SHARE'='';'GITHUB_UPDATE_ENABLED'='0';'GITHUB_BRANCH'='cybercroc2-refactor';'ADMIN_PASSWORD_PROTECTED'='';'WATCHDOG_ENABLED'='1';'AUTOSTART'='1'
        }
        foreach($key in $defaults.Keys){if(-not$script:CcConfigCache.ContainsKey([string]$key)){$script:CcConfigCache[[string]$key]=$defaults[$key]}}
        # One-time migration from the legacy plaintext admin password to user-scoped Windows DPAPI.
        if($script:CcConfigCache.ContainsKey('ADMIN_PASSWORD') -and -not [string]::IsNullOrWhiteSpace([string]$script:CcConfigCache['ADMIN_PASSWORD'])){
            $plain=[string]$script:CcConfigCache['ADMIN_PASSWORD'];$protected=Protect-CcSecret $plain
            if($protected){$script:CcConfigCache['ADMIN_PASSWORD_PROTECTED']=$protected}
            $script:CcConfigCache.Remove('ADMIN_PASSWORD')
            Save-CcConfig $script:CcConfigCache $Path|Out-Null
            Write-CcLog 'Legacy plaintext admin password migrated to DPAPI.' 'WARN' 'Get-CcConfig'
        }
        return $script:CcConfigCache
    }catch{Write-CcError -FunctionName 'Get-CcConfig' -Exception $_.Exception;return @{}}
}
function Protect-CcSecret([string]$PlainText){try{if($null -eq $PlainText){return ''};return (ConvertTo-SecureString $PlainText -AsPlainText -Force|ConvertFrom-SecureString)}catch{Write-CcError -FunctionName 'Protect-CcSecret' -Exception $_.Exception;return ''}}
function Unprotect-CcSecret([string]$CipherText){try{if([string]::IsNullOrWhiteSpace($CipherText)){return ''};$sec=ConvertTo-SecureString $CipherText;$b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec);try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}}catch{Write-CcError -FunctionName 'Unprotect-CcSecret' -Exception $_.Exception;return ''}}
function Get-CcRole { try { $cfg=Get-CcConfig; $r=[string]$cfg['ROLE']; if($r -notin @('client','admin')){$r='client'};return $r }catch{return 'client'} }
function Get-CcPcId { try { $cfg=Get-CcConfig; $id=[string]$cfg['PC_ID']; if([string]::IsNullOrWhiteSpace($id)){$id=[Environment]::MachineName};return $id }catch{return [Environment]::MachineName} }
function Test-CcAdminPassword([string]$Password){
    try {
        if((Get-CcRole) -ne 'admin'){return $false}
        $cfg=Get-CcConfig;$cipher=[string]$cfg['ADMIN_PASSWORD_PROTECTED'];if([string]::IsNullOrWhiteSpace($cipher)){return $false}
        $stored=Unprotect-CcSecret $cipher
        return [string]::Equals($Password,$stored,[StringComparison]::Ordinal)
    }catch{Write-CcError -FunctionName 'Test-CcAdminPassword' -Exception $_.Exception;return $false}
}
function Set-CcAdminPassword([string]$Password){
    try{if([string]::IsNullOrWhiteSpace($Password)){throw 'Пароль не может быть пустым.'};$cfg=Get-CcConfig;$cfg['ADMIN_PASSWORD_PROTECTED']=Protect-CcSecret $Password;if(-not(Save-CcConfig $cfg)){throw 'Не удалось сохранить пароль.'};return $true}catch{Write-CcError -FunctionName 'Set-CcAdminPassword' -Exception $_.Exception;return $false}
}
function Expand-CcPath([string]$Path) {try{if([string]::IsNullOrWhiteSpace($Path)){return ''};return [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))}catch{Write-CcError -FunctionName 'Expand-CcPath' -Exception $_.Exception;return ''}}
function Compare-CcVersion([string]$A,[string]$B){try{$av=[version]$A;$bv=[version]$B;return $av.CompareTo($bv)}catch{return [string]::Compare($A,$B,$true)}}
function Start-CcHidden {param([string]$FilePath,[string[]]$ArgumentList=@(),[string]$WorkingDirectory='')try{$p=Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru;Write-CcLog "Started $FilePath" 'INFO' 'Start-CcHidden';return $p}catch{Write-CcError -FunctionName 'Start-CcHidden' -Exception $_.Exception;return $null}}
function Write-CcJsonAtomic {param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Object)
    try{$dir=Split-Path -Parent $Path;if($dir -and -not(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$tmp="$Path.tmp.$([guid]::NewGuid().ToString('N'))";$Object|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $Path -Force;return $true}catch{Write-CcError -FunctionName 'Write-CcJsonAtomic' -Exception $_.Exception;return $false}
}
function Show-CcToast {param([string]$Title,[string]$Message,[ValidateSet('OK','ERROR','INFO')][string]$Level='INFO')try{Add-Type -AssemblyName System.Windows.Forms;$n=New-Object System.Windows.Forms.NotifyIcon;$n.Icon=[System.Drawing.SystemIcons]::Application;$n.Visible=$true;$tip=if($Level -eq 'ERROR'){'Error'}else{'Info'};$n.ShowBalloonTip(3500,$Title,$Message,[System.Windows.Forms.ToolTipIcon]::$tip);Start-Sleep -Milliseconds 100;$n.Dispose()}catch{Write-CcError -FunctionName 'Show-CcToast' -Exception $_.Exception}}
Initialize-CcCore
