@echo off
chcp 65001 >nul
set "F=%~dp0Master.cmd"
echo Fixing: %F%
if not exist "%F%" (
    echo [ERR] Master.cmd не найден рядом с Fix.cmd
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%F%';" ^
  "$b=[IO.File]::ReadAllBytes($p);" ^
  "$t=[Text.Encoding]::UTF8.GetString($b);" ^
  "$t=$t -replace [char]0xFEFF,'';" ^
  "$t=$t -replace ([char]13+[char]10),[char]10;" ^
  "$t=$t -replace [char]13,[char]10;" ^
  "$t=$t -replace [char]10,([char]13+[char]10);" ^
  "[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding $false));" ^
  "$c=[IO.File]::ReadAllBytes($p); $cr=0; $lf=0;" ^
  "foreach($x in $c){ if($x -eq 13){$cr++}; if($x -eq 10){$lf++} };" ^
  "Write-Host ('CR='+$cr+'  LF='+$lf)"
echo.
echo Если CR=LF и CR больше 0 - ОК. Запускай Master.cmd.
pause