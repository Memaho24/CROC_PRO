$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$Root=$PSScriptRoot
$Tools=Join-Path $Root 'tools'
. (Join-Path $Tools 'Core.ps1')
. (Join-Path $Tools 'Accounts.ps1')
. (Join-Path $Tools 'Hardware.ps1')
$cfg=Get-CcConfig
$Version=(Get-Content (Join-Path $Root 'version.txt') -Raw).Trim()
$ThemeName=if($cfg['THEME']){$cfg['THEME']}else{'dark'}
$C=@{}
function Set-Theme([string]$Name){
    $script:ThemeName=$Name
    if($Name -eq 'light'){$C.Bg=[Drawing.Color]::FromArgb(240,240,240);$C.Panel=[Drawing.Color]::White;$C.Control=[Drawing.Color]::White;$C.Fg=[Drawing.Color]::FromArgb(30,30,30);$C.Muted=[Drawing.Color]::Gray}
    else{$C.Bg=[Drawing.Color]::Black;$C.Panel=[Drawing.Color]::FromArgb(10,10,10);$C.Control=[Drawing.Color]::FromArgb(26,26,26);$C.Fg=[Drawing.Color]::FromArgb(57,255,20);$C.Muted=[Drawing.Color]::FromArgb(100,120,100)}
}
Set-Theme $ThemeName
$form=New-Object Windows.Forms.Form
$form.Text="CyberCroc $Version"
$form.StartPosition='CenterScreen'
$form.WindowState='Maximized'
$form.MinimumSize=New-Object Drawing.Size(900,600)
$form.BackColor=$C.Bg;$form.ForeColor=$C.Fg;$form.Font=New-Object Drawing.Font('Segoe UI',10)

function Apply-ControlTheme([Windows.Forms.Control]$x){
    try{
        if($x -is [Windows.Forms.TabPage] -or $x -is [Windows.Forms.Panel] -or $x -is [Windows.Forms.TableLayoutPanel] -or $x -is [Windows.Forms.FlowLayoutPanel]){$x.BackColor=$C.Bg}
        elseif($x -is [Windows.Forms.StatusStrip]){$x.BackColor=$C.Panel}
        else{$x.BackColor=$C.Control}
        $x.ForeColor=$C.Fg
        if($x -is [Windows.Forms.Button]){$x.FlatStyle='Flat';$x.FlatAppearance.BorderColor=$C.Border;$x.FlatAppearance.BorderSize=1}
        foreach($c in $x.Controls){Apply-ControlTheme $c}
    }catch{}
}
function New-Flow{
    $p=New-Object Windows.Forms.FlowLayoutPanel;$p.Dock='Fill';$p.WrapContents=$true;$p.AutoScroll=$true;$p.Padding=New-Object Windows.Forms.Padding(5);$p.BackColor=$C.Bg;return $p
}
function New-Button([string]$t){
    $b=New-Object Windows.Forms.Button;$b.Text=$t;$b.AutoSize=$true;$b.MinimumSize=New-Object Drawing.Size(130,34);Apply-ControlTheme $b;return $b
}
function New-Label([string]$t,[int]$size=10){
    $l=New-Object Windows.Forms.Label;$l.Text=$t;$l.AutoSize=$true;$l.Font=New-Object Drawing.Font('Segoe UI',$size);$l.ForeColor=$C.Fg;return $l
}
function Toast($t,$m,$level='INFO'){Show-CcToast $t $m $level}

