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
        Write-Error ($line + "`r`nPosition: " + $position + "`r`nStack: " + $stack)
    } catch {
        Write-Error ("CyberCroc fatal handler failed: " + $_.Exception.Message)
    }
    exit 1
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
. (Join-Path $Tools 'Games.ps1')
. (Join-Path $Tools 'Network.ps1')
. (Join-Path $Tools 'Queue.ps1')
. (Join-Path $Tools 'Orders.ps1')
. (Join-Path $Tools 'Products.ps1')
. (Join-Path $Tools 'Audit.ps1')
. (Join-Path $Tools 'Fleet.ps1')
. (Join-Path $Tools 'GameCache.ps1')

try{
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({param($sender,$args) Write-CcError -FunctionName 'WinForms.ThreadException' -Exception $args.Exception;[void][Windows.Forms.MessageBox]::Show("Ошибка программы.`n`n$($args.Exception.Message)`n`nПодробности записаны в logs\\errors.log.",'CyberCroc — ошибка',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)})
    [AppDomain]::CurrentDomain.add_UnhandledException({param($sender,$args) if($args.ExceptionObject -is [Exception]){Write-CcError -FunctionName 'AppDomain.UnhandledException' -Exception $args.ExceptionObject}})
}catch{}

$cfg=Get-CcConfig
if(-not $cfg.ContainsKey('THEME')){$cfg['THEME']='dark'}
$script:CcRole=Get-CcRole
$script:CcPcId=Get-CcPcId
$script:CcHeartbeatFile=Join-Path $Root 'runtime\heartbeat.txt'
$script:CcPidFile=Join-Path $Root 'runtime\cybercroc.pid'
New-Item -ItemType Directory -Path (Join-Path $Root 'runtime') -Force | Out-Null
Set-Content -LiteralPath $script:CcPidFile -Value ([string]$PID) -Encoding ASCII
Set-Content -LiteralPath $script:CcHeartbeatFile -Value (Get-Date).ToUniversalTime().ToString('o') -Encoding ASCII

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
$GithubBranch=if($cfg['GITHUB_BRANCH']){[string]$cfg['GITHUB_BRANCH']}else{'fix/0.5.1-launcher-updater'}
$GithubVersionUrl="https://raw.githubusercontent.com/$GithubRepo/$GithubBranch/version.txt"
$GithubUpdateScript=Join-Path $Tools 'Updater.ps1'

function Get-CcShareVersion([string]$Share){try{if([string]::IsNullOrWhiteSpace($Share)){return ''};$f=Join-Path $Share 'version.txt';if(Test-Path -LiteralPath $f){$v=(Get-Content -LiteralPath $f -Raw -ErrorAction Stop).Trim();if($v -match '^\d+(\.\d+){1,3}$'){return $v}}}catch{Write-CcLog "SMB version check failed: $($_.Exception.Message)" 'WARN' 'Get-CcShareVersion'};return ''}
function Test-CcShareUpdate {try{$share=[string]$cfg['UPDATE_SHARE'];if([string]::IsNullOrWhiteSpace($share)){return $null};if(-not(Test-Path -LiteralPath $share -PathType Container -ErrorAction Stop)){return $null};$remote=Get-CcShareVersion $share;if(-not$remote){return $null};$cmp=Compare-CcVersion $remote $Version;return [pscustomobject]@{Available=($cmp -gt 0);Local=$Version;Remote=$remote;Source=$share}}catch{Write-CcLog "SMB update check skipped: $($_.Exception.Message)" 'WARN' 'Test-CcShareUpdate';return $null}}
function Start-CcShareUpdate {try{$share=[string]$cfg['UPDATE_SHARE'];if([string]::IsNullOrWhiteSpace($share)){return $false};$args=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $Tools 'Updater.ps1'),'-Apply','-Source',$share,'-WaitPid',$PID);Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $args -WindowStyle Hidden|Out-Null;Write-CcLog "SMB update accepted: $Version -> $share" 'INFO' 'Start-CcShareUpdate';return $true}catch{Write-CcError -FunctionName 'Start-CcShareUpdate' -Exception $_.Exception;return $false}}

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
        Write-CcLog "GitHub update accepted: $Version -> $GithubBranch" 'INFO' 'Start-CcGithubUpdate'
        return $true
    } catch {
        Write-CcError -FunctionName 'Start-CcGithubUpdate' -Exception $_.Exception
        return $false
    }
}
function Invoke-CcStartupUpdateCheck {
    try {
        $u=Test-CcShareUpdate
        $useGithub=([string]$cfg['GITHUB_UPDATE_ENABLED'] -eq '1')
        if(-not$u -and $useGithub){$u=Test-CcGithubUpdate}
        if(-not $u -or -not $u.Available){return $false}
        $sourceText = 'GitHub'
        if ($u.PSObject.Properties.Name -contains 'Source') { $sourceText = [string]$u.Source }
        $nl = [Environment]::NewLine
        $updateMessage = 'A new CyberCroc version is available. Installed: ' + [string]$u.Local + '; new: ' + [string]$u.Remote + '; source: ' + $sourceText + '. Update now?'
        $answer = [Windows.Forms.MessageBox]::Show($updateMessage, 'CyberCroc update available', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Information)
        if($answer -ne [Windows.Forms.DialogResult]::Yes){Write-CcLog "Update declined: local=$($u.Local) remote=$($u.Remote)" 'INFO' 'Invoke-CcStartupUpdateCheck';return $false}
        $started=$false
        if($u.PSObject.Properties.Name -contains 'Source'){$started=Start-CcShareUpdate}elseif($useGithub){$started=Start-CcGithubUpdate}
        if($started){return $true}
        $updateWarning = 'Could not start update. CyberCroc will continue with the current version.'
        [void]([Windows.Forms.MessageBox]::Show($updateWarning, 'CyberCroc', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Warning))
        return $false
    }catch{Write-CcError -FunctionName 'Invoke-CcStartupUpdateCheck' -Exception $_.Exception;return $false}
}

$ThemeName=if($cfg['THEME']){$cfg['THEME']}else{'dark'}
if(Invoke-CcStartupUpdateCheck){exit 0}

$C=@{}
$C.Accent=[Drawing.Color]::FromArgb(68,190,255)
$C.AccentDark=[Drawing.Color]::FromArgb(34,120,180)
$C.Bg=[Drawing.Color]::FromArgb(14,16,20)
$C.Panel=[Drawing.Color]::FromArgb(24,27,33)
$C.Control=[Drawing.Color]::FromArgb(35,39,47)
$C.Fg=[Drawing.Color]::FromArgb(235,240,246)
$C.Muted=[Drawing.Color]::FromArgb(155,165,178)
$C.White=[Drawing.Color]::White
$C['Danger']=[Drawing.Color]::FromArgb(235,75,75)
$C['Warning']=[Drawing.Color]::FromArgb(250,185,70)

function Set-Theme([string]$Name){
    $script:ThemeName=$Name
    if($Name -eq 'light'){
        $C.Bg=[Drawing.Color]::FromArgb(245,245,245);$C.Panel=[Drawing.Color]::White;$C.Control=[Drawing.Color]::FromArgb(232,232,232);$C.Fg=[Drawing.Color]::FromArgb(25,25,25);$C.Muted=[Drawing.Color]::FromArgb(90,90,90);$C.White=[Drawing.Color]::FromArgb(25,25,25)
    }elseif($Name -eq 'neon'){
        $C.Bg=[Drawing.Color]::FromArgb(2,8,2);$C.Panel=[Drawing.Color]::FromArgb(5,18,5);$C.Control=[Drawing.Color]::FromArgb(10,35,10);$C.Fg=[Drawing.Color]::FromArgb(80,255,80);$C.Muted=[Drawing.Color]::FromArgb(110,180,110);$C.White=[Drawing.Color]::White
    }else{
        $C.Bg=[Drawing.Color]::FromArgb(14,16,20);$C.Panel=[Drawing.Color]::FromArgb(24,27,33);$C.Control=[Drawing.Color]::FromArgb(35,39,47);$C.Fg=[Drawing.Color]::FromArgb(235,240,246);$C.Muted=[Drawing.Color]::FromArgb(155,165,178);$C.White=[Drawing.Color]::White
    }
}
Set-Theme $ThemeName

$form=New-Object Windows.Forms.Form
$form.Text="CyberCroc — $script:CcPcId";$form.StartPosition='CenterScreen';$form.WindowState='Maximized';$form.AutoScaleMode=[Windows.Forms.AutoScaleMode]::Dpi;$form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96);$form.MinimumSize=New-Object Drawing.Size(960,640);$form.BackColor=$C.Bg;$form.ForeColor=$C.Fg;$form.Font=New-Object Drawing.Font('Segoe UI',10);$form.ControlBox=$false;

function New-Label([string]$Text,[int]$Size=10,[System.Drawing.FontStyle]$Style='Regular'){
    $x=New-Object Windows.Forms.Label;$x.Text=$Text;$x.AutoSize=$true;$x.Font=New-Object Drawing.Font('Segoe UI',$Size,$Style);$x.ForeColor=$C.Fg;return $x
}
function New-Button([string]$Text,[int]$Width=220,[int]$Height=56){
    $x=New-Object Windows.Forms.Button;$x.Text=$Text;$x.Width=$Width;$x.Height=$Height;$x.Margin=New-Object Windows.Forms.Padding(6);$x.FlatStyle='Flat';$x.FlatAppearance.BorderSize=1;$x.FlatAppearance.BorderColor=$C.Control;$x.BackColor=$C.Control;$x.ForeColor=$C.Fg;$x.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold);$x.Cursor=[Windows.Forms.Cursors]::Hand;$x.TabStop=$true
    try{ $gp=New-Object System.Drawing.Drawing2D.GraphicsPath; $r=New-Object Drawing.Rectangle(0,0,$Width,$Height); $rad=10; $gp.AddArc($r.X,$r.Y,$rad,$rad,180,90);$gp.AddArc($r.Right-$rad,$r.Y,$rad,$rad,270,90);$gp.AddArc($r.Right-$rad,$r.Bottom-$rad,$rad,$rad,0,90);$gp.AddArc($r.X,$r.Bottom-$rad,$rad,$rad,90,90);$gp.CloseFigure();$x.Region=New-Object Drawing.Region($gp) }catch{}
    return $x
}
function New-PageTitle([string]$Title,[string]$Hint){
    $p=New-Object Windows.Forms.Panel;$p.Dock='Top';$p.Height=82;$p.BackColor=$C.Panel
    $t=New-Label $Title 22 'Bold';$t.Location=New-Object Drawing.Point(24,14);$p.Controls.Add($t)
    $h=New-Label $Hint 10;$h.ForeColor=$C.Muted;$h.Location=New-Object Drawing.Point(26,50);$p.Controls.Add($h);return $p
}
function New-Card([string]$Title,[string]$Value,[string]$Hint){
    $p=New-Object Windows.Forms.Panel;$p.Width=280;$p.Height=132;$p.Margin=New-Object Windows.Forms.Padding(8);$p.BackColor=$C.Panel;$p.BorderStyle='FixedSingle'
    $a=New-Label $Title 10 'Bold';$a.ForeColor=$C.Muted;$a.Location=New-Object Drawing.Point(15,13);$a.MaximumSize=New-Object Drawing.Size(250,0);$p.Controls.Add($a)
    $v=New-Label $Value 21 'Bold';$v.Location=New-Object Drawing.Point(15,39);$v.MaximumSize=New-Object Drawing.Size(250,0);$p.Controls.Add($v)
    $h=New-Label $Hint 9;$h.ForeColor=$C.Muted;$h.Location=New-Object Drawing.Point(15,91);$h.MaximumSize=New-Object Drawing.Size(250,0);$p.Controls.Add($h);return $p
}
function New-Flow([string]$Direction='LeftToRight'){
    $p=New-Object Windows.Forms.FlowLayoutPanel;$p.Dock='Fill';$p.AutoScroll=$true;$p.WrapContents=$true;$p.Padding=New-Object Windows.Forms.Padding(18);$p.FlowDirection=$Direction;$p.BackColor=$C.Bg;return $p
}
function Toast($Title,$Message,$Level='INFO'){Show-CcToast $Title $Message $Level}
function Request-CcAdminAccess{try{$d=New-Object Windows.Forms.Form;$d.Text='Требуется пароль';$d.StartPosition='CenterParent';$d.Size=New-Object Drawing.Size(420,180);$d.BackColor=$C.Bg;$d.ForeColor=$C.Fg;$l=New-Object Windows.Forms.TableLayoutPanel;$l.Dock='Fill';$l.Padding=New-Object Windows.Forms.Padding(14);$l.ColumnCount=2;$l.RowCount=2;$d.Controls.Add($l);[void]$l.Controls.Add((New-Label 'Пароль администратора'),0,0);$p=New-Object Windows.Forms.TextBox;$p.UseSystemPasswordChar=$true;$p.Dock='Fill';Apply-ControlTheme $p;$l.Controls.Add($p,1,0);$ok=New-Button 'ПРОДОЛЖИТЬ' 150 50;$ok.Add_Click({if(Test-CcAdminPassword $p.Text){$d.DialogResult=[Windows.Forms.DialogResult]::OK;$d.Close()}else{[void][Windows.Forms.MessageBox]::Show('Неверный пароль.','CyberCroc',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)}});$l.Controls.Add($ok,1,1);$result=$d.ShowDialog($form);return ($result -eq [Windows.Forms.DialogResult]::OK)}catch{Write-CcError -FunctionName 'Request-CcAdminAccess' -Exception $_.Exception;return $false}}
function Show-CcErrorPopup([string]$Title,[System.Exception]$Exception){$msg=if($Exception){$Exception.Message}else{'Неизвестная ошибка.'};try{Write-CcError -FunctionName $Title -Exception $Exception}catch{};try{[void][Windows.Forms.MessageBox]::Show("Операция не выполнена.`n`n$msg`n`nПодробности: logs\\errors.log",'CyberCroc — ошибка',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)}catch{}}
function Apply-ControlTheme([Windows.Forms.Control]$x){
    try{
        $x.BackColor=$C.Control;$x.ForeColor=$C.Fg
        if($x -is [Windows.Forms.Button]){$x.FlatStyle='Flat';$x.FlatAppearance.BorderColor=$C.Fg;$x.FlatAppearance.BorderSize=1}
        foreach($child in $x.Controls){Apply-ControlTheme $child}
    }catch{}
}


function Show-CcClientOverlay([string]$Title,[string]$Message,[bool]$Emergency=$false){
    try{
        $d=New-Object Windows.Forms.Form;$d.Text=$Title;$d.StartPosition='CenterScreen';$d.WindowState='Maximized';$d.FormBorderStyle='None';$d.TopMost=$true;$d.ShowInTaskbar=$true;$d.BackColor=$(if($Emergency){$C['Danger']}else{$C.Panel});$d.ForeColor=$C.White
        $table=New-Object Windows.Forms.TableLayoutPanel;$table.Dock='Fill';$table.ColumnCount=1;$table.RowCount=3;[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,150)));[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$table.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,120)));$d.Controls.Add($table)
        $titleLabel=New-Label $Title 34 'Bold';$titleLabel.ForeColor=$C.White;$titleLabel.AutoSize=$false;$titleLabel.TextAlign='MiddleCenter';$titleLabel.Dock='Fill';$table.Controls.Add($titleLabel,0,0)
        $msg=New-Label $Message 18;$msg.ForeColor=$C.White;$msg.AutoSize=$false;$msg.TextAlign='MiddleCenter';$msg.Dock='Fill';$table.Controls.Add($msg,0,1)
        $ok=New-Button $(if($Emergency){'Я УВИДЕЛ'}else{'ЗАКРЫТЬ СООБЩЕНИЕ'}) 280 72;$ok.Anchor='None';$ok.BackColor=$C.White;$ok.ForeColor=$C.Panel;$ok.Add_Click({$d.Close()});$table.Controls.Add($ok,0,2)
        [System.Media.SystemSounds]::Exclamation.Play();[void]$d.ShowDialog($form)
    }catch{Write-CcError -FunctionName 'Show-CcClientOverlay' -Exception $_.Exception}
}
function Apply-RoleVisibility {
    if($script:CcRole -eq 'client'){
        foreach($key in @('hall','zapret','backup','cleanup','logs','audit','settings')){if($navButtons.ContainsKey($key)){$navButtons[$key].Visible=$false}}
        if($navButtons.ContainsKey('support')){$navButtons['support'].Visible=$true}
        if($navButtons.ContainsKey('accounts')){$aCheck.Visible=$false;$aAdd.Visible=$false;$aEdit.Visible=$false;$aDel.Visible=$false}
        $orderList.Visible=$false;$ordersGrid.ColumnStyles[0].Width=100;$ordersGrid.ColumnStyles[1].Width=0;$orderPreparing.Visible=$false;$orderDelivered.Visible=$false;$orderRejected.Visible=$false;$orderEdit.Visible=$false
        $appInstallOne.Visible=$false;$appUpdateOne.Visible=$false
    } else {
        if($navButtons.ContainsKey('support')){$navButtons['support'].Visible=$false}
        $orderList.Visible=$true;$ordersGrid.ColumnStyles[0].Width=56;$ordersGrid.ColumnStyles[1].Width=44;$orderPreparing.Visible=$true;$orderDelivered.Visible=$true;$orderRejected.Visible=$true;$orderEdit.Visible=$true
    }
}

# Application shell
$shell=New-Object Windows.Forms.TableLayoutPanel;$shell.Dock='Fill';$shell.ColumnCount=2;$shell.RowCount=2
[void]$shell.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,200)));[void]$shell.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
[void]$shell.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$shell.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,32)));$form.Controls.Add($shell)

$nav=New-Object Windows.Forms.Panel;$nav.Dock='Fill';$nav.BackColor=$C.Panel;$nav.Padding=New-Object Windows.Forms.Padding(12,18,12,12);$shell.Controls.Add($nav,0,0)
$brand=New-Label 'CYBER CROC' 20 'Bold';$brand.ForeColor=$C.Accent;$brand.Location=New-Object Drawing.Point(18,16);$nav.Controls.Add($brand)
$brand2=New-Label "$script:CcRole / $script:CcPcId  |  CyberCroc $Version" 8 'Bold';$brand2.ForeColor=$C.Muted;$brand2.Location=New-Object Drawing.Point(20,49);$brand2.AutoSize=$true;$nav.Controls.Add($brand2)
$menu=New-Object Windows.Forms.FlowLayoutPanel;$menu.Dock='Fill';$menu.Padding=New-Object Windows.Forms.Padding(0,92,0,8);$menu.FlowDirection='TopDown';$menu.WrapContents=$false;$menu.AutoScroll=$true;$menu.BackColor=$C.Panel;$nav.Controls.Add($menu)

