<#
CyberCroc watchdog for kiosk/client PCs.
Checks a PID + heartbeat pair and restarts the GUI when it disappears.
#>
[CmdletBinding()]
param(
    [string]$Root = $PSScriptRoot,
    [int]$IntervalSec = 1,
    [int]$GraceSec = 3
)
$ErrorActionPreference='SilentlyContinue'
$Runtime=Join-Path $Root 'runtime'
$PidFile=Join-Path $Runtime 'cybercroc.pid'
$Heartbeat=Join-Path $Runtime 'heartbeat.txt'
$Log=Join-Path $Root 'logs\errors.log'
$Launcher=Join-Path $Root 'CyberCroc.ps1'
if(-not(Test-Path -LiteralPath $Runtime)){New-Item -ItemType Directory -Path $Runtime -Force|Out-Null}
$boot=(Get-Date).ToUniversalTime()

function Write-WatchdogLog([string]$Text){try{Add-Content -LiteralPath (Join-Path $Root 'logs\launcher.log') -Value ("[{0}] [WATCHDOG] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),($Text -replace '[\r\n]+',' ')) -Encoding UTF8}catch{}}
function Get-GuiProcess([int]$Pid){
    if($Pid -le 0){return $null}
    try{
        $p=Get-CimInstance Win32_Process -Filter "ProcessId=$Pid" -ErrorAction Stop
        if($p -and [string]$p.CommandLine -match '(?i)CyberCroc\.ps1'){return $p}
    }catch{}
    return $null
}
function Start-Gui {
    try{
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $ps -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',$Launcher) -WorkingDirectory $Root -WindowStyle Hidden|Out-Null
        Write-WatchdogLog 'GUI restarted.'
    }catch{Write-WatchdogLog "GUI restart failed: $($_.Exception.Message)"}
}
Write-WatchdogLog 'Watchdog started.'
while($true){
    try{
        # Do not use the variable name $PID here: PowerShell reserves $PID as a read-only automatic variable.
        $processId=0
        if(Test-Path -LiteralPath $PidFile){try{$processId=[int](Get-Content -LiteralPath $PidFile -Raw).Trim()}catch{$processId=0}}
        $proc=Get-GuiProcess $processId
        $heartbeatOk=$false
        if(Test-Path -LiteralPath $Heartbeat){
            $age=((Get-Date).ToUniversalTime()-(Get-Item -LiteralPath $Heartbeat).LastWriteTimeUtc).TotalSeconds
            $heartbeatOk=($age -le 3.5)
        }
        $withinGrace=(((Get-Date).ToUniversalTime())-$boot).TotalSeconds -lt $GraceSec
        if(-not $withinGrace -and (-not $proc -or -not $heartbeatOk)){
            Start-Gui
            Start-Sleep -Seconds 3
        }
    }catch{Write-WatchdogLog "Watchdog loop error: $($_.Exception.Message)"}
    Start-Sleep -Seconds $IntervalSec
}
