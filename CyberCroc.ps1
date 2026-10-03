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
$form.Text="CyberCroc $Version";$form.Size=New-Object Drawing.Size(1180,760);$form.MinimumSize=New-Object Drawing.Size(980,650);$form.StartPosition='CenterScreen';$form.BackColor=$C.Bg;$form.ForeColor=$C.Fg;$form.Font=New-Object Drawing.Font('Segoe UI',9)
$tabs=New-Object Windows.Forms.TabControl;$tabs.Dock='Fill';$form.Controls.Add($tabs)
$status=New-Object Windows.Forms.StatusStrip;$status.BackColor=$C.Panel
$sl=New-Object Windows.Forms.ToolStripStatusLabel;$sl.Text="ПК: $env:COMPUTERNAME";$status.Items.Add($sl)|Out-Null
$sv=New-Object Windows.Forms.ToolStripStatusLabel;$sv.Text="Версия: $Version";$status.Items.Add($sv)|Out-Null
$clock=New-Object Windows.Forms.ToolStripStatusLabel;$clock.Spring=$true;$status.Items.Add($clock)|Out-Null
$progress=New-Object Windows.Forms.ToolStripProgressBar;$progress.Visible=$false;$progress.Width=140;$status.Items.Add($progress)|Out-Null
$form.Controls.Add($status)
function Style-Control($x){try{$x.BackColor=$C.Control;$x.ForeColor=$C.Fg;if($x -is [Windows.Forms.Button]){$x.FlatStyle='Flat';$x.FlatAppearance.BorderColor=$C.Fg;$x.FlatAppearance.BorderSize=1}}catch{}}
function New-Tab([string]$Text){$t=New-Object Windows.Forms.TabPage;$t.Text=$Text;$t.BackColor=$C.Bg;$t.ForeColor=$C.Fg;$tabs.TabPages.Add($t)|Out-Null;return $t}
function Btn($text,$x,$y,$w=170,$h=36){$b=New-Object Windows.Forms.Button;$b.Text=$text;$b.Location=New-Object Drawing.Point($x,$y);$b.Size=New-Object Drawing.Size($w,$h);Style-Control $b;return $b}
function Lbl($text,$x,$y,$w=220,$h=24){$l=New-Object Windows.Forms.Label;$l.Text=$text;$l.Location=New-Object Drawing.Point($x,$y);$l.Size=New-Object Drawing.Size($w,$h);$l.ForeColor=$C.Fg;return $l}
function Toast($title,$message,$level='INFO'){Show-CcToast $title $message $level}

$homeTab=New-Tab 'Главная'
$homeText=New-Object Windows.Forms.TextBox;$homeText.Multiline=$true;$homeText.ReadOnly=$true;$homeText.Dock='Fill';$homeText.Font=New-Object Drawing.Font('Consolas',11);Style-Control $homeText;$homeTab.Controls.Add($homeText)
$homeBtn=Btn 'Обновить статус' 15 15;$homeTab.Controls.Add($homeBtn)
function Refresh-Home{
    try{$h=Get-CcHardware;$share=[string]$cfg['UPDATE_SHARE'];$net=if($share -and(Test-Path $share)){'ONLINE'}else{'OFFLINE'}
    $homeText.Text="ПК: $($h.ComputerName)$( [Environment]::NewLine )ОС: $($h.OS)$( [Environment]::NewLine )CPU: $($h.CPU)$( [Environment]::NewLine )GPU: $($h.GPU)$( [Environment]::NewLine )RAM: $($h.RAM)$( [Environment]::NewLine )Диск C: $($h.Disk)$( [Environment]::NewLine )Температура CPU: $($h.CpuTemp)$( [Environment]::NewLine )Версия: $Version$( [Environment]::NewLine )SMB update: $net"}catch{Write-CcError -FunctionName 'Refresh-Home' -Exception $_.Exception}}
$homeBtn.Add_Click({Refresh-Home})