$content=New-Object Windows.Forms.Panel;$content.Dock='Fill';$content.BackColor=$C.Bg;$shell.Controls.Add($content,1,0)
$pageHost=New-Object Windows.Forms.Panel;$pageHost.Dock='Fill';$pageHost.BackColor=$C.Bg;$content.Controls.Add($pageHost)
$progressPanel=New-Object Windows.Forms.Panel;$progressPanel.Dock='Top';$progressPanel.Height=34;$progressPanel.BackColor=$C.Panel;$content.Controls.Add($progressPanel)
$progressLabel=New-Label 'Выполняется операция...' 9;$progressLabel.Location=New-Object Drawing.Point(12,7);$progressLabel.ForeColor=$C.Muted;$progressPanel.Controls.Add($progressLabel)
$progress=New-Object Windows.Forms.ProgressBar;$progress.Style='Marquee';$progress.Visible=$false;$progress.Dock='Right';$progress.Width=260;$progress.Height=18;$progressPanel.Controls.Add($progress)
$footer=New-Label "ПК: $([Environment]::MachineName)   |   CyberCroc $Version" 9;$footer.ForeColor=$C.Muted;$footer.TextAlign='MiddleLeft';$footer.Dock='Fill';$footer.Padding=New-Object Windows.Forms.Padding(14,0,0,0);$shell.Controls.Add($footer,0,1);$shell.SetColumnSpan($footer,2)
$clock=New-Label '' 9;$clock.ForeColor=$C.Muted;$clock.AutoSize=$false;$clock.Dock='Right';$clock.Width=110;$clock.TextAlign='MiddleRight';$footer.Controls.Add($clock)
$script:CcAllowClose=$false
$script:CcLastAdminSeenUtc=(Get-Date).ToUniversalTime().AddMinutes(-10)
$script:CcLastBeaconUtc=(Get-Date).ToUniversalTime().AddMinutes(-10)
$script:CcLastQueueRetryUtc=(Get-Date).ToUniversalTime().AddMinutes(-10)
$script:CcKnownNodes=@{}
$pages=@{};$navButtons=@{};$uiTip=New-Object Windows.Forms.ToolTip;$uiTip.AutoPopDelay=6000;$uiTip.InitialDelay=400;$uiTip.ReshowDelay=200
function Clear-Content{$pageHost.Controls.Clear()}
function Add-MenuButton([string]$Key,[string]$Text){
    $b=New-Button $Text 190 46;$b.TextAlign='MiddleLeft';$b.Padding=New-Object Windows.Forms.Padding(14,0,0,0);$b.Tag=$Key;$menu.Controls.Add($b);$navButtons[$Key]=$b;$b.Add_Click({param($sender,$eventArgs) try{Write-CcLog "Navigation: $($sender.Tag)" 'INFO' 'UI';Show-Page ([string]$sender.Tag)}catch{Show-CcErrorPopup 'Navigation' $_.Exception}})
}
function Show-Page([string]$Key){
    try{
        if(-not $pages.ContainsKey($Key)){return};Clear-Content;$pageHost.Controls.Add($pages[$Key])
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
$wl=New-Label "ПК $([Environment]::MachineName) готов к работе" 18 'Bold';$wl.Location=New-Object Drawing.Point(18,12);$welcome.Controls.Add($wl)
$wh=New-Label 'Зелёный статус = всё нормально. Если что-то красное — нажмите «Проверить ПК».' 10;$wh.ForeColor=$C.Muted;$wh.Location=New-Object Drawing.Point(20,50);$welcome.Controls.Add($wh)
$pcInfo=New-Object Windows.Forms.Panel;$pcInfo.Dock='Fill';$pcInfo.Margin=New-Object Windows.Forms.Padding(6);$pcInfo.BackColor=$C.Panel;$homeBody.Controls.Add($pcInfo,0,1)
$pcTitle=New-Label 'PC  ЭТОТ КОМПЬЮТЕР' 12 'Bold';$pcTitle.Location=New-Object Drawing.Point(16,12);$pcInfo.Controls.Add($pcTitle)
$pcDetails=New-Label 'Получение данных...' 9;$pcDetails.Location=New-Object Drawing.Point(18,42);$pcDetails.Size=New-Object Drawing.Size(500,100);$pcDetails.AutoSize=$false;$pcInfo.Controls.Add($pcDetails)
$diskInfo=New-Object Windows.Forms.Panel;$diskInfo.Dock='Fill';$diskInfo.Margin=New-Object Windows.Forms.Padding(6);$diskInfo.BackColor=$C.Panel;$homeBody.Controls.Add($diskInfo,1,1)
$diskTitle=New-Label 'ДИСК  ДИСКИ' 12 'Bold';$diskTitle.Location=New-Object Drawing.Point(16,12);$diskInfo.Controls.Add($diskTitle)
$diskDetails=New-Label 'Получение данных...' 9;$diskDetails.Location=New-Object Drawing.Point(18,42);$diskDetails.Size=New-Object Drawing.Size(500,100);$diskDetails.AutoSize=$false;$diskInfo.Controls.Add($diskDetails)
$health=New-Object Windows.Forms.Panel;$health.Dock='Fill';$health.Margin=New-Object Windows.Forms.Padding(6);$health.BackColor=$C.Panel;$homeBody.Controls.Add($health,0,2);$homeBody.SetColumnSpan($health,2)
$healthTitle=New-Label 'СТАТУС  СОСТОЯНИЕ ПК' 12 'Bold';$healthTitle.Location=New-Object Drawing.Point(16,12);$health.Controls.Add($healthTitle)
$healthText=New-Label 'Нажмите «Проверить ПК», чтобы проверить компьютер.' 10;$healthText.Location=New-Object Drawing.Point(18,45);$healthText.AutoSize=$true;$health.Controls.Add($healthText)
$homeActions=New-Object Windows.Forms.FlowLayoutPanel;$homeActions.Dock='Fill';$homeActions.Margin=New-Object Windows.Forms.Padding(6);$homeActions.BackColor=$C.Bg;$homeBody.Controls.Add($homeActions,0,3);$homeBody.SetColumnSpan($homeActions,2)
$homeCheck=New-Button 'ПРОВЕРКА  ПРОВЕРИТЬ ПК' 220 62;$homeCleanup=New-Button 'ОЧИСТКА  ОЧИСТИТЬ ПК' 220 62;$homeBackup=New-Button 'ДИСК  БЭКАП' 220 62
$homeActions.Controls.Add($homeCheck);$homeActions.Controls.Add($homeCleanup);$homeActions.Controls.Add($homeBackup)
function Refresh-Home{
    try{
        $h=Get-CcHardware;$inv=Get-CcInventory;$disks=@(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)
        $pcDetails.Text="Производитель: $($inv.Manufacturer)$([Environment]::NewLine)Модель: $($inv.Model)$([Environment]::NewLine)CPU: $($h.CPU)$([Environment]::NewLine)GPU: $($h.GPU)$([Environment]::NewLine)RAM: $($h.RAM)$([Environment]::NewLine)Windows: $($h.OS)$([Environment]::NewLine)Температура CPU: $($h.CpuTemp)"
        $diskDetails.Text=($disks|ForEach-Object{"$($_.DeviceID) — $([math]::Round($_.FreeSpace/1GB,1)) / $([math]::Round($_.Size/1GB,1)) GB свободно из $([math]::Round($_.Size/1GB,1)) GB"}) -join ([Environment]::NewLine)
        $healthText.Text='✓ Компьютер отвечает. Система готова к работе.';$healthText.ForeColor=$C.Accent
        $footer.Text="CyberCroc $Version   |   Разработчик: Эдуард   |   ПК: $([Environment]::MachineName)"
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
$gameButtons=New-Flow;$gameInstall=New-Button 'УСТАНОВКА  УСТАНОВИТЬ' 180 58;$gameLaunch=New-Button 'ЗАПУСК  ЗАПУСТИТЬ' 170 58;$gameUpdate=New-Button 'ОБНОВЛЕНИЕ  ОБНОВИТЬ' 160 58;$gameLan=New-Button 'LAN  ЛОКАЛЬНАЯ СЕТЬ' 190 58;$gameCachePublish=New-Button 'РАЗДАТЬ ИГРУ ПО LAN' 190 58;$gameCacheSync=New-Button 'СКАЧАТЬ ИГРУ ПО LAN' 190 58;$gameAdd=New-Button '+ Своя игра' 140 58;$gameAccounts=New-Button 'АККАУНТЫ АДМИНА' 190 58;$gameButtons.Controls.Add($gameInstall);$gameButtons.Controls.Add($gameLaunch);$gameButtons.Controls.Add($gameUpdate);$gameButtons.Controls.Add($gameLan);$gameButtons.Controls.Add($gameCachePublish);$gameButtons.Controls.Add($gameCacheSync);$gameButtons.Controls.Add($gameAdd);$gameButtons.Controls.Add($gameAccounts);$gameGrid.Controls.Add($gameButtons,0,2);$gameGrid.SetColumnSpan($gameButtons,2)
$script:GameCatalog=@()
function Load-GameCatalog{
    try{
        $path=Join-Path $Root 'games.txt'
        if(-not(Test-Path -LiteralPath $path)){
            Write-CcLog "games.txt not found: $path. Starting with empty local catalog." 'WARN' 'Load-GameCatalog'
            $script:GameCatalog=@()
        } else {
        foreach($raw in Get-Content -LiteralPath $path -Encoding UTF8){
            $line=$raw.Trim();if(-not $line -or $line -match '^[#;]'){continue}
            $c=@($line -split '\|',7);while($c.Count -lt 7){$c+=''}
            $source=$c[2].Trim().ToLowerInvariant();$launcher=$c[3].Trim()
            if(-not $launcher){$launcher=switch($source){'steam' {'Steam'} 'epic' {'Epic Games'} 'riot' {'Riot Games'} 'battle.net' {'Battle.net'} 'battle' {'Battle.net'} default {if($source){$source}else{'Other'}}}}
            $price=if($c[6].Trim()){$c[6].Trim()}else{'Бесплатно'}
            $script:GameCatalog += [pscustomobject]@{Name=$c[0].Trim();PathCheck=$c[1].Trim();Source=$source;Launcher=$launcher;AppID=$c[4].Trim();Price=$price}
        }
        }
        try{$remoteGames=@(Update-CcGamesCatalogDaily);foreach($rg in $remoteGames){$existing=$script:GameCatalog|Where-Object{$_.Name -eq $rg.Name}|Select-Object -First 1;$mapped=[pscustomobject]@{Name=$rg.Name;PathCheck=$rg.InstallPath;Source=$rg.Source;Launcher=$rg.Launcher;AppID=$rg.AppId;Price='Бесплатно'};if($existing){$script:GameCatalog=@($script:GameCatalog|Where-Object{$_.Name -ne $rg.Name})+$mapped}else{$script:GameCatalog+=$mapped}}}catch{Write-CcError -FunctionName 'Load-RemoteGames' -Exception $_.Exception}
if($script:GameCatalog.Count -eq 0){Write-CcLog 'games.txt пуст или отсутствует; каталог игр оставлен пустым.' 'WARN' 'Load-GameCatalog'}
        Write-CcLog "Game catalog loaded: $($script:GameCatalog.Count) items" 'OK' 'Load-GameCatalog'
    }catch{Write-CcError -FunctionName 'Load-GameCatalog' -Exception $_.Exception;throw}
}
Load-GameCatalog
function Get-CcFuzzyScore([string]$Text,[string]$Query){
    if([string]::IsNullOrWhiteSpace($Query)){return 100}
    $t=([string]$Text).ToLowerInvariant();$q=([string]$Query).ToLowerInvariant()
    if($t.Contains($q)){return 100}
    $m=$q.Length;$n=$t.Length;if($m -eq 0){return 100};if($n -eq 0){return 0}
    $prev=New-Object int[] ($n+1);$curr=New-Object int[] ($n+1);for($j=0;$j-le$n;$j++){$prev[$j]=$j}
    for($i=1;$i-le$m;$i++){ $curr[0]=$i; for($j=1;$j-le$n;$j++){ $cost=if($q[$i-1]-eq$t[$j-1]){0}else{1};$curr[$j]=[math]::Min([math]::Min($curr[$j-1]+1,$prev[$j]+1),$prev[$j-1]+$cost) };$tmp=$prev;$prev=$curr;$curr=$tmp }
    $distance=$prev[$n];$max=[math]::Max($m,$n);return [math]::Max(0,100-(100*$distance/$max))
}
function Test-CcGameInstalled([object]$Game){
    try{
        $path=Expand-CcPath ([string]$Game.PathCheck)
        if($path -and (Test-Path -LiteralPath $path -PathType Leaf)){return $true}
        if($Game.Launcher -eq 'Steam' -and $Game.AppID){$roots=@((Join-Path ${env:ProgramFiles(x86)} 'Steam\steamapps'),(Join-Path $env:ProgramFiles 'Steam\steamapps'));foreach($root in $roots){if(Test-Path $root){$manifest=Join-Path $root ("appmanifest_$($Game.AppID).acf");if(Test-Path $manifest){return $true}}}}
        return $false
    }catch{return $false}
}
function Refresh-GameCatalog{
    try{
        $gameList.Items.Clear();$q=$gameSearch.Text;if($q -eq 'Поиск игры...'){$q=''};$f=[string]$gameFilter.Text;$rows=@()
        foreach($g in $script:GameCatalog){if($f -ne 'Все' -and $g.Launcher -ne $f){continue};$score=Get-CcFuzzyScore $g.Name $q;if($q -and $score -lt 35){continue};$rows+=[pscustomobject]@{Game=$g;Score=$score}}
        foreach($row in @($rows|Sort-Object Score -Descending, @{Expression={$_.Game.Name}})){ $g=$row.Game;$installed=if(Test-CcGameInstalled $g){'Да'}else{'Нет'};$i=[Windows.Forms.ListViewItem]::new([string]$g.Name);[void]$i.SubItems.Add($g.Launcher);[void]$i.SubItems.Add($g.Price);[void]$i.SubItems.Add($installed);$i.Tag=$g;[void]$gameList.Items.Add($i) }
    }catch{Write-CcError -FunctionName 'Refresh-GameCatalog' -Exception $_.Exception}
}
$gameSearch.Add_GotFocus({if($gameSearch.Text -eq 'Поиск игры...'){$gameSearch.Text='';$gameSearch.ForeColor=$C.Fg}});$gameSearch.Add_TextChanged({Refresh-GameCatalog});$gameFilter.Add_SelectedIndexChanged({Refresh-GameCatalog});$gameLan.Add_Click({try{Write-CcLog 'LAN game scan requested' 'INFO' 'UI';Scan-LanGames}catch{Show-CcErrorPopup 'Локальная сеть' $_.Exception}})
$gameCachePublish.Add_Click({try{if($script:CcRole -ne 'admin'){throw 'Раздавать игры по LAN может только администратор.'};if(-not(Request-CcAdminAccess)){return};if(-not $gameList.SelectedItems.Count){throw 'Сначала выберите игру в списке.'};$g=$gameList.SelectedItems[0].Tag;$dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description="Выберите папку с установленными файлами игры $($g.Name) на этом ПК";$dialog.ShowNewFolderButton=$false;if($dialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK){return};$progress.Visible=$true;$result=Publish-CcGameCache -GameName ([string]$g.Name) -SourcePath $dialog.SelectedPath -Confirm:$false;Toast 'LAN-кэш' ("Опубликовано: {0} файлов, {1:N1} ГБ" -f $result.FileCount,($result.TotalBytes/1GB)) 'OK';$gameInfo.Text="Игра опубликована в локальной сети.`r`nФайлов: $($result.FileCount)`r`nРазмер: $([math]::Round($result.TotalBytes/1GB,1)) ГБ`r`nПуть: $($result.Path)"}catch{Show-CcErrorPopup 'Раздача игры по LAN' $_.Exception}finally{$progress.Visible=$false}})
$gameCacheSync.Add_Click({try{if(-not $gameList.SelectedItems.Count){throw 'Сначала выберите игру в списке.'};$g=$gameList.SelectedItems[0].Tag;$dialog=New-Object Windows.Forms.FolderBrowserDialog;$dialog.Description="Выберите папку установки игры $($g.Name) на этом ПК (файлы будут обновлены, другие файлы не удаляются)";$dialog.ShowNewFolderButton=$true;if($dialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK){return};$progress.Visible=$true;$result=Sync-CcGameCache -GameName ([string]$g.Name) -DestinationPath $dialog.SelectedPath -Confirm:$false;Toast 'LAN-кэш' ("Синхронизация завершена. Изменено файлов: {0}" -f $result.ChangedFiles) 'OK';$gameInfo.Text="Синхронизация из LAN-кэша завершена.`r`nИзменено файлов: $($result.ChangedFiles)`r`nПапка: $($result.Destination)"}catch{Show-CcErrorPopup 'Скачать игру по LAN' $_.Exception}finally{$progress.Visible=$false}})
$gameAdd.Add_Click({try{if($script:CcRole -ne 'admin' -or -not(Request-CcAdminAccess)){return};Show-CustomGameDialog}catch{Show-CcErrorPopup 'Своя игра' $_.Exception}});$gameAccounts.Add_Click({try{if($script:CcRole -ne 'admin'){throw 'Добавление аккаунтов доступно только администратору.'};if(-not(Request-CcAdminAccess)){return};Show-AccountDialog;Show-Page 'accounts'}catch{Show-CcErrorPopup 'Игровые аккаунты' $_.Exception}})
$gameInstall.Add_Click({if(-not $gameList.SelectedItems.Count){Show-CcErrorPopup 'Игры' ([Exception]'Сначала выберите игру.');return};$g=$gameList.SelectedItems[0].Tag;try{if($g.Launcher -eq 'Steam' -and $g.AppID){Start-Process "steam://install/$($g.AppID)"}elseif($g.Launcher -eq 'Epic Games'){Start-Process 'com.epicgames.launcher://apps'}elseif($g.Launcher -eq 'Riot Games'){$exe=Get-CcLauncherExe 'RiotClientServices.exe';if($exe){Start-Process $exe}else{throw 'Riot Client не найден.'}}else{Start-Process 'https://www.blizzard.com/'};Toast 'Игры' "Открыт лаунчер: $($g.Launcher)" 'OK'}catch{Show-CcErrorPopup 'Установка игры' $_.Exception}})
$gameLaunch.Add_Click({if($gameList.SelectedItems.Count){$g=$gameList.SelectedItems[0].Tag;try{if($g.Launcher -eq 'Steam' -and $g.AppID){Start-Process "steam://rungameid/$($g.AppID)"}else{throw "Запуск $($g.Name) требует лаунчер $($g.Launcher)."}}catch{Show-CcErrorPopup 'Запуск игры' $_.Exception}}else{Show-CcErrorPopup 'Игры' ([Exception]'Сначала выберите игру.')}})
$gameUpdate.Add_Click({Toast 'Игры' 'Проверка обновлений игры передана лаунчеру.' 'INFO'})
function Save-GameCatalogToFile{param([object[]]$Catalog);try{$path=Join-Path $Root 'games.txt';$lines=@('# CyberCroc game inventory','# Format: Name|PathCheck|Source|Launcher|AppID|MinVersion|Price');foreach($g in $Catalog){$lines+=('{0}|{1}|{2}|{3}|{4}||{5}' -f $g.Name,$g.PathCheck,([string]$g.Launcher).ToLowerInvariant(),$g.Launcher,$g.AppID,$g.Price)};Set-Content -LiteralPath $path -Value $lines -Encoding UTF8;Write-CcLog "Game catalog saved: $($Catalog.Count) items" 'OK' 'Save-GameCatalogToFile';return $true}catch{Write-CcError -FunctionName 'Save-GameCatalogToFile' -Exception $_.Exception;return $false}}
function Show-CustomGameDialog{
try{
$d=New-Object Windows.Forms.Form;$d.Text='Добавить свою игру';$d.StartPosition='CenterParent';$d.Size=New-Object Drawing.Size(560,360);$d.BackColor=$C.Bg;$d.ForeColor=$C.Fg
$l=New-Object Windows.Forms.TableLayoutPanel;$l.Dock='Fill';$l.Padding=New-Object Windows.Forms.Padding(14);$l.ColumnCount=2;$l.RowCount=6;[void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,150)));[void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));$d.Controls.Add($l)
$fields=@{};$labels=@('Название','Лаунчер','Цена','Путь к EXE','AppID');for($i=0;$i -lt 5;$i++){[void]$l.Controls.Add((New-Label $labels[$i]),0,$i);$t=New-Object Windows.Forms.TextBox;$t.Dock='Fill';Apply-ControlTheme $t;$fields[$labels[$i]]=$t;[void]$l.Controls.Add($t,1,$i)};$fields['Лаунчер'].Text='Steam';$fields['Цена'].Text='Бесплатно'
$buttons=New-Flow;$ok=New-Button 'Сохранить' 150 52;$cancel=New-Button 'Отмена' 130 52;$buttons.Controls.Add($ok);$buttons.Controls.Add($cancel);$l.Controls.Add($buttons,1,5);$cancel.Add_Click({$d.Close()})
$ok.Add_Click({try{if([string]::IsNullOrWhiteSpace($fields['Название'].Text)){throw 'Введите название игры.'};$g=[pscustomobject]@{Name=$fields['Название'].Text.Trim();PathCheck=$fields['Путь к EXE'].Text.Trim();Launcher=$fields['Лаунчер'].Text.Trim();Price=$fields['Цена'].Text.Trim();AppID=$fields['AppID'].Text.Trim()};$script:GameCatalog=@($script:GameCatalog|Where-Object{$_.Name -ne $g.Name})+$g;if(-not(Save-GameCatalogToFile $script:GameCatalog)){throw 'Не удалось сохранить games.txt'};Refresh-GameCatalog;$d.Close();Toast 'Игры' 'Игра добавлена в каталог.' 'OK'}catch{Write-CcError -FunctionName 'CustomGameDialog' -Exception $_.Exception;Show-CcErrorPopup 'Своя игра' $_.Exception}});[void]$d.ShowDialog($form)
}catch{Write-CcError -FunctionName 'Show-CustomGameDialog' -Exception $_.Exception;throw}}
function Scan-LanGames{
    try{
        $progressLabel.Text='Локальная сеть: сканирование...';$progress.Visible=$true;Write-CcLog 'LAN scan started' 'INFO' 'Scan-LanGames';$gameInfo.Text='Сканирую компьютеры локальной сети...'
        $cmd=Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue
        if($null -eq $cmd){throw 'Команда Get-NetNeighbor недоступна. Проверьте компоненты Windows.'}
        $peers=@(Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop | Where-Object {$_.State -in @('Reachable','Stale','Delay','Probe') -and $_.IPAddress -notlike '224.*' -and $_.IPAddress -notlike '239.*'} | Select-Object -ExpandProperty IPAddress -Unique)
        $rows=@()
        foreach($ip in $peers){$name=$ip;try{$name=[System.Net.Dns]::GetHostEntry($ip).HostName}catch{Write-CcLog "DNS lookup failed for $ip" 'WARN' 'Scan-LanGames'};$rows+="${name}  [$ip]"}
        if($rows.Count){$gameInfo.Text="Найдено ПК: $($rows.Count)`r`n`r`n"+($rows -join "`r`n")}else{$gameInfo.Text='Активные ПК в локальной сети не найдены.'}
        Write-CcLog "LAN scan finished: $($rows.Count) hosts" 'OK' 'Scan-LanGames'
    }catch{Write-CcError -FunctionName 'Scan-LanGames' -Exception $_.Exception;Show-CcErrorPopup 'Локальная сеть' $_.Exception}
    finally{$progress.Visible=$false;$progressLabel.Text='Выполняется операция...'}
}
$pages['games']=$games;$games.Controls[0].BringToFront();Refresh-GameCatalog
# Accounts
$accounts=New-Object Windows.Forms.Panel;$accounts.Dock='Fill';$accounts.BackColor=$C.Bg;$accounts.Controls.Add((New-PageTitle 'Аккаунты' 'Игровые аккаунты клуба. Не нужно открывать отдельные программы.'))
$accountArea=New-Object Windows.Forms.TableLayoutPanel;$accountArea.Dock='Fill';$accountArea.Padding=New-Object Windows.Forms.Padding(20,100,20,15);$accountArea.RowCount=2
[void]$accountArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$accountArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,72)));$accounts.Controls.Add($accountArea)
$aList=New-Object Windows.Forms.ListView;$aList.View='Details';$aList.FullRowSelect=$true;$aList.MultiSelect=$false;$aList.Dock='Fill';$aList.BackColor=$C.Control;$aList.ForeColor=$C.Fg
[void]$aList.Columns.Add('Платформа',130);[void]$aList.Columns.Add('Логин',180);[void]$aList.Columns.Add('Статус',110);[void]$aList.Columns.Add('Занят ПК',120);[void]$aList.Columns.Add('Проверка',145);$accountArea.Controls.Add($aList,0,0)
$ab=New-Flow;$aLogin=New-Button 'ВОЙТИ' 170 58;$aCheck=New-Button 'Проверить' 150 58;$aAdd=New-Button '+ Добавить' 150 58;$aEdit=New-Button 'Изменить' 140 58;$aDel=New-Button 'Удалить' 130 58
foreach($b in @($aLogin,$aCheck,$aAdd,$aEdit,$aDel)){$ab.Controls.Add($b)};$accountArea.Controls.Add($ab,0,1)
function Refresh-Accounts{try{$aList.Items.Clear();foreach($a in @(Get-CcAccounts)){$i=[Windows.Forms.ListViewItem]::new([string]$a.Platform);[void]$i.SubItems.Add([string]$a.Login);[void]$i.SubItems.Add([string]$a.Status);$occupiedBy=[string]$(if($a.UsedBy){$a.UsedBy}elseif($a.ActivePc){$a.ActivePc}elseif($a.PcId){$a.PcId}else{'—'});[void]$i.SubItems.Add($occupiedBy);[void]$i.SubItems.Add([string]$a.LastCheck);$i.Tag=$a;[void]$aList.Items.Add($i)}}catch{Write-CcError -FunctionName 'Refresh-Accounts' -Exception $_.Exception}}
function Invoke-AccountLogin {if(-not $aList.SelectedItems.Count){Toast 'Аккаунты' 'Выберите аккаунт.' 'INFO';return};try{Start-CcAccountSession $aList.SelectedItems[0].Tag|Out-Null;Refresh-Accounts}catch{Show-CcErrorPopup 'Вход' $_.Exception}}
function Invoke-AccountCheck {if($script:CcRole -ne 'admin'){Toast 'Аккаунты' 'Проверка доступна только админу.' 'INFO';return};try{if(-not(Request-CcAdminAccess)){return};$progress.Visible=$true;foreach($a in @(Get-CcAccounts)){Test-CcAccount $a $cfg|Out-Null};Save-CcAccounts @(Get-CcAccounts)|Out-Null;Refresh-Accounts;Toast 'Аккаунты' 'Проверка завершена.' 'OK'}catch{Write-CcError -FunctionName 'Account-Check' -Exception $_.Exception}finally{$progress.Visible=$false}}
function Invoke-AccountAdd {if($script:CcRole -ne 'admin'){return};if(Request-CcAdminAccess){Show-AccountDialog;Write-CcAudit -Action 'account.add' -Target 'game-account' -Result 'requested' -Details 'Диалог добавления игрового аккаунта открыт'}}
function Invoke-AccountEdit {if($script:CcRole -ne 'admin'){return};if(-not $aList.SelectedItems.Count){Toast 'Аккаунты' 'Выберите аккаунт.' 'INFO';return};if(Request-CcAdminAccess){$account=$aList.SelectedItems[0].Tag;Show-AccountDialog $account;Write-CcAudit -Action 'account.edit' -Target ([string]$account.Login) -Result 'requested' -Details ([string]$account.Platform)}}
function Invoke-AccountDelete {if($script:CcRole -ne 'admin'){return};if(-not $aList.SelectedItems.Count){Toast 'Аккаунты' 'Выберите аккаунт.' 'INFO';return};if(-not(Request-CcAdminAccess)){return};$a=$aList.SelectedItems[0].Tag;$answer=[Windows.Forms.MessageBox]::Show("Удалить аккаунт $($a.Login)?",'Удаление аккаунта',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning);if($answer -eq [Windows.Forms.DialogResult]::Yes){Remove-CcAccount $a.Id|Out-Null;Write-CcAudit -Action 'account.delete' -Target ([string]$a.Login) -Result 'success' -Details ([string]$a.Platform);Refresh-Accounts}}
$aLogin.Add_Click({Invoke-AccountLogin});$aCheck.Add_Click({Invoke-AccountCheck})
function Show-AccountDialog($existing=$null){
    $d = New-Object Windows.Forms.Form
    if ($null -ne $existing) {
        $d.Text = 'Изменить аккаунт'
    }
    else {
        $d.Text = 'Добавить аккаунт'
    }
    $d.StartPosition = 'CenterParent'
    $d.Size = New-Object Drawing.Size(560,430)
    $d.BackColor = $C.Bg
    $d.ForeColor = $C.Fg

    $l = New-Object Windows.Forms.TableLayoutPanel
    $l.Dock = 'Fill'
    $l.Padding = New-Object Windows.Forms.Padding(14)
    $l.ColumnCount = 2
    $l.RowCount = 6
    [void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,140)))
    [void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)))
    $d.Controls.Add($l)

    $names = @('Платформа','Логин','Пароль','Комментарий','Игры')
    $f = @{}

    for ($r = 0; $r -lt 5; $r++) {
        [void]$l.Controls.Add((New-Label $names[$r]),0,$r)

        if ($names[$r] -eq 'Платформа') {
            $t = New-Object Windows.Forms.ComboBox
            $t.DropDownStyle = 'DropDownList'
            $t.Dock = 'Fill'
            [void]$t.Items.AddRange(@(
                'Steam',
                'Riot Games',
                'Battle.net',
                'Epic Games',
                'EA App',
                'Rockstar Games',
                'VK Play',
                'Wargaming',
                'HoYoPlay',
                'Minecraft Legacy',
                'Roblox'
            ))
        }
        elseif ($names[$r] -eq 'Игры') {
            $t = New-Object Windows.Forms.CheckedListBox
            $t.Dock = 'Fill'
            $t.CheckOnClick = $true
        }
        else {
            $t = New-Object Windows.Forms.TextBox
            $t.Dock = 'Fill'
        }

        Apply-ControlTheme $t
        $f[$names[$r]] = $t
        [void]$l.Controls.Add($t,1,$r)
    }

    $l.RowStyles.Clear()
    for ($rr = 0; $rr -lt 6; $rr++) {
        if ($rr -eq 4) {
            [void]$l.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,150)))
        }
        elseif ($rr -eq 5) {
            [void]$l.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,64)))
        }
        else {
            [void]$l.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,42)))
        }
    }

    if ($null -ne $existing) {
        $f['Платформа'].Text = [string]$existing.Platform
        $f['Логин'].Text = [string]$existing.Login
        $f['Комментарий'].Text = [string]$existing.Comment
    }
    else {
        $f['Платформа'].Text = 'Steam'
    }

    function Refresh-AccountGameChoices {
        try {
            $f['Игры'].Items.Clear()
            $platform = [string]$f['Платформа'].Text

            foreach ($g in @($script:GameCatalog | Where-Object { $_.Launcher -eq $platform })) {
                $displayName = [string]$g.Name
                $price = [string]$g.Price
                $idx = $f['Игры'].Items.Add(('{0} — {1}' -f $displayName,$price))

                if ($null -ne $existing) {
                    $savedGames = @($existing.Games)
                    if ($savedGames -contains $displayName) {
                        $f['Игры'].SetItemChecked($idx,$true)
                    }
                }
            }
        }
        catch {
            Write-CcError -FunctionName 'Refresh-AccountGameChoices' -Exception $_.Exception
        }
    }

    $f['Платформа'].Add_SelectedIndexChanged({
        Refresh-AccountGameChoices
    })

    Refresh-AccountGameChoices
    $f['Пароль'].UseSystemPasswordChar = $true

    $p = New-Flow
    $p.FlowDirection = 'RightToLeft'

    $ok = New-Button 'Сохранить' 150 52
    $cancel = New-Button 'Отмена' 150 52

    [void]$p.Controls.Add($ok)
    [void]$p.Controls.Add($cancel)
    [void]$l.Controls.Add($p,1,5)

    $cancel.Add_Click({
        $d.Close()
    })

    $ok.Add_Click({
        try {
            $games = @(
                $f['Игры'].CheckedItems |
                    ForEach-Object {
                        $gameName = [string]$_
                        $gameName = $gameName -replace '\s+—\s+(Бесплатно|Платно)$',''
                        $gameName.Trim()
                    } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            )

            $platform = [string]$f['Платформа'].Text
            $login = [string]$f['Логин'].Text
            $password = [string]$f['Пароль'].Text
            $comment = [string]$f['Комментарий'].Text

            if ([string]::IsNullOrWhiteSpace($platform)) {
                throw 'Не выбрана платформа аккаунта.'
            }

            if ([string]::IsNullOrWhiteSpace($login)) {
                throw 'Не указан логин аккаунта.'
            }

            if ($null -ne $existing) {
                $data = @{
                    Platform = $platform
                    Login = $login
                    Password = $password
                    Comment = $comment
                    Games = $games
                }
                Update-CcAccount $existing.Id $data | Out-Null
            }
            else {
                New-CcAccount $platform $login $password $comment $games | Out-Null
            }

            $d.Close()
            Refresh-Accounts
        }
        catch {
            Write-CcError -FunctionName 'Account-Dialog' -Exception $_.Exception
            Show-CcErrorPopup 'Аккаунты' $_.Exception
        }
    })

    [void]$d.ShowDialog($form)
}
$aAdd.Add_Click({Invoke-AccountAdd})
$aEdit.Add_Click({Invoke-AccountEdit})
$aDel.Add_Click({Invoke-AccountDelete})
$pages['accounts']=$accounts
$accounts.Controls[0].BringToFront()