# Adaptive shell: no fixed screen coordinates.
$main=New-Object Windows.Forms.TableLayoutPanel;$main.Dock='Fill';$main.ColumnCount=1;$main.RowCount=3
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,100)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)))
$main.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,28)))
$form.Controls.Add($main)
$header=New-Object Windows.Forms.Panel;$header.Dock='Fill';$header.Padding=New-Object Windows.Forms.Padding(20,8,20,8);$header.BackColor=$C.Panel;$main.Controls.Add($header,0,0)
$hl=New-Object Windows.Forms.TableLayoutPanel;$hl.Dock='Fill';$hl.ColumnCount=2;$hl.RowCount=2
$hl.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,72)));$hl.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,28)))
$hl.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,65)));$hl.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,35)));$header.Controls.Add($hl)
$titleLabel=New-Label 'CYBER CROC' 25;$titleLabel.Font=New-Object Drawing.Font('Segoe UI',25,[Drawing.FontStyle]::Bold);$titleLabel.ForeColor=[Drawing.Color]::FromArgb(57,255,20);$hl.Controls.Add($titleLabel,0,0)
$subTitle=New-Label "Версия $Version  •  Разработчик: $Developer" 10;$subTitle.ForeColor=$C.Muted;$hl.Controls.Add($subTitle,0,1)
$clockHeader=New-Label '' 12;$clockHeader.TextAlign='MiddleRight';$clockHeader.Dock='Fill';$hl.Controls.Add($clockHeader,1,0);$hl.SetRowSpan($clockHeader,2)
$tabs=New-Object Windows.Forms.TabControl;$tabs.Dock='Fill';$tabs.Padding=New-Object Drawing.Point(14,8);$main.Controls.Add($tabs,0,1)
$footer=New-Label "ПК: $env:COMPUTERNAME";$footer.Dock='Fill';$footer.TextAlign='MiddleLeft';$main.Controls.Add($footer,0,2)
$status=New-Object Windows.Forms.StatusStrip;$status.Dock='Bottom'
$sl=New-Object Windows.Forms.ToolStripStatusLabel;$sl.Text="ПК: $env:COMPUTERNAME";[void]$status.Items.Add($sl)
$sv=New-Object Windows.Forms.ToolStripStatusLabel;$sv.Text="Версия: $Version";[void]$status.Items.Add($sv)
$progress=New-Object Windows.Forms.ToolStripProgressBar;$progress.Visible=$false;$progress.Width=160;[void]$status.Items.Add($progress);$form.Controls.Add($status)

# Home
$home=New-Object Windows.Forms.TabPage;$home.Text='Главная';$home.Padding=New-Object Windows.Forms.Padding(14);[void]$tabs.TabPages.Add($home)
$homeL=New-Object Windows.Forms.TableLayoutPanel;$homeL.Dock='Fill';$homeL.RowCount=2;$homeL.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));$homeL.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,48)));$home.Controls.Add($homeL)
$homeText=New-Object Windows.Forms.TextBox;$homeText.Multiline=$true;$homeText.ReadOnly=$true;$homeText.ScrollBars='Vertical';$homeText.Dock='Fill';$homeText.Font=New-Object Drawing.Font('Consolas',11);Apply-ControlTheme $homeText;$homeL.Controls.Add($homeText,0,0)
$hb=New-Flow;$homeBtn=New-Button 'Обновить статус';$hb.Controls.Add($homeBtn);$homeL.Controls.Add($hb,0,1)
function Refresh-Home{
 try{
  $h=Get-CcHardware;$c=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue;$d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='D:'" -ErrorAction SilentlyContinue
  $ct=if($c){"$([math]::Round($c.FreeSpace/1GB,1)) GB свободно / $([math]::Round($c.Size/1GB,1)) GB"}else{'Не найден'}
  $dt=if($d){"$([math]::Round($d.FreeSpace/1GB,1)) GB свободно / $([math]::Round($d.Size/1GB,1)) GB"}else{'Не найден'}
  $share=[string]$cfg['UPDATE_SHARE'];$net=if($share -and(Test-Path -LiteralPath $share)){'ONLINE'}else{'OFFLINE'}
  $homeText.Text="ПК: $($h.ComputerName)$( [Environment]::NewLine )ОС: $($h.OS)$( [Environment]::NewLine )CPU: $($h.CPU)$( [Environment]::NewLine )GPU: $($h.GPU)$( [Environment]::NewLine )RAM: $($h.RAM)$( [Environment]::NewLine )Диск C: $ct$( [Environment]::NewLine )Диск D: $dt$( [Environment]::NewLine )Температура CPU: $($h.CpuTemp)$( [Environment]::NewLine )SMB update: $net"
  $footer.Text="ПК: $env:COMPUTERNAME    |    Версия: $Version    |    Разработчик: $Developer"
 }catch{Write-CcError -FunctionName 'Refresh-Home' -Exception $_.Exception}
}
$homeBtn.Add_Click({Refresh-Home})

