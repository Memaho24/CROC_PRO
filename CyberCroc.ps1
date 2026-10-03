$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Root=$PSScriptRoot
$Developer='Eduard'
$Tools=Join-Path $Root 'tools'
. (Join-Path $Tools 'Core.ps1')
. (Join-Path $Tools 'Accounts.ps1')
. (Join-Path $Tools 'Hardware.ps1')

$cfg=Get-CcConfig
$Version=(Get-Content (Join-Path $Root 'version.txt') -Raw).Trim()
$ThemeName=if($cfg['THEME']){$cfg['THEME']}else{'dark'}

$C=@{}
$C.Accent=[Drawing.Color]::FromArgb(57,255,20)
$C.AccentDark=[Drawing.Color]::FromArgb(25,150,15)
$C.Bg=[Drawing.Color]::Black
$C.Panel=[Drawing.Color]::FromArgb(10,10,10)
$C.Control=[Drawing.Color]::FromArgb(26,26,26)
$C.Fg=$C.Accent
$C.Muted=[Drawing.Color]::FromArgb(125,145,125)
$C.White=[Drawing.Color]::White
$C.Danger=[Drawing.Color]::FromArgb(255,80,80)
$C.Warning=[Drawing.Color]::FromArgb(255,190,50)

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
$form.Text="CyberCroc — управление ПК";$form.StartPosition='CenterScreen';$form.WindowState='Maximized';$form.MinimumSize=New-Object Drawing.Size(1000,650);$form.BackColor=$C.Bg;$form.ForeColor=$C.Fg;$form.Font=New-Object Drawing.Font('Segoe UI',10)

function New-Label([string]$Text,[int]$Size=10,[System.Drawing.FontStyle]$Style='Regular'){
    $x=New-Object Windows.Forms.Label;$x.Text=$Text;$x.AutoSize=$true;$x.Font=New-Object Drawing.Font('Segoe UI',$Size,$Style);$x.ForeColor=$C.Fg;return $x
}
function New-Button([string]$Text,[int]$Width=190,[int]$Height=48){
    $x=New-Object Windows.Forms.Button;$x.Text=$Text;$x.Width=$Width;$x.Height=$Height;$x.Margin=New-Object Windows.Forms.Padding(6);$x.FlatStyle='Flat';$x.FlatAppearance.BorderSize=1;$x.FlatAppearance.BorderColor=$C.Fg;$x.BackColor=$C.Control;$x.ForeColor=$C.Fg;$x.Font=New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold);$x.Cursor=[Windows.Forms.Cursors]::Hand;return $x
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
$brand=New-Label 'CYBER CROC' 22 'Bold';$brand.ForeColor=$C.Accent;$brand.Location=New-Object Drawing.Point(18,18);$nav.Controls.Add($brand)
$brand2=New-Label 'ПАНЕЛЬ УПРАВЛЕНИЯ' 8 'Bold';$brand2.ForeColor=$C.Muted;$brand2.Location=New-Object Drawing.Point(20,52);$nav.Controls.Add($brand2)
$menu=New-Object Windows.Forms.FlowLayoutPanel;$menu.Location=New-Object Drawing.Point(12,90);$menu.Size=New-Object Drawing.Size(196,460);$menu.FlowDirection='TopDown';$menu.WrapContents=$false;$menu.AutoScroll=$true;$menu.BackColor=$C.Panel;$nav.Controls.Add($menu)

$content=New-Object Windows.Forms.Panel;$content.Dock='Fill';$content.BackColor=$C.Bg;$shell.Controls.Add($content,1,0)
$footer=New-Label "ПК: $env:COMPUTERNAME   •   CyberCroc $Version" 9;$footer.ForeColor=$C.Muted;$footer.TextAlign='MiddleLeft';$footer.Dock='Fill';$footer.Padding=New-Object Windows.Forms.Padding(14,0,0,0);$shell.Controls.Add($footer,0,1);$shell.SetColumnSpan($footer,2)
$clock=New-Label '' 9;$clock.ForeColor=$C.Muted;$clock.AutoSize=$false;$clock.Dock='Right';$clock.Width=90;$clock.TextAlign='MiddleRight';$footer.Controls.Add($clock)
$progress=New-Object Windows.Forms.ProgressBar;$progress.Style='Marquee';$progress.Visible=$false;$progress.Width=180;$progress.Height=14;$footer.Controls.Add($progress)