# Applications
$app=New-Object Windows.Forms.Panel;$app.Dock='Fill';$app.BackColor=$C.Bg;$app.Controls.Add((New-PageTitle 'Программы' 'Выберите программу и нажмите «Установить». Установка идёт прямо в этой программе.'))
$appGrid=New-Object Windows.Forms.TableLayoutPanel;$appGrid.Dock='Fill';$appGrid.Padding=New-Object Windows.Forms.Padding(20,96,20,15);$appGrid.ColumnCount=2;$appGrid.RowCount=3;$appGrid.BackColor=$C.Bg;$app.Controls.Add($appGrid)
[void]$appGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,62)));[void]$appGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,38)))
[void]$appGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,52)));[void]$appGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$appGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,76)))
$appSearch=New-Object Windows.Forms.TextBox;$appSearch.Dock='Fill';$appSearch.Text='Поиск: браузер, Office, Steam...';$appSearch.Font=New-Object Drawing.Font('Segoe UI',12);Apply-ControlTheme $appSearch;$appGrid.Controls.Add($appSearch,0,0)
$appHint=New-Label 'INFO Всё устанавливается через winget. Никаких чёрных окон.' 10;$appHint.ForeColor=$C.Muted;$appHint.Dock='Fill';$appHint.TextAlign='MiddleLeft';$appGrid.Controls.Add($appHint,1,0)
$appList=New-Object Windows.Forms.ListView;$appList.View='Details';$appList.FullRowSelect=$true;$appList.MultiSelect=$false;$appList.Dock='Fill';$appList.BackColor=$C.Control;$appList.ForeColor=$C.Fg;[void]$appList.Columns.Add('Программа',260);[void]$appList.Columns.Add('Тип',110);[void]$appList.Columns.Add('Цена',90);$appGrid.Controls.Add($appList,0,1)
$appInfo=New-Object Windows.Forms.TextBox;$appInfo.Multiline=$true;$appInfo.ReadOnly=$true;$appInfo.Dock='Fill';$appInfo.ScrollBars='Vertical';$appInfo.BackColor=$C.Panel;$appInfo.ForeColor=$C.Fg;$appInfo.Text='Выберите программу слева.`r`n`r`nСписок подготовлен для клуба: браузеры, Office, игровые лаунчеры, Discord и системные компоненты.';$appGrid.Controls.Add($appInfo,1,1)
$appButtons=New-Flow;$appInstallOne=New-Button 'УСТАНОВКА  УСТАНОВИТЬ' 200 58;$appUpdateOne=New-Button 'ОБНОВЛЕНИЕ  ОБНОВИТЬ' 180 58;$appRefresh=New-Button 'ОБНОВИТЬ  ОБНОВИТЬ СПИСОК' 210 58;$appButtons.Controls.Add($appInstallOne);$appButtons.Controls.Add($appUpdateOne);$appButtons.Controls.Add($appRefresh);$appGrid.Controls.Add($appButtons,0,2);$appGrid.SetColumnSpan($appButtons,2)
$script:AppCatalog=@(
    [pscustomobject]@{Name='Google Chrome';Id='Google.Chrome';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Mozilla Firefox';Id='Mozilla.Firefox';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Microsoft Edge';Id='Microsoft.Edge';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Opera GX';Id='Opera.OperaGX';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Yandex Browser';Id='Yandex.Browser';Type='Браузер';Price='Бесплатно'},
    [pscustomobject]@{Name='Discord';Id='Discord.Discord';Type='Мессенджер';Price='Бесплатно'},
    [pscustomobject]@{Name='Telegram';Id='Telegram.TelegramDesktop';Type='Мессенджер';Price='Бесплатно'},
    [pscustomobject]@{Name='WhatsApp';Id='WhatsApp.WhatsApp';Type='Мессенджер';Price='Бесплатно'},
    [pscustomobject]@{Name='Steam';Id='Valve.Steam';Type='Лаунчер';Price='Бесплатно'},
    [pscustomobject]@{Name='Epic Games Launcher';Id='EpicGames.EpicGamesLauncher';Type='Лаунчер';Price='Бесплатно'},
    [pscustomobject]@{Name='Battle.net';Id='Blizzard.BattleNet';Type='Лаунчер';Price='Бесплатно'},
    [pscustomobject]@{Name='Riot Client';Id='RiotGames.RiotClient';Type='Лаунчер';Price='Бесплатно'},
    [pscustomobject]@{Name='GOG Galaxy';Id='GOG.Galaxy';Type='Лаунчер';Price='Бесплатно'},
    [pscustomobject]@{Name='Ubisoft Connect';Id='Ubisoft.Connect';Type='Лаунчер';Price='Бесплатно'},
    [pscustomobject]@{Name='TeamSpeak';Id='TeamSpeakSystems.TeamSpeakClient';Type='Утилита';Price='Бесплатно'},
    [pscustomobject]@{Name='OBS Studio';Id='OBSProject.OBSStudio';Type='Утилита';Price='Бесплатно'},
    [pscustomobject]@{Name='Notepad++';Id='Notepad++.Notepad++';Type='Утилита';Price='Бесплатно'},
    [pscustomobject]@{Name='LibreOffice';Id='TheDocumentFoundation.LibreOffice';Type='Офис';Price='Бесплатно'},
    [pscustomobject]@{Name='OpenOffice';Id='Apache.OpenOffice';Type='Офис';Price='Бесплатно'},
    [pscustomobject]@{Name='VLC';Id='VideoLAN.VLC';Type='Медиа';Price='Бесплатно'},
    [pscustomobject]@{Name='AIMP';Id='AIMP.AIMP';Type='Медиа';Price='Бесплатно'},
    [pscustomobject]@{Name='Visual C++ 2015-2022 x64';Id='Microsoft.VCRedist.2015+.x64';Type='Система';Price='Бесплатно'},
    [pscustomobject]@{Name='DirectX Runtime';Id='Microsoft.DirectX';Type='Система';Price='Бесплатно'},
    [pscustomobject]@{Name='7-Zip';Id='7zip.7zip';Type='Архиватор';Price='Бесплатно'},
    [pscustomobject]@{Name='PeaZip';Id='Giorgiotani.Peazip';Type='Архиватор';Price='Бесплатно'},
    [pscustomobject]@{Name='Paint.NET';Id='dotPDN.PaintDotNet';Type='Графика';Price='Бесплатно'},
    [pscustomobject]@{Name='GIMP';Id='GIMP.GIMP';Type='Графика';Price='Бесплатно'},
    [pscustomobject]@{Name='ShareX';Id='ShareX.ShareX';Type='Утилита';Price='Бесплатно'},
    [pscustomobject]@{Name='PowerToys';Id='Microsoft.PowerToys';Type='Утилита';Price='Бесплатно'},
    [pscustomobject]@{Name='CPU-Z';Id='CPUID.CPU-Z';Type='Диагностика';Price='Бесплатно'},
    [pscustomobject]@{Name='GPU-Z';Id='TechPowerUp.GPU-Z';Type='Диагностика';Price='Бесплатно'},
    [pscustomobject]@{Name='CrystalDiskInfo';Id='CrystalDewWorld.CrystalDiskInfo';Type='Диагностика';Price='Бесплатно'},
    [pscustomobject]@{Name='HWiNFO';Id='REALiX.HWiNFO';Type='Диагностика';Price='Бесплатно'},
    [pscustomobject]@{Name='Microsoft .NET Desktop Runtime 8';Id='Microsoft.DotNet.DesktopRuntime.8';Type='Система';Price='Бесплатно'},
    [pscustomobject]@{Name='Microsoft Visual C++ x86';Id='Microsoft.VCRedist.2015+.x86';Type='Система';Price='Бесплатно'},
    [pscustomobject]@{Name='Java Runtime';Id='EclipseAdoptium.Temurin.21.JRE';Type='Система';Price='Бесплатно'},
    [pscustomobject]@{Name='Python 3';Id='Python.Python.3.12';Type='Разработка';Price='Бесплатно'}
)
function Refresh-AppCatalog{try{$appList.Items.Clear();$q=$appSearch.Text;if($q -like 'Поиск:*'){$q=''};$rows=@();foreach($x in $script:AppCatalog){$score=[math]::Max((Get-CcFuzzyScore $x.Name $q),(Get-CcFuzzyScore $x.Type $q));if($q -and $score -lt 35){continue};$rows+=[pscustomobject]@{Item=$x;Score=$score}};foreach($r in @($rows|Sort-Object Score -Descending, @{Expression={$_.Item.Name}})){$x=$r.Item;$categoryIcon=switch -Regex ([string]$x.Type) {'Браузер' {'🌐'} 'Мессенджер' {'💬'} 'Лаунчер' {'🎮'} 'Офис' {'📄'} 'Архиватор' {'🗜'} 'Графика' {'🎨'} 'Диагностика' {'🩺'} 'Система' {'⚙'} default {'🧰'}};$i=[Windows.Forms.ListViewItem]::new("$categoryIcon  $($x.Name)");[void]$i.SubItems.Add($x.Type);[void]$i.SubItems.Add($x.Price);$i.Tag=$x;[void]$appList.Items.Add($i)}}catch{Write-CcError -FunctionName 'Refresh-AppCatalog' -Exception $_.Exception}}
function Start-WingetApp([object]$Item,[string]$Mode){try{$winget=(Get-Command winget.exe -ErrorAction Stop).Source;$op=if($Mode -eq 'update'){'upgrade'}else{'install'};$args=@($op,'--id',$Item.Id,'--exact','--source','winget','--accept-source-agreements','--accept-package-agreements','--silent','--disable-interactivity');$progress.Visible=$true;$appInfo.Text="Операция: $op`r`n`r`n$($Item.Name)`r`n`r`nОжидайте завершения...";$p=Start-Process -FilePath $winget -ArgumentList $args -WindowStyle Hidden -PassThru;$script:AppProcess=$p;$script:AppProcessName=$Item.Name;$script:AppProcessMode=$Mode}catch{Show-CcErrorPopup 'Установка программы' $_.Exception}}
$appInstallOne.Add_Click({if($appList.SelectedItems.Count){Start-WingetApp $appList.SelectedItems[0].Tag 'install'}else{Show-CcErrorPopup 'Программы' ([Exception]'Сначала выберите программу.')}})
$appUpdateOne.Add_Click({if($appList.SelectedItems.Count){Start-WingetApp $appList.SelectedItems[0].Tag 'update'}else{Show-CcErrorPopup 'Программы' ([Exception]'Сначала выберите программу.')}})
$appRefresh.Add_Click({try{Write-CcLog 'Application catalog refreshed' 'INFO' 'UI';Refresh-AppCatalog}catch{Show-CcErrorPopup 'Программы' $_.Exception}})
$appSearch.Add_TextChanged({Refresh-AppCatalog})
$pages['apps']=$app;$app.Controls[0].BringToFront();Refresh-AppCatalog
# Backup and cleanup
$backup=New-Object Windows.Forms.Panel;$backup.Dock='Fill';$backup.BackColor=$C.Bg;$backup.Controls.Add((New-PageTitle 'Резервная копия' 'Сохраните важные данные перед обслуживанием компьютера.'))
$bb=New-Flow;$bb.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$backup.Controls.Add($bb);$backupInfo=New-Card 'БЭКАП' 'ГОТОВ' 'копирует данные клуба';$bb.Controls.Add($backupInfo);$backupBtn=New-Button 'ДИСК  СДЕЛАТЬ БЭКАП' 280 70;$bb.Controls.Add($backupBtn);$backupBtn.Add_Click({try{Run-HiddenCmd 'Backup.cmd'}catch{Show-CcErrorPopup 'Бэкап' $_.Exception}});$pages['backup']=$backup;$backup.Controls[0].BringToFront()
$cleanup=New-Object Windows.Forms.Panel;$cleanup.Dock='Fill';$cleanup.BackColor=$C.Bg;$cleanup.Controls.Add((New-PageTitle 'Очистка' 'Выберите, что удалить. Личные документы и игры по умолчанию не трогаются.'))
$clGrid=New-Object Windows.Forms.TableLayoutPanel;$clGrid.Dock='Fill';$clGrid.Padding=New-Object Windows.Forms.Padding(20,96,20,15);$clGrid.ColumnCount=2;$clGrid.RowCount=3;$clGrid.BackColor=$C.Bg;$cleanup.Controls.Add($clGrid)
[void]$clGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,55)));[void]$clGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,45)))
[void]$clGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,48)));[void]$clGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$clGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,78)))
$clHint=New-Label 'Отметьте нужные пункты:' 11 'Bold';$clHint.Dock='Fill';$clGrid.Controls.Add($clHint,0,0);$clStatus=New-Label 'Готово. Ничего не удалено.' 10;$clStatus.ForeColor=$C.Muted;$clStatus.Dock='Fill';$clStatus.TextAlign='MiddleLeft';$clGrid.Controls.Add($clStatus,1,0)
$clChecks=New-Object Windows.Forms.FlowLayoutPanel;$clChecks.Dock='Fill';$clChecks.FlowDirection='TopDown';$clChecks.WrapContents=$false;$clChecks.AutoScroll=$true;$clChecks.BackColor=$C.Panel;$clGrid.Controls.Add($clChecks,0,1)
$drivePanel=New-Object Windows.Forms.FlowLayoutPanel;$drivePanel.Dock='Fill';$drivePanel.FlowDirection='TopDown';$drivePanel.WrapContents=$false;$drivePanel.AutoScroll=$true;$drivePanel.BackColor=$C.Panel;$clGrid.Controls.Add($drivePanel,1,1)
$driveTitle=New-Label 'ДИСК Диски — очищаются только временные данные и корзина' 10 'Bold';$drivePanel.Controls.Add($driveTitle)
$driveChecks=@{};foreach($d in @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue)){$letter=$d.DeviceID.Substring(0,1);$dc=New-Object Windows.Forms.CheckBox;$dc.Text="$letter`:  $([math]::Round($d.FreeSpace/1GB,1)) GB свободно из $([math]::Round($d.Size/1GB,1)) GB";$dc.Tag=$letter;$dc.Width=380;$dc.Height=32;$dc.Checked=($letter -eq $env:SystemDrive.Substring(0,1));Apply-ControlTheme $dc;$drivePanel.Controls.Add($dc);$driveChecks[$letter]=$dc}
$cleanupItems=@(@{Text='Временные файлы пользователя';Id='temp'},@{Text='Временные файлы Windows';Id='wintemp'},@{Text='Корзина';Id='recycle'},@{Text='Кэш DNS';Id='dns'},@{Text='Кэш браузеров';Id='browser'},@{Text='Кэш Windows Update';Id='update'})
$clBox=@{};foreach($x in $cleanupItems){$cbx=New-Object Windows.Forms.CheckBox;$cbx.Text=$x.Text;$cbx.Tag=$x.Id;$cbx.Width=480;$cbx.Height=34;$cbx.Checked=($x.Id -in @('temp','recycle','dns'));Apply-ControlTheme $cbx;$clChecks.Controls.Add($cbx);$clBox[$x.Id]=$cbx}
$clActions=New-Flow;$clRun=New-Button 'ОЧИСТКА  ОЧИСТИТЬ ВЫБРАННОЕ' 260 62;$clAll=New-Button 'ПОЛНАЯ  ПОЛНАЯ БЕЗОПАСНАЯ ОЧИСТКА' 280 62;$clActions.Controls.Add($clRun);$clActions.Controls.Add($clAll);$clGrid.Controls.Add($clActions,0,2);$clGrid.SetColumnSpan($clActions,2)
function Invoke-CleanupSelected([bool]$Full){try{$progress.Visible=$true;$clStatus.Text='Идёт очистка...';$ids=@();foreach($x in $clBox.Values){if($Full -or $x.Checked){$ids+=[string]$x.Tag}};foreach($id in $ids){switch($id){'temp'{Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue};'wintemp'{Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'Temp') -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue};'recycle'{Clear-RecycleBin -Force -ErrorAction SilentlyContinue};'dns'{ipconfig /flushdns|Out-Null};'browser'{foreach($p in @((Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache'),(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache'),(Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'))){if(Test-Path $p){Get-ChildItem $p -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue}}};'update'{Stop-Service wuauserv -Force -ErrorAction SilentlyContinue;Remove-Item (Join-Path $env:SystemRoot 'SoftwareDistribution\Download\*') -Recurse -Force -ErrorAction SilentlyContinue;Start-Service wuauserv -ErrorAction SilentlyContinue}}};foreach($letter in $driveChecks.Keys){if($Full -or $driveChecks[$letter].Checked){$tempDrive=Join-Path ($letter+':') 'Temp';if(Test-Path $tempDrive){Get-ChildItem $tempDrive -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue};try{Clear-RecycleBin -DriveLetter $letter -Force -ErrorAction SilentlyContinue}catch{}}};$clStatus.Text='✓ Очистка завершена.';$clStatus.ForeColor=$C.Accent;Toast 'Очистка' 'Выбранные элементы очищены.' 'OK'}catch{Show-CcErrorPopup 'Очистка' $_.Exception;$clStatus.Text='✕ Ошибка очистки';$clStatus.ForeColor=$C['Danger']}finally{$progress.Visible=$false}}
$clRun.Add_Click({Invoke-CleanupSelected $false});$clAll.Add_Click({Invoke-CleanupSelected $true});$pages['cleanup']=$cleanup;$cleanup.Controls[0].BringToFront()
# Logs
$logs=New-Object Windows.Forms.Panel;$logs.Dock='Fill';$logs.BackColor=$C.Bg;$logs.Controls.Add((New-PageTitle 'Журнал' 'Техническая информация. Нужна в основном администратору.'))
$logArea=New-Object Windows.Forms.TableLayoutPanel;$logArea.Dock='Fill';$logArea.Padding=New-Object Windows.Forms.Padding(20,100,20,15);$logArea.RowCount=2
[void]$logArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$logArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,62)));$logs.Controls.Add($logArea)
$logText=New-Object Windows.Forms.TextBox;$logText.Multiline=$true;$logText.ReadOnly=$true;$logText.ScrollBars='Both';$logText.Dock='Fill';$logText.Font=New-Object Drawing.Font('Consolas',9);$logText.BackColor=$C.Control;$logText.ForeColor=$C.Fg;$logArea.Controls.Add($logText,0,0)
$logBtn=New-Button 'Обновить журнал' 190 50;$logArea.Controls.Add($logBtn,0,1)
function Refresh-Logs{try{$p=Join-Path $Root 'logs\CyberCroc.log';$e=Join-Path $Root 'logs\errors.log';$s='';if(Test-Path $p){$s+=Get-Content $p -Raw};if(Test-Path $e){$s+=[Environment]::NewLine+'===== ОШИБКИ ====='+[Environment]::NewLine+(Get-Content $e -Raw)};$logText.Text=$s;$logText.SelectionStart=$logText.TextLength;$logText.ScrollToCaret()}catch{Write-CcError -FunctionName 'Refresh-Logs' -Exception $_.Exception}}
$logBtn.Add_Click({try{Write-CcLog 'Log viewer refreshed' 'INFO' 'UI';Refresh-Logs}catch{Show-CcErrorPopup 'Журнал' $_.Exception}});$pages['logs']=$logs
$logs.Controls[0].BringToFront()


# Zapret
$zapret=New-Object Windows.Forms.Panel;$zapret.Dock='Fill';$zapret.BackColor=$C.Bg;$zapret.Controls.Add((New-PageTitle 'ZAPRET' 'Управление установленным Zapret из CyberCroc.'))
$zb=New-Flow;$zb.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$zapret.Controls.Add($zb)
$zStatus=New-Object Windows.Forms.TextBox;$zStatus.Multiline=$true;$zStatus.ReadOnly=$true;$zStatus.Width=760;$zStatus.Height=220;$zStatus.BackColor=$C.Panel;$zStatus.ForeColor=$C.Fg;$zb.Controls.Add($zStatus)
$zInstall=New-Button 'УСТАНОВИТЬ' 170 58;$zOn=New-Button 'ВКЛЮЧИТЬ' 150 58;$zOff=New-Button 'ВЫКЛЮЧИТЬ' 150 58;$zTest=New-Button 'ТЕСТ СТРАТЕГИЙ' 190 58;$zAuto=New-Button 'АВТОЗАПУСК' 170 58;$zRefresh=New-Button 'ОБНОВИТЬ СТАТУС' 190 58;foreach($b in @($zInstall,$zOn,$zOff,$zTest,$zAuto,$zRefresh)){$zb.Controls.Add($b)}
function Invoke-Zapret([string]$Action){try{$scriptPath=Join-Path $Root 'Zapret.ps1';if(-not(Test-Path -LiteralPath $scriptPath)){throw \"Zapret.ps1 не найден: $scriptPath\"};Write-CcLog \"Zapret action: $Action\" 'INFO' 'Zapret';$progressLabel.Text=\"ZAPRET: $Action\";$progress.Visible=$true;$ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\\v1.0\\powershell.exe';$p=Start-Process -FilePath $ps -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,'-Action',$Action) -WindowStyle Hidden -Wait -PassThru;if($p.ExitCode -ne 0){throw \"Zapret завершился с кодом $($p.ExitCode). Подробности: logs\zapret_log.txt\"};Refresh-Zapret;Toast 'ZAPRET' \"Операция $Action завершена.\" 'OK'}catch{Write-CcError -FunctionName \"Zapret.$Action\" -Exception $_.Exception;Show-CcErrorPopup \"ZAPRET: $Action\" $_.Exception}finally{$progress.Visible=$false;$progressLabel.Text='Выполняется операция...'}}
function Refresh-Zapret{try{$log=Join-Path $Root 'logs\zapret_log.txt';$zStatus.Text=if(Test-Path -LiteralPath $log){Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue}else{'Журнал Zapret ещё не создан.'}}catch{Write-CcError -FunctionName 'Refresh-Zapret' -Exception $_.Exception;Show-CcErrorPopup 'ZAPRET' $_.Exception}}
$zInstall.Add_Click({Invoke-Zapret 'install'});$zOn.Add_Click({Invoke-Zapret 'on'});$zOff.Add_Click({Invoke-Zapret 'off'});$zTest.Add_Click({Invoke-Zapret 'test'});$zAuto.Add_Click({Invoke-Zapret 'autostart-on'});$zRefresh.Add_Click({Refresh-Zapret})
$pages['zapret']=$zapret;$zapret.Controls[0].BringToFront();Refresh-Zapret

# FAQ / club rules
$faq=New-Object Windows.Forms.Panel;$faq.Dock='Fill';$faq.BackColor=$C.Bg;$faq.Controls.Add((New-PageTitle 'FAQ / правила клуба' 'Короткие ответы, цены и правила без обращения к админу.'))
$faqBody=New-Object Windows.Forms.TextBox;$faqBody.Multiline=$true;$faqBody.ReadOnly=$true;$faqBody.ScrollBars='Vertical';$faqBody.Dock='Fill';$faqBody.Padding=New-Object Windows.Forms.Padding(18);$faqBody.BackColor=$C.Control;$faqBody.ForeColor=$C.Fg;$faqBody.Font=New-Object Drawing.Font('Segoe UI',11);$faqBody.Text=@'
ПРАВИЛА

• Не отключайте CyberCroc и не пытайтесь обходить ограничения клиентского ПК.
• При проблеме нажмите «ПОЗВАТЬ АДМИНА» и выберите причину.
• Заказы еды и напитков оформляются через «ТОВАРЫ / ЗАКАЗЫ».
• Оплата заказа: наличные или безналичные — выбор делается при оформлении.
• Продление времени и вопросы по игровому времени оформляются через администратора и Langame.
• Запрещено передавать другим людям свои учётные данные.

ЧАСТЫЕ ВОПРОСЫ

Почему нет товара?
Проверьте каталог ещё раз. Если остаток не обновился, вызовите администратора.

ПК завис или не запускает игру?
Нажмите «ПОЗВАТЬ АДМИНА» → «Проблема». Администратор увидит номер вашего ПК.

Можно пересесть на другой ПК?
Отправьте заявку через администратора; пересадку подтверждает стойка.

Где узнать остаток времени?
Время сессии ведёт Langame. CyberCroc не считает и не изменяет игровое время.

Контакты и цены
Используйте актуальные данные, опубликованные администратором клуба.
'@;$faq.Controls.Add($faqBody);$pages['faq']=$faq;$faq.Controls[0].BringToFront()

# Products and orders
$ordersPage=New-Object Windows.Forms.Panel;$ordersPage.Dock='Fill';$ordersPage.BackColor=$C.Bg;$ordersPage.Controls.Add((New-PageTitle 'Товары и заказы' 'Каталог из Google Sheets с локальным кэшем. Оплата заказа — наличные или безналичные.'))
$ordersGrid=New-Object Windows.Forms.TableLayoutPanel;$ordersGrid.Dock='Fill';$ordersGrid.Padding=New-Object Windows.Forms.Padding(20,98,20,15);$ordersGrid.ColumnCount=2;$ordersGrid.RowCount=2;$ordersGrid.BackColor=$C.Bg;$ordersPage.Controls.Add($ordersGrid)
[void]$ordersGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,56)));[void]$ordersGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,44)));[void]$ordersGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$ordersGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,72)))
$productList=New-Object Windows.Forms.ListView;$productList.View='Details';$productList.FullRowSelect=$true;$productList.MultiSelect=$false;$productList.Dock='Fill';$productList.BackColor=$C.Control;$productList.ForeColor=$C.Fg;[void]$productList.Columns.Add('Товар',260);[void]$productList.Columns.Add('Цена',100);[void]$productList.Columns.Add('Остаток',100);[void]$productList.Columns.Add('Категория',140);$ordersGrid.Controls.Add($productList,0,0)
$orderList=New-Object Windows.Forms.ListView;$orderList.View='Details';$orderList.FullRowSelect=$true;$orderList.MultiSelect=$false;$orderList.Dock='Fill';$orderList.BackColor=$C.Control;$orderList.ForeColor=$C.Fg;[void]$orderList.Columns.Add('ПК',80);[void]$orderList.Columns.Add('Товар',145);[void]$orderList.Columns.Add('Кол-во',70);[void]$orderList.Columns.Add('Оплата',85);[void]$orderList.Columns.Add('Сумма',85);[void]$orderList.Columns.Add('Статус',90);[void]$orderList.Columns.Add('Время',125);$ordersGrid.Controls.Add($orderList,1,0)
$orderButtons=New-Flow;$orderBuy=New-Button 'ЗАКАЗАТЬ' 170 56;$orderRefresh=New-Button 'ОБНОВИТЬ' 150 56;$orderEdit=New-Button 'ТОВАР' 150 56;$orderPreparing=New-Button 'ГОТОВИТСЯ' 160 56;$orderDelivered=New-Button 'ДОСТАВЛЕН' 160 56;$orderRejected=New-Button 'ОТКЛОНИТЬ' 150 56;foreach($b in @($orderBuy,$orderRefresh,$orderEdit,$orderPreparing,$orderDelivered,$orderRejected)){$orderButtons.Controls.Add($b)};$ordersGrid.Controls.Add($orderButtons,0,1);$ordersGrid.SetColumnSpan($orderButtons,2)
function Refresh-OrdersPage {
    try {
        $productList.Items.Clear();$items=@(Get-CcProducts)
        foreach($x in $items){$productIcon=switch -Regex ([string]$x.Category) {'(?i)напит|drink|вода|кофе|чай' {'🥤'} '(?i)снэк|снек|еда|food|чипс|шоколад' {'🍫'} default {'🛒'}};$i=[Windows.Forms.ListViewItem]::new("$productIcon  $($x.Name)");[void]$i.SubItems.Add(([decimal]$x.Price).ToString('0.00'));[void]$i.SubItems.Add(([decimal]$x.Quantity).ToString('0.##'));[void]$i.SubItems.Add([string]$x.Category);$i.Tag=$x;[void]$productList.Items.Add($i)}
        $orderList.Items.Clear();foreach($o in @(Get-CcOrders|Sort-Object timestamp -Descending|Select-Object -First 100)){$i=[Windows.Forms.ListViewItem]::new([string]$o.client_pc);[void]$i.SubItems.Add([string]$o.item_name);[void]$i.SubItems.Add(([decimal]$o.quantity).ToString('0.##'));[void]$i.SubItems.Add([string]$o.payment_type);[void]$i.SubItems.Add(([decimal]$o.total).ToString('0.00'));[void]$i.SubItems.Add([string]$o.status);$orderTime='—';try{$orderTime=([datetime]::Parse([string]$o.timestamp)).ToLocalTime().ToString('dd.MM HH:mm')}catch{};[void]$i.SubItems.Add($orderTime);$i.Tag=$o;[void]$orderList.Items.Add($i)}
    } catch { Write-CcError -FunctionName 'Refresh-OrdersPage' -Exception $_.Exception }
}
function Show-PaymentDialog([object]$Product) {
    $d=New-Object Windows.Forms.Form;$d.Text="Оплата — $($Product.Name)";$d.StartPosition='CenterParent';$d.Size=New-Object Drawing.Size(430,250);$d.BackColor=$C.Bg;$d.ForeColor=$C.Fg
    $l=New-Object Windows.Forms.TableLayoutPanel;$l.Dock='Fill';$l.Padding=New-Object Windows.Forms.Padding(14);$l.RowCount=4;$l.ColumnCount=2;[void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,130)));[void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));$d.Controls.Add($l)
    [void]$l.Controls.Add((New-Label 'Количество'),0,0);$qty=New-Object Windows.Forms.NumericUpDown;$qty.Minimum=1;$qty.Maximum=[math]::Max(1,[int]$Product.Quantity);$qty.Value=1;$qty.Dock='Fill';Apply-ControlTheme $qty;$l.Controls.Add($qty,1,0)
    [void]$l.Controls.Add((New-Label 'Оплата'),0,1);$pay=New-Object Windows.Forms.ComboBox;$pay.DropDownStyle='DropDownList';[void]$pay.Items.AddRange(@('Cash','Card'));$pay.SelectedIndex=0;$pay.Dock='Fill';Apply-ControlTheme $pay;$l.Controls.Add($pay,1,1)
    $total=New-Label 'Итого: 0.00' 12 'Bold';$total.ForeColor=$C.Accent;$l.Controls.Add($total,1,2);$calc={ $total.Text=('Итого: {0:0.00}' -f ([decimal]$Product.Price*[decimal]$qty.Value)) };$qty.Add_ValueChanged($calc);&$calc
    $ok=New-Button 'ПОДТВЕРДИТЬ ЗАКАЗ' 210 52;$l.Controls.Add($ok,1,3)
    $ok.Add_Click({try{$o=New-CcOrder $Product ([decimal]$qty.Value) ([string]$pay.SelectedItem) $script:CcPcId;if(-not$o){throw 'Не удалось создать заказ.'};$d.Close();Refresh-OrdersPage;Toast 'Заказ' 'Заказ отправлен администратору.' 'OK'}catch{Show-CcErrorPopup 'Заказ' $_.Exception}})
    [void]$d.ShowDialog($form)
}
$orderBuy.Add_Click({try{if(-not$productList.SelectedItems.Count){throw 'Выберите товар.'};$p=$productList.SelectedItems[0].Tag;if([decimal]$p.Quantity -le 0){throw 'Товар закончился.'};Show-PaymentDialog $p}catch{Show-CcErrorPopup 'Заказ' $_.Exception}})
$orderRefresh.Add_Click({try{Refresh-OrdersPage;Toast 'Товары' 'Каталог обновлён.' 'OK'}catch{Show-CcErrorPopup 'Товары' $_.Exception}})
$orderEdit.Add_Click({try{if($script:CcRole -ne 'admin'){return};if(-not(Request-CcAdminAccess)){return};if(-not$productList.SelectedItems.Count){throw 'Выберите товар.'};$x=$productList.SelectedItems[0].Tag;$d=New-Object Windows.Forms.Form;$d.Text='Редактор товара';$d.Size=New-Object Drawing.Size(520,320);$d.StartPosition='CenterParent';$d.BackColor=$C.Bg;$t=New-Object Windows.Forms.TableLayoutPanel;$t.Dock='Fill';$t.Padding=New-Object Windows.Forms.Padding(14);$t.RowCount=4;$t.ColumnCount=2;[void]$t.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,140)));[void]$t.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));$d.Controls.Add($t);$f=@{};foreach($name in @('Название','Цена','Количество')){[void]$t.Controls.Add((New-Label $name),0,$f.Count);$tb=New-Object Windows.Forms.TextBox;$tb.Dock='Fill';Apply-ControlTheme $tb;$f[$name]=$tb;[void]$t.Controls.Add($tb,1,($f.Count-1))};$f['Название'].Text=$x.Name;$f['Цена'].Text=[string]$x.Price;$f['Количество'].Text=[string]$x.Quantity;$ok=New-Button 'СОХРАНИТЬ' 160 52;$t.Controls.Add($ok,1,3);$ok.Add_Click({try{$pr=[decimal]::Parse($f['Цена'].Text,[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::InvariantCulture);$qq=[decimal]::Parse($f['Количество'].Text,[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::InvariantCulture);if(-not(Set-CcProduct [int]$x.Row $f['Название'].Text.Trim() $pr $qq ([string]$x.Category))){throw 'Google Sheets недоступен; изменение не сохранено.'};$d.Close();Refresh-OrdersPage;Toast 'Товары' 'Изменения синхронизированы.' 'OK'}catch{Show-CcErrorPopup 'Редактор товара' $_.Exception}});[void]$d.ShowDialog($form)}catch{Show-CcErrorPopup 'Товар' $_.Exception}})
$orderPreparing.Add_Click({if($script:CcRole -eq 'admin' -and $orderList.SelectedItems.Count){$o=$orderList.SelectedItems[0].Tag;[void](Set-CcOrderStatus ([string]$o.order_id) 'preparing');Write-CcAudit -Action 'order.status' -Target ([string]$o.order_id) -Result 'success' -Details ('status=preparing; pc='+[string]$o.client_pc);Refresh-OrdersPage}})
$orderDelivered.Add_Click({if($script:CcRole -eq 'admin' -and $orderList.SelectedItems.Count){$o=$orderList.SelectedItems[0].Tag;[void](Set-CcOrderStatus ([string]$o.order_id) 'delivered');Write-CcAudit -Action 'order.status' -Target ([string]$o.order_id) -Result 'success' -Details ('status=delivered; pc='+[string]$o.client_pc);Refresh-OrdersPage}})
$orderRejected.Add_Click({if($script:CcRole -eq 'admin' -and $orderList.SelectedItems.Count){$o=$orderList.SelectedItems[0].Tag;[void](Set-CcOrderStatus ([string]$o.order_id) 'rejected');Write-CcAudit -Action 'order.status' -Target ([string]$o.order_id) -Result 'success' -Details ('status=rejected; pc='+[string]$o.client_pc);Refresh-OrdersPage}})
$pages['orders']=$ordersPage;$pages['bar']=$ordersPage;$ordersPage.Controls[0].BringToFront()

