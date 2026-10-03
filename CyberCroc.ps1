<#
  CyberCroc.ps1 - графическая оболочка (мастер-приложение) для ПК клуба.
  Запускает те же инструменты из папки tools\, что и Master.cmd, и даёт
  редактор конфигов и просмотр журналов. PowerShell 5.1, Windows 10/11.
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Root     = $PSScriptRoot
$ToolsDir = Join-Path $Root 'tools'
$LogDir   = Join-Path $Root 'logs'
$Version  = '0.3.2'

# ---- права администратора ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"{0}"' -f $PSCommandPath))
        exit
    } catch { }   # пользователь отказал в UAC - работаем без прав администратора
}

function Show-Msg([string]$Text, [string]$Title = 'CyberCroc') {
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title)
}

# ---- запуск инструмента в отдельном окне ----
function Run-Tool([string]$File, [string[]]$ToolArgs = @()) {
    $path = Join-Path $ToolsDir $File
    if (-not (Test-Path -LiteralPath $path)) { Show-Msg ("Не найден файл:`n" + $path); return }
    try {
        if ($File -like '*.ps1') {
            $a = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',('"{0}"' -f $path)) + $ToolArgs
            Start-Process -FilePath 'powershell.exe' -ArgumentList $a -WorkingDirectory $Root
        } else {
            $cmdLine = '/c ""{0}" {1} & pause"' -f $path, ($ToolArgs -join ' ')
            Start-Process -FilePath 'cmd.exe' -ArgumentList $cmdLine -WorkingDirectory $Root
        }
    } catch { Show-Msg ("Не удалось запустить $File`n" + $_.Exception.Message) }
}

# ---- описание кнопок: группа -> список ----
$Groups = [ordered]@{
    'Развёртывание и система' = @(
        @{ T = 'Развёртывание ПК';       F = 'Deploy.cmd';          A = @() },
        @{ T = 'Настройки Windows';      F = 'WindowsTweaks.cmd';   A = @() },
        @{ T = 'Диагностика ПК';         F = 'Diagnostics.ps1';     A = @() },
        @{ T = 'Диагностика + починка';  F = 'Diagnostics.ps1';     A = @('-Repair') },
        @{ T = 'Очистка';                F = 'Cleanup.cmd';         A = @() },
        @{ T = 'Резервная копия';        F = 'Backup.cmd';          A = @() },
        @{ T = 'Сброс ПК';               F = 'FactoryReset.ps1';    A = @('-DryRun') }
    )
    'Игры и программы' = @(
        @{ T = 'Проверка игр';               F = 'Games.cmd';            A = @() },
        @{ T = 'Игры: проверка и установка'; F = 'Games.cmd';            A = @('auto') },
        @{ T = 'Программы: проверка';        F = 'Apps.ps1';             A = @() },
        @{ T = 'Программы: установка';       F = 'Apps.ps1';             A = @('-Install','-Update') },
        @{ T = 'Офисные программы';          F = 'OfficePrograms.ps1';   A = @('-Install') }
    )
    'Zapret и уведомления' = @(
        @{ T = 'Zapret: статус';        F = 'Zapret.ps1'; A = @('status') },
        @{ T = 'Zapret: установить';    F = 'Zapret.ps1'; A = @('install') },
        @{ T = 'Zapret: запустить';     F = 'Zapret.ps1'; A = @('start') },
        @{ T = 'Zapret: остановить';    F = 'Zapret.ps1'; A = @('stop') },
        @{ T = 'Zapret: автозапуск вкл'; F = 'Zapret.ps1'; A = @('autostart-on') },
        @{ T = 'Тест Telegram';         F = 'TelegramTest.ps1'; A = @() }
    )
}

# ---- форма ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "CyberCroc $Version - управление клубом"
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(980, 680)
$form.MinimumSize = New-Object System.Drawing.Size(820, 560)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(238, 242, 238)