# Games
$games=New-Object Windows.Forms.TabPage;$games.Text='Игры';$games.Padding=New-Object Windows.Forms.Padding(8);[void]$tabs.TabPages.Add($games)
$gl=New-Object Windows.Forms.TableLayoutPanel;$gl.Dock='Fill';$gl.RowCount=3
$gl.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,48)));$gl.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));$gl.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,54)));$games.Controls.Add($gl)
$gt=New-Flow;$gameSearch=New-Object Windows.Forms.TextBox;$gameSearch.Width=280;$gameSearch.Height=30;Apply-ControlTheme $gameSearch;$gt.Controls.Add($gameSearch)
$gameAdd=New-Button 'Добавить';$gameEdit=New-Button 'Изменить';$gameDelete=New-Button 'Удалить';foreach($b in @($gameAdd,$gameEdit,$gameDelete)){$gt.Controls.Add($b)};$gl.Controls.Add($gt,0,0)
$gameList=New-Object Windows.Forms.ListView;$gameList.Dock='Fill';$gameList.View='Details';$gameList.FullRowSelect=$true;$gameList.GridLines=$true;$gameList.MultiSelect=$true
foreach($h in @('Игра','Источник','Установлена','AppID','Мин. версия')){[void]$gameList.Columns.Add($h,150)};Apply-ControlTheme $gameList;$gl.Controls.Add($gameList,0,1)
$gb=New-Flow;$gameLaunch=New-Button 'Запустить';$gameInstall=New-Button 'Установить';$gameUpdate=New-Button 'Проверить / обновить';$gameAllInstall=New-Button 'Установить все';$gameAllUpdate=New-Button 'Обновить все'
foreach($b in @($gameLaunch,$gameInstall,$gameUpdate,$gameAllInstall,$gameAllUpdate)){$gb.Controls.Add($b)};$gl.Controls.Add($gb,0,2)