# Client support
$support=New-Object Windows.Forms.Panel;$support.Dock='Fill';$support.BackColor=$C.Bg;$support.Controls.Add((New-PageTitle 'Помощь и вызов админа' 'Нажмите одну кнопку — запрос появится на главном ПК.'))
$supBody=New-Object Windows.Forms.FlowLayoutPanel;$supBody.Dock='Fill';$supBody.Padding=New-Object Windows.Forms.Padding(24,110,24,24);$supBody.FlowDirection='TopDown';$supBody.WrapContents=$false;$supBody.BackColor=$C.Bg;$support.Controls.Add($supBody)
$supCard=New-Object Windows.Forms.Panel;$supCard.Width=760;$supCard.Height=250;$supCard.BackColor=$C.Panel;$supBody.Controls.Add($supCard)
$supTitle=New-Label 'Позвать администратора' 18 'Bold';$supTitle.Location=New-Object Drawing.Point(20,18);$supCard.Controls.Add($supTitle)
$reason=New-Object Windows.Forms.ComboBox;$reason.DropDownStyle='DropDownList';[void]$reason.Items.AddRange(@('problem','question','other'));$reason.SelectedIndex=0;$reason.Location=New-Object Drawing.Point(20,64);$reason.Width=340;Apply-ControlTheme $reason;$supCard.Controls.Add($reason)
$callBtn=New-Button 'ПОЗВАТЬ АДМИНА' 260 62;$callBtn.Location=New-Object Drawing.Point(20,120);$supCard.Controls.Add($callBtn)
$supStatus=New-Label 'Запросов нет.' 10;$supStatus.ForeColor=$C.Muted;$supStatus.Location=New-Object Drawing.Point(310,135);$supStatus.MaximumSize=New-Object Drawing.Size(410,80);$supCard.Controls.Add($supStatus)
$callBtn.Add_Click({try{$c=New-CcAdminCall ([string]$reason.SelectedItem) $script:CcPcId;if(-not$c){throw 'Не удалось отправить вызов.'};$supStatus.Text='Запрос отправлен. Даже при временной потере связи он останется в локальной очереди.';Toast 'Администратор' 'Вызов отправлен.' 'OK'}catch{Show-CcErrorPopup 'Вызов админа' $_.Exception}})
$pages['support']=$support;$support.Controls[0].BringToFront()