$pages=@{};$navButtons=@{}
function Clear-Content{$content.Controls.Clear()}
function Add-MenuButton([string]$Key,[string]$Text){
    $b=New-Button $Text 190 46;$b.TextAlign='MiddleLeft';$b.Padding=New-Object Windows.Forms.Padding(14,0,0,0);$menu.Controls.Add($b);$navButtons[$Key]=$b;$b.Add_Click({Show-Page $Key})
}
function Show-Page([string]$Key){
    try{
        if(-not $pages.ContainsKey($Key)){return};Clear-Content;$content.Controls.Add($pages[$Key])
        foreach($k in $navButtons.Keys){$navButtons[$k].BackColor=$C.Control;$navButtons[$k].ForeColor=$C.Fg}
        $navButtons[$Key].BackColor=$C.AccentDark;$navButtons[$Key].ForeColor=$C.White
    }catch{Write-CcError -FunctionName 'Show-Page' -Exception $_.Exception}
}

# Home
$homePage=New-Object Windows.Forms.Panel;$homePage.Dock='Fill';$homePage.BackColor=$C.Bg;$homePage.Controls.Add((New-PageTitle 'Главная' 'Здесь видно, всё ли в порядке с этим компьютером.'))
$homeBody=New-Object Windows.Forms.FlowLayoutPanel;$homeBody.Dock='Fill';$homeBody.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$homeBody.WrapContents=$true;$homeBody.AutoScroll=$true;$homeBody.BackColor=$C.Bg;$homePage.Controls.Add($homeBody)
$welcome=New-Object Windows.Forms.Panel;$welcome.Width=740;$welcome.Height=105;$welcome.Margin=New-Object Windows.Forms.Padding(8);$welcome.BackColor=$C.Panel
$wl=New-Label "ПК $env:COMPUTERNAME готов к работе" 20 'Bold';$wl.Location=New-Object Drawing.Point(20,15);$welcome.Controls.Add($wl)
$wh=New-Label 'Если всё зелёное — ничего делать не нужно.' 10;$wh.ForeColor=$C.Muted;$wh.Location=New-Object Drawing.Point(22,57);$welcome.Controls.Add($wh);$homeBody.Controls.Add($welcome)
$cardPC=New-Card 'СОСТОЯНИЕ' 'Проверка...' 'нажмите «Проверить ПК»';$cardDisk=New-Card 'ДИСК C:' '—' 'свободное место';$cardNet=New-Card 'СЕТЬ' '—' 'обновления клуба';$homeBody.Controls.Add($cardPC);$homeBody.Controls.Add($cardDisk);$homeBody.Controls.Add($cardNet)
$homeActions=New-Object Windows.Forms.FlowLayoutPanel;$homeActions.Width=740;$homeActions.Height=190;$homeActions.Margin=New-Object Windows.Forms.Padding(8);$homeActions.WrapContents=$true;$homeActions.BackColor=$C.Bg;$homeBody.Controls.Add($homeActions)
$homeCheck=New-Button 'Проверить ПК' 220 62;$homeCleanup=New-Button 'Очистить ПК' 220 62;$homeBackup=New-Button 'Сделать бэкап' 220 62;$homeActions.Controls.Add($homeCheck);$homeActions.Controls.Add($homeCleanup);$homeActions.Controls.Add($homeBackup)

function Refresh-Home{
    try{
        $h=Get-CcHardware;$c=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue;$free=if($c){[math]::Round($c.FreeSpace/1GB,1)}else{0};$size=if($c){[math]::Round($c.Size/1GB,1)}else{0}
        $share=[string]$cfg['UPDATE_SHARE'];$online=if($share -and (Test-Path -LiteralPath $share)){$true}else{$false}
        $cardPC.Controls[1].Text='ГОТОВ';$cardPC.Controls[1].ForeColor=$C.Accent;$cardDisk.Controls[1].Text="$free GB";$cardDisk.Controls[2].Text="из $size GB";$cardNet.Controls[1].Text=if($online){'ONLINE'}else{'OFFLINE'};$cardNet.Controls[1].ForeColor=if($online){$C.Accent}else{$C.Warning}
        $footer.Text="ПК: $env:COMPUTERNAME   •   CyberCroc $Version   •   CPU: $($h.CPU)"
    }catch{$cardPC.Controls[1].Text='ОШИБКА';$cardPC.Controls[1].ForeColor=$C.Danger;Write-CcError -FunctionName 'Refresh-Home' -Exception $_.Exception}
}
$homeCheck.Add_Click({$progress.Visible=$true;try{Refresh-Home;Toast 'Проверка ПК' 'Компьютер проверен.' 'OK'}finally{$progress.Visible=$false}})
$homeCleanup.Add_Click({Run-HiddenCmd 'Cleanup.cmd'})
$homeBackup.Add_Click({Run-HiddenCmd 'Backup.cmd'})
$pages['home']=$homePage
$homePage.Controls[0].BringToFront()