function Read-Games{
 $r=@();try{$f=Join-Path $Root 'games.txt';if(Test-Path $f){foreach($raw in Get-Content $f -Encoding UTF8){$s=$raw.Trim();if(!$s -or $s.StartsWith('#')){continue};$c=@($s-split '\|',6);while($c.Count-lt 6){$c+=''};$r+=[pscustomobject]@{Name=$c[0].Trim();PathCheck=$c[1].Trim();Source=$c[2].Trim().ToLowerInvariant();Launcher=$c[3].Trim();AppID=$c[4].Trim();MinVersion=$c[5].Trim()}}}}catch{Write-CcError -FunctionName 'Read-Games' -Exception $_.Exception};return @($r)
}
function Save-Games([object[]]$Games){
 try{$lines=@('# CyberCroc game inventory','# Format: Name|PathCheck|Source|Launcher|AppID|MinVersion');foreach($g in @($Games)){if($g.Name){$lines+=('{0}|{1}|{2}|{3}|{4}|{5}'-f $g.Name,$g.PathCheck,$g.Source,$g.Launcher,$g.AppID,$g.MinVersion)}};Set-Content (Join-Path $Root 'games.txt') $lines -Encoding UTF8;Write-CcLog "Games inventory saved: $($Games.Count)" 'OK' 'Games';return $true}catch{Write-CcError -FunctionName 'Save-Games' -Exception $_.Exception;return $false}
}
function Refresh-Games([string]$q=''){
 try{$gameList.BeginUpdate();$gameList.Items.Clear();foreach($g in @(Read-Games)){if($q -and $g.Name -notlike "*$q*"){continue};$p=Expand-CcPath $g.PathCheck;$installed=$p -and(Test-Path -LiteralPath $p);$i=New-Object Windows.Forms.ListViewItem($g.Name);[void]$i.SubItems.Add($g.Source);[void]$i.SubItems.Add($(if($installed){'ДА'}else{'НЕТ'}));[void]$i.SubItems.Add($g.AppID);[void]$i.SubItems.Add($g.MinVersion);$i.Tag=$g;[void]$gameList.Items.Add($i)};$gameList.EndUpdate()}catch{Write-CcError -FunctionName 'Refresh-Games' -Exception $_.Exception}
}
function Selected-Games{return @($gameList.SelectedItems|ForEach-Object{$_.Tag})}
function Invoke-GameAction($g,[string]$Action){
 try{
  $p=Expand-CcPath $g.PathCheck;$launcher=Expand-CcPath $g.Launcher
  if($g.Source -eq 'steam' -and $g.AppID){if($Action -eq 'Launch'){Start-Process "steam://rungameid/$($g.AppID)"}else{Start-Process "steam://install/$($g.AppID)"};Write-CcLog "$Action $($g.Name) via Steam" 'OK' 'Games';return}
  if($Action -eq 'Launch'){if($p -and(Test-Path $p)){Start-Process -FilePath $p -WorkingDirectory (Split-Path $p -Parent);return};if($launcher -and(Test-Path $launcher)){Start-Process -FilePath $launcher;return};throw "Игра не установлена: $($g.Name)"}
  if($launcher -and(Test-Path $launcher)){Start-Process -FilePath $launcher;Write-CcLog "$Action launcher opened for $($g.Name)" 'OK' 'Games';return}
  throw "Лаунчер не найден для $($g.Name)"
 }catch{Write-CcError -FunctionName 'Invoke-GameAction' -Exception $_.Exception;Toast 'Игры' $_.Exception.Message 'ERROR'}
}
function Show-GameDialog($existing=$null){
 $d=New-Object Windows.Forms.Form;$d.Text=if($existing){'Изменить игру'}else{'Добавить игру'};$d.StartPosition='CenterParent';$d.Size=New-Object Drawing.Size(620,430);$d.BackColor=$C.Bg;$d.ForeColor=$C.Fg
 $l=New-Object Windows.Forms.TableLayoutPanel;$l.Dock='Fill';$l.Padding=New-Object Windows.Forms.Padding(14);$l.ColumnCount=2;$l.RowCount=7;$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,150)));$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));$d.Controls.Add($l)
 $names=@('Название','Путь проверки','Источник','Лаунчер','Steam AppID','Мин. версия');$f=@{}
 for($r=0;$r-lt 6;$r++){[void]$l.Controls.Add((New-Label $names[$r]),0,$r);$t=New-Object Windows.Forms.TextBox;$t.Dock='Fill';Apply-ControlTheme $t;$f[$names[$r]]=$t;[void]$l.Controls.Add($t,1,$r)}
 if($existing){$f['Название'].Text=$existing.Name;$f['Путь проверки'].Text=$existing.PathCheck;$f['Источник'].Text=$existing.Source;$f['Лаунчер'].Text=$existing.Launcher;$f['Steam AppID'].Text=$existing.AppID;$f['Мин. версия'].Text=$existing.MinVersion}else{$f['Источник'].Text='steam'}
 $bp=New-Flow;$bp.FlowDirection='RightToLeft';$ok=New-Button 'Сохранить';$cancel=New-Button 'Отмена';$bp.Controls.Add($ok);$bp.Controls.Add($cancel);$l.Controls.Add($bp,1,6)
 $cancel.Add_Click({$d.Close()})
 $ok.Add_Click({try{$g=[pscustomobject]@{Name=$f['Название'].Text.Trim();PathCheck=$f['Путь проверки'].Text.Trim();Source=$f['Источник'].Text.Trim().ToLower();Launcher=$f['Лаунчер'].Text.Trim();AppID=$f['Steam AppID'].Text.Trim();MinVersion=$f['Мин. версия'].Text.Trim()};if(!$g.Name){throw 'Введите название игры.'};$all=@(Read-Games);if($existing){$all=@($all|Where-Object{$_.Name-ne $existing.Name})};$all+=$g;Save-Games $all|Out-Null;$d.Close();Refresh-Games $gameSearch.Text}catch{Write-CcError -FunctionName 'Game-Dialog' -Exception $_.Exception;Toast 'Игры' $_.Exception.Message 'ERROR'}})
 [void]$d.ShowDialog($form)
}
$gameSearch.Add_TextChanged({Refresh-Games $gameSearch.Text})
$gameAdd.Add_Click({Show-GameDialog})
$gameEdit.Add_Click({$x=Selected-Games;if($x.Count-eq 1){Show-GameDialog $x[0]}else{Toast 'Игры' 'Выберите одну игру.' 'INFO'}})
$gameDelete.Add_Click({$x=Selected-Games;if($x.Count){$n=@($x|ForEach-Object{$_.Name});Save-Games @(Read-Games|Where-Object{$_.Name-notin $n})|Out-Null;Refresh-Games $gameSearch.Text}})
$gameLaunch.Add_Click({foreach($g in @(Selected-Games)){Invoke-GameAction $g 'Launch'};Refresh-Games $gameSearch.Text})
$gameInstall.Add_Click({foreach($g in @(Selected-Games)){Invoke-GameAction $g 'Install'};Refresh-Games $gameSearch.Text})
$gameUpdate.Add_Click({foreach($g in @(Selected-Games)){Invoke-GameAction $g 'Update'};Refresh-Games $gameSearch.Text})
$gameAllInstall.Add_Click({$progress.Visible=$true;$progress.Style='Marquee';foreach($g in @(Read-Games)){Invoke-GameAction $g 'Install'};$progress.Visible=$false;Toast 'Игры' 'Установка отправлена для всех игр.' 'OK'})
$gameAllUpdate.Add_Click({$progress.Visible=$true;$progress.Style='Marquee';foreach($g in @(Read-Games)){Invoke-GameAction $g 'Update'};$progress.Visible=$false;Toast 'Игры' 'Проверка/обновление отправлена для всех игр.' 'OK'})