# Admin hall
$hall=New-Object Windows.Forms.Panel;$hall.Dock='Fill';$hall.BackColor=$C.Bg;$hall.Controls.Add((New-PageTitle 'Карта зала' '25–50 ПК: онлайн-статус, зона, сообщения, блокировка и аварийная команда.'))
$hallGrid=New-Object Windows.Forms.TableLayoutPanel;$hallGrid.Dock='Fill';$hallGrid.Padding=New-Object Windows.Forms.Padding(20,98,20,15);$hallGrid.ColumnCount=2;$hallGrid.RowCount=2;$hallGrid.BackColor=$C.Bg;$hall.Controls.Add($hallGrid)
[void]$hallGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,65)));[void]$hallGrid.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,35)));[void]$hallGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$hallGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,82)))
$nodeList=New-Object Windows.Forms.ListView;$nodeList.View='Tile';$nodeList.FullRowSelect=$true;$nodeList.MultiSelect=$false;$nodeList.HideSelection=$false;$nodeList.TileSize=New-Object Drawing.Size(235,72);$nodeList.Dock='Fill';$nodeList.BackColor=$C.Control;$nodeList.ForeColor=$C.Fg;$hallGrid.Controls.Add($nodeList,0,0)
$hallInfo=New-Object Windows.Forms.TextBox;$hallInfo.Multiline=$true;$hallInfo.ReadOnly=$true;$hallInfo.Dock='Fill';$hallInfo.BackColor=$C.Panel;$hallInfo.ForeColor=$C.Fg;$hallInfo.Text='Выберите ПК для действий.';$hallGrid.Controls.Add($hallInfo,1,0)
$hallActions=New-Flow;$msgText=New-Object Windows.Forms.TextBox;$msgText.Width=280;$msgText.Height=52;$msgText.Text='';Apply-ControlTheme $msgText;$msgText.ToolTipText='Сообщение для всех или выбранного ПК';$hallActions.Controls.Add($msgText)
$sendMsg=New-Button 'РАССЫЛКА' 150 56;$blockPc=New-Button 'БЛОКИРОВКА' 160 56;$unblockPc=New-Button 'РАЗБЛОКИРОВКА' 170 56;$fleetBtn=New-Button 'РАЗОСЛАТЬ КОНФИГ' 190 56;$emergency=New-Button 'АВАРИЯ' 140 56;$emergency.BackColor=$C['Danger'];$emergency.ForeColor=$C.White;foreach($b in @($sendMsg,$blockPc,$unblockPc,$fleetBtn,$emergency)){$hallActions.Controls.Add($b)};$hallGrid.Controls.Add($hallActions,0,1);$hallGrid.SetColumnSpan($hallActions,2)
function Refresh-HallPage {try{$selectedPc='';if($nodeList.SelectedItems.Count){$selectedPc=[string]$nodeList.SelectedItems[0].Tag.PcId};$nodes=@(Get-CcKnownNodes);$expected=[int](Get-CcConfig)['EXPECTED_PCS'];if($expected -lt 1){$expected=50};if($nodes.Count -eq 0 -or @($nodes|Where-Object{$_.PcId -notmatch '^PC-\d+$nodeList.BeginUpdate();$nodeList.Items.Clear();foreach($n in $nodes){$state=if($n.Online){'ONLINE'}else{'OFFLINE'};$label="$($n.PcId)  |  $state  |  $($n.Zone)";$i=[Windows.Forms.ListViewItem]::new([string]$label);$i.ToolTipText="Хост: $($n.Host)`r`nВерсия: $($n.Version)";$i.Tag=$n;[void]$nodeList.Items.Add($i);if($selectedPc -and $selectedPc -eq [string]$n.PcId){$i.Selected=$true}};$nodeList.EndUpdate();if(-not $selectedPc){$hallInfo.Text="Обнаружено $($nodes.Count), онлайн $online из плановых $expected.`r`nВыберите плитку ПК для управления."}}catch{try{$nodeList.EndUpdate()}catch{};Write-CcError -FunctionName 'Refresh-HallPage' -Exception $_.Exception}}
$nodeList.Add_SelectedIndexChanged({if($nodeList.SelectedItems.Count){$n=$nodeList.SelectedItems[0].Tag;$hallInfo.Text="PC: $($n.PcId)`r`nСостояние: $(if($n.Online){'онлайн'}else{'нет связи'})`r`nЗона: $($n.Zone)`r`nХост: $($n.Host)`r`nВерсия: $($n.Version)`r`nПоследний beacon: $($n.LastSeenUtc.ToLocalTime().ToString('HH:mm:ss'))"}})
$sendMsg.Add_Click({try{$msg=[string]$msgText.Text.Trim();if(-not$msg){throw 'Введите сообщение.'};$target='*';if($nodeList.SelectedItems.Count){$target=[string]$nodeList.SelectedItems[0].Tag.PcId};Send-CcUdpMessage ([pscustomobject]@{type='command';sender_role='admin';sender_pc=$script:CcPcId;action='message';target_pc=$target;text=$msg;timestamp=(Get-Date).ToUniversalTime().ToString('o')})|Out-Null;Toast 'Рассылка' 'Сообщение отправлено.' 'OK'}catch{Show-CcErrorPopup 'Рассылка' $_.Exception}})
function Send-NodeCommand([string]$Action) {if(-not$nodeList.SelectedItems.Count){throw 'Выберите ПК.'};$n=$nodeList.SelectedItems[0].Tag;Write-CcAudit -Action ('fleet.'+$Action) -Target ([string]$n.PcId) -Result 'requested' -Details 'Команда управления ПК отправлена';Send-CcUdpMessage ([pscustomobject]@{type='command';sender_role='admin';sender_pc=$script:CcPcId;action=$Action;target_pc=[string]$n.PcId;reason='По решению администратора';timestamp=(Get-Date).ToUniversalTime().ToString('o')})|Out-Null}
$blockPc.Add_Click({try{if(-not(Request-CcAdminAccess)){return};Send-NodeCommand 'block';Toast 'Карта зала' 'ПК заблокирован.' 'OK'}catch{Show-CcErrorPopup 'Блокировка' $_.Exception}})
$unblockPc.Add_Click({try{if(-not(Request-CcAdminAccess)){return};Send-NodeCommand 'unblock';Toast 'Карта зала' 'Команда разблокировки отправлена.' 'OK'}catch{Show-CcErrorPopup 'Разблокировка' $_.Exception}})
$fleetBtn.Add_Click({try{if(-not(Request-CcAdminAccess)){return};$r=Sync-CcConfigToFleet;Toast 'Развёртывание' "Успешно: $($r.Success), ошибок: $($r.Failed), всего: $($r.Total)." $(if($r.Failed){'ERROR'}else{'OK'})}catch{Show-CcErrorPopup 'Массовое развёртывание' $_.Exception}})
$emergency.Add_Click({try{if(-not(Request-CcAdminAccess)){return};$a=[Windows.Forms.MessageBox]::Show('Отправить на все клиентские ПК сообщение «ПОКИНЬТЕ ЗАЛ» и сирену?','АВАРИЯ',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning);if($a -ne [Windows.Forms.DialogResult]::Yes){return};$reasonText='Аварийное уведомление';Send-CcUdpMessage ([pscustomobject]@{type='command';sender_role='admin';sender_pc=$script:CcPcId;action='emergency';target_pc='*';reason=$reasonText;timestamp=(Get-Date).ToUniversalTime().ToString('o')})|Out-Null;Write-CcLog "Emergency broadcast sent by $script:CcPcId" 'WARN' 'Emergency';Toast 'АВАРИЯ' 'Команда отправлена на все ПК.' 'ERROR'}catch{Show-CcErrorPopup 'Авария' $_.Exception}})
$pages['hall']=$hall;$hall.Controls[0].BringToFront();

# Audit trail for privileged operations
$auditPage=New-Object Windows.Forms.Panel;$auditPage.Dock='Fill';$auditPage.BackColor=$C.Bg;$auditPage.Controls.Add((New-PageTitle 'Аудит действий' 'Журнал действий и операций администратора на этом компьютере.'))
$auditGrid=New-Object Windows.Forms.TableLayoutPanel;$auditGrid.Dock='Fill';$auditGrid.Padding=New-Object Windows.Forms.Padding(18,98,18,12);$auditGrid.ColumnCount=1;$auditGrid.RowCount=2;[void]$auditGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$auditGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,64)));$auditPage.Controls.Add($auditGrid)
$auditList=New-Object Windows.Forms.ListView;$auditList.View='Details';$auditList.FullRowSelect=$true;$auditList.Dock='Fill';$auditList.BackColor=$C.Control;$auditList.ForeColor=$C.Fg;foreach($col in @(@('Время',135),@('Пользователь',110),@('Роль',75),@('ПК',90),@('Действие',170),@('Объект',140),@('Результат',90),@('Детали',280))){[void]$auditList.Columns.Add([string]$col[0],[int]$col[1])};$auditGrid.Controls.Add($auditList,0,0)
$auditActions=New-Flow;$auditRefresh=New-Button 'ОБНОВИТЬ' 150 46;$auditExport=New-Button 'ЭКСПОРТ CSV' 170 46;$auditActions.Controls.Add($auditRefresh);$auditActions.Controls.Add($auditExport);$auditGrid.Controls.Add($auditActions,0,1)
function Refresh-AuditPage {try{$auditList.BeginUpdate();$auditList.Items.Clear();foreach($event in @(Get-CcAuditEvents -Limit 2000)){$time='—';try{$time=([datetime]::Parse([string]$event.timestamp)).ToLocalTime().ToString('dd.MM.yyyy HH:mm:ss')}catch{};$item=[Windows.Forms.ListViewItem]::new($time);foreach($value in @($event.actor,$event.role,$event.pc_id,$event.action,$event.target,$event.result,$event.details)){[void]$item.SubItems.Add([string]$value)};[void]$auditList.Items.Add($item)}}catch{Write-CcError -FunctionName 'Refresh-AuditPage' -Exception $_.Exception}finally{try{$auditList.EndUpdate()}catch{}}}
$auditRefresh.Add_Click({Refresh-AuditPage})
$auditExport.Add_Click({try{$file=Join-Path $Root ('logs\audit-export-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'));@(Get-CcAuditEvents -Limit 100000)|Select-Object timestamp,actor,role,pc_id,action,target,result,details|Export-Csv -LiteralPath $file -NoTypeInformation -Encoding UTF8;Toast 'Аудит' "Экспортирован: $file" 'OK'}catch{Show-CcErrorPopup 'Экспорт аудита' $_.Exception}})
$pages['audit']=$auditPage;$auditPage.Controls[0].BringToFront();Refresh-AuditPage

# Settings
$settings=New-Object Windows.Forms.Panel;$settings.Dock='Fill';$settings.BackColor=$C.Bg;$settings.Controls.Add((New-PageTitle 'Настройки' 'Изменяйте только то, что действительно нужно.'))
$setBody=New-Object Windows.Forms.FlowLayoutPanel;$setBody.Dock='Fill';$setBody.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$setBody.WrapContents=$true;$setBody.AutoScroll=$true;$setBody.BackColor=$C.Bg;$settings.Controls.Add($setBody)
$themeBox=New-Object Windows.Forms.Panel;$themeBox.Width=760;$themeBox.Height=120;$themeBox.BackColor=$C.Panel;$setBody.Controls.Add($themeBox)
$themeLabel=New-Label 'ТЕМА' 11 'Bold';$themeLabel.Location=New-Object Drawing.Point(18,18);$themeBox.Controls.Add($themeLabel)
$theme=New-Object Windows.Forms.ComboBox;$theme.DropDownStyle='DropDownList';[void]$theme.Items.AddRange(@('dark','neon','light'));$theme.SelectedItem=$ThemeName;$theme.Width=220;$theme.Location=New-Object Drawing.Point(18,52);$theme.BackColor=$C.Control;$theme.ForeColor=$C.Fg;$themeBox.Controls.Add($theme)
$shareBox=New-Object Windows.Forms.Panel;$shareBox.Width=760;$shareBox.Height=120;$shareBox.BackColor=$C.Panel;$setBody.Controls.Add($shareBox)
$gamesShareBox=New-Object Windows.Forms.Panel;$gamesShareBox.Width=760;$gamesShareBox.Height=120;$gamesShareBox.BackColor=$C.Panel;$setBody.Controls.Add($gamesShareBox);$gamesShareLabel=New-Label 'ШАРА ИГР' 11 'Bold';$gamesShareLabel.Location=New-Object Drawing.Point(18,18);$gamesShareBox.Controls.Add($gamesShareLabel);$gamesShare=New-Object Windows.Forms.TextBox;$gamesShare.Text=$cfg['GAMES_SHARE'];$gamesShare.Width=690;$gamesShare.Location=New-Object Drawing.Point(18,52);Apply-ControlTheme $gamesShare;$gamesShareBox.Controls.Add($gamesShare)
$barShareBox=New-Object Windows.Forms.Panel;$barShareBox.Width=760;$barShareBox.Height=180;$barShareBox.BackColor=$C.Panel;$setBody.Controls.Add($barShareBox);$barShareLabel=New-Label 'ШАРА БАРА (общие данные)' 11 'Bold';$barShareLabel.Location=New-Object Drawing.Point(18,18);$barShareBox.Controls.Add($barShareLabel);$barShare=New-Object Windows.Forms.TextBox;$barShare.Text=$cfg['BAR_SHARE'];$barShare.Width=690;$barShare.Location=New-Object Drawing.Point(18,52);Apply-ControlTheme $barShare;$barShareBox.Controls.Add($barShare);$barSheetLabel=New-Label 'ССЫЛКА GOOGLE SHEETS (CSV)' 10 'Bold';$barSheetLabel.Location=New-Object Drawing.Point(18,92);$barShareBox.Controls.Add($barSheetLabel);$barSheetUrl=New-Object Windows.Forms.TextBox;$barSheetUrl.Text=$cfg['BAR_SHEET_URL'];$barSheetUrl.Width=690;$barSheetUrl.Location=New-Object Drawing.Point(18,125);Apply-ControlTheme $barSheetUrl;$barShareBox.Controls.Add($barSheetUrl)
$productBox=New-Object Windows.Forms.Panel;$productBox.Width=760;$productBox.Height=230;$productBox.BackColor=$C.Panel;$setBody.Controls.Add($productBox);$productLabel=New-Label 'GOOGLE SHEETS — ТОВАРЫ' 11 'Bold';$productLabel.Location=New-Object Drawing.Point(18,16);$productBox.Controls.Add($productLabel)
$sheetUrlText=New-Object Windows.Forms.TextBox;$sheetUrlText.Text=$cfg['PRODUCT_SHEET_URL'];$sheetUrlText.Width=690;$sheetUrlText.Location=New-Object Drawing.Point(18,48);Apply-ControlTheme $sheetUrlText;$productBox.Controls.Add($sheetUrlText)
$sheetIdText=New-Object Windows.Forms.TextBox;$sheetIdText.Text=$cfg['PRODUCT_SHEET_ID'];$sheetIdText.Width=300;$sheetIdText.Location=New-Object Drawing.Point(18,82);Apply-ControlTheme $sheetIdText;$productBox.Controls.Add($sheetIdText)
$sheetRangeText=New-Object Windows.Forms.TextBox;$sheetRangeText.Text=$cfg['PRODUCT_SHEET_RANGE'];$sheetRangeText.Width=300;$sheetRangeText.Location=New-Object Drawing.Point(332,82);Apply-ControlTheme $sheetRangeText;$productBox.Controls.Add($sheetRangeText)
$saLabel=New-Label 'Путь к JSON service account (ТОЛЬКО на admin-ПК; ключ вне репозитория)' 9;$saLabel.ForeColor=$C.Muted;$saLabel.Location=New-Object Drawing.Point(18,120);$productBox.Controls.Add($saLabel)
$saPathText=New-Object Windows.Forms.TextBox;$saPathText.Text=$cfg['GOOGLE_SERVICE_ACCOUNT_JSON'];$saPathText.Width=690;$saPathText.Location=New-Object Drawing.Point(18,150);Apply-ControlTheme $saPathText;$productBox.Controls.Add($saPathText)
$pcBox=New-Object Windows.Forms.Panel;$pcBox.Width=760;$pcBox.Height=120;$pcBox.BackColor=$C.Panel;$setBody.Controls.Add($pcBox)
$pcLabel=New-Label 'ID КОМПЬЮТЕРА (например PC-07)' 11 'Bold';$pcLabel.Location=New-Object Drawing.Point(18,18);$pcBox.Controls.Add($pcLabel)
$pcName=New-Object Windows.Forms.TextBox;$pcName.Text=$script:CcPcId;$pcName.Width=400;$pcName.Location=New-Object Drawing.Point(18,52);Apply-ControlTheme $pcName;$pcBox.Controls.Add($pcName)
$shareLabel=New-Label 'ПАПКА ОБНОВЛЕНИЙ' 11 'Bold';$shareLabel.Location=New-Object Drawing.Point(18,18);$shareBox.Controls.Add($shareLabel)
$share=New-Object Windows.Forms.TextBox;$share.Text=$cfg['UPDATE_SHARE'];$share.Width=690;$share.Location=New-Object Drawing.Point(18,52);$share.BackColor=$C.Control;$share.ForeColor=$C.Fg;$shareBox.Controls.Add($share)
$saveSettings=New-Button 'Сохранить настройки' 240 60;$googleTest=New-Button 'ПРОВЕРИТЬ GOOGLE' 220 60;$checkUpdate=New-Button 'Проверить обновление' 240 60;$setBody.Controls.Add($saveSettings);$setBody.Controls.Add($googleTest);$setBody.Controls.Add($checkUpdate)
$theme.Add_SelectedIndexChanged({Set-Theme $theme.Text;Apply-Theme})
$saveSettings.Add_Click({try{if(-not(Request-CcAdminAccess)){return};$cfg['THEME']=$theme.Text;$cfg['UPDATE_SHARE']=$share.Text;$cfg['GAMES_SHARE']=$gamesShare.Text;$cfg['BAR_SHARE']=$barShare.Text;$cfg['BAR_SHEET_URL']=$barSheetUrl.Text;$cfg['PRODUCT_SHEET_URL']=$sheetUrlText.Text;$cfg['PRODUCT_SHEET_ID']=$sheetIdText.Text;$cfg['PRODUCT_SHEET_RANGE']=$sheetRangeText.Text;$cfg['GOOGLE_SERVICE_ACCOUNT_JSON']=$saPathText.Text;if([string]::IsNullOrWhiteSpace($pcName.Text)){throw 'ID ПК не может быть пустым'};$cfg['PC_ID']=$pcName.Text.Trim();$script:CcPcId=$cfg['PC_ID'];if(-not(Save-CcConfig $cfg)){throw 'Не удалось сохранить config.ini'};Apply-Theme;Toast 'Настройки' 'Настройки сохранены.' 'OK'}catch{Write-CcError -FunctionName 'SaveSettings' -Exception $_.Exception;Show-CcErrorPopup 'Настройки' $_.Exception}})
$googleTest.Add_Click({try{if(-not(Request-CcAdminAccess)){return};$cfg['PRODUCT_SHEET_URL']=$sheetUrlText.Text;$cfg['PRODUCT_SHEET_ID']=$sheetIdText.Text;$cfg['PRODUCT_SHEET_RANGE']=$sheetRangeText.Text;$cfg['GOOGLE_SERVICE_ACCOUNT_JSON']=$saPathText.Text;if(-not(Save-CcConfig $cfg)){throw 'Не удалось сохранить настройки Google.'};$r=Test-CcGoogleProductsConnection;if($r.Ok){Toast 'Google Sheets' "Подключение успешно. Диапазон: $($r.Range), строк: $($r.Rows)" 'OK'}else{Show-CcErrorPopup 'Google Sheets' ([System.Exception]::new([string]$r.Message))}}catch{Show-CcErrorPopup 'Google Sheets' $_.Exception}})
$checkUpdate.Add_Click({try{$u=Test-CcShareUpdate;if(-not$u){Toast 'Обновление' 'SMB-источник недоступен или версия уже актуальна.' 'INFO';return};if($u.Available){$answer=[Windows.Forms.MessageBox]::Show("Доступна версия $($u.Remote). Установлена $($u.Local).`r`nИсточник: $($u.Source)`r`n`r`nОбновить сейчас?",'CyberCroc — обновление',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Information);if($answer -eq [Windows.Forms.DialogResult]::Yes){if(Start-CcShareUpdate){exit 0}}}else{Toast 'Обновление' "Установлена актуальная версия $($u.Local)." 'OK'}}catch{Write-CcError -FunctionName 'UpdateNow' -Exception $_.Exception}})
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

Add-MenuButton 'home' 'ГЛАВНАЯ'
Add-MenuButton 'games' 'ИГРЫ'
Add-MenuButton 'faq' 'FAQ / ПРАВИЛА'
Add-MenuButton 'orders' 'ТОВАРЫ / ЗАКАЗЫ'
Add-MenuButton 'support' 'ПОЗВАТЬ АДМИНА'
Add-MenuButton 'zapret' 'ZAPRET'
Add-MenuButton 'accounts' 'АККАУНТЫ'
Add-MenuButton 'apps' 'ПРОГРАММЫ'
Add-MenuButton 'backup' 'БЭКАП'
Add-MenuButton 'cleanup' 'ОЧИСТКА'
Add-MenuButton 'logs' 'ЖУРНАЛ'
Add-MenuButton 'audit' 'АУДИТ ДЕЙСТВИЙ'
Add-MenuButton 'hall' 'КАРТА ЗАЛА'
Add-MenuButton 'settings' 'НАСТРОЙКИ'


$form.KeyPreview=$true
$form.Add_KeyDown({param($sender,$e) try{
    if($e.Control -and $e.KeyCode -eq [Windows.Forms.Keys]::B -and $script:CcRole -eq 'admin'){if($nodeList.SelectedItems.Count){if(Request-CcAdminAccess){Send-NodeCommand 'block';Toast 'Карта зала' 'ПК заблокирован горячей клавишей Ctrl+B.' 'WARN'}}};$e.SuppressKeyPress=$true;return}
    switch($e.KeyCode){'F1'{Show-Page 'support'};'F2'{Show-Page 'orders'};'F3'{if($script:CcRole -eq 'admin'){Show-Page 'hall'}};'F4'{Show-Page 'orders'};'Escape'{Show-Page 'home'}};$e.SuppressKeyPress=$true
}catch{Write-CcError -FunctionName 'Hotkey' -Exception $_.Exception}})
$uiTip.SetToolTip($orderBuy,'Оформить заказ. Перед подтверждением выбирается способ оплаты.');$uiTip.SetToolTip($orderEdit,'Только админ: изменить название, цену и остаток в Google Sheets.');$uiTip.SetToolTip($callBtn,'Запрос попадает на админскую стойку; при отсутствии связи сохраняется в queue.json.');$uiTip.SetToolTip($emergency,'Аварийное сообщение на все клиентские ПК. Использовать только по реальной необходимости.');$uiTip.SetToolTip($fleetBtn,'Синхронизировать общие настройки со всеми обнаруженными клиентскими ПК по SMB.');$uiTip.SetToolTip($homeCheck,'Локальная диагностика Windows и железа.')
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000;$timer.Add_Tick({$clock.Text=(Get-Date).ToString('HH:mm:ss')});$timer.Start()
$logTimer=New-Object Windows.Forms.Timer;$logTimer.Interval=2000;$logTimer.Add_Tick({try{if($pages.ContainsKey('logs') -and $pageHost.Controls.Count -gt 0 -and $pageHost.Controls[0] -eq $pages['logs']){Refresh-Logs}}catch{}});$logTimer.Start()
$gamesTimer=New-Object Windows.Forms.Timer;$gamesTimer.Interval=3600000;$gamesTimer.Add_Tick({try{Update-CcGamesCatalogDaily|Out-Null;Refresh-GameCatalog;Write-CcLog 'Daily games catalog refresh checked' 'INFO' 'GamesTimer'}catch{Write-CcError -FunctionName 'GamesTimer' -Exception $_.Exception}});$gamesTimer.Start()
$productsTimer=New-Object Windows.Forms.Timer;$productsTimer.Interval=300000;$productsTimer.Add_Tick({try{if($pages.ContainsKey('orders') -and $pageHost.Controls.Count -gt 0 -and $pageHost.Controls[0] -eq $pages['orders']){Refresh-OrdersPage}}catch{Write-CcError -FunctionName 'ProductsTimer' -Exception $_.Exception}});$productsTimer.Start()
$heartbeatTimer=New-Object Windows.Forms.Timer;$heartbeatTimer.Interval=2000;$heartbeatTimer.Add_Tick({try{Set-Content -LiteralPath $script:CcHeartbeatFile -Value (Get-Date).ToUniversalTime().ToString('o') -Encoding ASCII}catch{}});$heartbeatTimer.Start()
$networkTimer=New-Object Windows.Forms.Timer;$networkTimer.Interval=500;$networkTimer.Add_Tick({try{
    $now=(Get-Date).ToUniversalTime();$messages=@(Get-CcNetworkMessages);foreach($packet in $messages){$m=$packet.Message;switch([string]$m.type){
        'beacon' { if([string]$m.role -eq 'admin'){ $script:CcLastAdminSeenUtc=$now }; if($script:CcRole -eq 'admin'){ $script:CcKnownNodes[[string]$m.pc_id]=$true } }
        'order' { if($script:CcRole -eq 'admin'){ $o=Register-CcIncomingOrder $m;if($o){Send-CcOrderAck ([string]$m.order_id) $packet.RemoteAddress $packet.RemotePort|Out-Null;[System.Media.SystemSounds]::Exclamation.Play();Toast 'Новый заказ' "$($m.item_name) × $($m.quantity), $($m.payment_type), ПК $($m.client_pc)" 'INFO';Refresh-OrdersPage} } }
        'admin_call' { if($script:CcRole -eq 'admin'){ $c=Register-CcIncomingCall $m;if($c){Send-CcCallAck ([string]$m.call_id) $packet.RemoteAddress $packet.RemotePort|Out-Null;[System.Media.SystemSounds]::Asterisk.Play();Toast 'Вызов админа' "ПК $($m.client_pc): $($m.reason)" 'WARN'} } }
        'ack' { if($script:CcRole -eq 'client'){if($m.ack_type -eq 'order'){Complete-CcQueuedOperation 'order' ([string]$m.reference_id)|Out-Null;Acknowledge-CcOrder ([string]$m.reference_id)}elseif($m.ack_type -eq 'admin_call'){Complete-CcQueuedOperation 'admin_call' ([string]$m.reference_id)|Out-Null;Acknowledge-CcCall ([string]$m.reference_id)}} }
        'account_presence' { if($script:CcRole -eq 'admin' -and $m.account_id){$accountList=@(Get-CcAccounts);$accountChanged=$false;foreach($account in $accountList){if([string]$account.Id -eq [string]$m.account_id){if(-not $account.PSObject.Properties['ActivePc']){$account|Add-Member -NotePropertyName ActivePc -NotePropertyValue ''};if(-not $account.PSObject.Properties['PcId']){$account|Add-Member -NotePropertyName PcId -NotePropertyValue ''};$account.Status=if([string]$m.state -eq 'occupied'){'occupied'}else{'available'};$account.UsedBy=if([string]$m.state -eq 'occupied'){[string]$m.used_by}else{''};$account.UsedSince=if([string]$m.state -eq 'occupied'){[string]$m.used_since}else{''};$account.ActivePc=if([string]$m.state -eq 'occupied'){[string]$m.pc_id}else{''};$account.PcId=[string]$m.pc_id;$accountChanged=$true;break}};if($accountChanged){[void](Save-CcAccounts $accountList);[void](Sync-CcAccounts -Mode Push);Refresh-Accounts;Write-CcAudit -Action 'account.presence' -Target ([string]$m.login) -Result 'success' -Details ('state='+[string]$m.state+'; pc='+[string]$m.pc_id)}} }
        'command' { if([string]$m.sender_role -ne 'admin'){continue};$target=[string]$m.target_pc;if($target -ne '*' -and $target -ne $script:CcPcId){continue};switch([string]$m.action){'message'{Toast 'Сообщение администратора' ([string]$m.text) 'INFO'};'block'{Show-CcClientOverlay 'ПК заблокирован администратором' ([string]$(if($m.reason){$m.reason}else{'Обратитесь к администратору.'})) $false};'unblock'{Toast 'Администратор' 'ПК снова доступен.' 'OK'};'emergency'{Show-CcClientOverlay 'ПОКИНЬТЕ ЗАЛ' ([string]$(if($m.reason){$m.reason}else{'Аварийная ситуация.'})) $true} } }
    }}
    if($script:CcRole -eq 'client'){if((($now-$script:CcLastBeaconUtc).TotalSeconds -ge (Get-CcNetworkConfig).BeaconIntervalSec)){Send-CcBeacon;$script:CcLastBeaconUtc=$now};if((($now-$script:CcLastQueueRetryUtc).TotalSeconds -ge 5 -and (Get-CcQueueItems).Count -gt 0)){Resend-CcQueuedOperations;$script:CcLastQueueRetryUtc=$now}}else{if((($now-$script:CcLastBeaconUtc).TotalSeconds -ge (Get-CcNetworkConfig).BeaconIntervalSec)){Send-CcBeacon;$script:CcLastBeaconUtc=$now};if($pageHost.Controls.Count -gt 0 -and $pageHost.Controls[0] -eq $pages['hall']){$hallNow=(Get-Date).ToUniversalTime();if(-not $script:CcLastHallRefreshUtc -or ($hallNow-$script:CcLastHallRefreshUtc).TotalSeconds -ge 2){Refresh-HallPage;$script:CcLastHallRefreshUtc=$hallNow}}}
    $networkState=if((($now-$script:CcLastAdminSeenUtc).TotalSeconds -le 30)){'АДМИН: ONLINE'}else{'АДМИН: нет связи'};$footer.Text="ПК: $script:CcPcId | Роль: $script:CcRole | Пользователь: $env:USERNAME | Версия: $Version | $networkState"
}catch{Write-CcError -FunctionName 'NetworkTimer' -Exception $_.Exception}});$networkTimer.Start()
Write-CcLog "CyberCroc GUI initialized role=$script:CcRole pc=$script:CcPcId version=$Version" 'OK' 'Startup';Write-CcAudit -Action 'application.start' -Target $script:CcPcId -Result 'success' -Details ("role={0}; version={1}" -f $script:CcRole,$Version)
$syncTimer=New-Object Windows.Forms.Timer;$syncTimer.Interval=30000;$syncTimer.Add_Tick({try{if(Sync-CcAccounts Pull){Refresh-Accounts}}catch{}});$syncTimer.Start()
try{Sync-CcAccounts Pull|Out-Null}catch{}
$script:AppProcess=$null;$script:AppProcessName=''
$appTimer=New-Object Windows.Forms.Timer;$appTimer.Interval=500;$appTimer.Add_Tick({try{if($null -ne $script:AppProcess){if($script:AppProcess.HasExited){$rc=$script:AppProcess.ExitCode;$appInfo.Text="Операция завершена: $script:AppProcessName`nКод: $rc";$progress.Visible=$false;if($rc -eq 0){Toast 'Программы' "$script:AppProcessName установлена/обновлена." 'OK'}else{Show-CcErrorPopup 'Установка программы' ([Exception]("$script:AppProcessName завершилась с кодом $rc"))};$script:AppProcess=$null}}}catch{}});$appTimer.Start()
Refresh-Home;Refresh-GameCatalog;Refresh-AppCatalog;Refresh-Accounts;Refresh-Logs;Refresh-OrdersPage;Apply-Theme;Apply-RoleVisibility;Show-Page 'home'
$form.Add_FormClosing({param($sender,$e) try{if($script:CcRole -eq 'admin' -and (Request-CcAdminAccess)){ $script:CcAllowClose=$true;Stop-CcUdpListener;$e.Cancel=$false;Write-CcLog 'Admin-authorized GUI close.' 'WARN' 'FormClosing';return } $e.Cancel=$true;Write-CcLog 'GUI close prevented by kiosk policy.' 'WARN' 'FormClosing'}catch{$e.Cancel=$true}})
try {
    [void][System.Windows.Forms.Application]::Run($form)
} catch {
    Write-CcError -FunctionName 'Application.Run' -Exception $_.Exception
    throw
}
}).Count -eq 0){$known=@{};foreach($n in $nodes){$known[[string]$n.PcId]=$true};for($pcIndex=1;$pcIndex -le $expected;$pcIndex++){$placeholder=('PC-{0:D2}' -f $pcIndex);if(-not $known.ContainsKey($placeholder)){$nodes+=,[pscustomobject]@{PcId=$placeholder;Role='client';Zone='standard';Version='—';Host='Не обнаружен';Address='';LastSeenUtc=[DateTime]::UtcNow.AddDays(-1);Online=$false}}}};$nodes=@($nodes|Sort-Object Zone,PcId);$online=@($nodes|Where-Object Online).Count;$nodeList.BeginUpdate();$nodeList.Items.Clear();foreach($n in $nodes){$state=if($n.Online){'ONLINE'}else{'OFFLINE'};$label="$($n.PcId)  |  $state  |  $($n.Zone)";$i=[Windows.Forms.ListViewItem]::new([string]$label);$i.ToolTipText="Хост: $($n.Host)`r`nВерсия: $($n.Version)";$i.Tag=$n;[void]$nodeList.Items.Add($i);if($selectedPc -and $selectedPc -eq [string]$n.PcId){$i.Selected=$true}};$nodeList.EndUpdate();if(-not $selectedPc){$hallInfo.Text="Обнаружено $($nodes.Count), онлайн $online из плановых $expected.`r`nВыберите плитку ПК для управления."}}catch{try{$nodeList.EndUpdate()}catch{};Write-CcError -FunctionName 'Refresh-HallPage' -Exception $_.Exception}}
$nodeList.Add_SelectedIndexChanged({if($nodeList.SelectedItems.Count){$n=$nodeList.SelectedItems[0].Tag;$hallInfo.Text="PC: $($n.PcId)`r`nСостояние: $(if($n.Online){'онлайн'}else{'нет связи'})`r`nЗона: $($n.Zone)`r`nХост: $($n.Host)`r`nВерсия: $($n.Version)`r`nПоследний beacon: $($n.LastSeenUtc.ToLocalTime().ToString('HH:mm:ss'))"}})
$sendMsg.Add_Click({try{$msg=[string]$msgText.Text.Trim();if(-not$msg){throw 'Введите сообщение.'};$target='*';if($nodeList.SelectedItems.Count){$target=[string]$nodeList.SelectedItems[0].Tag.PcId};Send-CcUdpMessage ([pscustomobject]@{type='command';sender_role='admin';sender_pc=$script:CcPcId;action='message';target_pc=$target;text=$msg;timestamp=(Get-Date).ToUniversalTime().ToString('o')})|Out-Null;Toast 'Рассылка' 'Сообщение отправлено.' 'OK'}catch{Show-CcErrorPopup 'Рассылка' $_.Exception}})
function Send-NodeCommand([string]$Action) {if(-not$nodeList.SelectedItems.Count){throw 'Выберите ПК.'};$n=$nodeList.SelectedItems[0].Tag;Write-CcAudit -Action ('fleet.'+$Action) -Target ([string]$n.PcId) -Result 'requested' -Details 'Команда управления ПК отправлена';Send-CcUdpMessage ([pscustomobject]@{type='command';sender_role='admin';sender_pc=$script:CcPcId;action=$Action;target_pc=[string]$n.PcId;reason='По решению администратора';timestamp=(Get-Date).ToUniversalTime().ToString('o')})|Out-Null}
$blockPc.Add_Click({try{if(-not(Request-CcAdminAccess)){return};Send-NodeCommand 'block';Toast 'Карта зала' 'ПК заблокирован.' 'OK'}catch{Show-CcErrorPopup 'Блокировка' $_.Exception}})
$unblockPc.Add_Click({try{if(-not(Request-CcAdminAccess)){return};Send-NodeCommand 'unblock';Toast 'Карта зала' 'Команда разблокировки отправлена.' 'OK'}catch{Show-CcErrorPopup 'Разблокировка' $_.Exception}})
$fleetBtn.Add_Click({try{if(-not(Request-CcAdminAccess)){return};$r=Sync-CcConfigToFleet;Toast 'Развёртывание' "Успешно: $($r.Success), ошибок: $($r.Failed), всего: $($r.Total)." $(if($r.Failed){'ERROR'}else{'OK'})}catch{Show-CcErrorPopup 'Массовое развёртывание' $_.Exception}})
$emergency.Add_Click({try{if(-not(Request-CcAdminAccess)){return};$a=[Windows.Forms.MessageBox]::Show('Отправить на все клиентские ПК сообщение «ПОКИНЬТЕ ЗАЛ» и сирену?','АВАРИЯ',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning);if($a -ne [Windows.Forms.DialogResult]::Yes){return};$reasonText='Аварийное уведомление';Send-CcUdpMessage ([pscustomobject]@{type='command';sender_role='admin';sender_pc=$script:CcPcId;action='emergency';target_pc='*';reason=$reasonText;timestamp=(Get-Date).ToUniversalTime().ToString('o')})|Out-Null;Write-CcLog "Emergency broadcast sent by $script:CcPcId" 'WARN' 'Emergency';Toast 'АВАРИЯ' 'Команда отправлена на все ПК.' 'ERROR'}catch{Show-CcErrorPopup 'Авария' $_.Exception}})
$pages['hall']=$hall;$hall.Controls[0].BringToFront();

