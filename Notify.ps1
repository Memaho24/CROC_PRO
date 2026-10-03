<#
  Notify.ps1 - отправка сообщений в Telegram.
  Поддерживает:
    - Прямое подключение к api.telegram.org
    - Через Google Apps Script proxy (TG_PROXY_URL в config.ini)
    - Через обычный HTTP/SOCKS5 прокси (PROXY в config.ini)
#>
param(
    [string]$Message,
    [string]$TextFile,
    [switch]$NoHeader
)

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$Root   = Split-Path -Parent $PSScriptRoot
$Config = Join-Path $Root 'config.ini'
if (-not (Test-Path -LiteralPath $Config)) { $Config = Join-Path $PSScriptRoot 'config.ini' }

$cfg = @{}
if (Test-Path -LiteralPath $Config) {
    foreach ($raw in Get-Content -LiteralPath $Config -Encoding UTF8) {
        $l = $raw.Trim()
        if (-not $l -or $l -match '^[#;\[]') { continue }
        $i = $l.IndexOf('=')
        if ($i -lt 1) { continue }
        $cfg[$l.Substring(0, $i).Trim().ToUpper()] = $l.Substring($i + 1).Trim()
    }
}

if ($cfg['NOTIFY_ENABLED'] -eq '0') { exit 0 }
if (-not $cfg['BOT_TOKEN']) { Write-Host '[Notify] BOT_TOKEN пустой'; exit 1 }
if (-not $cfg['CHAT_ID'])   { Write-Host '[Notify] CHAT_ID пустой';   exit 1 }

$timeout = 45
if ($cfg['HTTP_TIMEOUT'] -match '^\d+$') { $timeout = [int]$cfg['HTTP_TIMEOUT'] }

if ($TextFile) {
    if (-not (Test-Path -LiteralPath $TextFile)) { Write-Host "[Notify] Файл не найден: $TextFile"; exit 1 }
    $Message = Get-Content -LiteralPath $TextFile -Raw -Encoding UTF8
}
if (-not $Message) { $Message = 'Notification' }

if (-not $NoHeader) {
    $pc  = $env:COMPUTERNAME
    $hdr = "ПК $pc"
    if ($pc -match '(\d+)$') { $hdr += " (№$([int]$Matches[1]))" }
    $Message = "$hdr`n$Message"
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ---- разбиваем на 4000 символов (лимит TG) ----
$chunks = @()
for ($p = 0; $p -lt $Message.Length; $p += 4000) {
    $chunks += $Message.Substring($p, [Math]::Min(4000, $Message.Length - $p))
}

$proxyUrl   = $cfg['TG_PROXY_URL']
$directUri  = "https://api.telegram.org/bot$($cfg['BOT_TOKEN'])/sendMessage"
$useProxy   = $proxyUrl -and ($proxyUrl -match '^https?://')
$httpProxy  = $cfg['PROXY']

$failed = $false
foreach ($chunk in $chunks) {
    $payloadObj = @{ chat_id = $cfg['CHAT_ID']; text = $chunk; disable_web_page_preview = $true }
    $sent  = $false
    $err   = ''

    for ($try = 1; $try -le 3 -and -not $sent; $try++) {
        try {
            if ($useProxy) {
                # ---- через Google Apps Script ----
                $gasBody = @{
                    token   = $cfg['BOT_TOKEN']
                    method  = 'sendMessage'
                    payload = $payloadObj
                } | ConvertTo-Json -Depth 6 -Compress

                $resp = Invoke-RestMethod -Uri $proxyUrl -Method Post `
                        -ContentType 'application/json' `
                        -Body ([Text.Encoding]::UTF8.GetBytes($gasBody)) `
                        -TimeoutSec $timeout
                # GAS возвращает {ok,status,body}, где body — строка JSON от Telegram
                if ($resp.ok -and $resp.body) {
                    $inner = $resp.body | ConvertFrom-Json
                    if ($inner.ok) { $sent = $true } else { $err = "Telegram: $($inner.description)" }
                } else {
                    $err = "GAS: $($resp.error)"
                }
            } else {
                # ---- напрямую ----
                $json  = $payloadObj | ConvertTo-Json -Compress
                $bytes = [Text.Encoding]::UTF8.GetBytes($json)
                $opts  = @{}
                if ($httpProxy) { $opts['Proxy'] = $httpProxy }

                $r = Invoke-RestMethod -Uri $directUri -Method Post `
                     -ContentType 'application/json; charset=utf-8' `
                     -Body $bytes -TimeoutSec $timeout @opts
                if ($r.ok) { $sent = $true } else { $err = 'Telegram вернул ok=false' }
            }
        } catch {
            $err = $_.Exception.Message
        }
        if (-not $sent) { Start-Sleep -Seconds 3 }
    }

    if (-not $sent) { $failed = $true; Write-Host "[Notify] ОШИБКА: $err" }
}

if ($failed) { exit 1 }
Write-Host '[Notify] Отправлено'
exit 0