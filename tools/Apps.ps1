[CmdletBinding()]
param([switch]$Install,[switch]$Update,[switch]$Json,[string]$List='apps.txt')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
function Get-CcInstalledApps {
    try{
        $all=@()
        foreach($p in @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')){
            $all+=Get-ItemProperty -Path $p -ErrorAction SilentlyContinue|Where-Object{$_.DisplayName}
        }
        return @($all)
    }catch{Write-CcError -FunctionName 'Get-CcInstalledApps' -Exception $_.Exception;return @()}
}
function Test-CcApp {
    param([object]$Item,[object[]]$Installed,[bool]$Winget)
    try{
        if($Item.Check){
            $p=Expand-CcPath $Item.Check
            if(Test-Path -LiteralPath $p){return [pscustomobject]@{Installed=$true;Reason=$p}}
        }
        $hits=@($Installed|Where-Object{$_.DisplayName -like "*$($Item.Name)*"})
        if($hits.Count){return [pscustomobject]@{Installed=$true;Reason=$hits[0].DisplayName}}
        if($Item.Type -eq 'winget' -and $Winget){
            $o=& winget list --id $Item.Source --exact --source winget --accept-source-agreements 2>&1|Out-String
            if($LASTEXITCODE -eq 0 -and $o -match [regex]::Escape($Item.Source)){return [pscustomobject]@{Installed=$true;Reason="winget:$($Item.Source)"}}
        }
        [pscustomobject]@{Installed=$false;Reason='not found'}
    }catch{Write-CcError -FunctionName 'Test-CcApp' -Exception $_.Exception;return [pscustomobject]@{Installed=$false;Reason=$_.Exception.Message}}
}
try{
    $root=$script:CcRoot;$listPath=if([IO.Path]::IsPathRooted($List)){$List}else{Join-Path $root $List}
    if(-not(Test-Path $listPath)){throw "apps.txt not found: $listPath"}
    $items=@()
    foreach($raw in Get-Content $listPath -Encoding UTF8){
        $l=$raw.Trim();if(!$l -or $l -match '^[#;]'){continue}
        $c=@($l-split '\|');while($c.Count-lt 5){$c+=''}
        $items+=[pscustomobject]@{Name=$c[0].Trim();Source=$c[1].Trim();Type=$c[2].Trim().ToLower();Check=$c[3].Trim();Args=$c[4].Trim()}
    }
    $winget=$false;try{& winget --version 2>$null|Out-Null;$winget=($LASTEXITCODE -eq 0)}catch{}
    $installed=Get-CcInstalledApps;$results=@()
    foreach($it in $items){
        $t=Test-CcApp $it $installed $winget
        $results+=[pscustomobject]@{Name=$it.Name;Source=$it.Source;Type=$it.Type;Installed=$t.Installed;Reason=$t.Reason;Action=''}
        if($Install -and -not $t.Installed -and $it.Type -eq 'winget' -and $winget){
            $args=@('install','--id',$it.Source,'--exact','--source','winget','--accept-source-agreements','--accept-package-agreements','--silent','--disable-interactivity')
            & winget @args 2>&1|Out-Null;$rc=$LASTEXITCODE
            $results[-1].Action=if($rc -eq 0){'installed'}else{"failed:$rc"}
        }elseif($Update -and $t.Installed -and $it.Type -eq 'winget' -and $winget){
            $args=@('upgrade','--id',$it.Source,'--exact','--source','winget','--accept-source-agreements','--accept-package-agreements','--silent','--disable-interactivity')
            & winget @args 2>&1|Out-Null;$rc=$LASTEXITCODE
            $results[-1].Action=if($rc -eq 0){'updated'}else{"code:$rc"}
        }
    }
    Write-CcLog "Apps check completed: $($results.Count) items" 'OK' 'Apps'
    if($Json){$results|ConvertTo-Json -Depth 5}else{$results}
    exit 0
}catch{Write-CcError -FunctionName 'Apps' -Exception $_.Exception;exit 3}