# Audit trail for privileged operations
$auditPage=New-Object Windows.Forms.Panel;$auditPage.Dock='Fill';$auditPage.BackColor=$C.Bg;$auditPage.Controls.Add((New-PageTitle 'Аудит действий' 'Журнал действий и операций администратора на этом компьютере.'))
$auditGrid=New-Object Windows.Forms.TableLayoutPanel;$auditGrid.Dock='Fill';$auditGrid.Padding=New-Object Windows.Forms.Padding(18,98,18,12);$auditGrid.ColumnCount=1;$auditGrid.RowCount=2;[void]$auditGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$auditGrid.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,64)));$auditPage.Controls.Add($auditGrid)
$auditList=New-Object Windows.Forms.ListView;$auditList.View='Details';$auditList.FullRowSelect=$true;$auditList.Dock='Fill';$auditList.BackColor=$C.Control;$auditList.ForeColor=$C.Fg;foreach($col in @(@('Время',135),@('Пользователь',110),@('Роль',75),@('ПК',90),@('Действие',170),@('Объект',140),@('Результат',90),@('Детали',280))){[void]$auditList.Columns.Add([string]$col[0],[int]$col[1])};$auditGrid.Controls.Add($auditList,0,0)
$auditActions=New-Flow;$auditRefresh=New-Button 'ОБНОВИТЬ' 150 46;$auditExport=New-Button 'ЭКСПОРТ CSV' 170 46;$auditActions.Controls.Add($auditRefresh);$auditActions.Controls.Add($auditExport);$auditGrid.Controls.Add($auditActions,0,1)
function Refresh-AuditPage {try{$auditList.BeginUpdate();$auditList.Items.Clear();foreach($event in @(Get-CcAuditEvents -Limit 2000)){$time='—';try{$time=([datetime]::Parse([string]$event.timestamp)).ToLocalTime().ToString('dd.MM.yyyy HH:mm:ss')}catch{};$item=[Windows.Forms.ListViewItem]::new($time);foreach($value in @($event.actor,$event.role,$event.pc_id,$event.action,$event.target,$event.result,$event.details)){[void]$item.SubItems.Add([string]$value)};[void]$auditList.Items.Add($item)}}catch{Write-CcError -FunctionName 'Refresh-AuditPage' -Exception $_.Exception}finally{try{$auditList.EndUpdate()}catch{}}}
$auditRefresh.Add_Click({Refresh-AuditPage})
$auditExport.Add_Click({try{$file=Join-Path $Root ('logs\audit-export-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'));@(Get-CcAuditEvents -Limit 100000)|Select-Object timestamp,actor,role,pc_id,action,target,result,details|Export-Csv -LiteralPath $file -NoTypeInformation -Encoding UTF8;Toast 'Аудит' "Экспортирован: $file" 'OK'}catch{Show-CcErrorPopup 'Экспорт аудита' $_.Exception}})
$pages['audit']=$auditPage;$auditPage.Controls[0].BringToFront();Refresh-AuditPage

