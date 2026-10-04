param([Parameter(Mandatory=$true)][string]$ScriptPath)
$ErrorActionPreference = 'Stop'
try {
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        Write-Error ("CyberCroc.ps1 not found: " + $ScriptPath)
        exit 20
    }
    Write-Output ("LauncherRunner: starting " + $ScriptPath)
    & $ScriptPath
    if ($LASTEXITCODE -is [int] -and $LASTEXITCODE -ne 0) {
        Write-Error ("CyberCroc.ps1 returned exit code " + $LASTEXITCODE)
        exit $LASTEXITCODE
    }
    exit 0
}
catch {
    Write-Error ("CyberCroc fatal error: " + $_.Exception.GetType().FullName + ": " + $_.Exception.Message)
    Write-Error ("Position: " + $_.InvocationInfo.PositionMessage)
    Write-Error ("ScriptStack: " + $_.ScriptStackTrace)
    exit 1
}