# Games
$games=New-Object Windows.Forms.Panel;$games.Dock='Fill';$games.BackColor=$C.Bg;$games.Controls.Add((New-PageTitle 'Игры' 'Выберите игру и нажмите нужную большую кнопку.'))
$gameArea=New-Object Windows.Forms.TableLayoutPanel;$gameArea.Dock='Fill';$gameArea.Padding=New-Object Windows.Forms.Padding(20,100,20,15);$gameArea.RowCount=3
[void]$gameArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,48)));[void]$gameArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));[void]$gameArea.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,76)));$games.Controls.Add($gameArea)
$gameSearch=New-Object Windows.Forms.TextBox;$gameSearch.Dock='Fill';$gameSearch.Font=New-Object Drawing.Font('Segoe UI',12);$gameSearch.Text='Поиск игры...';$gameSearch.ForeColor=$C.Muted;$gameSearch.BackColor=$C.Control;$gameArea.Controls.Add($gameSearch,0,0)
$gameList=New-Object Windows.Forms.ListView;$gameList.Dock='Fill';$gameList.View='Details';$gameList.FullRowSelect=$true;$gameList.GridLines=$false;$gameList.MultiSelect=$false;$gameList.BackColor=$C.Control;$gameList.ForeColor=$C.Fg
[void]$gameList.Columns.Add('Игра',280);[void]$gameList.Columns.Add('Статус',130);[void]$gameList.Columns.Add('Источник',130);$gameArea.Controls.Add($gameList,0,1)
$gameButtons=New-Flow;$gameLaunch=New-Button '▶  ЗАПУСТИТЬ' 190 58;$gameInstall=New-Button 'Установить' 150 58;$gameUpdate=New-Button 'Обновить' 150 58;$gameAdd=New-Button '+ Добавить игру' 170 58
$gameButtons.Controls.Add($gameLaunch);$gameButtons.Controls.Add($gameInstall);$gameButtons.Controls.Add($gameUpdate);$gameButtons.Controls.Add($gameAdd);$gameArea.Controls.Add($gameButtons,0,2)
function Read-Games{
    $r=@();try{$f=Join-Path $Root 'games.txt';if(Test-Path $f){foreach($raw in Get-Content $f -Encoding UTF8){$s=$raw.Trim();if(!$s -or $s.StartsWith('#')){continue};$c=@($s-split '\|',6);while($c.Count-lt 6){$c+=''};$r+=[pscustomobject]@{Name=$c[0].Trim();PathCheck=$c[1].Trim();Source=$c[2].Trim().ToLowerInvariant();Launcher=$c[3].Trim();AppID=$c[4].Trim();MinVersion=$c[5].Trim()}}}}catch{Write-CcError -FunctionName 'Read-Games' -Exception $_.Exception};return @($r)
}
function Refresh-Games([string]$q=''){
    try{$gameList.BeginUpdate();$gameList.Items.Clear();foreach($g in @(Read-Games)){if($q -and $q -ne 'Поиск игры...' -and $g.Name -notlike "*$q*"){continue};$p=Expand-CcPath $g.PathCheck;$installed=$p -and (Test-Path -LiteralPath $p);$i=New-Object Windows.Forms.ListViewItem($g.Name);[void]$i.SubItems.Add($(if($installed){'УСТАНОВЛЕНА'}else{'НЕТ'}));[void]$i.SubItems.Add($g.Source);$i.Tag=$g;[void]$gameList.Items.Add($i)};$gameList.EndUpdate()}catch{Write-CcError -FunctionName 'Refresh-Games' -Exception $_.Exception}
}
function Invoke-GameAction($g,[string]$Action){
    try{$p=Expand-CcPath $g.PathCheck;$launcher=Expand-CcPath $g.Launcher;if($g.Source -eq 'steam' -and $g.AppID){if($Action -eq 'Launch'){Start-Process "steam://rungameid/$($g.AppID)"}else{Start-Process "steam://install/$($g.AppID)"};return};if($Action -eq 'Launch'){if($p -and (Test-Path $p)){Start-Process -FilePath $p -WorkingDirectory (Split-Path $p -Parent);return};if($launcher -and (Test-Path $launcher)){Start-Process -FilePath $launcher;return};throw "Игра не установлена: $($g.Name)"};if($launcher -and (Test-Path $launcher)){Start-Process -FilePath $launcher;return};throw "Лаунчер не найден: $($g.Name)"}catch{Write-CcError -FunctionName 'Invoke-GameAction' -Exception $_.Exception;Toast 'Игры' $_.Exception.Message 'ERROR'}
}
$gameSearch.Add_GotFocus({if($gameSearch.Text -eq 'Поиск игры...'){$gameSearch.Text='';$gameSearch.ForeColor=$C.Fg}})
$gameSearch.Add_TextChanged({Refresh-Games $gameSearch.Text})
$gameLaunch.Add_Click({if($gameList.SelectedItems.Count){Invoke-GameAction $gameList.SelectedItems[0].Tag 'Launch';Refresh-Games $gameSearch.Text}else{Toast 'Игры' 'Сначала выберите игру.' 'INFO'}})
$gameInstall.Add_Click({if($gameList.SelectedItems.Count){Invoke-GameAction $gameList.SelectedItems[0].Tag 'Install';Refresh-Games $gameSearch.Text}else{Toast 'Игры' 'Сначала выберите игру.' 'INFO'}})
$gameUpdate.Add_Click({if($gameList.SelectedItems.Count){Invoke-GameAction $gameList.SelectedItems[0].Tag 'Update';Refresh-Games $gameSearch.Text}else{Toast 'Игры' 'Сначала выберите игру.' 'INFO'}})
function Show-GameDialog($existing=$null){
    $d=New-Object Windows.Forms.Form;$d.Text=if($existing){'Изменить игру'}else{'Добавить игру'};$d.StartPosition='CenterParent';$d.Size=New-Object Drawing.Size(620,430);$d.BackColor=$C.Bg;$d.ForeColor=$C.Fg
    $l=New-Object Windows.Forms.TableLayoutPanel;$l.Dock='Fill';$l.Padding=New-Object Windows.Forms.Padding(14);$l.ColumnCount=2;$l.RowCount=7
    [void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,150)));[void]$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));$d.Controls.Add($l)
    $names=@('Название','Путь проверки','Источник','Лаунчер','Steam AppID','Мин. версия');$f=@{}
    for($r=0;$r-lt 6;$r++){[void]$l.Controls.Add((New-Label $names[$r]),0,$r);$t=New-Object Windows.Forms.TextBox;$t.Dock='Fill';Apply-ControlTheme $t;$f[$names[$r]]=$t;[void]$l.Controls.Add($t,1,$r)}
    if($existing){$f['Название'].Text=$existing.Name;$f['Путь проверки'].Text=$existing.PathCheck;$f['Источник'].Text=$existing.Source;$f['Лаунчер'].Text=$existing.Launcher;$f['Steam AppID'].Text=$existing.AppID;$f['Мин. версия'].Text=$existing.MinVersion}else{$f['Источник'].Text='steam'}
    $bp=New-Flow;$bp.FlowDirection='RightToLeft';$ok=New-Button 'Сохранить';$cancel=New-Button 'Отмена';$bp.Controls.Add($ok);$bp.Controls.Add($cancel);$l.Controls.Add($bp,1,6);$cancel.Add_Click({$d.Close()})
    $ok.Add_Click({try{$g=[pscustomobject]@{Name=$f['Название'].Text.Trim();PathCheck=$f['Путь проверки'].Text.Trim();Source=$f['Источник'].Text.Trim().ToLower();Launcher=$f['Лаунчер'].Text.Trim();AppID=$f['Steam AppID'].Text.Trim();MinVersion=$f['Мин. версия'].Text.Trim()};if(!$g.Name){throw 'Введите название игры.'};$all=@(Read-Games);if($existing){$all=@($all|Where-Object{$_.Name-ne $existing.Name})};$all+=$g;Save-Games $all|Out-Null;$d.Close();Refresh-Games $gameSearch.Text}catch{Write-CcError -FunctionName 'Game-Dialog' -Exception $_.Exception;Toast 'Игры' $_.Exception.Message 'ERROR'}})
    [void]$d.ShowDialog($form)
}
$gameAdd.Add_Click({Show-GameDialog})
$pages['games']=$games
$games.Controls[0].BringToFront()

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
    for($r=0;$r-lt 5;$r++){[void]$l.Controls.Add((New-Label $names[$r]),0,$r);$t=New-Object Windows.Forms.TextBox;$t.Dock='Fill';Apply-ControlTheme $t;$f[$names[$r]]=$t;[void]$l.Controls.Add($t,1,$r)}
    if($existing){$f['Платформа'].Text=$existing.Platform;$f['Логин'].Text=$existing.Login;$f['Комментарий'].Text=$existing.Comment;$f['Игры'].Text=($existing.Games -join ',')}else{$f['Платформа'].Text='Steam'}
    $f['Пароль'].UseSystemPasswordChar=$true
    $p=New-Flow;$p.FlowDirection='RightToLeft';$ok=New-Button 'Сохранить';$cancel=New-Button 'Отмена';$p.Controls.Add($ok);$p.Controls.Add($cancel);$l.Controls.Add($p,1,5);$cancel.Add_Click({$d.Close()})
    $ok.Add_Click({try{$games=@($f['Игры'].Text-split ','|ForEach-Object{$_.Trim()}|Where-Object{$_});if($existing){Update-CcAccount $existing.Id @{Platform=$f['Платформа'].Text;Login=$f['Логин'].Text;Password=$f['Пароль'].Text;Comment=$f['Комментарий'].Text;Games=$games}|Out-Null}else{New-CcAccount $f['Платформа'].Text $f['Логин'].Text $f['Пароль'].Text $f['Комментарий'].Text $games|Out-Null};$d.Close();Refresh-Accounts}catch{Write-CcError -FunctionName 'Account-Dialog' -Exception $_.Exception;Toast 'Аккаунты' $_.Exception.Message 'ERROR'}})
    [void]$d.ShowDialog($form)
}
$aAdd.Add_Click({Show-AccountDialog})
$aEdit.Add_Click({if($aList.SelectedItems.Count){Show-AccountDialog $aList.SelectedItems[0].Tag}else{Toast 'Аккаунты' 'Выберите аккаунт.' 'INFO'}})
$aDel.Add_Click({if($aList.SelectedItems.Count){Remove-CcAccount $aList.SelectedItems[0].Tag.Id|Out-Null;Refresh-Accounts}})
$pages['accounts']=$accounts
$accounts.Controls[0].BringToFront()

