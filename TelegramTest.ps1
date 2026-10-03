# TelegramTest.ps1 - проверка отправки уведомления в Telegram (пункт [B] в Master.cmd)
$notify = Join-Path $PSScriptRoot 'Notify.ps1'
if (-not (Test-Path -LiteralPath $notify)) { Write-Host '[ОШИБКА] Notify.ps1 не найден' -ForegroundColor Red; exit 1 }
Write-Host 'Отправляю тестовое сообщение в Telegram...' -ForegroundColor Cyan
& $notify -Message ("Тест уведомлений CyberCroc`n" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$rc = $LASTEXITCODE
if ($rc -eq 0) { Write-Host '[OK] Проверьте чат.' -ForegroundColor Green }
else { Write-Host '[ОШИБКА] Не отправлено. Проверьте BOT_TOKEN, CHAT_ID, TG_PROXY_URL / PROXY в config.ini.' -ForegroundColor Red }
exit $rc
