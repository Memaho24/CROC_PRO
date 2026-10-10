[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ScriptPath)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $ScriptPath
$logDir = Join-Path $root 'logs'
try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch {}
$runnerLog = Join-Path $logDir 'launcher-runner.log'
$outFile = Join-Path $logDir 'cybercroc-stdout.log'
$errFile = Join-Path $logDir 'cybercroc-stderr.log'

function Write-RunnerLog([string]$Message) {
    try { Add-Content -LiteralPath $runnerLog -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8 } catch {}
}
try {
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        Write-RunnerLog ("ERROR: CyberCroc.ps1 not found: " + $ScriptPath)
        exit 20
    }
    $resolvedScript = (Resolve-Path -LiteralPath $ScriptPath -ErrorAction Stop).Path
    $info = Get-Item -LiteralPath $resolvedScript -ErrorAction Stop
    $hash = (Get-FileHash -LiteralPath $resolvedScript -Algorithm SHA256).Hash.ToUpperInvariant()
    Write-RunnerLog ("Actual file: " + $resolvedScript)
    Write-RunnerLog ("Size: " + $info.Length + " bytes")
    Write-RunnerLog ("Modified: " + $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-RunnerLog ("SHA256: " + $hash)

    # Do not compare a file SHA256 with a Git blob SHA: they use different algorithms/formats.
    # Syntax validation provides a useful local safety check without blocking legitimate edits.
    Write-RunnerLog "Validating PowerShell syntax..."
    $files = @($resolvedScript)
    $toolsDir = Join-Path (Split-Path -Parent $resolvedScript) 'tools'
    if (Test-Path -LiteralPath $toolsDir -PathType Container) {
        $files += @(Get-ChildItem -LiteralPath $toolsDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -ExpandProperty FullName)
    }
    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Write-RunnerLog ("SYNTAX ERROR in " + $file)
            $lines = @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)
            foreach ($pe in $parseErrors) {
                Write-RunnerLog ("Line " + $pe.Extent.StartLineNumber + ", column " + $pe.Extent.StartColumnNumber + ": " + $pe.Message)
                $n = [int]$pe.Extent.StartLineNumber
                $from = [Math]::Max(1, $n - 2)
                $to = [Math]::Min($lines.Count, $n + 2)
                for ($i = $from; $i -le $to; $i++) { Write-RunnerLog (("{0,5}: {1}" -f $i, $lines[$i-1])) }
            }
            exit 10
        }
    }
    Write-RunnerLog ("Syntax validation OK (" + $files.Count + " files)")
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',$resolvedScript)
    Write-RunnerLog ("Starting GUI: " + $resolvedScript)
    $child = Start-Process -FilePath $psExe -ArgumentList $args -WorkingDirectory (Split-Path -Parent $resolvedScript) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (Test-Path -LiteralPath $outFile) {
        foreach ($line in @(Get-Content -LiteralPath $outFile -ErrorAction SilentlyContinue)) { if ($line) { Write-RunnerLog ("STDOUT: " + $line) } }
    }
    if (Test-Path -LiteralPath $errFile) {
        foreach ($line in @(Get-Content -LiteralPath $errFile -ErrorAction SilentlyContinue)) { if ($line) { Write-RunnerLog ("STDERR: " + $line) } }
    }
    Write-RunnerLog ("Child exit code: " + $child.ExitCode)
    exit $child.ExitCode
}
catch {
    Write-RunnerLog ("FATAL: " + $_.Exception.GetType().FullName + ": " + $_.Exception.Message)
    Write-RunnerLog ("Position: " + $_.InvocationInfo.PositionMessage)
    Write-RunnerLog ("Stack: " + $_.ScriptStackTrace)
    exit 1
}