<# CyberCroc Games - SMB game catalog and patch management. PowerShell 5.1 compatible.  #>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')
function Get-CcGamesConfig { try { $cfg=Get-CcConfig; [pscustomobject]@{Share=[string]$cfg['GAMES_SHARE'];SourceUrl=[string]$cfg['GAMES_SOURCE_URL'];Cache=Join-Path $script:CcRoot 'games-cache.json'} } catch { Write-CcError -FunctionName 'Get-CcGamesConfig' -Exception $_.Exception; return [pscustomobject]@{Share='';Cache=(Join-Path $script:CcRoot 'games-cache.json')} } }
function Convert-CcGameRecord([object]$Game) { [pscustomobject]@{Id=[string]$Game.Id;Name=[string]$Game.Name;InstallPath=[string]$Game.InstallPath;Launcher=[string]$Game.Launcher;AppId=[string]$Game.AppId;LatestPatch=[string]$Game.LatestPatch;Source=[string]$Game.Source;SizeGB=if($Game.SizeGB){[double]$Game.SizeGB}else{0}} }
function Get-CcGameLauncherInfo([string]$Launcher){
    $n=([string]$Launcher).Trim().ToLowerInvariant()
    switch -Regex ($n) {
        '^steam$' { return [pscustomobject]@{Name='Steam';Type='Exe';InstallerUrl='https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe';InstallerName='SteamSetup.exe';ExeNames=@('steam.exe');Page='https://store.steampowered.com/about/'} }
        '^epic games$|^epic$' { return [pscustomobject]@{Name='Epic Games Launcher';Type='Msi';InstallerUrl='https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi';InstallerName='EpicGamesLauncherInstaller.msi';ExeNames=@('EpicGamesLauncher.exe');Page='https://store.epicgames.com/download'} }
        '^riot games$|^riot$' { return [pscustomobject]@{Name='Riot Client';Type='Web';InstallerUrl='https://www.riotgames.com/en/download';InstallerName='';ExeNames=@('RiotClientServices.exe');Page='https://www.riotgames.com/en/download'} }
        '^battle.net$|^battle$' { return [pscustomobject]@{Name='Battle.net';Type='Web';InstallerUrl='https://download.battle.net/en-us/desktop';InstallerName='';ExeNames=@('Battle.net.exe');Page='https://download.battle.net/en-us/desktop'} }
        '^ea app$|^ea$' { return [pscustomobject]@{Name='EA app';Type='Web';InstallerUrl='https://www.ea.com/ea-app';InstallerName='';ExeNames=@('EADesktop.exe','EALauncher.exe');Page='https://www.ea.com/ea-app'} }
        '^rockstar games$|^rockstar$' { return [pscustomobject]@{Name='Rockstar Games Launcher';Type='Web';InstallerUrl='https://socialclub.rockstargames.com/rockstar-games-launcher';InstallerName='';ExeNames=@('Launcher.exe');Page='https://socialclub.rockstargames.com/rockstar-games-launcher'} }
        '^vk play$|^vk$' { return [pscustomobject]@{Name='VK Play';Type='Web';InstallerUrl='https://vkplay.ru/';InstallerName='';ExeNames=@('GameCenter.exe');Page='https://vkplay.ru/'} }
        '^wargaming$' { return [pscustomobject]@{Name='Wargaming Game Center';Type='Web';InstallerUrl='https://eu.wargaming.net/wgc/';InstallerName='';ExeNames=@('wgc.exe');Page='https://eu.wargaming.net/wgc/'} }
        '^hoyoplay$|^hoyo$' { return [pscustomobject]@{Name='HoYoPlay';Type='Web';InstallerUrl='https://hoyoplay.hoyoverse.com/';InstallerName='';ExeNames=@('launcher.exe');Page='https://hoyoplay.hoyoverse.com/'} }
        '^legacy launcher$|^minecraft legacy$|^minecraft$' { return [pscustomobject]@{Name='Legacy Launcher';Type='Exe';InstallerUrl='https://dl.llaun.ch/legacy/installer';InstallerName='LegacyLauncherSetup.exe';ExeNames=@('TL.exe','LegacyLauncher.exe');Page='https://llaun.ch/EN'} }
        '^roblox$|^roblox - windows$' { return [pscustomobject]@{Name='Roblox - Windows';Type='Store';InstallerUrl='ms-windows-store://pdp/?productid=9PMF91N3LZ3M';InstallerName='';ExeNames=@('RobloxPlayerBeta.exe','Roblox.exe');Page='https://apps.microsoft.com/detail/9PMF91N3LZ3M'} }
        default { return [pscustomobject]@{Name=[string]$Launcher;Type='Web';InstallerUrl='';InstallerName='';ExeNames=@();Page=''} }
    }
}
function Find-CcLauncherExe([string[]]$Names){
    foreach($name in @($Names)){try{$x=Get-CcLauncherExe $name;if($x){return [string]$x}}catch{}}
    return ''
}
function Install-CcGameLauncher([object]$Game){
    try{
        $info=Get-CcGameLauncherInfo ([string]$Game.Launcher)
        $existing=Find-CcLauncherExe $info.ExeNames
        if($existing){Write-CcLog "Launcher already installed: $($info.Name) -> $existing" 'OK' 'Install-CcGameLauncher';return $existing}
        if($info.Type -eq 'Store'){try{$winget=Get-Command winget.exe -ErrorAction Stop;$p=Start-Process -FilePath $winget.Source -ArgumentList @('install','--id','9PMF91N3LZ3M','-e','--source','msstore','--accept-source-agreements','--accept-package-agreements') -Wait -PassThru;if($p.ExitCode -eq 0){Write-CcLog "Roblox - Windows installed via Microsoft Store/winget" 'OK' 'Install-CcGameLauncher';return ''}}catch{Write-CcLog "winget Roblox install unavailable: $($_.Exception.Message)" 'WARN' 'Install-CcGameLauncher'};Start-Process -FilePath $info.InstallerUrl;Write-CcLog "Opened Microsoft Store for launcher: $($info.Name)" 'INFO' 'Install-CcGameLauncher';return ''}
        if($info.Type -eq 'Web'){if([string]::IsNullOrWhiteSpace($info.InstallerUrl)){throw "Ссылка на установку лаунчера $($info.Name) не задана."};Start-Process $info.InstallerUrl;Write-CcLog "Opened launcher download page: $($info.Name)" 'INFO' 'Install-CcGameLauncher';return ''}
        $tmpRoot=Join-Path $env:TEMP 'CyberCroc\Launchers'
        New-Item -ItemType Directory -Path $tmpRoot -Force|Out-Null
        $installer=Join-Path $tmpRoot $info.InstallerName
        Write-CcLog "Downloading launcher: $($info.Name) -> $installer" 'INFO' 'Install-CcGameLauncher'
        $wc=New-Object System.Net.WebClient
        try{$wc.DownloadFile($info.InstallerUrl,$installer)}finally{$wc.Dispose()}
        if(-not(Test-Path -LiteralPath $installer)){throw "Не удалось скачать установщик: $($info.Name)"}
        $p=Start-Process -FilePath $installer -Wait -PassThru
        if($p.ExitCode -ne 0){throw "Установка $($info.Name) завершилась с кодом $($p.ExitCode)."}
        Start-Sleep -Seconds 2
        return (Find-CcLauncherExe $info.ExeNames)
    }catch{Write-CcError -FunctionName 'Install-CcGameLauncher' -Exception $_.Exception;throw}
}
function Start-CcGame([object]$Game){
    $launcher=[string]$Game.Launcher
    switch -Regex ($launcher.ToLowerInvariant()){
        '^steam$' {if(-not $Game.AppId){throw "Для Steam-игры $($Game.Name) не задан AppID."};Start-Process "steam://rungameid/$($Game.AppId)";return}
        '^epic games$|^epic$' {Start-Process 'com.epicgames.launcher://apps';return}
        '^roblox' {Start-Process 'roblox-player:';return}
        '^riot games$|^riot$' {$x=Find-CcLauncherExe @('RiotClientServices.exe');if($x){Start-Process $x}else{Start-Process 'https://www.riotgames.com/en/download'};return}
        '^battle.net$|^battle$' {$x=Find-CcLauncherExe @('Battle.net.exe');if($x){Start-Process $x}else{Start-Process 'https://download.battle.net/en-us/desktop'};return}
        '^ea app$|^ea$' {$x=Find-CcLauncherExe @('EADesktop.exe','EALauncher.exe');if($x){Start-Process $x}else{Start-Process 'https://www.ea.com/ea-app'};return}
        '^rockstar games$|^rockstar$' {$x=Find-CcLauncherExe @('Launcher.exe');if($x){Start-Process $x}else{Start-Process 'https://socialclub.rockstargames.com/rockstar-games-launcher'};return}
        '^vk play$|^vk$' {$x=Find-CcLauncherExe @('GameCenter.exe');if($x){Start-Process $x}else{Start-Process 'https://vkplay.ru/'};return}
        '^wargaming$' {$x=Find-CcLauncherExe @('wgc.exe');if($x){Start-Process $x}else{Start-Process 'https://eu.wargaming.net/wgc/'};return}
        '^hoyoplay$|^hoyo$' {$x=Find-CcLauncherExe @('launcher.exe');if($x){Start-Process $x}else{Start-Process 'https://hoyoplay.hoyoverse.com/'};return}
        '^legacy launcher$|^minecraft legacy$|^minecraft$' {$x=Find-CcLauncherExe @('TL.exe','LegacyLauncher.exe');if($x){Start-Process $x}else{Start-Process 'https://llaun.ch/EN'};return}
        default {if($Game.PathCheck -and (Test-Path -LiteralPath (Expand-CcPath $Game.PathCheck))){Start-Process (Expand-CcPath $Game.PathCheck);return};throw "Для игры $($Game.Name) не настроен запуск."}
    }
}
function Get-CcGamesFromJson([string]$Path) { try { if(-not(Test-Path -LiteralPath $Path)){throw "games.json not found: $Path"};$json=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json;$items=if($json.Games){@($json.Games)}else{@($json)};return @($items|ForEach-Object{Convert-CcGameRecord $_}) } catch { Write-CcError -FunctionName 'Get-CcGamesFromJson' -Exception $_.Exception;return @() } }
function Get-CcGamesCatalog([switch]$ForceRefresh) { try { $c=Get-CcGamesConfig;$remote=if($c.Share){Join-Path $c.Share 'games.json'}else{''};if($remote -and (Test-Path -LiteralPath $remote) -and ($ForceRefresh -or -not(Test-Path -LiteralPath $c.Cache) -or (Get-Item $remote).LastWriteTimeUtc -gt (Get-Item $c.Cache).LastWriteTimeUtc)){ $items=Get-CcGamesFromJson $remote;if($items.Count){$items|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $c.Cache -Encoding UTF8;Write-CcLog "Games catalog pulled from SMB: $remote ($($items.Count))" 'OK' 'Get-CcGamesCatalog';return $items}};if($c.SourceUrl){try{$web=(Invoke-WebRequest -Uri $c.SourceUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop).Content;$items=@((ConvertFrom-Json $web).Games);if($items.Count){$items=@($items|ForEach-Object{Convert-CcGameRecord $_});$items|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $c.Cache -Encoding UTF8;Write-CcLog "Games catalog pulled from URL: $($c.SourceUrl)" 'OK' 'Get-CcGamesCatalog';return $items}}catch{Write-CcLog "Games URL refresh failed: $($_.Exception.Message)" 'WARN' 'Get-CcGamesCatalog'}};if(Test-Path -LiteralPath $c.Cache){return @(Get-CcGamesFromJson $c.Cache)};return @() } catch { Write-CcError -FunctionName 'Get-CcGamesCatalog' -Exception $_.Exception;return @() } }
function Get-CcGameStatus([object]$Game) { try { $path=Expand-CcPath $Game.InstallPath;$installed=Test-Path -LiteralPath $path;$installedPatch='';$marker=Join-Path $path 'cybercroc.patch';if($installed -and (Test-Path -LiteralPath $marker)){$installedPatch=(Get-Content $marker -Raw -ErrorAction SilentlyContinue).Trim()};if(-not $installed){$installedPatch='Not installed'};$state=if(-not $installed){'NotInstalled'}elseif($Game.LatestPatch -and $installedPatch -ne [string]$Game.LatestPatch){'UpdateRequired'}else{'Latest'};return [pscustomobject]@{Id=$Game.Id;Name=$Game.Name;Installed=$installed;LatestPatch=[string]$Game.LatestPatch;InstalledPatch=$installedPatch;Status=$state} } catch { Write-CcError -FunctionName 'Get-CcGameStatus' -Exception $_.Exception;return [pscustomobject]@{Id=$Game.Id;Name=$Game.Name;Installed=$false;LatestPatch=[string]$Game.LatestPatch;InstalledPatch='Error';Status='Error'} } }
function Install-CcGame([object]$Game) {
    try {$launcherPath=Install-CcGameLauncher $Game;if($launcherPath){Write-CcLog "Launcher ready for game: $($Game.Name)" 'OK' 'Install-CcGame'};return $true}
    catch {Write-CcError -FunctionName 'Install-CcGame' -Exception $_.Exception;return $false}
}
function Update-CcGame([object]$Game) { return Install-CcGame $Game }
function Update-CcGamesCatalogDaily { try { $marker=Join-Path $script:CcRoot 'games-sync.txt';$today=(Get-Date).ToString('yyyy-MM-dd');$last=if(Test-Path $marker){(Get-Content $marker -Raw).Trim()}else{''};if($last -ne $today){$items=Get-CcGamesCatalog -ForceRefresh;Set-Content -LiteralPath $marker -Value $today -Encoding ASCII;return $items};return @(Get-CcGamesCatalog) } catch { Write-CcError -FunctionName 'Update-CcGamesCatalogDaily' -Exception $_.Exception;return @() } }