$games=New-Tab 'Игры'
$gameSearch=New-Object Windows.Forms.TextBox;$gameSearch.Location=New-Object Drawing.Point(15,15);$gameSearch.Size=New-Object Drawing.Size(350,30);Style-Control $gameSearch;$games.Controls.Add($gameSearch)
$gameList=New-Object Windows.Forms.ListBox;$gameList.Location=New-Object Drawing.Point(15,55);$gameList.Size=New-Object Drawing.Size(1050,560);Style-Control $gameList;$games.Controls.Add($gameList)
function Load-Games([string]$q=''){try{$gameList.Items.Clear();$f=Join-Path $Root 'games.txt';if(Test-Path $f){foreach($l in Get-Content $f -Encoding UTF8){$s=$l.Trim();if((!$s) -or $s.StartsWith('#')){continue};$name=($s-split '\|')[0].Trim();if((!$q) -or ($name -like "*$q*")){$gameList.Items.Add($name)|Out-Null}}}}catch{Write-CcError -FunctionName 'Load-Games' -Exception $_.Exception}}
$gameSearch.Add_TextChanged({Load-Games $gameSearch.Text})

$accounts=New-Tab 'Аккаунты'
$aList=New-Object Windows.Forms.ListView;$aList.View='Details';$aList.FullRowSelect=$true;$aList.GridLines=$true;$aList.Location=New-Object Drawing.Point(15,15);$aList.Size=New-Object Drawing.Size(760,590);Style-Control $aList
foreach($h in @('Платформа','Логин','Статус','Бан','Последняя проверка')){$aList.Columns.Add($h,145)|Out-Null};$accounts.Controls.Add($aList)
$aSearch=New-Object Windows.Forms.TextBox;$aSearch.Location=New-Object Drawing.Point(15,615);$aSearch.Size=New-Object Drawing.Size(300,30);Style-Control $aSearch;$accounts.Controls.Add($aSearch)
$aAdd=Btn 'Добавить' 800 15;$aEdit=Btn 'Изменить' 800 55;$aDel=Btn 'Удалить' 800 95;$aCheck=Btn 'Проверить сейчас' 800 135;$aLogin=Btn 'Сменить аккаунт' 800 175;$aExport=Btn 'Экспорт JSON' 800 215;$aImport=Btn 'Импорт JSON' 800 255
foreach($b in @($aAdd,$aEdit,$aDel,$aCheck,$aLogin,$aExport,$aImport)){$accounts.Controls.Add($b)}
function Refresh-Accounts([string]$q=''){try{$aList.Items.Clear();foreach($a in Get-CcAccounts){if($q -and ("$($a.Platform) $($a.Login)" -notlike "*$q*")){continue};$i=New-Object Windows.Forms.ListViewItem($a.Platform);$i.SubItems.Add($a.Login)|Out-Null;$i.SubItems.Add($a.Status)|Out-Null;$i.SubItems.Add($(if($a.Banned){'BAN'}else{'-'}))|Out-Null;$i.SubItems.Add([string]$a.LastCheck)|Out-Null;$i.Tag=$a;$aList.Items.Add($i)|Out-Null}}catch{Write-CcError -FunctionName 'Refresh-Accounts' -Exception $_.Exception}}
function Account-Dialog($existing=$null){
    $d=New-Object Windows.Forms.Form;$d.Text=if($existing){'Изменить аккаунт'}else{'Добавить аккаунт'};$d.Size=New-Object Drawing.Size(500,430);$d.StartPosition='CenterParent';$d.BackColor=$C.Bg;$d.ForeColor=$C.Fg
    $d.Controls.Add((Lbl 'Платформа' 20 20));$d.Controls.Add((Lbl 'Логин' 20 80));$d.Controls.Add((Lbl 'Пароль' 20 140));$d.Controls.Add((Lbl 'Комментарий' 20 200));$d.Controls.Add((Lbl 'Игры' 20 260))
    $cb=New-Object Windows.Forms.ComboBox;$cb.Location=New-Object Drawing.Point(170,18);$cb.Size=New-Object Drawing.Size(280,30);$cb.Items.AddRange(@('Steam','Riot Games','Battle.net','Epic Games'));Style-Control $cb;$d.Controls.Add($cb)
    $login=New-Object Windows.Forms.TextBox;$login.Location=New-Object Drawing.Point(170,78);$login.Size=New-Object Drawing.Size(280,30);Style-Control $login;$d.Controls.Add($login)
    $pass=New-Object Windows.Forms.TextBox;$pass.Location=New-Object Drawing.Point(170,138);$pass.Size=New-Object Drawing.Size(280,30);$pass.UseSystemPasswordChar=$true;Style-Control $pass;$d.Controls.Add($pass)
    $comment=New-Object Windows.Forms.TextBox;$comment.Location=New-Object Drawing.Point(170,198);$comment.Size=New-Object Drawing.Size(280,50);$comment.Multiline=$true;Style-Control $comment;$d.Controls.Add($comment)
    $ag=New-Object Windows.Forms.TextBox;$ag.Location=New-Object Drawing.Point(170,258);$ag.Size=New-Object Drawing.Size(280,30);Style-Control $ag;$d.Controls.Add($ag)
    if($existing){$cb.SelectedItem=$existing.Platform;$login.Text=$existing.Login;$comment.Text=$existing.Comment;$ag.Text=($existing.Games -join ',')}else{$cb.SelectedIndex=0}
    $ok=Btn 'Сохранить' 170 315 130;$cancel=Btn 'Отмена' 320 315 130;$d.Controls.Add($ok);$d.Controls.Add($cancel);$cancel.Add_Click({$d.Close()})
    $ok.Add_Click({try{if($existing){Update-CcAccount $existing.Id @{Platform=$cb.Text;Login=$login.Text;Password=$pass.Text;Comment=$comment.Text;Games=@($ag.Text -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_})}|Out-Null}else{New-CcAccount $cb.Text $login.Text $pass.Text $comment.Text @($ag.Text -split ','|ForEach-Object{$_.Trim()}|Where-Object{$_})|Out-Null};Refresh-Accounts $aSearch.Text;$d.Close();Toast 'Аккаунты' 'Сохранено' 'OK'}catch{Write-CcError -FunctionName 'Account-Dialog' -Exception $_.Exception;Toast 'Ошибка' $_.Exception.Message 'ERROR'}})
    $d.ShowDialog()|Out-Null
}
$aAdd.Add_Click({Account-Dialog});$aEdit.Add_Click({if($aList.SelectedItems.Count){Account-Dialog $aList.SelectedItems[0].Tag}})
$aDel.Add_Click({if($aList.SelectedItems.Count){if([Windows.Forms.MessageBox]::Show('Удалить выбранный аккаунт?','CyberCroc','YesNo','Warning')-eq'Yes'){Remove-CcAccount $aList.SelectedItems[0].Tag.Id|Out-Null;Refresh-Accounts}}})
$aLogin.Add_Click({if($aList.SelectedItems.Count){if(Start-CcAccountSession $aList.SelectedItems[0].Tag){Refresh-Accounts;Toast 'Сессия' 'Аккаунт запущен' 'OK'}else{Toast 'Ошибка' 'Не удалось запустить аккаунт' 'ERROR'}}})
$aCheck.Add_Click({try{$progress.Visible=$true;$progress.Style='Marquee';foreach($a in @(Get-CcAccounts)){Test-CcAccount $a $cfg|Out-Null};Save-CcAccounts @(Get-CcAccounts)|Out-Null;Refresh-Accounts;$progress.Visible=$false;Toast 'Аккаунты' 'Проверка завершена' 'OK'}catch{$progress.Visible=$false;Toast 'Ошибка' $_.Exception.Message 'ERROR'}})
$aSearch.Add_TextChanged({Refresh-Accounts $aSearch.Text})
$aExport.Add_Click({try{$d=New-Object Windows.Forms.SaveFileDialog;$d.Filter='CyberCroc accounts (*.json)|*.json';if($d.ShowDialog() -eq 'OK'){@(Get-CcAccounts)|ConvertTo-Json -Depth 12|Set-Content $d.FileName -Encoding UTF8;Toast 'Экспорт' 'JSON сохранён. DPAPI-протектированные пароли привязаны к этому Windows-пользователю.' 'OK'}}catch{Toast 'Экспорт' $_.Exception.Message 'ERROR'}})
$aImport.Add_Click({try{$d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='CyberCroc accounts (*.json)|*.json';if($d.ShowDialog() -eq 'OK'){$x=@(Get-Content $d.FileName -Raw -Encoding UTF8|ConvertFrom-Json);if($x.Count -gt 0){Save-CcAccounts $x|Out-Null;Refresh-Accounts;Toast 'Импорт' 'JSON импортирован' 'OK'}}}catch{Toast 'Импорт' $_.Exception.Message 'ERROR'}})


