<#
CyberCroc Accounts - PowerShell 5.1.
Account storage, DPAPI protection and optional LAN synchronization.
#>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')

$script:CcAccountsFile = Join-Path $script:CcRoot 'accounts.json'

function Initialize-CcAccounts {
    try {
        if (-not (Test-Path -LiteralPath $script:CcAccountsFile)) {
            @{ Version = 1; Accounts = @() } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:CcAccountsFile -Encoding UTF8
        }
    } catch { Write-CcError -FunctionName 'Initialize-CcAccounts' -Exception $_.Exception }
}

function Get-CcAccountsSharePath {
    try { $cfg=Get-CcConfig;$share=[string]$cfg['ACCOUNTS_SHARE'];if([string]::IsNullOrWhiteSpace($share)){return ''};return (Join-Path $share 'accounts.json') }
    catch { Write-CcError -FunctionName 'Get-CcAccountsSharePath' -Exception $_.Exception;return '' }
}
function Get-CcAccounts {
    try {
        Initialize-CcAccounts
        $raw = Get-Content -LiteralPath $script:CcAccountsFile -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

        $json = $raw | ConvertFrom-Json
        if ($null -eq $json -or $null -eq $json.Accounts) { return @() }
        return @($json.Accounts)
    } catch {
        Write-CcError -FunctionName 'Get-CcAccounts' -Exception $_.Exception
        return @()
    }
}

function Save-CcAccounts {
    param([object[]]$Accounts)
    try {
        $tmp = "$script:CcAccountsFile.tmp"
        @{ Version = 1; Accounts = @($Accounts) } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $script:CcAccountsFile -Force
        Write-CcLog "Accounts saved: $(@($Accounts).Count)" 'OK' 'Save-CcAccounts'
        return $true
    } catch {
        Write-CcError -FunctionName 'Save-CcAccounts' -Exception $_.Exception
        return $false
    }
}

function Sync-CcAccounts {
    param([ValidateSet('Pull','Push')][string]$Mode = 'Pull')

    try {
        $share = Get-CcAccountsSharePath
        if ([string]::IsNullOrWhiteSpace($share)) { return $false }

        if ($Mode -eq 'Pull') {
            if (-not (Test-Path -LiteralPath $share)) { return $false }

            $localInfo = Get-Item -LiteralPath $script:CcAccountsFile -ErrorAction SilentlyContinue
            $remoteInfo = Get-Item -LiteralPath $share -ErrorAction Stop
            if ($null -ne $localInfo -and $remoteInfo.LastWriteTimeUtc -le $localInfo.LastWriteTimeUtc) { return $false }

            $remoteRaw = Get-Content -LiteralPath $share -Raw -Encoding UTF8
            if ([string]::IsNullOrWhiteSpace($remoteRaw)) { return $false }

            $remoteJson = $remoteRaw | ConvertFrom-Json
            if ($null -eq $remoteJson -or $null -eq $remoteJson.Accounts) { return $false }

            $remoteList = @($remoteJson.Accounts)
            $localList = @(Get-CcAccounts)
            $localById = @{}

            foreach ($account in $localList) {
                if ($account.Id) { $localById[[string]$account.Id] = $account }
            }

            foreach ($account in $remoteList) {
                if ($account.Id -and $localById.ContainsKey([string]$account.Id)) {
                    $local = $localById[[string]$account.Id]
                    if ([string]::IsNullOrWhiteSpace([string]$account.PasswordProtected) -and
                        -not [string]::IsNullOrWhiteSpace([string]$local.PasswordProtected)) {
                        $account.PasswordProtected = $local.PasswordProtected
                    }
                }
            }

            $tmp = "$script:CcAccountsFile.sync.tmp"
            @{ Version = 1; Accounts = $remoteList } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
            Move-Item -LiteralPath $tmp -Destination $script:CcAccountsFile -Force
            Write-CcLog "Accounts pulled from LAN share: $share" 'OK' 'Sync-CcAccounts'
            return $true
        }

        $shareDir = Split-Path -Parent $share
        if ([string]::IsNullOrWhiteSpace($shareDir) -or -not (Test-Path -LiteralPath $shareDir)) { return $false }

        $localList = @(Get-CcAccounts)
        $tmp = "$share.tmp"
        @{ Version = 1; Accounts = $localList } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $share -Force

        Write-CcLog "Accounts pushed to LAN share: $share" 'OK' 'Sync-CcAccounts'
        return $true
    } catch {
        Write-CcError -FunctionName 'Sync-CcAccounts' -Exception $_.Exception
        return $false
    }
}

