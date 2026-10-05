Option Explicit

Dim shell, fso, root, ps1, runner, watchdog, logDir, logFile, psExe
Dim cmd, watchdogCmd, rc, ok

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(root, "CyberCroc.ps1")
runner = fso.BuildPath(root, "LauncherRunner.ps1")
watchdog = fso.BuildPath(root, "watchdog.ps1")
logDir = fso.BuildPath(root, "logs")
logFile = fso.BuildPath(logDir, "launcher.log")

If Not fso.FolderExists(logDir) Then
    On Error Resume Next
    fso.CreateFolder(logDir)
    On Error GoTo 0
End If

Sub LogLine(message)
    On Error Resume Next
    Dim h
    Set h = fso.OpenTextFile(logFile, 8, True, 0)
    h.WriteLine "[" & Year(Now) & "-" & Right("0" & Month(Now), 2) & "-" & Right("0" & Day(Now), 2) & " " & _
        Right("0" & Hour(Now), 2) & ":" & Right("0" & Minute(Now), 2) & ":" & Right("0" & Second(Now), 2) & "] " & message
    h.Close
    On Error GoTo 0
End Sub

Function QuoteArg(value)
    QuoteArg = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function

LogLine "=== CyberCroc launcher started ==="
LogLine "Root: " & root

If Not fso.FileExists(ps1) Then
    LogLine "ERROR: CyberCroc.ps1 not found: " & ps1
    MsgBox "CyberCroc.ps1 was not found." & vbCrLf & vbCrLf & ps1, 16, "CyberCroc"
    WScript.Quit 1
End If

If Not fso.FileExists(runner) Then
    LogLine "ERROR: LauncherRunner.ps1 not found: " & runner
    MsgBox "LauncherRunner.ps1 was not found." & vbCrLf & vbCrLf & runner, 16, "CyberCroc"
    WScript.Quit 2
End If

psExe = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

If fso.FileExists(watchdog) Then
    watchdogCmd = QuoteArg(psExe) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & _
                  QuoteArg(watchdog) & " -Root " & QuoteArg(root)
    On Error Resume Next
    shell.Run watchdogCmd, 0, False
    If Err.Number <> 0 Then
        LogLine "WARNING: watchdog start failed: " & Err.Description
        Err.Clear
    Else
        LogLine "Watchdog started."
    End If
    On Error GoTo 0
End If

On Error Resume Next
shell.CurrentDirectory = root
If Err.Number <> 0 Then
    LogLine "WARNING: working directory could not be set: " & Err.Description
    Err.Clear
End If
On Error GoTo 0

cmd = QuoteArg(psExe) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & _
      QuoteArg(runner) & " -ScriptPath " & QuoteArg(ps1)

LogLine "Starting LauncherRunner.ps1..."

On Error Resume Next
rc = shell.Run(cmd, 0, True)
If Err.Number <> 0 Then
    LogLine "ERROR: failed to start PowerShell: " & Err.Description
    MsgBox "CyberCroc could not be started." & vbCrLf & vbCrLf & Err.Description, 16, "CyberCroc"
    WScript.Quit 3
End If
On Error GoTo 0

LogLine "LauncherRunner exit code: " & rc

If rc <> 0 Then
    LogLine "=== CyberCroc launcher finished with error ==="
    MsgBox "CyberCroc stopped with an error." & vbCrLf & vbCrLf & _
           "Exit code: " & rc & vbCrLf & vbCrLf & _
           "Check logs\launcher.log and logs\errors.log", 16, "CyberCroc"
    WScript.Quit rc
End If

LogLine "=== CyberCroc launcher finished normally ==="
WScript.Quit 0
