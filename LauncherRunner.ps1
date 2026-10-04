param([Parameter(Mandatory=$true)][string]$ScriptPath)
$ErrorActionPreference = 'Stop'
$outFile = Join-Path $env:TEMP ('CyberCroc_stdout_' + [guid]::NewGuid().ToString('N') + '.log')
$errFile = Join-Path $env:TEMP ('CyberCroc_stderr_' + [guid]::NewGuid().ToString('N') + '.log')
try {
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        Write-Error ("CyberCroc.ps1 not found: " + $ScriptPath)
        exit 20
    }

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = @(
        '-NoLogo'
        '-NoProfile'
        '-NonInteractive'
        '-ExecutionPolicy'
        'Bypass'
        '-STA'
        '-WindowStyle'
        'Hidden'
        '-File'
        $ScriptPath
    )

    Write-Output ("LauncherRunner: starting child PowerShell for " + $ScriptPath)
    $child = Start-Process -FilePath $psExe -ArgumentList $args -WorkingDirectory (Split-Path -Parent $ScriptPath) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile

    if (Test-Path -LiteralPath $outFile) {
        $out = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
        if ($out) { Write-Output $out }
    }
    if (Test-Path -LiteralPath $errFile) {
        $err = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        if ($err) { Write-Error $err }
    }

    Write-Output ("LauncherRunner: child exit code " + $child.ExitCode)
    exit $child.ExitCode
}
catch {
    Write-Error ("LauncherRunner fatal error: " + $_.Exception.GetType().FullName + ": " + $_.Exception.Message)
    Write-Error ("Position: " + $_.InvocationInfo.PositionMessage)
    Write-Error ("ScriptStack: " + $_.ScriptStackTrace)
    exit 1
}
finally {
    Remove-Item -LiteralPath $outFile,$errFile -Force -ErrorAction SilentlyContinue
}
