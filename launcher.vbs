Option Explicit

Dim shell, fso, root, ps1, logDir, logFile, psExe, cmd, rc, proc
Dim stdoutText, stderrText, errLog, errText, userMsg

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

root = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(root, "CyberCroc.ps1")
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
    Set h = fso.OpenTextFile(logFile, 8, True, -1)
    h.WriteLine "[" & Year(Now) & "-" & Right("0" & Month(Now),2) & "-" & Right("0" & Day(Now),2) & " " & _
        Right("0" & Hour(Now),2) & ":" & Right("0" & Minute(Now),2) & ":" & Right("0" & Second(Now),2) & "] " & message
    h.Close
    On Error GoTo 0
End Sub

LogLine "=== CyberCroc launcher started ==="
LogLine "Root: " & root

If Not fso.FileExists(ps1) Then
    LogLine "ERROR: CyberCroc.ps1 not found: " & ps1
    MsgBox "CyberCroc.ps1 не найден." & vbCrLf & vbCrLf & ps1 & vbCrLf & vbCrLf & _
           "Подробности: " & logFile, 16, "CyberCroc"
    WScript.Quit 1
End If


psExe = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"

If Not fso.FileExists(psExe) Then
    LogLine "ERROR: Windows PowerShell not found: " & psExe
    MsgBox "Windows PowerShell 5.1 не найден." & vbCrLf & vbCrLf & psExe, 16, "CyberCroc"
    WScript.Quit 2
End If

On Error Resume Next
shell.CurrentDirectory = root
If Err.Number <> 0 Then
    LogLine "WARNING: Could not set working directory: " & Err.Description
    Err.Clear
End If
On Error GoTo 0

LogLine "PowerShell: " & psExe
LogLine "Script: " & ps1

Dim q, psPath
q = Chr(34)
psPath = Replace(ps1, q, q & q)
cmd = q & psExe & q & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command " & _
      q & "try { & " & q & psPath & q & " } catch { Write-Error $_; exit 1 }" & q

LogLine "Starting PowerShell directly..."

On Error Resume Next
Set proc = shell.Exec(cmd)
If Err.Number <> 0 Then
    LogLine "ERROR: Failed to start PowerShell: " & Err.Description
    MsgBox "Не удалось запустить CyberCroc." & vbCrLf & vbCrLf & _
           Err.Description & vbCrLf & vbCrLf & "Лог: " & logFile, 16, "CyberCroc"
    WScript.Quit 3
End If
On Error GoTo 0

Do While proc.Status = 0
    WScript.Sleep 100
Loop

stdoutText = proc.StdOut.ReadAll
stderrText = proc.StdErr.ReadAll
rc = proc.ExitCode

If Len(stdoutText) > 0 Then LogLine "PowerShell stdout:" & vbCrLf & stdoutText
If Len(stderrText) > 0 Then LogLine "PowerShell stderr:" & vbCrLf & stderrText

LogLine "PowerShell exited with code: " & rc

If rc <> 0 Then
    errLog = fso.BuildPath(logDir, "errors.log")
    errText = ""

    If fso.FileExists(errLog) Then
        On Error Resume Next
        Dim ef, allErr
        Set ef = fso.OpenTextFile(errLog, 1, False, -1)
        allErr = ef.ReadAll
        ef.Close
        If Len(allErr) > 1800 Then
            errText = Right(allErr, 1800)
        Else
            errText = allErr
        End If
        On Error GoTo 0
    End If

    LogLine "Application error. errors.log tail:" & vbCrLf & errText
    userMsg = "CyberCroc завершился с ошибкой." & vbCrLf & vbCrLf & "Код: " & rc & vbCrLf & vbCrLf
    If Len(errText) > 0 Then userMsg = userMsg & "Последняя ошибка:" & vbCrLf & errText & vbCrLf & vbCrLf
    userMsg = userMsg & "Лог запуска: " & logFile & vbCrLf & "Лог ошибок: " & errLog
    MsgBox userMsg, 16, "CyberCroc"
    WScript.Quit rc
End If

LogLine "=== CyberCroc launcher finished normally ==="
WScript.Quit 0
