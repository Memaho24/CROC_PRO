$ErrorActionPreference='Stop'
trap {
    try {
        $logDir = Join-Path $PSScriptRoot 'logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $inv = $_.InvocationInfo
        $position = if ($inv) { $inv.PositionMessage } else { '' }
        $scriptName = if ($inv -and $inv.ScriptName) { $inv.ScriptName } else { 'CyberCroc.ps1' }
        $lineNumber = if ($inv -and $inv.ScriptLineNumber) { [string]$inv.ScriptLineNumber } else { '?' }
        $stack = if ($inv -and $inv.ScriptStackTrace) { $inv.ScriptStackTrace } else { $_.ScriptStackTrace }
        $line = '[{0}] [FATAL] [{1}:{2}] {3} :: {4}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $scriptName, $lineNumber, $_.Exception.GetType().FullName, $_.Exception.Message
        Add-Content -LiteralPath (Join-Path $logDir 'errors.log') -Value ($line + "`r`nPosition: " + $position + "`r`nStack: " + $stack) -Encoding UTF8
    } catch {}
    throw
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Root=$PSScriptRoot
$Developer='Eduard'
$Tools=Join-Path $Root 'tools'
. (Join-Path $Tools 'Core.ps1')
. (Join-Path $Tools 'Accounts.ps1')
. (Join-Path $Tools 'Hardware.ps1')

try{
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({param($sender,$args) Write-CcError -FunctionName 'WinForms.ThreadException' -Exception $args.Exception;[void][Windows.Forms.MessageBox]::Show("Ошибка программы.`n`n$($args.Exception.Message)`n`nПодробности записаны в logs\\errors.log.",'CyberCroc — ошибка',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)})
    [AppDomain]::CurrentDomain.add_UnhandledException({param($sender,$args) if($args.ExceptionObject -is [Exception]){Write-CcError -FunctionName 'AppDomain.UnhandledException' -Exception $args.ExceptionObject}})
}catch{}

function Get-CcStartupConfig {
    param([string]$Path)
    $result=@{}
    try{
        if(Test-Path -LiteralPath $Path){
            foreach($raw in Get-Content -LiteralPath $Path -Encoding UTF8){
                $line=$raw.Trim()
                if(-not $line -or $line -match '^[#;]'){continue}
                $eq=$line.IndexOf('=')
                if($eq -lt 1){continue}
                $key=$line.Substring(0,$eq).Trim().ToUpperInvariant()
                $value=$line.Substring($eq+1).Trim()
                $result[$key]=$value
            }
        }
    }catch{
        Write-CcError -FunctionName 'Get-CcStartupConfig' -Exception $_.Exception
    }
    return $result
}

# Read startup configuration independently of the shared Core implementation.
# This prevents an old/mismatched Core.ps1 from turning $cfg into a CIM object.
$cfg=Get-CcStartupConfig (Join-Path $Root 'config.ini')
if(-not $cfg.ContainsKey('THEME')){
    $cfg['THEME']='dark'
}
$Version='0.0.0'
try{
    $versionFile=Join-Path $Root 'version.txt'
    if(Test-Path -LiteralPath $versionFile){
        $Version=(Get-Content -LiteralPath $versionFile -Raw -ErrorAction Stop).Trim()
    }
}catch{
    Write-CcLog "version.txt read failed: $($_.Exception.Message)" 'WARN' 'Startup'
}
if([string]::IsNullOrWhiteSpace($Version)){
    $Version='0.0.0'
}

# GitHub update settings. The application is fully portable: everything is resolved from $PSScriptRoot.
$GithubRepo='Memaho24/CROC_PRO'
$GithubBranch='main'
$GithubVersionUrl="https://raw.githubusercontent.com/$GithubRepo/$GithubBranch/version.txt"
$GithubUpdateScript=Join-Path $Tools 'Updater.ps1'

function Get-CcGithubVersion {
    try {
        $r=Invoke-WebRequest -Uri $GithubVersionUrl -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $v=([string]$r.Content).Trim()
        if($v -and $v -match '^\d+(\.\d+){1,3}$'){ return $v }
    } catch {
        Write-CcLog "GitHub version check skipped: $($_.Exception.Message)" 'WARN' 'Get-CcGithubVersion'
    }
    return ''
}
function Test-CcGithubUpdate {
    try {
        $remote=Get-CcGithubVersion
        if([string]::IsNullOrWhiteSpace($remote)){ return $null }
        $cmp=Compare-CcVersion $remote $Version
        return [pscustomobject]@{Available=($cmp -gt 0);Local=$Version;Remote=$remote;Repo=$GithubRepo;Branch=$GithubBranch}
    } catch {
        Write-CcError -FunctionName 'Test-CcGithubUpdate' -Exception $_.Exception
        return $null
    }
}
function Start-CcGithubUpdate {
    try {
        if(-not(Test-Path -LiteralPath $GithubUpdateScript)){ throw "Updater.ps1 not found: $GithubUpdateScript" }
        $args=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"{0}"' -f $GithubUpdateScript),'-Apply','-Github','-Repo',$GithubRepo,'-Branch',$GithubBranch,'-WaitPid',$PID)
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $args -WindowStyle Hidden | Out-Null
        Write-CcLog "GitHub update accepted: $Version -> remote main" 'INFO' 'Start-CcGithubUpdate'
        return $true
    } catch {
        Write-CcError -FunctionName 'Start-CcGithubUpdate' -Exception $_.Exception
        return $false
    }
}
function Invoke-CcStartupUpdateCheck {
    try {
        $u=Test-CcGithubUpdate
        if(-not $u -or -not $u.Available){ return $false }
        $answer=[System.Windows.Forms.MessageBox]::Show("Доступна новая версия CyberCroc.`r`n`r`nУстановлена: $($u.Local)`r`nНовая: $($u.Remote)`r`n`r`nОбновить программу сейчас?",'CyberCroc — доступно обновление',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Information)
        if($answer -ne [System.Windows.Forms.DialogResult]::Yes){
            Write-CcLog "GitHub update declined: local=$($u.Local) remote=$($u.Remote)" 'INFO' 'Invoke-CcStartupUpdateCheck'
            return $false
        }
        if(Start-CcGithubUpdate){ return $true }
        [void][System.Windows.Forms.MessageBox]::Show('Не удалось запустить обновление. CyberCroc продолжит запуск без обновления.','CyberCroc',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning)
        return $false
    } catch {
        Write-CcError -FunctionName 'Invoke-CcStartupUpdateCheck' -Exception $_.Exception
        return $false
    }
}

$ThemeName=if($cfg['THEME']){$cfg['THEME']}else{'dark'}
if(Invoke-CcStartupUpdateCheck){exit 0}

$C=@{}
$C.Accent=[Drawing.Color]::FromArgb(57,255,20)
$C.AccentDark=[Drawing.Color]::FromArgb(25,150,15)
$C.Bg=[Drawing.Color]::Black
$C.Panel=[Drawing.Color]::FromArgb(10,10,10)
$C.Control=[Drawing.Color]::FromArgb(26,26,26)
$C.Fg=$C.Accent
$C.Muted=[Drawing.Color]::FromArgb(125,145,125)
$C.White=[Drawing.Color]::White
$C['Danger']=[Drawing.Color]::FromArgb(255,80,80)
$C['Warning']=[Drawing.Color]::FromArgb(255,190,50)

function Set-Theme([string]$Name){
    $script:ThemeName=$Name
    if($Name -eq 'light'){
        $C.Bg=[Drawing.Color]::FromArgb(245,245,245);$C.Panel=[Drawing.Color]::White;$C.Control=[Drawing.Color]::FromArgb(232,232,232);$C.Fg=[Drawing.Color]::FromArgb(25,25,25);$C.Muted=[Drawing.Color]::FromArgb(90,90,90);$C.White=[Drawing.Color]::FromArgb(25,25,25)
    }elseif($Name -eq 'neon'){
        $C.Bg=[Drawing.Color]::FromArgb(2,8,2);$C.Panel=[Drawing.Color]::FromArgb(5,18,5);$C.Control=[Drawing.Color]::FromArgb(10,35,10);$C.Fg=[Drawing.Color]::FromArgb(80,255,80);$C.Muted=[Drawing.Color]::FromArgb(110,180,110);$C.White=[Drawing.Color]::White
    }else{
        $C.Bg=[Drawing.Color]::Black;$C.Panel=[Drawing.Color]::FromArgb(10,10,10);$C.Control=[Drawing.Color]::FromArgb(26,26,26);$C.Fg=[Drawing.Color]::FromArgb(57,255,20);$C.Muted=[Drawing.Color]::FromArgb(125,145,125);$C.White=[Drawing.Color]::White
    }
}
Set-Theme $ThemeName

$form=New-Object Windows.Forms.Form
$form.Text="🐊 CyberCroc 🐊 — управление ПК";$form.StartPosition='CenterScreen';$form.WindowState='Maximized';$form.MinimumSize=New-Object Drawing.Size(1100,700);$form.BackColor=$C.Bg;$form.ForeColor=$C.Fg;$form.Font=New-Object Drawing.Font('Segoe UI',10)

function New-Label([string]$Text,[int]$Size=10,[System.Drawing.FontStyle]$Style='Regular'){
    $x=New-Object Windows.Forms.Label;$x.Text=$Text;$x.AutoSize=$true;$x.Font=New-Object Drawing.Font('Segoe UI',$Size,$Style);$x.ForeColor=$C.Fg;return $x
}
function New-Button([string]$Text,[int]$Width=190,[int]$Height=48){
    $x=New-Object Windows.Forms.Button;$x.Text=$Text;$x.Width=$Width;$x.Height=$Height;$x.Margin=New-Object Windows.Forms.Padding(6);$x.FlatStyle='Flat';$x.FlatAppearance.BorderSize=1;$x.FlatAppearance.BorderColor=$C.Fg;if($x -is [Windows.Forms.Label]){$x.BackColor=[Drawing.Color]::Transparent;$x.ForeColor=$C.Fg}else{$x.BackColor=$C.Control;$x.ForeColor=$C.Fg};$x.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold);$x.Cursor=[Windows.Forms.Cursors]::Hand;return $x
}
function New-PageTitle([string]$Title,[string]$Hint){
    $p=New-Object Windows.Forms.Panel;$p.Dock='Top';$p.Height=82;$p.BackColor=$C.Panel
    $t=New-Label $Title 22 'Bold';$t.Location=New-Object Drawing.Point(24,14);$p.Controls.Add($t)
    $h=New-Label $Hint 10;$h.ForeColor=$C.Muted;$h.Location=New-Object Drawing.Point(26,50);$p.Controls.Add($h);return $p
}
function New-Card([string]$Title,[string]$Value,[string]$Hint){
    $p=New-Object Windows.Forms.Panel;$p.Width=235;$p.Height=125;$p.Margin=New-Object Windows.Forms.Padding(8);$p.BackColor=$C.Panel;$p.BorderStyle='FixedSingle'
    $a=New-Label $Title 10 'Bold';$a.ForeColor=$C.Muted;$a.Location=New-Object Drawing.Point(15,13);$p.Controls.Add($a)
    $v=New-Label $Value 23 'Bold';$v.Location=New-Object Drawing.Point(15,39);$p.Controls.Add($v)
    $h=New-Label $Hint 9;$h.ForeColor=$C.Muted;$h.Location=New-Object Drawing.Point(15,88);$p.Controls.Add($h);return $p
}
function New-Flow([string]$Direction='LeftToRight'){
    $p=New-Object Windows.Forms.FlowLayoutPanel;$p.Dock='Fill';$p.AutoScroll=$true;$p.WrapContents=$true;$p.Padding=New-Object Windows.Forms.Padding(18);$p.FlowDirection=$Direction;$p.BackColor=$C.Bg;return $p
}
function Toast($Title,$Message,$Level='INFO'){Show-CcToast $Title $Message $Level}
function Show-CcErrorPopup([string]$Title,[System.Exception]$Exception){try{Write-CcError -FunctionName $Title -Exception $Exception;[void][Windows.Forms.MessageBox]::Show("Операция не выполнена.`n`n$($Exception.Message)`n`nПодробности записаны в logs\\errors.log.",'CyberCroc — ошибка',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)}catch{}}
function Apply-ControlTheme([Windows.Forms.Control]$x){
    try{
        $x.BackColor=$C.Control;$x.ForeColor=$C.Fg
        if($x -is [Windows.Forms.Button]){$x.FlatStyle='Flat';$x.FlatAppearance.BorderColor=$C.Fg;$x.FlatAppearance.BorderSize=1}
        foreach($child in $x.Controls){Apply-ControlTheme $child}
    }catch{}
}