# Settings
$settings=New-Object Windows.Forms.Panel;$settings.Dock='Fill';$settings.BackColor=$C.Bg;$settings.Controls.Add((New-PageTitle 'Настройки' 'Изменяйте только то, что действительно нужно.'))
$setBody=New-Object Windows.Forms.FlowLayoutPanel;$setBody.Dock='Fill';$setBody.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$setBody.WrapContents=$true;$setBody.AutoScroll=$true;$setBody.BackColor=$C.Bg;$settings.Controls.Add($setBody)
$themeBox=New-Object Windows.Forms.Panel;$themeBox.Width=760;$themeBox.Height=120;$themeBox.BackColor=$C.Panel;$setBody.Controls.Add($themeBox)
$themeLabel=New-Label 'ТЕМА' 11 'Bold';$themeLabel.Location=New-Object Drawing.Point(18,18);$themeBox.Controls.Add($themeLabel)
$theme=New-Object Windows.Forms.ComboBox;$theme.DropDownStyle='DropDownList';[void]$theme.Items.AddRange(@('dark','neon','light'));$theme.SelectedItem=$ThemeName;$theme.Width=220;$theme.Location=New-Object Drawing.Point(18,52);$theme.BackColor=$C.Control;$theme.ForeColor=$C.Fg;$themeBox.Controls.Add($theme)
$shareBox=New-Object Windows.Forms.Panel;$shareBox.Width=760;$shareBox.Height=120;$shareBox.BackColor=$C.Panel;$setBody.Controls.Add($shareBox)
$gamesShareBox=New-Object Windows.Forms.Panel;$gamesShareBox.Width=760;$gamesShareBox.Height=120;$gamesShareBox.BackColor=$C.Panel;$setBody.Controls.Add($gamesShareBox);$gamesShareLabel=New-Label 'ШАРА ИГР' 11 'Bold';$gamesShareLabel.Location=New-Object Drawing.Point(18,18);$gamesShareBox.Controls.Add($gamesShareLabel);$gamesShare=New-Object Windows.Forms.TextBox;$gamesShare.Text=$cfg['GAMES_SHARE'];$gamesShare.Width=690;$gamesShare.Location=New-Object Drawing.Point(18,52);Apply-ControlTheme $gamesShare;$gamesShareBox.Controls.Add($gamesShare)
$barShareBox=New-Object Windows.Forms.Panel;$barShareBox.Width=760;$barShareBox.Height=180;$barShareBox.BackColor=$C.Panel;$setBody.Controls.Add($barShareBox);$barShareLabel=New-Label 'ШАРА БАРА (общие данные)' 11 'Bold';$barShareLabel.Location=New-Object Drawing.Point(18,18);$barShareBox.Controls.Add($barShareLabel);$barShare=New-Object Windows.Forms.TextBox;$barShare.Text=$cfg['BAR_SHARE'];$barShare.Width=690;$barShare.Location=New-Object Drawing.Point(18,52);Apply-ControlTheme $barShare;$barShareBox.Controls.Add($barShare);$barSheetLabel=New-Label 'ССЫЛКА GOOGLE SHEETS (CSV)' 10 'Bold';$barSheetLabel.Location=New-Object Drawing.Point(18,92);$barShareBox.Controls.Add($barSheetLabel);$barSheetUrl=New-Object Windows.Forms.TextBox;$barSheetUrl.Text=$cfg['BAR_SHEET_URL'];$barSheetUrl.Width=690;$barSheetUrl.Location=New-Object Drawing.Point(18,125);Apply-ControlTheme $barSheetUrl;$barShareBox.Controls.Add($barSheetUrl)
$productBox=New-Object Windows.Forms.Panel;$productBox.Width=760;$productBox.Height=230;$productBox.BackColor=$C.Panel;$setBody.Controls.Add($productBox);$productLabel=New-Label 'GOOGLE SHEETS — ТОВАРЫ' 11 'Bold';$productLabel.Location=New-Object Drawing.Point(18,16);$productBox.Controls.Add($productLabel)
$sheetUrlText=New-Object Windows.Forms.TextBox;$sheetUrlText.Text=$cfg['PRODUCT_SHEET_URL'];$sheetUrlText.Width=690;$sheetUrlText.Location=New-Object Drawing.Point(18,48);Apply-ControlTheme $sheetUrlText;$productBox.Controls.Add($sheetUrlText)
$sheetIdText=New-Object Windows.Forms.TextBox;$sheetIdText.Text=$cfg['PRODUCT_SHEET_ID'];$sheetIdText.Width=300;$sheetIdText.Location=New-Object Drawing.Point(18,82);Apply-ControlTheme $sheetIdText;$productBox.Controls.Add($sheetIdText)
$sheetRangeText=New-Object Windows.Forms.TextBox;$sheetRangeText.Text=$cfg['PRODUCT_SHEET_RANGE'];$sheetRangeText.Width=300;$sheetRangeText.Location=New-Object Drawing.Point(332,82);Apply-ControlTheme $sheetRangeText;$productBox.Controls.Add($sheetRangeText)
$saLabel=New-Label 'Путь к JSON service account (ТОЛЬКО на admin-ПК; ключ вне репозитория)' 9;$saLabel.ForeColor=$C.Muted;$saLabel.Location=New-Object Drawing.Point(18,120);$productBox.Controls.Add($saLabel)
$saPathText=New-Object Windows.Forms.TextBox;$saPathText.Text=$cfg['GOOGLE_SERVICE_ACCOUNT_JSON'];$saPathText.Width=690;$saPathText.Location=New-Object Drawing.Point(18,150);Apply-ControlTheme $saPathText;$productBox.Controls.Add($saPathText)
$pcBox=New-Object Windows.Forms.Panel;$pcBox.Width=760;$pcBox.Height=120;$pcBox.BackColor=$C.Panel;$setBody.Controls.Add($pcBox)
$pcLabel=New-Label 'ID КОМПЬЮТЕРА (например PC-07)' 11 'Bold';$pcLabel.Location=New-Object Drawing.Point(18,18);$pcBox.Controls.Add($pcLabel)
$pcName=New-Object Windows.Forms.TextBox;$pcName.Text=$script:CcPcId;$pcName.Width=400;$pcName.Location=New-Object Drawing.Point(18,52);Apply-ControlTheme $pcName;$pcBox.Controls.Add($pcName)
$shareLabel=New-Label 'ПАПКА ОБНОВЛЕНИЙ' 11 'Bold';$shareLabel.Location=New-Object Drawing.Point(18,18);$shareBox.Controls.Add($shareLabel)
$share=New-Object Windows.Forms.TextBox;$share.Text=$cfg['UPDATE_SHARE'];$share.Width=690;$share.Location=New-Object Drawing.Point(18,52);$share.BackColor=$C.Control;$share.ForeColor=$C.Fg;$shareBox.Controls.Add($share)
$saveSettings=New-Button 'Сохранить настройки' 240 60;$googleTest=New-Button 'ПРОВЕРИТЬ GOOGLE' 220 60;$checkUpdate=New-Button 'Проверить обновление' 240 60;$setBody.Controls.Add($saveSettings);$setBody.Controls.Add($googleTest);$setBody.Controls.Add($checkUpdate)
$theme.Add_SelectedIndexChanged({Set-Theme $theme.Text;Apply-Theme})
$saveSettings.Add_Click({try{if(-not(Request-CcAdminAccess)){return};$cfg['THEME']=$theme.Text;$cfg['UPDATE_SHARE']=$share.Text;$cfg['GAMES_SHARE']=$gamesShare.Text;$cfg['BAR_SHARE']=$barShare.Text;$cfg['BAR_SHEET_URL']=$barSheetUrl.Text;$cfg['PRODUCT_SHEET_URL']=$sheetUrlText.Text;$cfg['PRODUCT_SHEET_ID']=$sheetIdText.Text;$cfg['PRODUCT_SHEET_RANGE']=$sheetRangeText.Text;$cfg['GOOGLE_SERVICE_ACCOUNT_JSON']=$saPathText.Text;if([string]::IsNullOrWhiteSpace($pcName.Text)){throw 'ID ПК не может быть пустым'};$cfg['PC_ID']=$pcName.Text.Trim();$script:CcPcId=$cfg['PC_ID'];if(-not(Save-CcConfig $cfg)){throw 'Не удалось сохранить config.ini'};Apply-Theme;Toast 'Настройки' 'Настройки сохранены.' 'OK'}catch{Write-CcError -FunctionName 'SaveSettings' -Exception $_.Exception;Show-CcErrorPopup 'Настройки' $_.Exception}})
$googleTest.Add_Click({try{if(-not(Request-CcAdminAccess)){return};$cfg['PRODUCT_SHEET_URL']=$sheetUrlText.Text;$cfg['PRODUCT_SHEET_ID']=$sheetIdText.Text;$cfg['PRODUCT_SHEET_RANGE']=$sheetRangeText.Text;$cfg['GOOGLE_SERVICE_ACCOUNT_JSON']=$saPathText.Text;if(-not(Save-CcConfig $cfg)){throw 'Не удалось сохранить настройки Google.'};$r=Test-CcGoogleProductsConnection;if($r.Ok){Toast 'Google Sheets' "Подключение успешно. Диапазон: $($r.Range), строк: $($r.Rows)" 'OK'}else{Show-CcErrorPopup 'Google Sheets' ([System.Exception]::new([string]$r.Message))}}catch{Show-CcErrorPopup 'Google Sheets' $_.Exception}})
$checkUpdate.Add_Click({try{$u=Test-CcShareUpdate;if(-not$u){Toast 'Обновление' 'SMB-источник недоступен или версия уже актуальна.' 'INFO';return};if($u.Available){$answer=[Windows.Forms.MessageBox]::Show("Доступна версия $($u.Remote). Установлена $($u.Local).`r`nИсточник: $($u.Source)`r`n`r`nОбновить сейчас?",'CyberCroc — обновление',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Information);if($answer -eq [Windows.Forms.DialogResult]::Yes){if(Start-CcShareUpdate){exit 0}}}else{Toast 'Обновление' "Установлена актуальная версия $($u.Local)." 'OK'}}catch{Write-CcError -FunctionName 'UpdateNow' -Exception $_.Exception}})
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