$status = New-Object System.Windows.Forms.Label
$status.Dock = 'Top'
$status.Height = 56
$status.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 4)
$status.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($status)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)
$tabs.BringToFront()

function Update-Status {
    $cfg  = Test-Path -LiteralPath (Join-Path $Root 'config.ini')
    $gm   = Test-Path -LiteralPath (Join-Path $Root 'games.txt')
    $adm  = if ($isAdmin) { 'да' } else { 'НЕТ (часть функций не заработает)' }
    $c1   = if ($cfg) { 'есть' } else { 'НЕТ (вкладка «Файлы»)' }
    $c2   = if ($gm)  { 'есть' } else { 'НЕТ' }
    $status.Text = ("ПК: {0}    Администратор: {1}`r`nconfig.ini: {2}    games.txt: {3}    Папка: {4}" -f $env:COMPUTERNAME, $adm, $c1, $c2, $Root)
}

# ===== вкладка 1: действия =====
$tabActions = New-Object System.Windows.Forms.TabPage
$tabActions.Text = 'Действия'
$tabs.TabPages.Add($tabActions)

$scroll = New-Object System.Windows.Forms.FlowLayoutPanel
$scroll.Dock = 'Fill'
$scroll.AutoScroll = $true
$scroll.FlowDirection = 'TopDown'
$scroll.WrapContents = $false
$scroll.Padding = New-Object System.Windows.Forms.Padding(10)
$tabActions.Controls.Add($scroll)

$onToolClick = {
    param($sender, $e)
    $item = $sender.Tag
    Run-Tool $item.F ([string[]]$item.A)
}

foreach ($g in $Groups.Keys) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $g
    $lbl.AutoSize = $true
    $lbl.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 4)
    $scroll.Controls.Add($lbl)

    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.AutoSize = $true
    $row.WrapContents = $true
    $row.Width = 900
    foreach ($item in $Groups[$g]) {
        $b = New-Object System.Windows.Forms.Button
        $b.Text = $item.T
        $b.Tag = $item
        $b.Size = New-Object System.Drawing.Size(210, 42)
        $b.FlatStyle = 'Flat'
        $b.BackColor = [System.Drawing.Color]::FromArgb(47, 125, 91)
        $b.ForeColor = [System.Drawing.Color]::White
        $b.FlatAppearance.BorderSize = 0
        $b.Add_Click($onToolClick)
        $row.Controls.Add($b)
    }
    $scroll.Controls.Add($row)
}

# ===== вкладка 2: файлы =====
$tabFiles = New-Object System.Windows.Forms.TabPage
$tabFiles.Text = 'Файлы'
$tabs.TabPages.Add($tabFiles)

$fileList = @('config.ini','games.txt','apps.txt','office.txt','steam_path.txt')
$cbFile = New-Object System.Windows.Forms.ComboBox
$cbFile.DropDownStyle = 'DropDownList'
$cbFile.Location = New-Object System.Drawing.Point(10, 10)
$cbFile.Width = 220
[void]$cbFile.Items.AddRange($fileList)
$tabFiles.Controls.Add($cbFile)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = 'Сохранить'
$btnSave.Location = New-Object System.Drawing.Point(245, 8)
$btnSave.Size = New-Object System.Drawing.Size(120, 30)
$tabFiles.Controls.Add($btnSave)

$txtFile = New-Object System.Windows.Forms.TextBox
$txtFile.Multiline = $true
$txtFile.ScrollBars = 'Both'
$txtFile.WordWrap = $false
$txtFile.AcceptsReturn = $true
$txtFile.AcceptsTab = $true
$txtFile.Font = New-Object System.Drawing.Font('Consolas', 10)
$txtFile.Location = New-Object System.Drawing.Point(10, 48)
$txtFile.Size = New-Object System.Drawing.Size(930, 480)
$txtFile.Anchor = 'Top,Bottom,Left,Right'
$tabFiles.Controls.Add($txtFile)

