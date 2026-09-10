' DiskReport.vbs
' UNC-safe launcher — does not use CMD, so no UNC warning.
Option Explicit
Dim fso, sh, here, ps1, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
ps1  = here & "\DiskReport.ps1"
If Not fso.FileExists(ps1) Then
  MsgBox "DiskReport.ps1 not found:" & vbCrLf & ps1, 16, "Disk Report"
  WScript.Quit 1
End If
cmd = "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"
sh.Run cmd, 1, True