function New-CcAccount {
    param([string]$Platform,[string]$Login,[string]$Password,[string]$Comment,[string[]]$Games)
    try {
        if ($Platform -notin @('Steam','Riot Games','Battle.net','Epic Games')) { throw "Unsupported platform: $Platform" }
        if ([string]::IsNullOrWhiteSpace($Login)) { throw 'Login is required' }

        $list = @(Get-CcAccounts)
        $account = [pscustomobject]@{
            Id=[guid]::NewGuid().ToString()
            Platform=$Platform
            Login=$Login
            PasswordProtected=(Protect-CcSecret $Password)
            Comment=$Comment
            Games=@($Games | Where-Object { $_ })
            Status='not_checked'
            UsedBy=''
            UsedSince=''
            Banned=$false
            BanText=''
            LastCheck=''
            Library=@()
        }

        $list += $account
        if (-not (Save-CcAccounts $list)) { throw 'Could not save accounts.json' }
        [void](Sync-CcAccounts -Mode Push)
        Write-CcLog "Account added: $Platform / $Login" 'OK' 'New-CcAccount'
        return $account
    } catch {
        Write-CcError -FunctionName 'New-CcAccount' -Exception $_.Exception
        return $null
    }
}

function Update-CcAccount {
    param([string]$Id,[hashtable]$Values)
    try {
        $list = @(Get-CcAccounts)
        $account = $list | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
        if ($null -eq $account) { throw "Account not found: $Id" }

        foreach ($key in $Values.Keys) {
            if ($key -eq 'Password') { $account.PasswordProtected = Protect-CcSecret ([string]$Values[$key]) }
            elseif ($key -eq 'Games') { $account.Games = @($Values[$key]) }
            elseif ($key -in @('Platform','Login','Comment','Status','UsedBy','UsedSince')) { $account.$key = [string]$Values[$key] }
        }

        if (-not (Save-CcAccounts $list)) { throw 'Could not save accounts.json' }
        [void](Sync-CcAccounts -Mode Push)
        Write-CcLog "Account updated: $Id" 'OK' 'Update-CcAccount'
        return $account
    } catch {
        Write-CcError -FunctionName 'Update-CcAccount' -Exception $_.Exception
        return $null
    }
}

function Remove-CcAccount {
    param([string]$Id)
    try {
        $list = @(Get-CcAccounts)
        $newList = @($list | Where-Object { $_.Id -ne $Id })
        if ($newList.Count -eq $list.Count) { throw "Account not found: $Id" }
        if (-not (Save-CcAccounts $newList)) { throw 'Could not save accounts.json' }
        [void](Sync-CcAccounts -Mode Push)
        Write-CcLog "Account removed: $Id" 'OK' 'Remove-CcAccount'
        return $true
    } catch {
        Write-CcError -FunctionName 'Remove-CcAccount' -Exception $_.Exception
        return $false
    }
}

function Get-CcSteamExe {
    try {
        $candidates = @()
        foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
            try {
                $props = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
                foreach ($name in @('SteamPath','InstallPath')) {
                    if ($props.$name) { $candidates += (Join-Path $props.$name 'steam.exe') }
                }
            } catch {}
        }

        $candidates += @('C:\Program Files (x86)\Steam\steam.exe','C:\Program Files\Steam\steam.exe')
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
        return $null
    } catch {
        Write-CcError -FunctionName 'Get-CcSteamExe' -Exception $_.Exception
        return $null
    }
}

function Get-CcSteamId64 {
    param([string]$SteamRoot,[string]$Login)
    try {
        $file = Join-Path $SteamRoot 'config\loginusers.vdf'
        if (-not (Test-Path -LiteralPath $file)) { return '' }

        $text = Get-Content -LiteralPath $file -Raw -ErrorAction Stop
        foreach ($match in [regex]::Matches($text,'(?ms)"(?<id>\d{17})"\s*{(?<body>.*?)}')) {
            if ($match.Groups['body'].Value -match '"AccountName"\s+"' + [regex]::Escape($Login) + '"') {
                return $match.Groups['id'].Value
            }
        }

        $first = [regex]::Match($text,'"(\d{17})"')
        if ($first.Success) { return $first.Groups[1].Value }
        return ''
    } catch {
        Write-CcError -FunctionName 'Get-CcSteamId64' -Exception $_.Exception
        return ''
    }
}

