[CmdletBinding()]
param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$required=@('CyberCroc.ps1','launcher.vbs','watchdog.ps1','install.ps1','config.ini','config.example.ini','config.template.ini','version.txt','tools\Core.ps1','tools\Network.ps1','tools\Queue.ps1','tools\Orders.ps1','tools\Products.ps1','tools\Fleet.ps1','tools\Accounts.ps1')
$fail=@();$pass=0
foreach($r in $required){if(Test-Path -LiteralPath (Join-Path $Root $r)){$pass++}else{$fail+="Missing: $r"}}
$psFiles=Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse | Where-Object { $_.FullName -notmatch '\\logs\\' }
foreach($f in $psFiles){
    try{
        $tokens=$null;$errs=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errs)
        if($errs.Count){$fail+="Parse: $($f.FullName) :: $($errs[0].Message)"}else{$pass++}
    }catch{$fail+="Parse engine unavailable/failed: $($f.FullName) :: $($_.Exception.Message)"}
}
$ini=Get-Content -LiteralPath (Join-Path $Root 'config.ini') -Raw -Encoding UTF8
if($ini -match '(?im)^\s*ADMIN_PASSWORD\s*='){ $fail+='config.ini contains plaintext ADMIN_PASSWORD' } else {$pass++}
$version=(Get-Content -LiteralPath (Join-Path $Root 'version.txt') -Raw).Trim()
if($version -ne '0.5.0'){$fail+="Unexpected version: $version"}else{$pass++}
Write-Host "PASS=$pass FAIL=$($fail.Count)"
$fail|ForEach-Object {Write-Host $_}
if($fail.Count){exit 1}else{exit 0}