$app=New-Tab 'Приложения'
$appSearch=New-Object Windows.Forms.TextBox;$appSearch.Location=New-Object Drawing.Point(15,15);$appSearch.Size=New-Object Drawing.Size(350,30);Style-Control $appSearch;$app.Controls.Add($appSearch)
$appList=New-Object Windows.Forms.ListView;$appList.View='Details';$appList.FullRowSelect=$true;$appList.Location=New-Object Drawing.Point(15,55);$appList.Size=New-Object Drawing.Size(900,520);Style-Control $appList
foreach($h in @('Название','Источник','Тип','Установлено','Действие')){$appList.Columns.Add($h,170)|Out-Null};$app.Controls.Add($appList)
$appRun=Btn 'Проверить программы' 940 55 190;$appInstall=Btn 'Установить / обновить' 940 105 190;$app.Controls.Add($appRun);$app.Controls.Add($appInstall)
function Run-AppTool([bool]$InstallMode){
    try{$args=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $Tools 'Apps.ps1'));if($InstallMode){$args+=@('-Install','-Update')};$p=Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden -Wait -PassThru;Toast 'Приложения' "Завершено, код $($p.ExitCode)" $(if($p.ExitCode-eq 0){'OK'}else{'ERROR'})}catch{Write-CcError -FunctionName 'Run-AppTool' -Exception $_.Exception}}