Add-MenuButton 'home' 'ГЛАВНАЯ'
Add-MenuButton 'games' 'ИГРЫ'
Add-MenuButton 'faq' 'FAQ / ПРАВИЛА'
Add-MenuButton 'orders' 'ТОВАРЫ / ЗАКАЗЫ'
Add-MenuButton 'support' 'ПОЗВАТЬ АДМИНА'
Add-MenuButton 'zapret' 'ZAPRET'
Add-MenuButton 'accounts' 'АККАУНТЫ'
Add-MenuButton 'apps' 'ПРОГРАММЫ'
Add-MenuButton 'backup' 'БЭКАП'
Add-MenuButton 'cleanup' 'ОЧИСТКА'
Add-MenuButton 'logs' 'ЖУРНАЛ'
Add-MenuButton 'audit' 'АУДИТ ДЕЙСТВИЙ'
Add-MenuButton 'hall' 'КАРТА ЗАЛА'
Add-MenuButton 'settings' 'НАСТРОЙКИ'


$form.KeyPreview=$true
$form.Add_KeyDown({param($sender,$e) try{
    if($e.Control -and $e.KeyCode -eq [Windows.Forms.Keys]::B -and $script:CcRole -eq 'admin'){if($nodeList.SelectedItems.Count){if(Request-CcAdminAccess){Send-NodeCommand 'block';Toast 'Карта зала' 'ПК заблокирован горячей клавишей Ctrl+B.' 'WARN'}}};$e.SuppressKeyPress=$true;return}
    switch($e.KeyCode){'F1'{Show-Page 'support'};'F2'{Show-Page 'orders'};'F3'{if($script:CcRole -eq 'admin'){Show-Page 'hall'}};'F4'{Show-Page 'orders'};'Escape'{Show-Page 'home'}};$e.SuppressKeyPress=$true
}catch{Write-CcError -FunctionName 'Hotkey' -Exception $_.Exception}})
$uiTip.SetToolTip($orderBuy,'Оформить заказ. Перед подтверждением выбирается способ оплаты.');$uiTip.SetToolTip($orderEdit,'Только админ: изменить название, цену и остаток в Google Sheets.');$uiTip.SetToolTip($callBtn,'Запрос попадает на админскую стойку; при отсутствии связи сохраняется в queue.json.');$uiTip.SetToolTip($emergency,'Аварийное сообщение на все клиентские ПК. Использовать только по реальной необходимости.');$uiTip.SetToolTip($fleetBtn,'Синхронизировать общие настройки со всеми обнаруженными клиентскими ПК по SMB.');$uiTip.SetToolTip($homeCheck,'Локальная диагностика Windows и железа.')
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000;$timer.Add_Tick({$clock.Text=(Get-Date).ToString('HH:mm:ss')});$timer.Start()
$logTimer=New-Object Windows.Forms.Timer;$logTimer.Interval=2000;$logTimer.Add_Tick({try{if($pages.ContainsKey('logs') -and $pageHost.Controls.Count -gt 0 -and $pageHost.Controls[0] -eq $pages['logs']){Refresh-Logs}}catch{}});$logTimer.Start()
$gamesTimer=New-Object Windows.Forms.Timer;$gamesTimer.Interval=3600000;$gamesTimer.Add_Tick({try{Update-CcGamesCatalogDaily|Out-Null;Refresh-GameCatalog;Write-CcLog 'Daily games catalog refresh checked' 'INFO' 'GamesTimer'}catch{Write-CcError -FunctionName 'GamesTimer' -Exception $_.Exception}});$gamesTimer.Start()
$productsTimer=New-Object Windows.Forms.Timer;$productsTimer.Interval=300000;$productsTimer.Add_Tick({try{if($pages.ContainsKey('orders') -and $pageHost.Controls.Count -gt 0 -and $pageHost.Controls[0] -eq $pages['orders']){Refresh-OrdersPage}}catch{Write-CcError -FunctionName 'ProductsTimer' -Exception $_.Exception}});$productsTimer.Start()
$heartbeatTimer=New-Object Windows.Forms.Timer;$heartbeatTimer.Interval=2000;$heartbeatTimer.Add_Tick({try{Set-Content -LiteralPath $script:CcHeartbeatFile -Value (Get-Date).ToUniversalTime().ToString('o') -Encoding ASCII}catch{}});$heartbeatTimer.Start()
$networkTimer=New-Object Windows.Forms.Timer;$networkTimer.Interval=500;$networkTimer.Add_Tick({try{
    $now=(Get-Date).ToUniversalTime();$messages=@(Get-CcNetworkMessages);foreach($packet in $messages){$m=$packet.Message;switch([string]$m.type){
        'beacon' { if([string]$m.role -eq 'admin'){ $script:CcLastAdminSeenUtc=$now }; if($script:CcRole -eq 'admin'){ $script:CcKnownNodes[[string]$m.pc_id]=$true } }
        'order' { if($script:CcRole -eq 'admin'){ $o=Register-CcIncomingOrder $m;if($o){Send-CcOrderAck ([string]$m.order_id) $packet.RemoteAddress $packet.RemotePort|Out-Null;[System.Media.SystemSounds]::Exclamation.Play();Toast 'Новый заказ' "$($m.item_name) × $($m.quantity), $($m.payment_type), ПК $($m.client_pc)" 'INFO';Refresh-OrdersPage} } }
        'admin_call' { if($script:CcRole -eq 'admin'){ $c=Register-CcIncomingCall $m;if($c){Send-CcCallAck ([string]$m.call_id) $packet.RemoteAddress $packet.RemotePort|Out-Null;[System.Media.SystemSounds]::Asterisk.Play();Toast 'Вызов админа' "ПК $($m.client_pc): $($m.reason)" 'WARN'} } }
        'ack' { if($script:CcRole -eq 'client'){if($m.ack_type -eq 'order'){Complete-CcQueuedOperation 'order' ([string]$m.reference_id)|Out-Null;Acknowledge-CcOrder ([string]$m.reference_id)}elseif($m.ack_type -eq 'admin_call'){Complete-CcQueuedOperation 'admin_call' ([string]$m.reference_id)|Out-Null;Acknowledge-CcCall ([string]$m.reference_id)}} }
        'account_presence' { if($script:CcRole -eq 'admin' -and $m.account_id){$accountList=@(Get-CcAccounts);$accountChanged=$false;foreach($account in $accountList){if([string]$account.Id -eq [string]$m.account_id){$account.Status=if([string]$m.state -eq 'occupied'){'occupied'}else{'available'};$account.UsedBy=if([string]$m.state -eq 'occupied'){[string]$m.used_by}else{''};$account.UsedSince=if([string]$m.state -eq 'occupied'){[string]$m.used_since}else{''};$account.ActivePc=if([string]$m.state -eq 'occupied'){[string]$m.pc_id}else{''};$account.PcId=[string]$m.pc_id;$accountChanged=$true;break}};if($accountChanged){[void](Save-CcAccounts $accountList);[void](Sync-CcAccounts -Mode Push);Refresh-Accounts;Write-CcAudit -Action 'account.presence' -Target ([string]$m.login) -Result 'success' -Details ('state='+[string]$m.state+'; pc='+[string]$m.pc_id)}} }
        'command' { if([string]$m.sender_role -ne 'admin'){continue};$target=[string]$m.target_pc;if($target -ne '*' -and $target -ne $script:CcPcId){continue};switch([string]$m.action){'message'{Toast 'Сообщение администратора' ([string]$m.text) 'INFO'};'block'{Show-CcClientOverlay 'ПК заблокирован администратором' ([string]$(if($m.reason){$m.reason}else{'Обратитесь к администратору.'})) $false};'unblock'{Toast 'Администратор' 'ПК снова доступен.' 'OK'};'emergency'{Show-CcClientOverlay 'ПОКИНЬТЕ ЗАЛ' ([string]$(if($m.reason){$m.reason}else{'Аварийная ситуация.'})) $true} } }
    }}
    if($script:CcRole -eq 'client'){if((($now-$script:CcLastBeaconUtc).TotalSeconds -ge (Get-CcNetworkConfig).BeaconIntervalSec)){Send-CcBeacon;$script:CcLastBeaconUtc=$now};if((($now-$script:CcLastQueueRetryUtc).TotalSeconds -ge 5 -and (Get-CcQueueItems).Count -gt 0)){Resend-CcQueuedOperations;$script:CcLastQueueRetryUtc=$now}}else{if((($now-$script:CcLastBeaconUtc).TotalSeconds -ge (Get-CcNetworkConfig).BeaconIntervalSec)){Send-CcBeacon;$script:CcLastBeaconUtc=$now};if($pageHost.Controls.Count -gt 0 -and $pageHost.Controls[0] -eq $pages['hall']){$hallNow=(Get-Date).ToUniversalTime();if(-not $script:CcLastHallRefreshUtc -or ($hallNow-$script:CcLastHallRefreshUtc).TotalSeconds -ge 2){Refresh-HallPage;$script:CcLastHallRefreshUtc=$hallNow}}}
    $networkState=if((($now-$script:CcLastAdminSeenUtc).TotalSeconds -le 30)){'АДМИН: ONLINE'}else{'АДМИН: нет связи'};$footer.Text="ПК: $script:CcPcId | Роль: $script:CcRole | Пользователь: $env:USERNAME | Версия: $Version | $networkState"
}catch{Write-CcError -FunctionName 'NetworkTimer' -Exception $_.Exception}});$networkTimer.Start()
Write-CcLog "CyberCroc GUI initialized role=$script:CcRole pc=$script:CcPcId version=$Version" 'OK' 'Startup';Write-CcAudit -Action 'application.start' -Target $script:CcPcId -Result 'success' -Details ("role={0}; version={1}" -f $script:CcRole,$Version)
$syncTimer=New-Object Windows.Forms.Timer;$syncTimer.Interval=30000;$syncTimer.Add_Tick({try{if(Sync-CcAccounts Pull){Refresh-Accounts}}catch{}});$syncTimer.Start()
try{Sync-CcAccounts Pull|Out-Null}catch{}
$script:AppProcess=$null;$script:AppProcessName=''
$appTimer=New-Object Windows.Forms.Timer;$appTimer.Interval=500;$appTimer.Add_Tick({try{if($null -ne $script:AppProcess){if($script:AppProcess.HasExited){$rc=$script:AppProcess.ExitCode;$appInfo.Text="Операция завершена: $script:AppProcessName`nКод: $rc";$progress.Visible=$false;if($rc -eq 0){Toast 'Программы' "$script:AppProcessName установлена/обновлена." 'OK'}else{Show-CcErrorPopup 'Установка программы' ([Exception]("$script:AppProcessName завершилась с кодом $rc"))};$script:AppProcess=$null}}}catch{}});$appTimer.Start()
Refresh-Home;Refresh-GameCatalog;Refresh-AppCatalog;Refresh-Accounts;Refresh-Logs;Refresh-OrdersPage;Apply-Theme;Apply-RoleVisibility;Show-Page 'home'
$form.Add_FormClosing({param($sender,$e) try{if($script:CcRole -eq 'admin' -and (Request-CcAdminAccess)){ $script:CcAllowClose=$true;Stop-CcUdpListener;$e.Cancel=$false;Write-CcLog 'Admin-authorized GUI close.' 'WARN' 'FormClosing';return } $e.Cancel=$true;Write-CcLog 'GUI close prevented by kiosk policy.' 'WARN' 'FormClosing'}catch{$e.Cancel=$true}})
try {
    [void][System.Windows.Forms.Application]::Run($form)
} catch {
    Write-CcError -FunctionName 'Application.Run' -Exception $_.Exception
    throw
}