# Applications
$app=New-Object Windows.Forms.Panel;$app.Dock='Fill';$app.BackColor=$C.Bg;$app.Controls.Add((New-PageTitle 'Программы' 'Проверка и установка нужных программ для клуба.'))
$appBody=New-Flow;$appBody.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$app.Controls.Add($appBody)
$appInfo=New-Object Windows.Forms.Panel;$appInfo.Width=720;$appInfo.Height=125;$appInfo.BackColor=$C.Panel;$appBody.Controls.Add($appInfo)
$ai=New-Label 'ПРОГРАММЫ ПК' 18 'Bold';$ai.Location=New-Object Drawing.Point(20,18);$appInfo.Controls.Add($ai)
$aih=New-Label 'Проверить наличие программ или установить недостающие.' 10;$aih.ForeColor=$C.Muted;$aih.Location=New-Object Drawing.Point(22,55);$appInfo.Controls.Add($aih)
$appCheck=New-Button 'Проверить программы' 240 62;$appInstall=New-Button 'Установить / обновить' 240 62;$appBody.Controls.Add($appCheck);$appBody.Controls.Add($appInstall)
function Run-AppTool([bool]$Install){
    try{$args=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $Tools 'Apps.ps1'));if($Install){$args+=@('-Install','-Update')};$p=Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden -Wait -PassThru;Toast 'Программы' $(if($p.ExitCode -eq 0){'Готово.'}else{"Операция завершилась с кодом $($p.ExitCode)."}) $(if($p.ExitCode -eq 0){'OK'}else{'ERROR'})}catch{Write-CcError -FunctionName 'Run-AppTool' -Exception $_.Exception}
}
$appCheck.Add_Click({$progress.Visible=$true;try{Run-AppTool $false}finally{$progress.Visible=$false}});$appInstall.Add_Click({$progress.Visible=$true;try{Run-AppTool $true}finally{$progress.Visible=$false}});$pages['apps']=$app
$app.Controls[0].BringToFront()