# Accounts
$accounts=New-Object Windows.Forms.TabPage;$accounts.Text='Аккаунты';$accounts.Padding=New-Object Windows.Forms.Padding(8);[void]$tabs.TabPages.Add($accounts)
$al=New-Object Windows.Forms.TableLayoutPanel;$al.Dock='Fill';$al.ColumnCount=2;$al.RowCount=2;$al.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,75)));$al.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,25)));$al.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));$al.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,45)));$accounts.Controls.Add($al)
$aList=New-Object Windows.Forms.ListView;$aList.View='Details';$aList.FullRowSelect=$true;$aList.Dock='Fill';foreach($h in @('Платформа','Логин','Статус','Бан','Последняя проверка')){[void]$aList.Columns.Add($h,145)};Apply-ControlTheme $aList;$al.Controls.Add($aList,0,0)
$ab=New-Flow;$aAdd=New-Button 'Добавить';$aEdit=New-Button 'Изменить';$aDel=New-Button 'Удалить';$aCheck=New-Button 'Проверить';$aLogin=New-Button 'Сменить';$aExport=New-Button 'Экспорт';$aImport=New-Button 'Импорт';foreach($b in @($aAdd,$aEdit,$aDel,$aCheck,$aLogin,$aExport,$aImport)){$ab.Controls.Add($b)};$al.Controls.Add($ab,1,0)
$aSearch=New-Object Windows.Forms.TextBox;$aSearch.Width=280;Apply-ControlTheme $aSearch;$al.Controls.Add($aSearch,0,1)
function Refresh-Accounts([string]$q=''){try{$aList.Items.Clear();foreach($a in Get-CcAccounts){if($q -and "$($a.Platform) $($a.Login)" -notlike "*$q*"){continue};$i=New-Object Windows.Forms.ListViewItem($a.Platform);[void]$i.SubItems.Add($a.Login);[void]$i.SubItems.Add($a.Status);[void]$i.SubItems.Add($(if($a.Banned){'BAN'}else{'-'}));[void]$i.SubItems.Add([string]$a.LastCheck);$i.Tag=$a;[void]$aList.Items.Add($i)}}catch{Write-CcError -FunctionName 'Refresh-Accounts' -Exception $_.Exception}}
function Show-AccountDialog($existing=$null){
    $d=New-Object Windows.Forms.Form;$d.Text=if($existing){'Изменить аккаунт'}else{'Добавить аккаунт'};$d.StartPosition='CenterParent';$d.Size=New-Object Drawing.Size(520,390);$d.BackColor=$C.Bg;$d.ForeColor=$C.Fg
    $l=New-Object Windows.Forms.TableLayoutPanel;$l.Dock='Fill';$l.Padding=New-Object Windows.Forms.Padding(14);$l.ColumnCount=2;$l.RowCount=6;$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,130)));$l.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));$d.Controls.Add($l)
    $names=@('Платформа','Логин','Пароль','Комментарий','Игры');$f=@{}
    for($r=0;$r-lt 5;$r++){[void]$l.Controls.Add((New-Label $names[$r]),0,$r);$t=New-Object Windows.Forms.TextBox;$t.Dock='Fill';Apply-ControlTheme $t;$f[$names[$r]]=$t;[void]$l.Controls.Add($t,1,$r)}
    if($existing){$f['Платформа'].Text=$existing.Platform;$f['Логин'].Text=$existing.Login;$f['Комментарий'].Text=$existing.Comment;$f['Игры'].Text=($existing.Games -join ',')}else{$f['Платформа'].Text='Steam'};$f['Пароль'].UseSystemPasswordChar=$true
    $p=New-Flow;$p.FlowDirection='RightToLeft';$ok=New-Button 'Сохранить';$cancel=New-Button 'Отмена';$p.Controls.Add($ok);$p.Controls.Add($cancel);$l.Controls.Add($p,1,5);$cancel.Add_Click({$d.Close()})
    $ok.Add_Click({try{$games=@($f['Игры'].Text-split ','|ForEach-Object{$_.Trim()}|Where-Object{$_});if($existing){Update-CcAccount $existing.Id @{Platform=$f['Платформа'].Text;Login=$f['Логин'].Text;Password=$f['Пароль'].Text;Comment=$f['Комментарий'].Text;Games=$games}|Out-Null}else{New-CcAccount $f['Платформа'].Text $f['Логин'].Text $f['Пароль'].Text $f['Комментарий'].Text $games|Out-Null};$d.Close();Refresh-Accounts $aSearch.Text}catch{Write-CcError -FunctionName 'Account-Dialog' -Exception $_.Exception}})
    [void]$d.ShowDialog($form)
}
$aAdd.Add_Click({Show-AccountDialog})
$aEdit.Add_Click({if($aList.SelectedItems.Count){Show-AccountDialog $aList.SelectedItems[0].Tag}})
$aDel.Add_Click({if($aList.SelectedItems.Count){Remove-CcAccount $aList.SelectedItems[0].Tag.Id|Out-Null;Refresh-Accounts $aSearch.Text}})
$aLogin.Add_Click({if($aList.SelectedItems.Count){Start-CcAccountSession $aList.SelectedItems[0].Tag|Out-Null;Refresh-Accounts $aSearch.Text}})
$aExport.Add_Click({try{$d=New-Object Windows.Forms.SaveFileDialog;$d.Filter='JSON|*.json';if($d.ShowDialog() -eq 'OK'){@(Get-CcAccounts)|ConvertTo-Json -Depth 12|Set-Content $d.FileName -Encoding UTF8}}catch{Write-CcError -FunctionName 'Account-Export' -Exception $_.Exception}})
$aImport.Add_Click({try{$d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='JSON|*.json';if($d.ShowDialog() -eq 'OK'){Save-CcAccounts @(Get-Content $d.FileName -Raw -Encoding UTF8|ConvertFrom-Json)|Out-Null;Refresh-Accounts}}catch{Write-CcError -FunctionName 'Account-Import' -Exception $_.Exception}})
$aCheck.Add_Click({try{$progress.Visible=$true;$progress.Style='Marquee';foreach($a in @(Get-CcAccounts)){Test-CcAccount $a $cfg|Out-Null};Save-CcAccounts @(Get-CcAccounts)|Out-Null;Refresh-Accounts;$progress.Visible=$false}catch{$progress.Visible=$false;Write-CcError -FunctionName 'Account-Check' -Exception $_.Exception}})
$aSearch.Add_TextChanged({Refresh-Accounts $aSearch.Text})