$appRun.Add_Click({$progress.Visible=$true;$progress.Style='Marquee';Run-AppTool $false;$progress.Visible=$false});$appInstall.Add_Click({$progress.Visible=$true;$progress.Style='Marquee';Run-AppTool $true;$progress.Visible=$false})

$backup=New-Tab 'Бэкап';$backup.Controls.Add((Lbl 'Резервное копирование' 20 20 300));$backupBtn=Btn 'Запустить бэкап' 20 60 180;$backup.Controls.Add($backupBtn)
$cleanup=New-Tab 'Очистка';$cleanup.Controls.Add((Lbl 'Очистка ПК' 20 20 300));$cleanupBtn=Btn 'Запустить очистку' 20 60 180;$cleanup.Controls.Add($cleanupBtn)

function Run-HiddenCmd([string]$Name){try{$path=Join-Path $Root $Name;if(-not(Test-Path $path)){throw "File not found: $path"};$p=Start-Process cmd.exe -ArgumentList @('/d','/c','"'+$path+'"') -WindowStyle Hidden -Wait -PassThru;Toast 'CyberCroc' "$Name завершён, код $($p.ExitCode)" $(if($p.ExitCode-eq 0){'OK'}else{'ERROR'})}catch{Write-CcError -FunctionName 'Run-HiddenCmd' -Exception $_.Exception;Toast 'Ошибка' $_.Exception.Message 'ERROR'}}