# Backup and cleanup
$backup=New-Object Windows.Forms.Panel;$backup.Dock='Fill';$backup.BackColor=$C.Bg;$backup.Controls.Add((New-PageTitle 'Резервная копия' 'Сохраните важные данные перед обслуживанием ПК.'))
$bb=New-Flow;$bb.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$backup.Controls.Add($bb);$backupInfo=New-Card 'БЭКАП' 'ГОТОВ' 'создаёт резервную копию';$bb.Controls.Add($backupInfo);$backupBtn=New-Button 'СДЕЛАТЬ БЭКАП' 250 70;$bb.Controls.Add($backupBtn);$backupBtn.Add_Click({Run-HiddenCmd 'Backup.cmd'});$pages['backup']=$backup
$backup.Controls[0].BringToFront()
$cleanup=New-Object Windows.Forms.Panel;$cleanup.Dock='Fill';$cleanup.BackColor=$C.Bg;$cleanup.Controls.Add((New-PageTitle 'Очистка ПК' 'Удаление временных файлов и мусора.'))
$cb=New-Flow;$cb.Padding=New-Object Windows.Forms.Padding(24,105,24,24);$cleanup.Controls.Add($cb);$cleanupInfo=New-Card 'ОЧИСТКА' 'БЕЗОПАСНО' 'личные файлы не трогаются';$cb.Controls.Add($cleanupInfo);$cleanupBtn=New-Button 'ОЧИСТИТЬ ПК' 250 70;$cb.Controls.Add($cleanupBtn);$cleanupBtn.Add_Click({Run-HiddenCmd 'Cleanup.cmd'});$pages['cleanup']=$cleanup
$cleanup.Controls[0].BringToFront()

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
$checkUpdate.Add_Click({try{$u=Join-Path $Tools 'Updater.ps1';$p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$u,'-Check','-Source',$share.Text) -WindowStyle Hidden -Wait -PassThru;Toast 'Обновление' $(if($p.ExitCode -eq 0){'Проверка завершена.'}else{"Код $($p.ExitCode)"}) 'INFO'}catch{Write-CcError -FunctionName 'UpdateNow' -Exception $_.Exception}})
$pages['settings']=$settings
$settings.Controls[0].BringToFront()