# Apps
$app=New-Object Windows.Forms.TabPage;$app.Text='Приложения';$app.Padding=New-Object Windows.Forms.Padding(8);[void]$tabs.TabPages.Add($app)
$appL=New-Object Windows.Forms.TableLayoutPanel;$appL.Dock='Fill';$appL.RowCount=2;$appL.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));$appL.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,48)));$app.Controls.Add($appL)
$appList=New-Object Windows.Forms.ListView;$appList.View='Details';$appList.FullRowSelect=$true;$appList.Dock='Fill';foreach($h in @('Название','Источник','Тип','Установлено','Действие')){[void]$appList.Columns.Add($h,170)};Apply-ControlTheme $appList;$appL.Controls.Add($appList,0,0)
$appB=New-Flow;$appRun=New-Button 'Проверить программы';$appInstall=New-Button 'Установить / обновить';$appB.Controls.Add($appRun);$appB.Controls.Add($appInstall);$appL.Controls.Add($appB,0,1)
function Run-AppTool([bool]$install){try{$args=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $Tools 'Apps.ps1'));if($install){$args+=@('-Install','-Update')};$p=Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden -Wait -PassThru;Toast 'Приложения' "Код $($p.ExitCode)" $(if($p.ExitCode-eq 0){'OK'}else{'ERROR'})}catch{Write-CcError -FunctionName 'Run-AppTool' -Exception $_.Exception}}
$appRun.Add_Click({$progress.Visible=$true;$progress.Style='Marquee';Run-AppTool $false;$progress.Visible=$false});$appInstall.Add_Click({$progress.Visible=$true;$progress.Style='Marquee';Run-AppTool $true;$progress.Visible=$false})