$backupBtn.Add_Click({Run-HiddenCmd 'Backup.cmd'});$cleanupBtn.Add_Click({Run-HiddenCmd 'Cleanup.cmd'})
$logs=New-Tab 'Логи'
$logText=New-Object Windows.Forms.TextBox;$logText.Multiline=$true;$logText.ReadOnly=$true;$logText.ScrollBars='Both';$logText.Dock='Fill';$logText.Font=New-Object Drawing.Font('Consolas',9);Style-Control $logText;$logs.Controls.Add($logText)
$logBtn=Btn 'Обновить' 15 15;$logs.Controls.Add($logBtn)
function Refresh-Logs{try{$p=Join-Path $Root 'logs\CyberCroc.log';$e=Join-Path $Root 'logs\errors.log';$s='';if(Test-Path $p){$s+=Get-Content $p -Raw};if(Test-Path $e){$s+=[Environment]::NewLine+'===== ERRORS ====='+[Environment]::NewLine+(Get-Content $e -Raw)};$logText.Text=$s}catch{}};$logBtn.Add_Click({Refresh-Logs})

$settings=New-Tab 'Настройки'
$settings.Controls.Add((Lbl 'Тема' 20 25 120));$theme=New-Object Windows.Forms.ComboBox;$theme.Location=New-Object Drawing.Point(150,22);$theme.Size=New-Object Drawing.Size(220,30);$theme.Items.AddRange(@('dark','neon','light'));$theme.SelectedItem=$ThemeName;Style-Control $theme;$settings.Controls.Add($theme)
$settings.Controls.Add((Lbl 'SMB update' 20 75 120));$share=New-Object Windows.Forms.TextBox;$share.Location=New-Object Drawing.Point(150,72);$share.Size=New-Object Drawing.Size(500,30);$share.Text=$cfg['UPDATE_SHARE'];Style-Control $share;$settings.Controls.Add($share)
$save=Btn 'Сохранить настройки' 150 125 200;$update=Btn 'Проверить обновления сейчас' 370 125 240;$settings.Controls.Add($save);$settings.Controls.Add($update)
$save.Add_Click({try{Set-Theme $theme.Text;$cfg['THEME']=$theme.Text;$cfg['UPDATE_SHARE']=$share.Text;$lines=@();foreach($k in $cfg.Keys){$lines+=($k+'='+$cfg[$k])};Set-Content (Join-Path $Root 'config.ini') ($lines -join [Environment]::NewLine) -Encoding UTF8;Toast 'Настройки' 'Сохранено' 'OK'}catch{Write-CcError -FunctionName 'SaveSettings' -Exception $_.Exception}})
$update.Add_Click({try{$u=Join-Path $Tools 'Updater.ps1';$args=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$u,'-Check','-Source',$share.Text);$p=Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden -Wait -PassThru;Toast 'Обновление' "Проверка завершена, код $($p.ExitCode)" 'INFO'}catch{Toast 'Обновление' $_.Exception.Message 'ERROR'}})

$timer=New-Object Windows.Forms.Timer;$timer.Interval=1000;$timer.Add_Tick({$clock.Text=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')});$timer.Start()
$timer2=New-Object Windows.Forms.Timer;$timer2.Interval=3600000;$timer2.Add_Tick({try{foreach($a in @(Get-CcAccounts)){Test-CcAccount $a $cfg|Out-Null};Save-CcAccounts @(Get-CcAccounts)|Out-Null;$share=[string]$cfg['UPDATE_SHARE'];if($share){Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $Tools 'Updater.ps1'),'-Apply','-Source',$share,'-WaitPid',$PID) -WindowStyle Hidden|Out-Null}}catch{Write-CcError -FunctionName 'HourlyTimer' -Exception $_.Exception}});$timer2.Start()
Refresh-Home;Load-Games;Refresh-Accounts;Refresh-Logs
$form.Add_FormClosing({Write-CcLog 'GUI closed' 'INFO' 'FormClosing'})
[void]$form.ShowDialog()