function Run-HiddenCmd([string]$Name){
    try{$p=Start-Process cmd.exe -ArgumentList @('/d','/c','"'+(Join-Path $Root $Name)+'"') -WindowStyle Hidden -Wait -PassThru;Toast 'CyberCroc' $(if($p.ExitCode -eq 0){"$Name завершено."}else{"$($Name): ошибка $($p.ExitCode)"}) $(if($p.ExitCode -eq 0){'OK'}else{'ERROR'})}catch{Write-CcError -FunctionName 'Run-HiddenCmd' -Exception $_.Exception}
}
function Apply-Theme{
    try{
        $form.BackColor=$C.Bg;$form.ForeColor=$C.Fg;$nav.BackColor=$C.Panel;$content.BackColor=$C.Bg;$footer.BackColor=$C.Panel
        foreach($b in $navButtons.Values){$b.BackColor=$C.Control;$b.ForeColor=$C.Fg;$b.FlatAppearance.BorderColor=$C.Fg}
        if($navButtons.ContainsKey('home')){$navButtons['home'].BackColor=$C.AccentDark;$navButtons['home'].ForeColor=$C.White}
        foreach($p in $pages.Values){$p.BackColor=$C.Bg}
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
Refresh-Home;Refresh-Games;Refresh-Accounts;Refresh-Logs;Apply-Theme;Show-Page 'home'
$form.Add_FormClosing({Write-CcLog 'GUI closed' 'INFO' 'FormClosing'})
[void]$form.ShowDialog()