# Backup/Cleanup/Logs
$backup=New-Object Windows.Forms.TabPage;$backup.Text='Бэкап';$backup.Padding=New-Object Windows.Forms.Padding(14);[void]$tabs.TabPages.Add($backup);$bfp=New-Flow;$backup.Controls.Add($bfp);$backupBtn=New-Button 'Запустить бэкап';$bfp.Controls.Add($backupBtn)
$cleanup=New-Object Windows.Forms.TabPage;$cleanup.Text='Очистка';$cleanup.Padding=New-Object Windows.Forms.Padding(14);[void]$tabs.TabPages.Add($cleanup);$cfp=New-Flow;$cleanup.Controls.Add($cfp);$cleanupBtn=New-Button 'Запустить очистку';$cfp.Controls.Add($cleanupBtn)
function Run-HiddenCmd([string]$Name){try{$p=Start-Process cmd.exe -ArgumentList @('/d','/c','"'+(Join-Path $Root $Name)+'"') -WindowStyle Hidden -Wait -PassThru;Toast 'CyberCroc' "$Name: $($p.ExitCode)" $(if($p.ExitCode-eq 0){'OK'}else{'ERROR'})}catch{Write-CcError -FunctionName 'Run-HiddenCmd' -Exception $_.Exception}}
$backupBtn.Add_Click({Run-HiddenCmd 'Backup.cmd'});$cleanupBtn.Add_Click({Run-HiddenCmd 'Cleanup.cmd'})
$logs=New-Object Windows.Forms.TabPage;$logs.Text='Логи';$logs.Padding=New-Object Windows.Forms.Padding(8);[void]$tabs.TabPages.Add($logs)
$ll=New-Object Windows.Forms.TableLayoutPanel;$ll.Dock='Fill';$ll.RowCount=2;$ll.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent,100)));$ll.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute,45)));$logs.Controls.Add($ll)
$logText=New-Object Windows.Forms.TextBox;$logText.Multiline=$true;$logText.ReadOnly=$true;$logText.ScrollBars='Both';$logText.Dock='Fill';$logText.Font=New-Object Drawing.Font('Consolas',9);Apply-ControlTheme $logText;$ll.Controls.Add($logText,0,0);$lp=New-Flow;$logBtn=New-Button 'Обновить';$lp.Controls.Add($logBtn);$ll.Controls.Add($lp,0,1)
function Refresh-Logs{try{$p=Join-Path $Root 'logs\CyberCroc.log';$e=Join-Path $Root 'logs\errors.log';$s='';if(Test-Path $p){$s+=Get-Content $p -Raw};if(Test-Path $e){$s+=[Environment]::NewLine+'===== ERRORS ====='+[Environment]::NewLine+(Get-Content $e -Raw)};$logText.Text=$s}catch{}};$logBtn.Add_Click({Refresh-Logs})