function Load-EditorFile {
    $name = [string]$cbFile.SelectedItem
    if (-not $name) { return }
    $path = Join-Path $Root $name
    if (Test-Path -LiteralPath $path) {
        $txtFile.Text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    } else {
        $ex = Join-Path $Root ($name -replace '\.(\w+)$', '.example.$1')
        if (Test-Path -LiteralPath $ex) {
            $txtFile.Text = [IO.File]::ReadAllText($ex, [Text.Encoding]::UTF8)
            Show-Msg "$name ещё не создан. Показан пример - нажмите «Сохранить», чтобы создать файл."
        } else { $txtFile.Text = '' }
    }
}
$cbFile.Add_SelectedIndexChanged({ Load-EditorFile })
$btnSave.Add_Click({
    $name = [string]$cbFile.SelectedItem
    if (-not $name) { return }
    $path = Join-Path $Root $name
    $text = ($txtFile.Text -replace "`r?`n", "`r`n")
    # UTF-8 БЕЗ BOM: иначе cmd-скрипты теряют первую строку/ключ
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
    Update-Status
    Show-Msg "Сохранено: $name"
})
$cbFile.SelectedIndex = 0

# ===== вкладка 3: журнал =====
$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = 'Журнал'
$tabs.TabPages.Add($tabLog)

$cbLog = New-Object System.Windows.Forms.ComboBox
$cbLog.DropDownStyle = 'DropDownList'
$cbLog.Location = New-Object System.Drawing.Point(10, 10)
$cbLog.Width = 260
$tabLog.Controls.Add($cbLog)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Обновить'
$btnRefresh.Location = New-Object System.Drawing.Point(285, 8)
$btnRefresh.Size = New-Object System.Drawing.Size(110, 30)
$tabLog.Controls.Add($btnRefresh)

$btnFolder = New-Object System.Windows.Forms.Button
$btnFolder.Text = 'Открыть папку'
$btnFolder.Location = New-Object System.Drawing.Point(405, 8)
$btnFolder.Size = New-Object System.Drawing.Size(130, 30)
$tabLog.Controls.Add($btnFolder)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Both'
$txtLog.WordWrap = $false
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 10)
$txtLog.Location = New-Object System.Drawing.Point(10, 48)
$txtLog.Size = New-Object System.Drawing.Size(930, 480)
$txtLog.Anchor = 'Top,Bottom,Left,Right'
$tabLog.Controls.Add($txtLog)

function Load-LogFile {
    $name = [string]$cbLog.SelectedItem
    if (-not $name) { $txtLog.Text = 'Журналов пока нет. Запустите любое действие.'; return }
    $path = Join-Path $LogDir $name
    try {
        # читаем с общим доступом, чтобы работало, пока инструмент пишет в файл
        $fs = New-Object IO.FileStream($path, 'Open', 'Read', 'ReadWrite')
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $all = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
        if ($all.Length -gt 200000) { $all = $all.Substring($all.Length - 200000) }
        $txtLog.Text = $all
        $txtLog.SelectionStart = $txtLog.Text.Length
        $txtLog.ScrollToCaret()
    } catch { $txtLog.Text = 'Не удалось прочитать журнал: ' + $_.Exception.Message }
}
function Refresh-LogList {
    $cbLog.Items.Clear()
    if (Test-Path -LiteralPath $LogDir) {
        Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.log','.txt' } |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { [void]$cbLog.Items.Add($_.Name) }
    }
    if ($cbLog.Items.Count -gt 0) { $cbLog.SelectedIndex = 0 } else { Load-LogFile }
}
$cbLog.Add_SelectedIndexChanged({ Load-LogFile })
$btnRefresh.Add_Click({ Refresh-LogList })
$btnFolder.Add_Click({
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList ('"{0}"' -f $LogDir)
})
$tabs.Add_SelectedIndexChanged({ if ($tabs.SelectedTab -eq $tabLog) { Refresh-LogList } })

Update-Status
[void]$form.ShowDialog()
