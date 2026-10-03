<#
CyberCroc Accounts - PowerShell 5.1.
Passwords are protected with Windows DPAPI for the current Windows user.
#>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')

$script:CcAccountsFile=Join-Path $script:CcRoot 'accounts.json'

function Initialize-CcAccounts {
    try {
        if(-not (Test-Path -LiteralPath $script:CcAccountsFile)){
            @{Version=1;Accounts=@()} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:CcAccountsFile -Encoding UTF8
        }
    } catch { Write-CcError -FunctionName 'Initialize-CcAccounts' -Exception $_.Exception }
}
function Protect-CcSecret([string]$PlainText) {
    try { if($null -eq $PlainText){return ''}; ConvertTo-SecureString $PlainText -AsPlainText -Force | ConvertFrom-SecureString } catch { Write-CcError -FunctionName 'Protect-CcSecret' -Exception $_.Exception; return '' }
}
function Unprotect-CcSecret([string]$CipherText) {
    try {
        if([string]::IsNullOrWhiteSpace($CipherText)){return ''}
        $sec=ConvertTo-SecureString $CipherText
        $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
    } catch { Write-CcError -FunctionName 'Unprotect-CcSecret' -Exception $_.Exception; return '' }
}
function Get-CcAccounts {
    try {
        Initialize-CcAccounts
        $raw=Get-Content -LiteralPath $script:CcAccountsFile -Raw -Encoding UTF8
        $j=$raw|ConvertFrom-Json
        if($null -eq $j.Accounts){return @()}
        return @($j.Accounts)
    } catch { Write-CcError -FunctionName 'Get-CcAccounts' -Exception $_.Exception; return @() }
}
function Save-CcAccounts {
    param([object[]]$Accounts)
    try {
        $tmp="$script:CcAccountsFile.tmp"
        @{Version=1;Accounts=@($Accounts)}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $script:CcAccountsFile -Force
        Write-CcLog "Accounts saved: $(@($Accounts).Count)" 'OK' 'Save-CcAccounts'
        return $true
    } catch { Write-CcError -FunctionName 'Save-CcAccounts' -Exception $_.Exception; return $false }
}
function New-CcAccount {
    param([string]$Platform,[string]$Login,[string]$Password,[string]$Comment,[string[]]$Games)
    try {
        if($Platform -notin @('Steam','Riot Games','Battle.net','Epic Games')){throw "Unsupported platform: $Platform"}
        if([string]::IsNullOrWhiteSpace($Login)){throw 'Login is required'}
        $list=@(Get-CcAccounts)
        $obj=[pscustomobject]@{
            Id=[guid]::NewGuid().ToString()
            Platform=$Platform
            Login=$Login
            PasswordProtected=(Protect-CcSecret $Password)
            Comment=$Comment
            Games=@($Games|Where-Object{$_})
            Status='not_checked'
            UsedBy=''
            UsedSince=''
            Banned=$false
            BanText=''
            LastCheck=''
            Library=@()
        }
        $list+= $obj
        Save-CcAccounts $list|Out-Null
        Write-CcLog "Account added: $Platform / $Login" 'OK' 'New-CcAccount'
        return $obj
    } catch { Write-CcError -FunctionName 'New-CcAccount' -Exception $_.Exception; return $null }
}
function Update-CcAccount {
    param([string]$Id,[hashtable]$Values)
    try {
        $list=@(Get-CcAccounts); $a=$list|Where-Object{$_.Id -eq $Id}|Select-Object -First 1
        if(-not $a){throw "Account not found: $Id"}
        foreach($k in $Values.Keys){
            if($k -eq 'Password'){ $a.PasswordProtected=Protect-CcSecret ([string]$Values[$k]) }
            elseif($k -eq 'Games'){ $a.Games=@($Values[$k]) }
            elseif($k -in @('Platform','Login','Comment','Status','UsedBy','UsedSince')){$a.$k=[string]$Values[$k]}
        }
        Save-CcAccounts $list|Out-Null; Write-CcLog "Account updated: $Id" 'OK' 'Update-CcAccount'; return $a
    } catch { Write-CcError -FunctionName 'Update-CcAccount' -Exception $_.Exception; return $null }
}
function Remove-CcAccount {
    param([string]$Id)
    try {
        $list=@(Get-CcAccounts); $new=@($list|Where-Object{$_.Id -ne $Id})
        if($new.Count -eq $list.Count){throw "Account not found: $Id"}
        Save-CcAccounts $new|Out-Null; Write-CcLog "Account removed: $Id" 'OK' 'Remove-CcAccount'; return $true
    } catch { Write-CcError -FunctionName 'Remove-CcAccount' -Exception $_.Exception; return $false }
}
function Get-CcSteamExe {
    try {
        $candidates=@()
        foreach($k in @('HKCU:SoftwareValveSteam','HKLM:SOFTWAREValveSteam','HKLM:SOFTWAREWOW6432NodeValveSteam')){
            try{$p=Get-ItemProperty -LiteralPath $k -ErrorAction Stop; foreach($n in 'SteamPath','InstallPath'){if($p.$n){$candidates+=(Join-Path $p.$n 'steam.exe')}}}catch{}
        }
        $candidates+=@('C:Program Files (x86)Steamsteam.exe','C:Program FilesSteamsteam.exe')
        foreach($c in $candidates){if(Test-Path -LiteralPath $c){return $c}}
        return $null
    } catch { Write-CcError -FunctionName 'Get-CcSteamExe' -Exception $_.Exception; return $null }
}
function Get-CcSteamId64([string]$SteamRoot,[string]$Login) {
    try {
        $f=Join-Path $SteamRoot 'configloginusers.vdf'; if(-not(Test-Path $f)){return ''}
        $txt=Get-Content $f -Raw -ErrorAction Stop
        foreach($m in [regex]::Matches($txt,'(?ms)"(?<id>d{17})"s*{(?<body>.*?)}')){
            if($m.Groups['body'].Value -match '"AccountName"s+"'+[regex]::Escape($Login)+'"'){return $m.Groups['id'].Value}
        }
        $first=[regex]::Match($txt,'"(\d{17})"'); if($first.Success){return $first.Groups[1].Value}
        return ''
    } catch { Write-CcError -FunctionName 'Get-CcSteamId64' -Exception $_.Exception; return '' }
}
function Test-CcSteamAccount {
    param([object]$Account,[string]$ApiKey)
    try {
        if([string]::IsNullOrWhiteSpace($ApiKey)){return [pscustomobject]@{Ok=$false;Reason='STEAM_API_KEY is not configured';Library=@();Banned=$false}}
        $exe=Get-CcSteamExe; if(-not $exe){return [pscustomobject]@{Ok=$false;Reason='Steam not installed';Library=@();Banned=$false}}
        $root=Split-Path $exe -Parent; $sid=Get-CcSteamId64 $root $Account.Login
        if(-not $sid){return [pscustomobject]@{Ok=$false;Reason='SteamID64 not found in loginusers.vdf';Library=@();Banned=$false}}
        $headers=@{'User-Agent'='CyberCroc/0.4'}
        $gamesUri="https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=$ApiKey&steamid=$sid&include_appinfo=1&include_played_free_games=1"
        $banUri="https://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=$ApiKey&steamids=$sid"
        $g=Invoke-RestMethod -Uri $gamesUri -Headers $headers -TimeoutSec 20
        $b=Invoke-RestMethod -Uri $banUri -Headers $headers -TimeoutSec 20
        $lib=@($g.response.games|ForEach-Object{[pscustomobject]@{Name=$_.name;Hours=[math]::Round(([double]$_.playtime_forever/60),1)}})
        $bp=$b.players|Select-Object -First 1
        [pscustomobject]@{Ok=$true;Reason='OK';Library=$lib;Banned=([bool]($bp.VACBanned -or $bp.NumberOfGameBans));BanText=("VAC={0}; GameBans={1}" -f $bp.VACBanned,$bp.NumberOfGameBans)}
    } catch { Write-CcError -FunctionName 'Test-CcSteamAccount' -Exception $_.Exception; return [pscustomobject]@{Ok=$false;Reason=$_.Exception.Message;Library=@();Banned=$false} }
}
function Test-CcAccount {
    param([object]$Account,[hashtable]$Config)
    try {
        $r=$null
        if($Account.Platform -eq 'Steam'){$r=Test-CcSteamAccount $Account $Config['STEAM_API_KEY']}
        else {$r=[pscustomobject]@{Ok=$false;Reason='Public API does not provide a reliable account library/ban check for this platform';Library=@();Banned=$false}}
        $Account.LastCheck=(Get-Date).ToString('s')
        $Account.Library=@($r.Library)
        $Account.Banned=[bool]$r.Banned
        $Account.BanText=[string]$r.BanText
        $Account.Status=if($r.Banned){'ban'}elseif($r.Ok){'free'}else{'not_checked'}
        if(-not $r.Ok){$Account.Comment=if($Account.Comment){$Account.Comment}else{"Check: $($r.Reason)"}}
        Write-CcLog "Account check: $($Account.Platform)/$($Account.Login) => $($Account.Status)" $(if($r.Ok){'OK'}else{'WARN'}) 'Test-CcAccount'
        return $r
    } catch { Write-CcError -FunctionName 'Test-CcAccount' -Exception $_.Exception; return $null }
}
function Start-CcAccountSession {
    param([object]$Account)
    try {
        switch($Account.Platform){
            'Steam' {
                $exe=Get-CcSteamExe;if(-not $exe){throw 'Steam not found'}
                if(Get-Process -Name steam -ErrorAction SilentlyContinue){Get-Process -Name steam -ErrorAction SilentlyContinue|Stop-Process -Force;Start-Sleep 2}
                $pw=Unprotect-CcSecret $Account.PasswordProtected
                # Steam accepts -login, but command-line credentials are visible to local process inspection.
                if($pw){Start-Process -FilePath $exe -ArgumentList @('-login',$Account.Login,$pw) -WindowStyle Hidden|Out-Null}
                else{Start-Process -FilePath $exe -WindowStyle Hidden|Out-Null}
            }
            'Riot Games' {
                $exe=Get-CcLauncherExe 'RiotClientServices.exe'
                if(-not $exe){throw 'Riot Client not found'}
                Start-Process -FilePath $exe -ArgumentList @('--launch-product=league_of_legends','--launch-patchline=live') -WindowStyle Hidden|Out-Null
            }
            'Battle.net' {
                $exe=Get-CcLauncherExe 'Battle.net.exe'
                if(-not $exe){throw 'Battle.net not found'}
                Start-Process -FilePath $exe -ArgumentList @('--exec=launch') -WindowStyle Hidden|Out-Null
            }
            'Epic Games' {
                $exe=Get-CcLauncherExe 'EpicGamesLauncher.exe'
                if(-not $exe){throw 'Epic Games Launcher not found'}
                # Epic auth tokens are launcher-managed; do not extract or log them.
                Start-Process -FilePath $exe -WindowStyle Hidden|Out-Null
            }
        }
        $Account.Status='occupied';$Account.UsedBy=$env:USERNAME;$Account.UsedSince=(Get-Date).ToString('s')
        Write-CcLog "Account session started: $($Account.Platform)/$($Account.Login)" 'OK' 'Start-CcAccountSession'
        return $true
    } catch { Write-CcError -FunctionName 'Start-CcAccountSession' -Exception $_.Exception; return $false }
}
function Get-CcLauncherExe([string]$Name) {
    try {
        $roots=@($env:ProgramFiles,$env:ProgramFilesX86,$env:ProgramData,$env:LOCALAPPDATA,$env:APPDATA)|Where-Object{$_}
        foreach($r in $roots){$hit=Get-ChildItem -LiteralPath $r -Filter $Name -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1;if($hit){return $hit.FullName}}
        return $null
    } catch { Write-CcError -FunctionName 'Get-CcLauncherExe' -Exception $_.Exception; return $null }
}
Initialize-CcAccounts