function Test-CcSteamAccount {
    param([object]$Account,[string]$ApiKey)
    try {
        if ([string]::IsNullOrWhiteSpace($ApiKey)) {
            return [pscustomobject]@{Ok=$false;Reason='STEAM_API_KEY is not configured';Library=@();Banned=$false;BanText=''}
        }

        $exe = Get-CcSteamExe
        if (-not $exe) {
            return [pscustomobject]@{Ok=$false;Reason='Steam not installed';Library=@();Banned=$false;BanText=''}
        }

        $root = Split-Path $exe -Parent
        $steamId = Get-CcSteamId64 -SteamRoot $root -Login $Account.Login
        if (-not $steamId) {
            return [pscustomobject]@{Ok=$false;Reason='SteamID64 not found in loginusers.vdf';Library=@();Banned=$false;BanText=''}
        }

        $headers=@{'User-Agent'='CyberCroc/0.4'}
        $gamesUri="https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=$ApiKey&steamid=$steamId&include_appinfo=1&include_played_free_games=1"
        $banUri="https://api.steampowered.com/ISteamUser/GetPlayerBans/v1/?key=$ApiKey&steamids=$steamId"
        $gamesResponse=Invoke-RestMethod -Uri $gamesUri -Headers $headers -TimeoutSec 20
        $banResponse=Invoke-RestMethod -Uri $banUri -Headers $headers -TimeoutSec 20

        $library=@($gamesResponse.response.games | ForEach-Object {
            [pscustomobject]@{Name=$_.name;Hours=[math]::Round(([double]$_.playtime_forever/60),1)}
        })

        $banPlayer=$banResponse.players | Select-Object -First 1
        $banned=$false
        $banText=''
        if ($null -ne $banPlayer) {
            $banned=[bool]($banPlayer.VACBanned -or $banPlayer.NumberOfGameBans)
            $banText="VAC=$($banPlayer.VACBanned); GameBans=$($banPlayer.NumberOfGameBans)"
        }

        return [pscustomobject]@{Ok=$true;Reason='OK';Library=$library;Banned=$banned;BanText=$banText}
    } catch {
        Write-CcError -FunctionName 'Test-CcSteamAccount' -Exception $_.Exception
        return [pscustomobject]@{Ok=$false;Reason=$_.Exception.Message;Library=@();Banned=$false;BanText=''}
    }
}

function Test-CcAccount {
    param([object]$Account,[hashtable]$Config)
    try {
        if ($Account.Platform -eq 'Steam') {
            $apiKey=''
            if ($Config.ContainsKey('STEAM_API_KEY')) { $apiKey=[string]$Config['STEAM_API_KEY'] }
            $result=Test-CcSteamAccount -Account $Account -ApiKey $apiKey
        } else {
            $result=[pscustomobject]@{Ok=$false;Reason='Public API does not provide a reliable account library/ban check for this platform';Library=@();Banned=$false;BanText=''}
        }

        $Account.LastCheck=(Get-Date).ToString('s')
        $Account.Library=@($result.Library)
        $Account.Banned=[bool]$result.Banned
        $Account.BanText=[string]$result.BanText
        if ($result.Banned) { $Account.Status='ban' }
        elseif ($result.Ok) { $Account.Status='free' }
        else { $Account.Status='not_checked' }

        if (-not $result.Ok -and [string]::IsNullOrWhiteSpace([string]$Account.Comment)) {
            $Account.Comment="Check: $($result.Reason)"
        }

        Write-CcLog "Account check: $($Account.Platform)/$($Account.Login) => $($Account.Status)" $(if($result.Ok){'OK'}else{'WARN'}) 'Test-CcAccount'
        return $result
    } catch {
        Write-CcError -FunctionName 'Test-CcAccount' -Exception $_.Exception
        return $null
    }
}

function Start-CcAccountSession {
    param([object]$Account)
    try {
        switch ($Account.Platform) {
            'Steam' {
                $exe=Get-CcSteamExe
                if (-not $exe) { throw 'Steam not found' }
                # Never decrypt or pass a foreign account password through the process command line.
                Start-Process -FilePath $exe -ArgumentList @('-silent') -WindowStyle Hidden | Out-Null
            }
            'Riot Games' {
                $exe=Get-CcLauncherExe 'RiotClientServices.exe'
                if (-not $exe) { throw 'Riot Client not found' }
                Start-Process -FilePath $exe -ArgumentList @('--launch-product=league_of_legends','--launch-patchline=live') -WindowStyle Hidden | Out-Null
            }
            'Battle.net' {
                $exe=Get-CcLauncherExe 'Battle.net.exe'
                if (-not $exe) { throw 'Battle.net not found' }
                Start-Process -FilePath $exe -ArgumentList @('--exec=launch') -WindowStyle Hidden | Out-Null
            }
            'Epic Games' {
                $exe=Get-CcLauncherExe 'EpicGamesLauncher.exe'
                if (-not $exe) { throw 'Epic Games Launcher not found' }
                Start-Process -FilePath $exe -WindowStyle Hidden | Out-Null
            }
            default { throw "Unsupported platform: $($Account.Platform)" }
        }

        $Account.Status='occupied'
        $Account.UsedBy=$env:USERNAME
        $Account.UsedSince=(Get-Date).ToString('s')
        Write-CcLog "Account session started: $($Account.Platform)/$($Account.Login)" 'OK' 'Start-CcAccountSession'
        return $true
    } catch {
        Write-CcError -FunctionName 'Start-CcAccountSession' -Exception $_.Exception
        return $false
    }
}

function Get-CcLauncherExe {
    param([string]$Name)
    try {
        $roots=@($env:ProgramFiles,$env:ProgramFilesX86,$env:ProgramData,$env:LOCALAPPDATA,$env:APPDATA) | Where-Object { $_ }
        foreach ($root in $roots) {
            $hit=Get-ChildItem -LiteralPath $root -Filter $Name -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
        return $null
    } catch {
        Write-CcError -FunctionName 'Get-CcLauncherExe' -Exception $_.Exception
        return $null
    }
}

Initialize-CcAccounts