# Application shell
$shell=New-Object Windows.Forms.TableLayoutPanel;$shell.Dock='Fill';$shell.ColumnCount=2;$shell.RowCount=2
[void]$shell.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,220)));[void]$shell.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$shell.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$shell.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,32)));$form.Controls.Add($shell)

$nav=New-Object Windows.Forms.Panel;$nav.Dock='Fill';$nav.BackColor=$C.Panel;$nav.Padding=New-Object Windows.Forms.Padding(12,18,12,12);$shell.Controls.Add($nav,0,0)
$brand=New-Label '🐊 CYBER CROC 🐊' 20 'Bold';$brand.ForeColor=$C.Accent;$brand.Location=New-Object Drawing.Point(18,16);$nav.Controls.Add($brand)
$brand2=New-Label "Разработчик: Эдуард  |  Патч: $Version" 8 'Bold';$brand2.ForeColor=$C.Muted;$brand2.Location=New-Object Drawing.Point(20,49);$brand2.AutoSize=$true;$nav.Controls.Add($brand2)
$menu=New-Object Windows.Forms.FlowLayoutPanel;$menu.Location=New-Object Drawing.Point(12,92);$menu.Size=New-Object Drawing.Size(196,520);$menu.FlowDirection='TopDown';$menu.WrapContents=$false;$menu.AutoScroll=$true;$menu.BackColor=$C.Panel;$nav.Controls.Add($menu)

$content=New-Object Windows.Forms.Panel;$content.Dock='Fill';$content.BackColor=$C.Bg;$shell.Controls.Add($content,1,0)
$footer=New-Label "ПК: $env:COMPUTERNAME   •   CyberCroc $Version" 9;$footer.ForeColor=$C.Muted;$footer.TextAlign='MiddleLeft';$footer.Dock='Fill';$footer.Padding=New-Object Windows.Forms.Padding(14,0,0,0);$shell.Controls.Add($footer,0,1);$shell.SetColumnSpan($footer,2)
$clock=New-Label '' 9;$clock.ForeColor=$C.Muted;$clock.AutoSize=$false;$clock.Dock='Right';$clock.Width=90;$clock.TextAlign='MiddleRight';$footer.Controls.Add($clock)
$progress=New-Object Windows.Forms.ProgressBar;$progress.Style='Marquee';$progress.Visible=$false;$progress.Width=180;$progress.Height=14;$footer.Controls.Add($progress)