# Settings / live theme
$settings=New-Object Windows.Forms.TabPage;$settings.Text='Настройки';$settings.Padding=New-Object Windows.Forms.Padding(14);[void]$tabs.TabPages.Add($settings)
$set=New-Object Windows.Forms.TableLayoutPanel;$set.Dock='Top';$set.AutoSize=$true;$set.ColumnCount=2;$set.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Absolute,180)));$set.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,100)));$settings.Controls.Add($set)
[void]$set.Controls.Add((New-Label 'Тема'),0,0);$theme=New-Object Windows.Forms.ComboBox;$theme.DropDownStyle='DropDownList';$theme.Items.AddRange(@('dark','neon','light'));$theme.SelectedItem=$ThemeName;$theme.Width=220;Apply-ControlTheme $theme;$set.Controls.Add($theme,1,0)
[void]$set.Controls.Add((New-Label 'SMB update'),0,1);$share=New-Object Windows.Forms.TextBox;$share.Text=$cfg['UPDATE_SHARE'];$share.Dock='Fill';Apply-ControlTheme $share;$set.Controls.Add($share,1,1)
$setB=New-Flow;$save=New-Button 'Сохранить настройки';$update=New-Button 'Проверить обновления сейчас';$setB.Controls.Add($save);$setB.Controls.Add($update);$set.Controls.Add($setB,1,2)
$theme.Add_SelectedIndexChanged({Set-Theme $theme.Text;Apply-Theme})
$save.Add_Click({try{Set-Theme $theme.Text;$cfg['THEME']=$theme.Text;$cfg['UPDATE_SHARE']=$share.Text;$lines=@();foreach($k in $cfg.Keys){$lines+=($k+'='+$cfg[$k])};Set-Content (Join-Path $Root 'config.ini') ($lines -join [Environment]::NewLine) -Encoding UTF8;Apply-Theme;Toast 'Настройки' 'Сохранено' 'OK'}catch{Write-CcError -FunctionName 'SaveSettings' -Exception $_.Exception}})
$update.Add_Click({try{$u=Join-Path $Tools 'Updater.ps1';$p=Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$u,'-Check','-Source',$share.Text) -WindowStyle Hidden -Wait -PassThru;Toast 'Обновление' "Код $($p.ExitCode)" 'INFO'}catch{Write-CcError -FunctionName 'UpdateNow' -Exception $_.Exception}})

function Apply-Theme{
 try{
  $form.BackColor=$C.Bg;$form.ForeColor=$C.Fg;$header.BackColor=$C.Panel;$titleLabel.ForeColor=[Drawing.Color]::FromArgb(57,255,20);$subTitle.ForeColor=$C.Muted;$footer.ForeColor=$C.Muted;$status.BackColor=$C.Panel
  foreach($c in $form.Controls){Apply-ControlTheme $c}
 }catch{Write-CcError -FunctionName 'Apply-Theme' -Exception $_.Exception}
}
$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000;$timer.Add_Tick({$clockHeader.Text=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')});$timer.Start()
Refresh-Home;Refresh-Games;Refresh-Accounts;Refresh-Logs;Apply-Theme
$form.Add_FormClosing({Write-CcLog 'GUI closed' 'INFO' 'FormClosing'})
[void]$form.ShowDialog()
