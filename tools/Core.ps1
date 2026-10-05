<#
CyberCroc Core - PowerShell 5.1
Shared configuration, logging, process and toast helpers.
#>
Set-StrictMode -Version 2.0

$script:CcRoot = Split-Path -Parent $PSScriptRoot
$script:CcLogDir = Join-Path $script:CcRoot 'logs'
$script:CcLogFile = Join-Path $script:CcLogDir 'CyberCroc.log'
$script:CcErrorFile = Join-Path $script:CcLogDir 'errors.log'
$script:CcConfigCache = $null
$script:CcConfigPath = Join-Path $script:CcRoot 'config.ini'

function Initialize-CcCore {
    try { if (-not (Test-Path -LiteralPath $script:CcLogDir)) { New-Item -ItemType Directory -Path $script:CcLogDir -Force | Out-Null } } catch {}
}
function Write-CcLog {
    param([string]$Message,[ValidateSet('INFO','OK','WARN','ERROR')][string]$Level='INFO',[string]$FunctionName='')
    try {
        Initialize-CcCore
        $line = '[{0}] [{1}] [{2}] {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$FunctionName,$Message
        Add-Content -LiteralPath $script:CcLogFile -Value $line -Encoding UTF8
    } catch {}
}
function Write-CcError {
    param([string]$FunctionName,[System.Exception]$Exception,[string]$Message='')
    try {
        Initialize-CcCore
        $msg = if($Message){$Message}else{$Exception.Message}
        $line='[{0}] [ERROR] [{1}] {2} :: {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$FunctionName,$msg,$Exception.ToString()
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
                $l=$raw.Trim(); if(!$l -or $l -match '^[#;]'){continue}
                $i=$l.IndexOf('='); if($i -lt 1){continue}
                $h[$l.Substring(0,$i).Trim().ToUpperInvariant()]=$l.Substring($i+1).Trim()
            }
        }
    } catch { Write-CcError -FunctionName 'Read-CcIni' -Exception $_.Exception }
    return $h
}
function Get-CcConfig {
    param([string]$Path = $script:CcConfigPath,[switch]$Refresh)
    try {
        if($script:CcConfigCache -and -not $Refresh){return $script:CcConfigCache}
        if(-not(Test-Path -LiteralPath $Path)){ $example=Join-Path $script:CcRoot 'config.example.ini';if(Test-Path -LiteralPath $example){Copy-Item $example $Path -Force} }
        $script:CcConfigPath=$Path;$script:CcConfigCache=Read-CcIni -Path $Path
        $defaults=@{'THEME'='dark';'GAMES_SHARE'='';'BAR_SHEET_ID'='1l-p_ck7hS1PmrqJDYAQcni6_boxFK3Pl5BFGqKoMRWM';'BAR_SHEET_URL'='';'BAR_SHARE'='';'BAR_PRICE_SHEET_NAME'='Цены';'GOOGLE_SERVICE_ACCOUNT_JSON'='';'GAMES_SOURCE_URL'='';'ADMIN_PASSWORD'='croc'}; foreach($key in $defaults.Keys){if(-not $script:CcConfigCache.ContainsKey([string]$key)){$script:CcConfigCache[[string]$key]=$defaults[$key]}}
        return $script:CcConfigCache
    } catch {Write-CcError -FunctionName 'Get-CcConfig' -Exception $_.Exception;return @{}}
}
function Save-CcConfig([hashtable]$Config,[string]$Path=$script:CcConfigPath){
    try{$lines=@();foreach($key in $Config.Keys|Sort-Object){$lines+=("$key=$($Config[$key])")};Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8;$script:CcConfigCache=$Config;return $true}catch{Write-CcError -FunctionName 'Save-CcConfig' -Exception $_.Exception;return $false}
}
function Protect-CcSecret([string]$PlainText){try{if($null -eq $PlainText){return ''};return (ConvertTo-SecureString $PlainText -AsPlainText -Force|ConvertFrom-SecureString)}catch{Write-CcError -FunctionName 'Protect-CcSecret' -Exception $_.Exception;return ''}}
function Unprotect-CcSecret([string]$CipherText){try{if([string]::IsNullOrWhiteSpace($CipherText)){return ''};$sec=ConvertTo-SecureString $CipherText;$b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec);try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}}catch{Write-CcError -FunctionName 'Unprotect-CcSecret' -Exception $_.Exception;return ''}}
function Test-CcAdminPassword([string]$Password){try{$cfg=Get-CcConfig;if([string]::IsNullOrWhiteSpace([string]$cfg['ADMIN_PASSWORD'])){return $false};return [string]::Equals($Password,[string]$cfg['ADMIN_PASSWORD'],[StringComparison]::OrdinalIgnoreCase)}catch{Write-CcError -FunctionName 'Test-CcAdminPassword' -Exception $_.Exception;return $false}}
function Expand-CcPath([string]$Path) {
    try { if([string]::IsNullOrWhiteSpace($Path)){return ''}; return [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')) } catch { Write-CcError -FunctionName 'Expand-CcPath' -Exception $_.Exception; return '' }
}
function Compare-CcVersion([string]$A,[string]$B) {
    try {
        $av=[version]$A; $bv=[version]$B
        return $av.CompareTo($bv)
    } catch { return [string]::Compare($A,$B,$true) }
}
function Start-CcHidden {
    param([string]$FilePath,[string[]]$ArgumentList=@(),[string]$WorkingDirectory='')
    try {
        $p=Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru
        Write-CcLog "Started $FilePath" 'INFO' 'Start-CcHidden'
        return $p
    } catch { Write-CcError -FunctionName 'Start-CcHidden' -Exception $_.Exception; return $null }
}
function Show-CcToast {
    param([string]$Title,[string]$Message,[ValidateSet('OK','ERROR','INFO')][string]$Level='INFO')
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $n=New-Object System.Windows.Forms.NotifyIcon
        $n.Icon=[System.Drawing.SystemIcons]::Application
        $n.Visible=$true
        $tip=if($Level -eq 'ERROR'){'Error'}elseif($Level -eq 'OK'){'Info'}else{'Info'}
        $n.ShowBalloonTip(3500,$Title,$Message,[System.Windows.Forms.ToolTipIcon]::$tip)
        Start-Sleep -Milliseconds 100
        $n.Dispose()
    } catch { Write-CcError -FunctionName 'Show-CcToast' -Exception $_.Exception }
}
Initialize-CcCore