$pages=@{};$navButtons=@{}
function Clear-Content{$content.Controls.Clear()}
function Add-MenuButton([string]$Key,[string]$Text){
    $b=New-Button $Text 190 46;$b.TextAlign='MiddleLeft';$b.Padding=New-Object Windows.Forms.Padding(14,0,0,0);$b.Tag=$Key;$menu.Controls.Add($b);$navButtons[$Key]=$b;$b.Add_Click({param($sender,$eventArgs) Show-Page ([string]$sender.Tag)})
}
function Show-Page([string]$Key){
    try{
        if(-not $pages.ContainsKey($Key)){return};Clear-Content;$content.Controls.Add($pages[$Key])
        foreach($k in $navButtons.Keys){$navButtons[$k].BackColor=$C.Control;$navButtons[$k].ForeColor=$C.Fg}
        $navButtons[$Key].BackColor=$C.AccentDark;$navButtons[$Key].ForeColor=$C.White
    }catch{Write-CcError -FunctionName 'Show-Page' -Exception $_.Exception}
}

# Home
$homePage=New-Object Windows.Forms.Panel;$homePage.Dock='Fill';$homePage.BackColor=$C.Bg
$homePage.Controls.Add((New-PageTitle 'Главная' 'Здесь собрана вся важная информация о компьютере.'))
$homeBody=New-Object Windows.Forms.TableLayoutPanel;$homeBody.Dock='Fill';$homeBody.Padding=New-Object Windows.Forms.Padding(22,96,22,18);$homeBody.ColumnCount=2;$homeBody.RowCount=4;$homeBody.BackColor=$C.Bg;$homePage.Controls.Add($homeBody)
[void]$homeBody.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,50)))
[void]$homeBody.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,50)))
[void]$homeBody.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,92)))
[void]$homeBody.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,150)))
[void]$homeBody.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$homeBody.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,86)))
$welcome=New-Object Windows.Forms.Panel;$welcome.Dock='Fill';$welcome.Margin=New-Object Windows.Forms.Padding(6);$welcome.BackColor=$C.Panel;$homeBody.Controls.Add($welcome,0,0);$homeBody.SetColumnSpan($welcome,2)
$wl=New-Label '🐊  ПК $env:COMPUTERNAME готов к работе' 18 'Bold';$wl.Location=New-Object Drawing.Point(18,12);$welcome.Controls.Add($wl)
$wh=New-Label 'Зелёный статус = всё нормально. Если что-то красное — нажмите «Проверить ПК».' 10;$wh.ForeColor=$C.Muted;$wh.Location=New-Object Drawing.Point(20,50);$welcome.Controls.Add($wh)
$pcInfo=New-Object Windows.Forms.Panel;$pcInfo.Dock='Fill';$pcInfo.Margin=New-Object Windows.Forms.Padding(6);$pcInfo.BackColor=$C.Panel;$homeBody.Controls.Add($pcInfo,0,1)
$pcTitle=New-Label '🖥  ЭТОТ КОМПЬЮТЕР' 12 'Bold';$pcTitle.Location=New-Object Drawing.Point(16,12);$pcInfo.Controls.Add($pcTitle)
$pcDetails=New-Label 'Получение данных...' 9;$pcDetails.Location=New-Object Drawing.Point(18,42);$pcDetails.Size=New-Object Drawing.Size(500,100);$pcDetails.AutoSize=$false;$pcInfo.Controls.Add($pcDetails)
$diskInfo=New-Object Windows.Forms.Panel;$diskInfo.Dock='Fill';$diskInfo.Margin=New-Object Windows.Forms.Padding(6);$diskInfo.BackColor=$C.Panel;$homeBody.Controls.Add($diskInfo,1,1)
$diskTitle=New-Label '💾  ДИСКИ' 12 'Bold';$diskTitle.Location=New-Object Drawing.Point(16,12);$diskInfo.Controls.Add($diskTitle)
$diskDetails=New-Label 'Получение данных...' 9;$diskDetails.Location=New-Object Drawing.Point(18,42);$diskDetails.Size=New-Object Drawing.Size(500,100);$diskDetails.AutoSize=$false;$diskInfo.Controls.Add($diskDetails)
$health=New-Object Windows.Forms.Panel;$health.Dock='Fill';$health.Margin=New-Object Windows.Forms.Padding(6);$health.BackColor=$C.Panel;$homeBody.Controls.Add($health,0,2);$homeBody.SetColumnSpan($health,2)
$healthTitle=New-Label '🛡  СОСТОЯНИЕ ПК' 12 'Bold';$healthTitle.Location=New-Object Drawing.Point(16,12);$health.Controls.Add($healthTitle)
$healthText=New-Label 'Нажмите «Проверить ПК», чтобы проверить компьютер.' 10;$healthText.Location=New-Object Drawing.Point(18,45);$healthText.AutoSize=$true;$health.Controls.Add($healthText)
$homeActions=New-Object Windows.Forms.FlowLayoutPanel;$homeActions.Dock='Fill';$homeActions.Margin=New-Object Windows.Forms.Padding(6);$homeActions.BackColor=$C.Bg;$homeBody.Controls.Add($homeActions,0,3);$homeBody.SetColumnSpan($homeActions,2)
$homeCheck=New-Button '🔍  ПРОВЕРИТЬ ПК' 220 62;$homeCleanup=New-Button '🧹  ОЧИСТИТЬ ПК' 220 62;$homeBackup=New-Button '💾  БЭКАП' 220 62
$homeActions.Controls.Add($homeCheck);$homeActions.Controls.Add($homeCleanup);$homeActions.Controls.Add($homeBackup)
function Refresh-Home{
    try{
        $h=Get-CcHardware;$inv=Get-CcInventory;$disks=@(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
        $pcDetails.Text="Производитель: $($inv.Manufacturer)$([Environment]::NewLine)Модель: $($inv.Model)$([Environment]::NewLine)CPU: $($h.CPU)$([Environment]::NewLine)GPU: $($h.GPU)$([Environment]::NewLine)RAM: $($h.RAM)$([Environment]::NewLine)Windows: $($h.OS)$([Environment]::NewLine)Температура CPU: $($h.CpuTemp)"
        $diskDetails.Text=($disks|ForEach-Object{"$($_.DeviceID) — $([math]::Round($_.FreeSpace/1GB,1)) / $([math]::Round($_.Size/1GB,1)) GB свободно из $([math]::Round($_.Size/1GB,1)) GB"}) -join ([Environment]::NewLine)
        $healthText.Text='✓ Компьютер отвечает. Система готова к работе.';$healthText.ForeColor=$C.Accent
        $footer.Text="🐊 CyberCroc 🐊   •   Разработчик: Эдуард   •   Патч: $Version   •   ПК: $env:COMPUTERNAME   •   CPU: $($h.CPU)"
    }catch{$healthText.Text="✕ Не удалось полностью проверить ПК: $($_.Exception.Message)";$healthText.ForeColor=$C['Danger'];Write-CcError -FunctionName 'Refresh-Home' -Exception $_.Exception;Show-CcErrorPopup 'Проверка ПК' $_.Exception}
}
$homeCheck.Add_Click({$progress.Visible=$true;try{Refresh-Home;Toast 'Проверка ПК' 'Проверка завершена.' 'OK'}catch{Show-CcErrorPopup 'Проверка ПК' $_.Exception}finally{$progress.Visible=$false}})
$homeCleanup.Add_Click({try{Run-HiddenCmd 'Cleanup.cmd'}catch{Show-CcErrorPopup 'Очистка' $_.Exception}})
$homeBackup.Add_Click({try{Run-HiddenCmd 'Backup.cmd'}catch{Show-CcErrorPopup 'Бэкап' $_.Exception}})
$pages['home']=$homePage;$homePage.Controls[0].BringToFront()
# Games
$games=New-Object Windows.Forms.Panel;$games.Dock='Fill';$games.BackColor=$C.Bg;$games.Controls.Add((New-PageTitle 'Игры' 'Выберите игру. Видно, бесплатная она или платная, и через какой лаунчер ставится.'))
$gameGrid=New-Object Windows.Forms.TableLayoutPanel;$gameGrid.Dock='Fill';$gameGrid.Padding=New-Object Windows.Forms.Padding(20,96,20,15);$gameGrid.ColumnCount=2;$gameGrid.RowCount=3;$gameGrid.BackColor=$C.Bg;$games.Controls.Add($gameGrid)
[void]$gameGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,70)));[void]$gameGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,30)))
[void]$gameGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,52)));[void]$gameGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$gameGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,76)))
$gameSearch=New-Object Windows.Forms.TextBox;$gameSearch.Dock='Fill';$gameSearch.Text='Поиск игры...';$gameSearch.Font=New-Object Drawing.Font('Segoe UI',12);Apply-ControlTheme $gameSearch;$gameGrid.Controls.Add($gameSearch,0,0)
$gameFilter=New-Object Windows.Forms.ComboBox;$gameFilter.DropDownStyle='DropDownList';[void]$gameFilter.Items.AddRange(@('Все','Steam','Epic Games','Riot Games','Battle.net'));$gameFilter.SelectedIndex=0;$gameFilter.Dock='Fill';Apply-ControlTheme $gameFilter;$gameGrid.Controls.Add($gameFilter,1,0)
$gameList=New-Object Windows.Forms.ListView;$gameList.Dock='Fill';$gameList.View='Details';$gameList.FullRowSelect=$true;$gameList.MultiSelect=$false;$gameList.BackColor=$C.Control;$gameList.ForeColor=$C.Fg;[void]$gameList.Columns.Add('Игра',260);[void]$gameList.Columns.Add('Лаунчер',120);[void]$gameList.Columns.Add('Цена',100);[void]$gameList.Columns.Add('Установлена',120);$gameGrid.Controls.Add($gameList,0,1)
$gameInfo=New-Object Windows.Forms.TextBox;$gameInfo.Multiline=$true;$gameInfo.ReadOnly=$true;$gameInfo.Dock='Fill';$gameInfo.BackColor=$C.Panel;$gameInfo.ForeColor=$C.Fg;$gameInfo.Text='Выберите игру.`r`n`r`nМожно установить её через установленный лаунчер. Для Steam используется официальный Steam URI, для Epic/Riot/Battle.net — запуск соответствующего лаунчера.';$gameGrid.Controls.Add($gameInfo,1,1)
$gameButtons=New-Flow;$gameInstall=New-Button '⬇  УСТАНОВИТЬ' 180 58;$gameLaunch=New-Button '▶  ЗАПУСТИТЬ' 170 58;$gameUpdate=New-Button '↻  ОБНОВИТЬ' 160 58;$gameLan=New-Button '🌐  ЛОКАЛЬНАЯ СЕТЬ' 190 58;$gameAdd=New-Button '+ Своя игра' 140 58;$gameButtons.Controls.Add($gameInstall);$gameButtons.Controls.Add($gameLaunch);$gameButtons.Controls.Add($gameUpdate);$gameButtons.Controls.Add($gameLan);$gameButtons.Controls.Add($gameAdd);$gameGrid.Controls.Add($gameButtons,0,2);$gameGrid.SetColumnSpan($gameButtons,2)
$script:GameCatalog=@(
 [pscustomobject]@{Name='Counter-Strike 2';Launcher='Steam';Price='Бесплатно';AppID='730'},
 [pscustomobject]@{Name='Dota 2';Launcher='Steam';Price='Бесплатно';AppID='570'},
 [pscustomobject]@{Name='PUBG: BATTLEGROUNDS';Launcher='Steam';Price='Бесплатно';AppID='578080'},
 [pscustomobject]@{Name='Apex Legends';Launcher='Steam';Price='Бесплатно';AppID='1172470'},
 [pscustomobject]@{Name='Team Fortress 2';Launcher='Steam';Price='Бесплатно';AppID='440'},
 [pscustomobject]@{Name='Warframe';Launcher='Steam';Price='Бесплатно';AppID='230410'},
 [pscustomobject]@{Name='Fortnite';Launcher='Epic Games';Price='Бесплатно';AppID=''},
 [pscustomobject]@{Name='Rocket League';Launcher='Epic Games';Price='Бесплатно';AppID=''},
 [pscustomobject]@{Name='League of Legends';Launcher='Riot Games';Price='Бесплатно';AppID=''},
 [pscustomobject]@{Name='Valorant';Launcher='Riot Games';Price='Бесплатно';AppID=''},
 [pscustomobject]@{Name='Overwatch 2';Launcher='Battle.net';Price='Бесплатно';AppID=''},
 [pscustomobject]@{Name='Diablo IV';Launcher='Battle.net';Price='Платно';AppID=''}
)
function Refresh-GameCatalog{try{$gameList.Items.Clear();$q=$gameSearch.Text;if($q -eq 'Поиск игры...'){$q=''};$f=[string]$gameFilter.Text;foreach($g in $script:GameCatalog){if($q -and $g.Name -notlike "*$q*"){continue};if($f -ne 'Все' -and $g.Launcher -ne $f){continue};$installed='Нет';if($g.Launcher -eq 'Steam' -and (Get-CcSteamExe)){$installed='Лаунчер найден'};$i=New-Object Windows.Forms.ListViewItem($g.Name);[void]$i.SubItems.Add($g.Launcher);[void]$i.SubItems.Add($g.Price);[void]$i.SubItems.Add($installed);$i.Tag=$g;[void]$gameList.Items.Add($i)}}catch{Write-CcError -FunctionName 'Refresh-GameCatalog' -Exception $_.Exception}}
$gameSearch.Add_GotFocus({if($gameSearch.Text -eq 'Поиск игры...'){$gameSearch.Text='';$gameSearch.ForeColor=$C.Fg}});$gameSearch.Add_TextChanged({Refresh-GameCatalog});$gameFilter.Add_SelectedIndexChanged({Refresh-GameCatalog});$gameLan.Add_Click({Scan-LanGames});$gameAdd.Add_Click({Toast 'Игры' 'Свои игры добавляются через games.txt в текущей версии.' 'INFO'})
$gameInstall.Add_Click({if(-not $gameList.SelectedItems.Count){Show-CcErrorPopup 'Игры' ([Exception]'Сначала выберите игру.');return};$g=$gameList.SelectedItems[0].Tag;try{if($g.Launcher -eq 'Steam' -and $g.AppID){Start-Process "steam://install/$($g.AppID)"}elseif($g.Launcher -eq 'Epic Games'){Start-Process 'com.epicgames.launcher://apps'}elseif($g.Launcher -eq 'Riot Games'){$exe=Get-CcLauncherExe 'RiotClientServices.exe';if($exe){Start-Process $exe}else{throw 'Riot Client не найден.'}}else{Start-Process 'https://www.blizzard.com/'};Toast 'Игры' "Открыт лаунчер: $($g.Launcher)" 'OK'}catch{Show-CcErrorPopup 'Установка игры' $_.Exception}})
$gameLaunch.Add_Click({if($gameList.SelectedItems.Count){$g=$gameList.SelectedItems[0].Tag;try{if($g.Launcher -eq 'Steam' -and $g.AppID){Start-Process "steam://rungameid/$($g.AppID)"}else{throw "Запуск $($g.Name) требует лаунчер $($g.Launcher)."}}catch{Show-CcErrorPopup 'Запуск игры' $_.Exception}}else{Show-CcErrorPopup 'Игры' ([Exception]'Сначала выберите игру.')}})
$gameUpdate.Add_Click({Toast 'Игры' 'Проверка обновлений игры передана лаунчеру.' 'INFO'})
function Scan-LanGames{try{$progress.Visible=$true;$gameInfo.Text='Сканирую компьютеры локальной сети...';$peers=@(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue|Where-Object{$_.State -in @('Reachable','Stale','Delay','Probe') -and $_.IPAddress -notlike '224.*' -and $_.IPAddress -notlike '239.*'}|Select-Object -ExpandProperty IPAddress -Unique);$rows=@();$selected=if($gameList.SelectedItems.Count){$gameList.SelectedItems[0].Tag}else{$null};foreach($ip in $peers){$name=$ip;try{$name=[System.Net.Dns]::GetHostEntry($ip).HostName}catch{};$steam='нет';$base="\\$ip\C$\Program Files (x86)\Steam";if(Test-Path -LiteralPath (Join-Path $base 'steam.exe')){$steam='есть'};$rows+="${name}  [$ip]  — Steam: $steam"};if($rows.Count){$gameInfo.Text="ПК в локальной сети:`r`n`r`n"+($rows -join "`r`n")}else{$gameInfo.Text='Активные ПК в локальной сети не найдены или недоступны.'}}catch{Show-CcErrorPopup 'Локальная сеть' $_.Exception}finally{$progress.Visible=$false}}
$pages['games']=$games;$games.Controls[0].BringToFront();Refresh-GameCatalog
# Accounts
$accounts=New-Object Windows.Forms.Panel;$accounts.Dock='Fill';$accounts.BackColor=$C.Bg;$accounts.Controls.Add((New-PageTitle 'Аккаунты' 'Игровые аккаунты клуба. Не нужно открывать отдельные программы.'))
$accountArea=New-Object Windows.Forms.TableLayoutPanel;$accountArea.Dock='Fill';$accountArea.Padding=New-Object Windows.Forms.Padding(20,100,20,15);$accountArea.RowCount=2
[void]$accountArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$accountArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,72)));$accounts.Controls.Add($accountArea)
$aList=New-Object Windows.Forms.ListView;$aList.View='Details';$aList.FullRowSelect=$true;$aList.MultiSelect=$false;$aList.Dock='Fill';$aList.BackColor=$C.Control;$aList.ForeColor=$C.Fg
[void]$aList.Columns.Add('Платформа',150);[void]$aList.Columns.Add('Логин',220);[void]$aList.Columns.Add('Статус',150);[void]$aList.Columns.Add('Проверка',180);$accountArea.Controls.Add($aList,0,0)
$ab=New-Flow;$aLogin=New-Button 'ВОЙТИ' 170 58;$aCheck=New-Button 'Проверить' 150 58;$aAdd=New-Button '+ Добавить' 150 58;$aEdit=New-Button 'Изменить' 140 58;$aDel=New-Button 'Удалить' 130 58
foreach($b in @($aLogin,$aCheck,$aAdd,$aEdit,$aDel)){$ab.Controls.Add($b)};$accountArea.Controls.Add($ab,0,1)
function Refresh-Accounts{try{$aList.Items.Clear();foreach($a in @(Get-CcAccounts)){$i=New-Object Windows.Forms.ListViewItem($a.Platform);[void]$i.SubItems.Add($a.Login);[void]$i.SubItems.Add($a.Status);[void]$i.SubItems.Add([string]$a.LastCheck);$i.Tag=$a;[void]$aList.Items.Add($i)}}catch{Write-CcError -FunctionName 'Refresh-Accounts' -Exception $_.Exception}}
$aLogin.Add_Click({if($aList.SelectedItems.Count){Start-CcAccountSession $aList.SelectedItems[0].Tag|Out-Null;Refresh-Accounts}else{Toast 'Аккаунты' 'Выберите аккаунт.' 'INFO'}})
$aCheck.Add_Click({try{$progress.Visible=$true;foreach($a in @(Get-CcAccounts)){Test-CcAccount $a $cfg|Out-Null};Save-CcAccounts @(Get-CcAccounts)|Out-Null;Refresh-Accounts;Toast 'Аккаунты' 'Проверка завершена.' 'OK'}catch{Write-CcError -FunctionName 'Account-Check' -Exception $_.Exception}finally{$progress.Visible=$false}})
function Show-AccountDialog($existing=$null){
    $d=New-Object Windows.Forms.Form;$d.Text=if($existing){'Изменить аккаунт'}else{'Добавить аккаунт'};$d.StartPosition='CenterParent';$d.Size=New-Object Drawing.Size(520,390);$d.BackColor=$C.Bg;$d.ForeColor=$C.Fg
    $l=New-Object Windows.Forms.TableLayoutPanel;$l.Dock='Fill';$l.Padding=New-Object Windows.Forms.Padding(14);$l.ColumnCount=2;$l.RowCount=6
    [void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,130)));[void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));$d.Controls.Add($l)
    $names=@('Платформа','Логин','Пароль','Комментарий','Игры');$f=@{}
    for($r=0;$r-lt 5;$r++){[void]$l.Controls.Add((New-Label $names[$r]),0,$r);if($names[$r] -eq 'Платформа'){$t=New-Object Windows.Forms.ComboBox;$t.DropDownStyle='DropDownList';[void]$t.Items.AddRange(@('Steam','Riot Games','Battle.net','Epic Games'));$t.Dock='Fill';Apply-ControlTheme $t}elseif($names[$r] -eq 'Игры'){$t=New-Object Windows.Forms.CheckedListBox;$t.Dock='Fill';$t.CheckOnClick=$true;Apply-ControlTheme $t}else{$t=New-Object Windows.Forms.TextBox;$t.Dock='Fill';Apply-ControlTheme $t};$f[$names[$r]]=$t;[void]$l.Controls.Add($t,1,$r)}
    $l.RowStyles.Clear(); for($rr=0;$rr -lt 6;$rr++){ if($rr -eq 4){[void]$l.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,120)))} else {[void]$l.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,42)))}}
    if($existing){$f['Платформа'].Text=$existing.Platform;$f['Логин'].Text=$existing.Login;$f['Комментарий'].Text=$existing.Comment}else{$f['Платформа'].Text='Steam'}
    function Refresh-AccountGameChoices{$f['Игры'].Items.Clear();$platform=[string]$f['Платформа'].Text;foreach($g in @($script:GameCatalog|Where-Object{$_.Launcher -eq $platform})){$idx=$f['Игры'].Items.Add("$($g.Name) — $($g.Price)");if($existing -and @($existing.Games) -contains $g.Name){$f['Игры'].SetItemChecked($idx,$true)}}}
    $f['Платформа'].Add_SelectedIndexChanged({Refresh-AccountGameChoices});Refresh-AccountGameChoices
    $f['Пароль'].UseSystemPasswordChar=$true
    $p=New-Flow;$p.FlowDirection='RightToLeft';$ok=New-Button 'Сохранить';$cancel=New-Button 'Отмена';$p.Controls.Add($ok);$p.Controls.Add($cancel);$l.Controls.Add($p,1,5);$cancel.Add_Click({$d.Close()})
    $ok.Add_Click({ try { $games=@($f['Игры'].CheckedItems | ForEach-Object { ([string]$_) -replace ' — (Бесплатно|Платно)$','' } | Where-Object {$_}); if($existing){ Update-CcAccount $existing.Id @{Platform=$f['Платформа'].Text;Login=$f['Логин'].Text;Password=$f['Пароль'].Text;Comment=$f['Комментарий'].Text;Games=$games} | Out-Null } else { New-CcAccount $f['Платформа'].Text $f['Логин'].Text $f['Пароль'].Text $f['Комментарий'].Text $games | Out-Null }; $d.Close(); Refresh-Accounts } catch { Write-CcError -FunctionName 'Account-Dialog' -Exception $_.Exception; Show-CcErrorPopup 'Аккаунты' $_.Exception } })
    [void]$d.ShowDialog($form)
}
$aAdd.Add_Click({try{Show-AccountDialog}catch{Show-CcErrorPopup 'Аккаунты' $_.Exception}})
$aEdit.Add_Click({if($aList.SelectedItems.Count){Show-AccountDialog $aList.SelectedItems[0].Tag}else{Toast 'Аккаунты' 'Выберите аккаунт.' 'INFO'}})
$aDel.Add_Click({if($aList.SelectedItems.Count){Remove-CcAccount $aList.SelectedItems[0].Tag.Id|Out-Null;Refresh-Accounts}})
$pages['accounts']=$accounts
$accounts.Controls[0].BringToFront()

