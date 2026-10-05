<# Applies reversible client-side Task Manager restriction for the kiosk Windows account. #>
[CmdletBinding()]
param([switch]$Disable)
$ErrorActionPreference='Stop'
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
if(-not(Test-Path $key)){New-Item -Path $key -Force|Out-Null}
if($Disable){New-ItemProperty -Path $key -Name DisableTaskMgr -PropertyType DWord -Value 1 -Force|Out-Null;Write-Host 'Task Manager disabled for current user.'}
else{New-ItemProperty -Path $key -Name DisableTaskMgr -PropertyType DWord -Value 0 -Force|Out-Null;Write-Host 'Task Manager restriction removed.'}
