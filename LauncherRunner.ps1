param([Parameter(Mandatory=$true)][string]$ScriptPath)
$ErrorActionPreference = 'Stop'
$ExpectedCyberCrocSha256 = '29C03AC227964DAB7FD16C7FE25B3B410F1009C5'
$outFile = Join-Path $env:TEMP ('CyberCroc_stdout_' + [guid]::NewGuid().ToString('N') + '.log')
$errFile = Join-Path $env:TEMP ('CyberCroc_stderr_' + [guid]::NewGuid().ToString('N') + '.log')
try {
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        Write-Error ("CyberCroc.ps1 not found: " + $ScriptPath)
        exit 20
    }
    $resolvedScript = (Resolve-Path -LiteralPath $ScriptPath -ErrorAction Stop).Path
    $info = Get-Item -LiteralPath $resolvedScript -ErrorAction Stop
    $hash = (Get-FileHash -LiteralPath $resolvedScript -Algorithm SHA256).Hash.ToUpperInvariant()
    Write-Output ("LauncherRunner: actual file = " + $resolvedScript)
    Write-Output ("LauncherRunner: size = " + $info.Length + " bytes")
    Write-Output ("LauncherRunner: modified = " + $info.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-Output ("LauncherRunner: SHA256 = " + $hash)
    Write-Output ("LauncherRunner: expected SHA256 = " + $ExpectedCyberCrocSha256)
    if ($hash -ne $ExpectedCyberCrocSha256) {
        Write-Error "LOCAL FILE MISMATCH: CyberCroc.ps1 on disk is not the Pizda version expected by this launcher. No files were modified."
        exit 11
    }

    Write-Output "LauncherRunner: validating PowerShell syntax..."
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
            Write-Output ("LauncherRunner: syntax errors in " + $file)
            foreach ($pe in $parseErrors) {
                Write-Output ("SYNTAX ERROR: line " + $pe.Extent.StartLineNumber + ", column " + $pe.Extent.StartColumnNumber + " - " + $pe.Message)
            }
            $lines = @(Get-Content -LiteralPath $file -ErrorAction SilentlyContinue)
            foreach ($pe in @($parseErrors | Select-Object -First 3)) {
                $n = [int]$pe.Extent.StartLineNumber
                $from = [Math]::Max(1, $n - 2)
                $to = [Math]::Min($lines.Count, $n + 2)
                if ($to -ge $from) {
                    Write-Output ("--- context " + $file + ":" + $from + "-" + $to + " ---")
                    for ($i = $from; $i -le $to; $i++) {
                        Write-Output (("{0,5}: {1}" -f $i, $lines[$i-1]))
                    }
                }
            }
            exit 10
        }
    }
    Write-Output ("LauncherRunner: syntax validation OK (" + $files.Count + " files)")
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden','-File',$resolvedScript)
    Write-Output ("LauncherRunner: starting child PowerShell for " + $resolvedScript)
    $child = Start-Process -FilePath $psExe -ArgumentList $args -WorkingDirectory (Split-Path -Parent $resolvedScript) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
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