# Applications
$app=New-Object Windows.Forms.Panel;$app.Dock='Fill';$app.BackColor=$C.Bg;$app.Controls.Add((New-PageTitle 'Программы' 'Выберите программу и нажмите «Установить». Установка идёт прямо в этой программе.'))
$appGrid=New-Object Windows.Forms.TableLayoutPanel;$appGrid.Dock='Fill';$appGrid.Padding=New-Object Windows.Forms.Padding(20,96,20,15);$appGrid.ColumnCount=2;$appGrid.RowCount=3;$appGrid.BackColor=$C.Bg;$app.Controls.Add($appGrid)
[void]$appGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,62)));[void]$appGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,38)))
[void]$appGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,52)));[void]$appGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$appGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,76)))
$appSearch=New-Object Windows.Forms.TextBox;$appSearch.Dock='Fill';$appSearch.Text='Поиск: браузер, Office, Steam...';$appSearch.Font=New-Object Drawing.Font('Segoe UI',12);Apply-ControlTheme $appSearch;$appGrid.Controls.Add($appSearch,0,0)
$appHint=New-Label '💡 Всё устанавливается через winget. Никаких чёрных окон.' 10;$appHint.ForeColor=$C.Muted;$appHint.Dock='Fill';$appHint.TextAlign='MiddleLeft';$appGrid.Controls.Add($appHint,1,0)
$appList=New-Object Windows.Forms.ListView;$appList.View='Details';$appList.FullRowSelect=$true;$appList.MultiSelect=$false;$appList.Dock='Fill';$appList.BackColor=$C.Control;$appList.ForeColor=$C.Fg;[void]$appList.Columns.Add('Программа',260);[void]$appList.Columns.Add('Тип',110);[void]$appList.Columns.Add('Цена',90);$appGrid.Controls.Add($appList,0,1)
$appInfo=New-Object Windows.Forms.TextBox;$appInfo.Multiline=$true;$appInfo.ReadOnly=$true;$appInfo.Dock='Fill';$appInfo.ScrollBars='Vertical';$appInfo.BackColor=$C.Panel;$appInfo.ForeColor=$C.Fg;$appInfo.Text='Выберите программу слева.`r`n`r`nСписок подготовлен для клуба: браузеры, Office, игровые лаунчеры, Discord и системные компоненты.';$appGrid.Controls.Add($appInfo,1,1)
$appButtons=New-Flow;$appInstallOne=New-Button '⬇  УСТАНОВИТЬ' 200 58;$appUpdateOne=New-Button '↻  ОБНОВИТЬ' 180 58;$appRefresh=New-Button '⟳  ОБНОВИТЬ СПИСОК' 210 58;$appButtons.Controls.Add($appInstallOne);$appButtons.Controls.Add($appUpdateOne);$appButtons.Controls.Add($appRefresh);$appGrid.Controls.Add($appButtons,0,2);$appGrid.SetColumnSpan($appButtons,2)
$script:AppCatalog=@(
    [pscustomobject]@{Name='Google Chrome';Id='Google.Chrome';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Mozilla Firefox';Id='Mozilla.Firefox';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Brave Browser';Id='Brave.Brave';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Opera';Id='Opera.Opera';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Microsoft Edge';Id='Microsoft.Edge';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Microsoft 365 / Office';Id='Microsoft.Office';Type='Офис';Price='Платно'},
    [pscustomobject]@{Name='LibreOffice';Id='TheDocumentFoundation.LibreOffice';Type='Офис';Price='Бесплатно'},
    [pscustomobject]@{Name='Steam';Id='Valve.Steam';Type='Игры';Price='Бесплатно'},
    [pscustomobject]@{Name='Epic Games Launcher';Id='EpicGames.EpicGamesLauncher';Type='Игры';Price='Бесплатно'},
    [pscustomobject]@{Name='Battle.net';Id='Blizzard.BattleNet';Type='Игры';Price='Бесплатно'},
    [pscustomobject]@{Name='Discord';Id='Discord.Discord';Type='Связь';Price='Бесплатно'},
    [pscustomobject]@{Name='Visual C++ 2015-2022 x64';Id='Microsoft.VCRedist.2015+.x64';Type='Система';Price='Бесплатно'},
    [pscustomobject]@{Name='DirectX Runtime';Id='Microsoft.DirectX';Type='Система';Price='Бесплатно'}
)
function Refresh-AppCatalog{try{$appList.Items.Clear();$q=$appSearch.Text;if($q -like 'Поиск:*'){$q=''};foreach($x in $script:AppCatalog){if($q -and $x.Name -notlike "*$q*" -and $x.Type -notlike "*$q*"){continue};$i=New-Object Windows.Forms.ListViewItem($x.Name);[void]$i.SubItems.Add($x.Type);[void]$i.SubItems.Add($x.Price);$i.Tag=$x;[void]$appList.Items.Add($i)}}catch{Write-CcError -FunctionName 'Refresh-AppCatalog' -Exception $_.Exception}}
function Start-WingetApp([object]$Item,[string]$Mode){try{$winget=(Get-Command winget.exe -ErrorAction Stop).Source;$op=if($Mode -eq 'update'){'upgrade'}else{'install'};$args="`$op --id $($Item.Id) --exact --source winget --accept-source-agreements --accept-package-agreements --silent --disable-interactivity";$progress.Visible=$true;$appInfo.Text="Операция: $op`r`n`r`n$($Item.Name)`r`n`r`nОжидайте завершения...";$p=Start-Process -FilePath $winget -ArgumentList $args -WindowStyle Hidden -PassThru;$script:AppProcess=$p;$script:AppProcessName=$Item.Name;$script:AppProcessMode=$Mode}catch{Show-CcErrorPopup 'Установка программы' $_.Exception}}
$appInstallOne.Add_Click({if($appList.SelectedItems.Count){Start-WingetApp $appList.SelectedItems[0].Tag 'install'}else{Show-CcErrorPopup 'Программы' ([Exception]'Сначала выберите программу.')}})
$appUpdateOne.Add_Click({if($appList.SelectedItems.Count){Start-WingetApp $appList.SelectedItems[0].Tag 'update'}else{Show-CcErrorPopup 'Программы' ([Exception]'Сначала выберите программу.')}})
$appRefresh.Add_Click({Refresh-AppCatalog})
$appSearch.Add_TextChanged({Refresh-AppCatalog})
$pages['apps']=$app;$app.Controls[0].BringToFront();Refresh-AppCatalog
# Backup and cleanup
$backup=New-Object Windows.Forms.Panel;$backup.Dock='Fill';$backup.BackColor=$C.Bg;$backup.Controls.Add((New-PageTitle 'Резервная копия' 'Сохраните важные данные перед обслуживанием компьютера.'))
$bb=New-Flow;$bb.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$backup.Controls.Add($bb);$backupInfo=New-Card 'БЭКАП' 'ГОТОВ' 'копирует данные клуба';$bb.Controls.Add($backupInfo);$backupBtn=New-Button '💾  СДЕЛАТЬ БЭКАП' 280 70;$bb.Controls.Add($backupBtn);$backupBtn.Add_Click({try{Run-HiddenCmd 'Backup.cmd'}catch{Show-CcErrorPopup 'Бэкап' $_.Exception}});$pages['backup']=$backup;$backup.Controls[0].BringToFront()
$cleanup=New-Object Windows.Forms.Panel;$cleanup.Dock='Fill';$cleanup.BackColor=$C.Bg;$cleanup.Controls.Add((New-PageTitle 'Очистка' 'Выберите, что удалить. Личные документы и игры по умолчанию не трогаются.'))
$clGrid=New-Object Windows.Forms.TableLayoutPanel;$clGrid.Dock='Fill';$clGrid.Padding=New-Object Windows.Forms.Padding(20,96,20,15);$clGrid.ColumnCount=2;$clGrid.RowCount=3;$clGrid.BackColor=$C.Bg;$cleanup.Controls.Add($clGrid)
[void]$clGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,55)));[void]$clGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,45)))
[void]$clGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,48)));[void]$clGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$clGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,78)))
$clHint=New-Label 'Отметьте нужные пункты:' 11 'Bold';$clHint.Dock='Fill';$clGrid.Controls.Add($clHint,0,0);$clStatus=New-Label 'Готово. Ничего не удалено.' 10;$clStatus.ForeColor=$C.Muted;$clStatus.Dock='Fill';$clStatus.TextAlign='MiddleLeft';$clGrid.Controls.Add($clStatus,1,0)
$clChecks=New-Object Windows.Forms.FlowLayoutPanel;$clChecks.Dock='Fill';$clChecks.FlowDirection='TopDown';$clChecks.WrapContents=$false;$clChecks.AutoScroll=$true;$clChecks.BackColor=$C.Panel;$clGrid.Controls.Add($clChecks,0,1)
$drivePanel=New-Object Windows.Forms.FlowLayoutPanel;$drivePanel.Dock='Fill';$drivePanel.FlowDirection='TopDown';$drivePanel.WrapContents=$false;$drivePanel.AutoScroll=$true;$drivePanel.BackColor=$C.Panel;$clGrid.Controls.Add($drivePanel,1,1)
$driveTitle=New-Label '💾 Диски — очищаются только временные данные и корзина' 10 'Bold';$drivePanel.Controls.Add($driveTitle)
$driveChecks=@{};foreach($d in @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)){$letter=$d.DeviceID.Substring(0,1);$dc=New-Object Windows.Forms.CheckBox;$dc.Text="$letter`:  $([math]::Round($d.FreeSpace/1GB,1)) GB свободно из $([math]::Round($d.Size/1GB,1)) GB";$dc.Tag=$letter;$dc.Width=380;$dc.Height=32;$dc.Checked=($letter -eq $env:SystemDrive.Substring(0,1));Apply-ControlTheme $dc;$drivePanel.Controls.Add($dc);$driveChecks[$letter]=$dc}
$cleanupItems=@(@{Text='Временные файлы пользователя';Id='temp'},@{Text='Временные файлы Windows';Id='wintemp'},@{Text='Корзина';Id='recycle'},@{Text='Кэш DNS';Id='dns'},@{Text='Кэш браузеров';Id='browser'},@{Text='Кэш Windows Update';Id='update'})
$clBox=@{};foreach($x in $cleanupItems){$cbx=New-Object Windows.Forms.CheckBox;$cbx.Text=$x.Text;$cbx.Tag=$x.Id;$cbx.Width=480;$cbx.Height=34;$cbx.Checked=($x.Id -in @('temp','recycle','dns'));Apply-ControlTheme $cbx;$clChecks.Controls.Add($cbx);$clBox[$x.Id]=$cbx}
$clActions=New-Flow;$clRun=New-Button '🧹  ОЧИСТИТЬ ВЫБРАННОЕ' 260 62;$clAll=New-Button '⚡  ПОЛНАЯ БЕЗОПАСНАЯ ОЧИСТКА' 280 62;$clActions.Controls.Add($clRun);$clActions.Controls.Add($clAll);$clGrid.Controls.Add($clActions,0,2);$clGrid.SetColumnSpan($clActions,2)
function Invoke-CleanupSelected([bool]$Full){try{$progress.Visible=$true;$clStatus.Text='Идёт очистка...';$ids=@();foreach($x in $clBox.Values){if($Full -or $x.Checked){$ids+=[string]$x.Tag}};foreach($id in $ids){switch($id){'temp'{Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue};'wintemp'{Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'Temp') -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue};'recycle'{Clear-RecycleBin -Force -ErrorAction SilentlyContinue};'dns'{ipconfig /flushdns|Out-Null};'browser'{foreach($p in @((Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache'),(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache'),(Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'))){if(Test-Path $p){Get-ChildItem $p -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue}}};'update'{Stop-Service wuauserv -Force -ErrorAction SilentlyContinue;Remove-Item (Join-Path $env:SystemRoot 'SoftwareDistribution\Download\*') -Recurse -Force -ErrorAction SilentlyContinue;Start-Service wuauserv -ErrorAction SilentlyContinue}}};foreach($letter in $driveChecks.Keys){if($Full -or $driveChecks[$letter].Checked){$tempDrive=Join-Path ($letter+':') 'Temp';if(Test-Path $tempDrive){Get-ChildItem $tempDrive -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue};try{Clear-RecycleBin -DriveLetter $letter -Force -ErrorAction SilentlyContinue}catch{}}};$clStatus.Text='✓ Очистка завершена.';$clStatus.ForeColor=$C.Accent;Toast 'Очистка' 'Выбранные элементы очищены.' 'OK'}catch{Show-CcErrorPopup 'Очистка' $_.Exception;$clStatus.Text='✕ Ошибка очистки';$clStatus.ForeColor=$C['Danger']}finally{$progress.Visible=$false}}
$clRun.Add_Click({Invoke-CleanupSelected $false});$clAll.Add_Click({Invoke-CleanupSelected $true});$pages['cleanup']=$cleanup;$cleanup.Controls[0].BringToFront()
# Logs
$logs=New-Object Windows.Forms.Panel;$logs.Dock='Fill';$logs.BackColor=$C.Bg;$logs.Controls.Add((New-PageTitle 'Журнал' 'Техническая информация. Нужна в основном администратору.'))
$logArea=New-Object Windows.Forms.TableLayoutPanel;$logArea.Dock='Fill';$logArea.Padding=New-Object Windows.Forms.Padding(20,100,20,15);$logArea.RowCount=2
[void]$logArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$logArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,62)));$logs.Controls.Add($logArea)
$logText=New-Object Windows.Forms.TextBox;$logText.Multiline=$true;$logText.ReadOnly=$true;$logText.ScrollBars='Both';$logText.Dock='Fill';$logText.Font=New-Object Drawing.Font('Consolas',9);$logText.BackColor=$C.Control;$logText.ForeColor=$C.Fg;$logArea.Controls.Add($logText,0,0)
$logBtn=New-Button 'Обновить журнал' 190 50;$logArea.Controls.Add($logBtn,0,1)
function Refresh-Logs{try{$p=Join-Path $Root 'logs\CyberCroc.log';$e=Join-Path $Root 'logs\errors.log';$s='';if(Test-Path $p){$s+=Get-Content $p -Raw};if(Test-Path $e){$s+=[Environment]::NewLine+'===== ОШИБКИ ====='+[Environment]::NewLine+(Get-Content $e -Raw)};$logText.Text=$s}catch{}}
$logBtn.Add_Click({Refresh-Logs});$pages['logs']=$logs
$logs.Controls[0].BringToFront()

# Settings
$settings=New-Object Windows.Forms.Panel;$settings.Dock='Fill';$settings.BackColor=$C.Bg;$settings.Controls.Add((New-PageTitle 'Настройки' 'Изменяйте только то, что действительно нужно.'))
$setBody=New-Object Windows.Forms.FlowLayoutPanel;$setBody.Dock='Fill';$setBody.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$setBody.WrapContents=$true;$setBody.AutoScroll=$true;$setBody.BackColor=$C.Bg;$settings.Controls.Add($setBody)
$themeBox=New-Object Windows.Forms.Panel;$themeBox.Width=700;$themeBox.Height=120;$themeBox.BackColor=$C.Panel;$setBody.Controls.Add($themeBox)
$themeLabel=New-Label 'ТЕМА' 11 'Bold';$themeLabel.Location=New-Object Drawing.Point(18,18);$themeBox.Controls.Add($themeLabel)
$theme=New-Object Windows.Forms.ComboBox;$theme.DropDownStyle='DropDownList';[void]$theme.Items.AddRange(@('dark','neon','light'));$theme.SelectedItem=$ThemeName;$theme.Width=220;$theme.Location=New-Object Drawing.Point(18,52);$theme.BackColor=$C.Control;$theme.ForeColor=$C.Fg;$themeBox.Controls.Add($theme)
$shareBox=New-Object Windows.Forms.Panel;$shareBox.Width=700;$shareBox.Height=120;$shareBox.BackColor=$C.Panel;$setBody.Controls.Add($shareBox)
$shareLabel=New-Label 'ПАПКА ОБНОВЛЕНИЙ' 11 'Bold';$shareLabel.Location=New-Object Drawing.Point(18,18);$shareBox.Controls.Add($shareLabel)
$share=New-Object Windows.Forms.TextBox;$share.Text=$cfg['UPDATE_SHARE'];$share.Width=630;$share.Location=New-Object Drawing.Point(18,52);$share.BackColor=$C.Control;$share.ForeColor=$C.Fg;$shareBox.Controls.Add($share)
$saveSettings=New-Button 'Сохранить настройки' 240 60;$checkUpdate=New-Button 'Проверить обновление' 240 60;$setBody.Controls.Add($saveSettings);$setBody.Controls.Add($checkUpdate)
$theme.Add_SelectedIndexChanged({Set-Theme $theme.Text;Apply-Theme})
$saveSettings.Add_Click({try{$cfg['THEME']=$theme.Text;$cfg['UPDATE_SHARE']=$share.Text;$lines=@();foreach($k in $cfg.Keys){$lines+=($k+'='+$cfg[$k])};Set-Content (Join-Path $Root 'config.ini') ($lines -join [Environment]::NewLine) -Encoding UTF8;Apply-Theme;Toast 'Настройки' 'Настройки сохранены.' 'OK'}catch{Write-CcError -FunctionName 'SaveSettings' -Exception $_.Exception}})
$checkUpdate.Add_Click({try{$u=Test-CcGithubUpdate;if(-not $u){Toast 'Обновление' 'GitHub сейчас недоступен. Проверьте интернет.' 'INFO';return};if($u.Available){$answer=[System.Windows.Forms.MessageBox]::Show("Доступна версия $($u.Remote). Установлена $($u.Local).`r`n`r`nОбновить сейчас?",'CyberCroc — обновление',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Information);if($answer -eq [System.Windows.Forms.DialogResult]::Yes){if(Start-CcGithubUpdate){exit 0}}}else{Toast 'Обновление' "Установлена актуальная версия $($u.Local)." 'OK'}}catch{Write-CcError -FunctionName 'UpdateNow' -Exception $_.Exception}})
$pages['settings']=$settings
$settings.Controls[0].BringToFront()

function Run-HiddenCmd([string]$Name){
    try{$p=Start-Process cmd.exe -ArgumentList @('/d','/c','"'+(Join-Path $Root $Name)+'"') -WindowStyle Hidden -Wait -PassThru;Toast 'CyberCroc' $(if($p.ExitCode -eq 0){"$Name завершено."}else{"$($Name): ошибка $($p.ExitCode)"}) $(if($p.ExitCode -eq 0){'OK'}else{'ERROR'})}catch{Write-CcError -FunctionName 'Run-HiddenCmd' -Exception $_.Exception}
}
function Apply-Theme{
    try{
        $form.BackColor=$C.Bg;$form.ForeColor=$C.Fg;$nav.BackColor=$C.Panel;$content.BackColor=$C.Bg;$footer.BackColor=$C.Panel
        foreach($p in $pages.Values){$p.BackColor=$C.Bg;Apply-ControlTheme $p}
        foreach($b in $navButtons.Values){$b.BackColor=$C.Control;$b.ForeColor=$C.Fg;$b.FlatAppearance.BorderColor=$C.Fg}
        if($navButtons.ContainsKey('home')){$navButtons['home'].BackColor=$C.AccentDark;$navButtons['home'].ForeColor=$C.White}
    }catch{Write-CcError -FunctionName 'Apply-Theme' -Exception $_.Exception}
}

Add-MenuButton 'home' '⌂  ГЛАВНАЯ'
Add-MenuButton 'games' '▶  ИГРЫ'
Add-MenuButton 'accounts' '●  АККАУНТЫ'
Add-MenuButton 'apps' '▣  ПРОГРАММЫ'
Add-MenuButton 'backup' '▤  БЭКАП'
Add-MenuButton 'cleanup' '♻  ОЧИСТКА'
Add-MenuButton 'logs' '≡  ЖУРНАЛ'
Add-MenuButton 'settings' '⚙  НАСТРОЙКИ'

$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000;$timer.Add_Tick({$clock.Text=(Get-Date).ToString('HH:mm:ss')});$timer.Start()
$syncTimer=New-Object Windows.Forms.Timer;$syncTimer.Interval=30000;$syncTimer.Add_Tick({try{if(Sync-CcAccounts Pull){Refresh-Accounts}}catch{}});$syncTimer.Start()
try{Sync-CcAccounts Pull|Out-Null}catch{}
$script:AppProcess=$null;$script:AppProcessName=''
$appTimer=New-Object Windows.Forms.Timer;$appTimer.Interval=500;$appTimer.Add_Tick({try{if($null -ne $script:AppProcess){if($script:AppProcess.HasExited){$rc=$script:AppProcess.ExitCode;$appInfo.Text="Операция завершена: $script:AppProcessName`nКод: $rc";$progress.Visible=$false;if($rc -eq 0){Toast 'Программы' "$script:AppProcessName установлена/обновлена." 'OK'}else{Show-CcErrorPopup 'Установка программы' ([Exception]("$script:AppProcessName завершилась с кодом $rc"))};$script:AppProcess=$null}}}catch{}});$appTimer.Start()
Refresh-Home;Refresh-GameCatalog;Refresh-AppCatalog;Refresh-Accounts;Refresh-Logs;Apply-Theme;Show-Page 'home'
$form.Add_FormClosing({Write-CcLog 'GUI closed' 'INFO' 'FormClosing'})
try {
    [void][System.Windows.Forms.Application]::Run($form)
} catch {
    Write-CcError -FunctionName 'Application.Run' -Exception $_.Exception
    throw
}
