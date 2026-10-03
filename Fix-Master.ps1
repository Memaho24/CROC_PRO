# Fix-Master.ps1 — нормализует переносы строк и кодировку Master.cmd
$ErrorActionPreference = "Stop"
$file = Join-Path $PSScriptRoot "Master.cmd"
if (-not (Test-Path $file)) {
    Write-Host "[ERR] Master.cmd не найден рядом со скриптом" -ForegroundColor Red
    Read-Host "Enter..."
    exit 1
}

# 1. Читаем как UTF-8 (без BOM), с fallback на 1251 если кракозябры
$bytes = [IO.File]::ReadAllBytes($file)
$utf8  = [Text.Encoding]::UTF8.GetString($bytes)
# Простая эвристика: если много '?' или замена U+FFFD — пробуем CP1251
$bad = ([regex]::Matches($utf8, [char]0xFFFD)).Count
if ($bad -gt 5) {
    $cp1251 = [Text.Encoding]::GetEncoding(1251)
    $text = $cp1251.GetString($bytes)
    Write-Host "[INFO] Прочитано как CP1251" -ForegroundColor Yellow
} else {
    # Убираем BOM если есть
    $text = $utf8.TrimStart([char]0xFEFF)
    Write-Host "[INFO] Прочитано как UTF-8" -ForegroundColor Yellow
}

# 2. Нормализуем переносы: любые -> LF -> CRLF
$text = $text -replace "`r`n", "`n"
$text = $text -replace "`r",   "`n"
$text = $text -replace "`n",   "`r`n"

# 3. Сохраняем UTF-8 БЕЗ BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($file, $text, $utf8NoBom)

# 4. Контроль
$check = [IO.File]::ReadAllBytes($file)
$cr = 0; $lf = 0
for ($i=0; $i -lt $check.Length; $i++) {
    if ($check[$i] -eq 13) { $cr++ }
    if ($check[$i] -eq 10) { $lf++ }
}
Write-Host ""
Write-Host "CR=$cr  LF=$lf" -ForegroundColor Cyan
if ($cr -eq $lf -and $cr -gt 0) {
    Write-Host "[OK] Переносы строк исправлены (CRLF)." -ForegroundColor Green
} else {
    Write-Host "[WARN] CR != LF — что-то не так." -ForegroundColor Red
}
Write-Host ""
Write-Host "Теперь запусти Master.cmd." -ForegroundColor Green
Read-Host "Enter..."