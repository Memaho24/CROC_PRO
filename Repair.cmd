@echo off
setlocal EnableExtensions
cd /d "%~dp0"

echo ==========================================
echo CyberCroc - repair/synchronize application
echo ==========================================
echo.
echo Updating program files from branch cybercroc2-refactor.
echo Local config, accounts, games and logs will be preserved.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$root=(Get-Location).Path;" ^
  "$url='https://github.com/Memaho24/CROC_PRO/archive/refs/heads/cybercroc2-refactor.zip';" ^
  "$tmp=Join-Path $env:TEMP ('CyberCrocRepair_'+[guid]::NewGuid().ToString('N'));" ^
  "New-Item -ItemType Directory -Path $tmp -Force | Out-Null;" ^
  "$zip=Join-Path $tmp 'croc.zip';" ^
  "try {" ^
    "Write-Host 'Downloading current CyberCroc files...';" ^
    "Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 60;" ^
    "Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force;" ^
    "$src=(Get-ChildItem -LiteralPath $tmp -Directory | Where-Object { $_.Name -like 'CROC_PRO-*' } | Select-Object -First 1).FullName;" ^
    "if(-not $src){throw 'Extracted CyberCroc directory not found.'};" ^
    "Write-Host 'Synchronizing program files...';" ^
    "$args=@($src,$root,'/E','/R:2','/W:1','/NFL','/NDL','/NP','/NJH','/NJS','/XD',(Join-Path $root 'logs'),(Join-Path $root 'BACKUP'),'/XF','config.ini','accounts.json','games.txt','steam_path.txt');" ^
    "$p=Start-Process -FilePath 'robocopy.exe' -ArgumentList $args -Wait -PassThru -NoNewWindow;" ^
    "if($p.ExitCode -ge 8){throw ('Robocopy failed with code '+$p.ExitCode)};" ^
    "Write-Host 'Repair completed successfully.';" ^
  "} catch {" ^
    "Write-Host ('ERROR: '+$_.Exception.Message) -ForegroundColor Red;" ^
    "exit 1" ^
  "} finally {" ^
    "Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue" ^
  "}"
if errorlevel 1 (
  echo.
  echo Repair failed. Check the message above.
  pause
  exit /b 1
)

echo.
echo CyberCroc files are synchronized.
echo Start Master.cmd now.
pause
exit /b 0
