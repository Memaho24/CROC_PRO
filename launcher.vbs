Option Explicit
Dim shell, fso, root, ps1
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = fso.BuildPath(root, "CyberCroc.ps1")
If Not fso.FileExists(ps1) Then
    MsgBox "CyberCroc.ps1 not found: " & ps1, 16, "CyberCroc"
    WScript.Quit 1
End If
shell.Run "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, False
