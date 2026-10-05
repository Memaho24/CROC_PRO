<# CyberCroc Bar - Google Sheets menu + LAN order/stock queue. #>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')
function Get-CcBarConfig { $cfg=Get-CcConfig;[pscustomobject]@{SheetId=if($cfg['BAR_SHEET_ID']){[string]$cfg['BAR_SHEET_ID']}else{'1l-p_ck7hS1PmrqJDYAQcni6_boxFK3Pl5BFGqKoMRWM'};Share=[string]$cfg['BAR_SHARE'];Cache=Join-Path $script:CcRoot 'bar-menu.json';Orders=if($cfg['BAR_SHARE']){Join-Path $cfg['BAR_SHARE'] 'bar-orders.json'}else{Join-Path $script:CcRoot 'bar-orders.json'};Stock=if($cfg['BAR_SHARE']){Join-Path $cfg['BAR_SHARE'] 'bar-stock.json'}else{Join-Path $script:CcRoot 'bar-stock.json'};Balances=if($cfg['BAR_SHARE']){Join-Path $cfg['BAR_SHARE'] 'bar-balances.json'}else{Join-Path $script:CcRoot 'bar-balances.json'}} }
function Resolve-CcBarSheetUrl([string]$Url) {
    try {
        if([string]::IsNullOrWhiteSpace($Url)){return ''}
        $u=$Url.Trim()
        if($u -match 'export\\?format=csv' -or $u -match 'gviz/tq'){return $u}
        if($u -match 'docs\\.google\\.com/spreadsheets/d/([^/]+)'){
            $id=$Matches[1];$gid=''
            if($u -match '[?&]gid=(\\d+)'){$gid=$Matches[1]}
            if($gid){return "https://docs.google.com/spreadsheets/d/$id/export?format=csv&gid=$gid"}
            return "https://docs.google.com/spreadsheets/d/$id/export?format=csv"
        }
        return $u
    } catch { Write-CcLog "Google Sheets URL parse failed: $($_.Exception.Message)" 'WARN' 'Resolve-CcBarSheetUrl'; return $Url }
}
function ConvertFrom-CcCsvLine([string]$Line) { $out=@();$cur='';$quote=$false;foreach($ch in $Line.ToCharArray()){if($ch -eq '"'){$quote=-not $quote}elseif($ch -eq ',' -and -not $quote){$out+=$cur;$cur=''}else{$cur+=$ch}};$out+=$cur;return @($out|ForEach-Object{$_.Trim().Trim('"')}) }
function Get-CcBarConfig {
    $cfg=Get-CcConfig;$share=[string]$cfg['BAR_SHARE'];$shareOk=$false;if($share){try{$shareOk=Test-Path -LiteralPath $share -ErrorAction Stop}catch{$shareOk=$false}};$root=$script:CcRoot
    [pscustomobject]@{SheetId=[string]$cfg['BAR_SHEET_ID'];SheetUrl=[string]$cfg['BAR_SHEET_URL'];Share=$share;ShareAvailable=$shareOk;Cache=if($shareOk){Join-Path $share 'bar-menu.json'}else{Join-Path $root 'bar-menu.json'};Orders=if($shareOk){Join-Path $share 'bar-orders.json'}else{Join-Path $root 'bar-orders.json'};Stock=if($shareOk){Join-Path $share 'bar-stock.json'}else{Join-Path $root 'bar-stock.json'};Balances=if($shareOk){Join-Path $share 'bar-balances.json'}else{Join-Path $root 'bar-balances.json'};Prices=if($shareOk){Join-Path $share 'bar-prices.json'}else{Join-Path $root 'bar-prices.json'}}
}
function ConvertFrom-CcCsvLine([string]$Line) {$out=@();$cur='';$quote=$false;foreach($ch in $Line.ToCharArray()){if($ch -eq '"'){$quote=-not $quote}elseif($ch -eq ',' -and -not $quote){$out+=$cur;$cur=''}else{$cur+=$ch}};$out+=$cur;return @($out|ForEach-Object{$_.Trim().Trim('"')})}
function ConvertTo-CcBarDecimalValue([object]$Value,[decimal]$Default=0){
    try{
        if($null -eq $Value){return $Default}
        if($Value -is [System.Array]){
            $items=@($Value)
            if($items.Count -eq 0){return $Default}
            $Value=$items[0]
        }
        $text=[string]$Value
        if([string]::IsNullOrWhiteSpace($text)){return $Default}
        $text=$text.Trim().Replace([string][char]0xA0,' ').Replace(' ','')
        $parsed=[decimal]0
        if([decimal]::TryParse($text,[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::GetCultureInfo('ru-RU'),[ref]$parsed)){return $parsed}
        if([decimal]::TryParse($text,[Globalization.NumberStyles]::Number,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)){return $parsed}
        return $Default
    }catch{return $Default}
}
function Get-CcBarSeed {
    $rows=@()
    $rows+=,@('Adrenaline 0,449л',0,32)
    $rows+=,@('Aqua Minerale 0,5л',0,0)
    $rows+=,@('BonAqua 0,5л',0,0)
    $rows+=,@('BURN 0,449л',195,38)
    $rows+=,@('Chillout 0,45л',0,5)
    $rows+=,@('Cola fresh bar 0,45л',0,8)
    $rows+=,@('Flash Up Energy 0,45л',0,51)
    $rows+=,@('Fresh bar 0,45л',0,37)
    $rows+=,@('Gorilla 0,45л',0,42)
    $rows+=,@('Lipton 0,5л',0,11)
    $rows+=,@('Lit energy 0,45л',0,20)
    $rows+=,@('Rich чай 0,5л',0,38)
    $rows+=,@('Tornado 0,45л',110,90)
    $rows+=,@('X-TURBO 0,45',0,4)
    $rows+=,@('Вода Sensia Fresh',0,32)
    $rows+=,@('Вода Хрустальная 0,5л',0,3)
    $rows+=,@('Добрый 0,5л',0,72)
    $rows+=,@('ПАЛПИ 0,45л',0,32)
    $rows+=,@('Tornado 1л',0,5)
    $rows+=,@('Черноголовка 1л',0,7)
    $rows+=,@('Fresh bar 1,5л',0,9)
    $rows+=,@('Cheetos 50г',0,19)
    $rows+=,@('Lays 140г',0,9)
    $rows+=,@('Lays 70г',0,5)
    $rows+=,@('Lays из печи 85г',0,17)
    $rows+=,@('Хрустим Багет 60г',0,0)
    $rows+=,@('Хруст Nut 80 г',0,6)
    $rows+=,@('Choco pie',40,40)
    $rows+=,@('BOUNTY',0,0)
    $rows+=,@('Bounty Trio',0,3)
    $rows+=,@('Mars',0,0)
    $rows+=,@('Mars Max',0,0)
    $rows+=,@('SNICKERS',0,0)
    $rows+=,@('Snickers Super',0,3)
    $rows+=,@('TWIX',0,0)
    $rows+=,@('TWIX Xtra',0,0)
    $rows+=,@('Гудмикс 40г',0,0)
    $rows+=,@('Любятово 50г',0,19)
    $rows+=,@('Мармелад GORILLA 60г',140,9)
    $rows+=,@('Бельмеши 300гр',0,11)
    $rows+=,@('Круггетсы 200г',0,6)
    $rows+=,@('Хотстеры 250гр',0,10)
    $rows+=,@('Чебупели с ветчиной и сыром 240гр',0,11)
    $rows+=,@('Чебупели сочные с мясом 240гр',0,11)
    $rows+=,@('Чебупицца 250гр',0,14)
    $rows+=,@('Burn',195,38)
    $rows+=,@('Tornado',110,90)
    $rows+=,@('Chitos',110,0)
    $rows+=,@('Chocopai',40,40)
    $rows+=,@('Gorila en',150,0)
    $rows+=,@('Gorila мармелад',140,9)
    return @($rows | ForEach-Object {
        [pscustomobject]@{
            Name=$_[0]
            Price=[decimal]$($_[1])
            Sku=([string]$_[0]).ToLowerInvariant().Replace(' ','_')
            StockItem=$_[0]
            StockQty=1
            Category='Бар'
            Available=$true
            Stock=[decimal]$($_[2])
        }
    })
}
function Save-CcBarLocalSeed {try{$c=Get-CcBarConfig;if(Test-Path -LiteralPath $c.Cache){return};$items=@(Get-CcBarSeed);$items|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $c.Cache -Encoding UTF8;$stock=@{};foreach($x in $items){$stock[$x.Sku]=[decimal]$x.Stock};$stock|ConvertTo-Json|Set-Content -LiteralPath $c.Stock -Encoding UTF8;Write-CcLog "Bar local seed created: $($items.Count) items" 'OK' 'Save-CcBarLocalSeed'}catch{Write-CcError -FunctionName 'Save-CcBarLocalSeed' -Exception $_.Exception}}
function ConvertTo-CcBarBase64Url([byte[]]$Bytes){ return ([Convert]::ToBase64String($Bytes)).TrimEnd('=').Replace('+','-').Replace('/','_') }
function Get-CcBarGoogleToken {
    try {
        $cfg=Get-CcConfig; $keyPath=[string]$cfg['GOOGLE_SERVICE_ACCOUNT_JSON']
        if([string]::IsNullOrWhiteSpace($keyPath)){ foreach($candidate in @('google-service-account.json','service-account.json','credentials.json')){ $p=Join-Path $script:CcRoot $candidate; if(Test-Path -LiteralPath $p){$keyPath=$p;break} } }
        if([string]::IsNullOrWhiteSpace($keyPath) -or -not(Test-Path -LiteralPath $keyPath)){return ''}
        $cred=Get-Content -LiteralPath $keyPath -Raw -Encoding UTF8|ConvertFrom-Json
        if(-not $cred.client_email -or -not $cred.private_key){throw 'В JSON ключе Google нет client_email/private_key.'}
        $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $header=@{alg='RS256';typ='JWT'}; if($cred.private_key_id){$header.kid=[string]$cred.private_key_id}
        $payload=@{iss=[string]$cred.client_email;scope='https://www.googleapis.com/auth/spreadsheets.readonly';aud='https://oauth2.googleapis.com/token';iat=$now;exp=($now+3600)}
        $h=ConvertTo-CcBarBase64Url ([Text.Encoding]::UTF8.GetBytes(($header|ConvertTo-Json -Compress))); $p=ConvertTo-CcBarBase64Url ([Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Compress))); $unsigned="$h.$p"
        $pem=[string]$cred.private_key; $b64=($pem -replace '-----BEGIN PRIVATE KEY-----','' -replace '-----END PRIVATE KEY-----','' -replace 's',''); $key=[Convert]::FromBase64String($b64)
        $cng=[Security.Cryptography.CngKey]::Import($key,[Security.Cryptography.CngKeyBlobFormat]::Pkcs8PrivateBlob); $rsa=New-Object Security.Cryptography.RSACng($cng)
        try{$sig=$rsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)}finally{$rsa.Dispose();$cng.Dispose()}
        $jwt="$unsigned.$(ConvertTo-CcBarBase64Url $sig)"; $body="grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=$([Uri]::EscapeDataString($jwt))"
        $resp=Invoke-RestMethod -Uri 'https://oauth2.googleapis.com/token' -Method Post -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec 20 -ErrorAction Stop
        return [string]$resp.access_token
    } catch { Write-CcLog "Google service-account auth unavailable: $($_.Exception.Message)" 'WARN' 'Get-CcBarGoogleToken'; return '' }
}
function Get-CcBarGoogleValues([string]$SheetName,[string]$Range='A:Z') {
    try {
        $token=Get-CcBarGoogleToken; if([string]::IsNullOrWhiteSpace($token)){return $null}; $cfg=Get-CcConfig; $id=[string]$cfg['BAR_SHEET_ID']; if([string]::IsNullOrWhiteSpace($id)){return $null}
        $a1="$SheetName!$Range"; $url="https://sheets.googleapis.com/v4/spreadsheets/$id/values/$([Uri]::EscapeDataString($a1))?majorDimension=ROWS&valueRenderOption=FORMATTED_VALUE"
        $resp=Invoke-RestMethod -Uri $url -Headers @{Authorization="Bearer $token"} -Method Get -TimeoutSec 20 -ErrorAction Stop
        if($resp.values){return @($resp.values)}; return @()
    } catch { Write-CcLog "Google API read failed for sheet '$SheetName': $($_.Exception.Message)" 'WARN' 'Get-CcBarGoogleValues'; return $null }
}
function Normalize-CcBarKey([object]$Value){if($null -eq $Value){return ''};return ([string]$Value).Trim().ToLowerInvariant() -replace '[^0-9a-zа-яё]+',''}
function Get-CcBarPriceRows([string]$SheetName='Цены') {
    $rows=Get-CcBarGoogleValues $SheetName 'A:Z'; if($null -eq $rows -or @($rows).Count -lt 2){return @()}
    $head=@($rows[0]|ForEach-Object{([string]$_).Trim().ToLowerInvariant()}); $nameIdx=-1;$skuIdx=-1;$priceIdx=-1;$stockIdx=-1
    for($i=0;$i -lt $head.Count;$i++){switch($head[$i]){'name' {$nameIdx=$i};'товар' {$nameIdx=$i};'название' {$nameIdx=$i};'наименование' {$nameIdx=$i};'sku' {$skuIdx=$i};'артикул' {$skuIdx=$i};'price' {$priceIdx=$i};'цена' {$priceIdx=$i};'stock' {$stockIdx=$i};'остаток' {$stockIdx=$i};'количество' {$stockIdx=$i}}}
    if($nameIdx -lt 0 -and $skuIdx -lt 0){return @()}; $out=@()
    foreach($row in @($rows|Select-Object -Skip 1)){$v=@($row);$name=if($nameIdx -ge 0 -and $nameIdx -lt $v.Count){[string]$v[$nameIdx]}else{''};$sku=if($skuIdx -ge 0 -and $skuIdx -lt $v.Count){[string]$v[$skuIdx]}else{''};if([string]::IsNullOrWhiteSpace($name)-and[string]::IsNullOrWhiteSpace($sku)){continue};$price=0;if($priceIdx -ge 0 -and $priceIdx -lt $v.Count){$price=ConvertTo-CcBarDecimalValue $v[$priceIdx]};$stock=0;if($stockIdx -ge 0 -and $stockIdx -lt $v.Count){$stock=ConvertTo-CcBarDecimalValue $v[$stockIdx]};$out+=[pscustomobject]@{Name=$name;Sku=$sku;Price=$price;Stock=$stock}}
    return @($out)
}
function Get-CcBarMenu {
 try{$c=Get-CcBarConfig;Save-CcBarLocalSeed;$uri=if($c.SheetUrl){Resolve-CcBarSheetUrl $c.SheetUrl}elseif($c.SheetId){"https://docs.google.com/spreadsheets/d/$($c.SheetId)/export?format=csv"}else{''};if($uri){try{$csv=(Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop).Content;$rows=@($csv -split '?
'|Where-Object{$_.Trim()});if($rows.Count -ge 2){$head=ConvertFrom-CcCsvLine $rows[0];$result=@();for($i=1;$i -lt $rows.Count;$i++){$v=ConvertFrom-CcCsvLine $rows[$i];$o=@{};for($j=0;$j -lt $head.Count;$j++){if($j -lt $v.Count){$o[$head[$j].Trim().ToLowerInvariant()]=$v[$j]}};if($o['name']){$result+=[pscustomobject]@{Name=[string]$o['name'];Price=(ConvertTo-CcBarDecimalValue (if($o['price']){$o['price']}else{0}));Sku=[string]$(if($o['sku']){$o['sku']}else{$o['name']});StockItem=[string]$o['name'];StockQty=1;Stock=(ConvertTo-CcBarDecimalValue (if($o['stock']){$o['stock']}elseif($o['stockqty']){$o['stockqty']}elseif($o['наличие']){$o['наличие']}else{0}));Category=[string]$(if($o['category']){$o['category']}else{'Бар'});Available=if($o.ContainsKey('available')){[string]$o['available'] -notin @('0','false','нет')}else{$true}}}};if($result.Count -gt 0){$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $c.Cache -Encoding UTF8;Write-CcLog "Bar menu synchronized from Google Sheets: $($result.Count) items" 'OK' 'Get-CcBarMenu'}}}catch{Write-CcLog "Google Sheets unavailable, using local bar cache: $($_.Exception.Message)" 'WARN' 'Get-CcBarMenu'}};$priceRows=@(Get-CcBarPriceRows 'Цены');if($priceRows.Count -gt 0){$result=@(Get-CcBarSeed);$byName=@{};$bySku=@{};foreach($pr in $priceRows){$nk=Normalize-CcBarKey $pr.Name;$sk=Normalize-CcBarKey $pr.Sku;if($nk){$byName[$nk]=$pr};if($sk){$bySku[$sk]=$pr}};foreach($m in $result){$nk=Normalize-CcBarKey $m.Name;$sk=Normalize-CcBarKey $m.Sku;$pr=$null;if($sk -and $bySku.ContainsKey($sk)){$pr=$bySku[$sk]}elseif($nk -and $byName.ContainsKey($nk)){$pr=$byName[$nk]};if($null -ne $pr){$m.Price=ConvertTo-CcBarDecimalValue $pr.Price;$m.Stock=ConvertTo-CcBarDecimalValue $pr.Stock}};foreach($pr in $priceRows){$nk=Normalize-CcBarKey $pr.Name;$sk=Normalize-CcBarKey $pr.Sku;$exists=$false;foreach($m in $result){if(($nk -and $nk -eq (Normalize-CcBarKey $m.Name))-or($sk -and $sk -eq (Normalize-CcBarKey $m.Sku))){$exists=$true;break}};if(-not$exists -and -not[string]::IsNullOrWhiteSpace($pr.Name)){$result+=[pscustomobject]@{Name=$pr.Name;Price=ConvertTo-CcBarDecimalValue $pr.Price;Sku=if($pr.Sku){$pr.Sku}else{$pr.Name.ToLowerInvariant().Replace(' ','_')};StockItem=$pr.Name;StockQty=1;Category='Бар';Available=$true;Stock=ConvertTo-CcBarDecimalValue $pr.Stock}}};$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $c.Cache -Encoding UTF8;Write-CcLog "Bar catalog synchronized from Google sheet 'Цены': $($result.Count) items" 'OK' 'Get-CcBarMenu'};$result=@();if(Test-Path -LiteralPath $c.Cache){$json=Get-Content -LiteralPath $c.Cache -Raw; $parsed=ConvertFrom-Json -InputObject $json; $result=@($parsed)};if(-not$result -or $result.Count -eq 0){$result=@(Get-CcBarSeed)};if(Test-Path -LiteralPath $c.Prices){$ov=Get-Content -LiteralPath $c.Prices -Raw|ConvertFrom-Json;foreach($m in $result){if($m.Sku -and $ov.PSObject.Properties.Name -contains $m.Sku){$m.Price=ConvertTo-CcBarDecimalValue $ov.($m.Sku)}}};return $result
 }catch{Write-CcError -FunctionName 'Get-CcBarMenu' -Exception $_.Exception;return @(Get-CcBarSeed)}}
function Get-CcBarStock {try{$c=Get-CcBarConfig;Save-CcBarLocalSeed;if(-not(Test-Path -LiteralPath $c.Stock)){return @{}};$json=Get-Content -LiteralPath $c.Stock -Raw; $j=ConvertFrom-Json -InputObject $json;$h=@{};foreach($p in $j.PSObject.Properties){$h[$p.Name]=[decimal]$p.Value};return $h}catch{Write-CcError -FunctionName 'Get-CcBarStock' -Exception $_.Exception;return @{}}}
function Save-CcBarStock([hashtable]$Stock){try{$c=Get-CcBarConfig;$Stock|ConvertTo-Json|Set-Content -LiteralPath $c.Stock -Encoding UTF8}catch{Write-CcError -FunctionName 'Save-CcBarStock' -Exception $_.Exception}}
function Get-CcBarOrders {try{$c=Get-CcBarConfig;Save-CcBarLocalSeed;if(-not(Test-Path -LiteralPath $c.Orders)){@()|ConvertTo-Json|Set-Content -LiteralPath $c.Orders -Encoding UTF8};$json=Get-Content -LiteralPath $c.Orders -Raw; $parsed=ConvertFrom-Json -InputObject $json; return @($parsed)}catch{Write-CcError -FunctionName 'Get-CcBarOrders' -Exception $_.Exception;return @()}}
function Save-CcBarOrders([object[]]$Orders){try{$c=Get-CcBarConfig;$tmp="$($c.Orders).tmp";@($Orders)|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $c.Orders -Force}catch{Write-CcError -FunctionName 'Save-CcBarOrders' -Exception $_.Exception;throw}}
function Get-CcBarBalances {try{$c=Get-CcBarConfig;Save-CcBarLocalSeed;if(-not(Test-Path -LiteralPath $c.Balances)){@{}|ConvertTo-Json|Set-Content -LiteralPath $c.Balances -Encoding UTF8};$json=Get-Content -LiteralPath $c.Balances -Raw; $j=ConvertFrom-Json -InputObject $json;$h=@{};foreach($p in $j.PSObject.Properties){$h[$p.Name]=[decimal]$p.Value};return $h}catch{Write-CcError -FunctionName 'Get-CcBarBalances' -Exception $_.Exception;return @{}}}
function Save-CcBarBalances([hashtable]$Balances){try{$c=Get-CcBarConfig;$Balances|ConvertTo-Json|Set-Content -LiteralPath $c.Balances -Encoding UTF8}catch{Write-CcError -FunctionName 'Save-CcBarBalances' -Exception $_.Exception}}
function Set-CcBarBalance([string]$Pc,[decimal]$Balance){$h=Get-CcBarBalances;$h[$Pc]=$Balance;Save-CcBarBalances $h;return $true}
function New-CcBarOrder([string]$Pc,[object]$Item,[decimal]$Qty=1){try{$orders=@(Get-CcBarOrders);$o=[pscustomobject]@{Id=[guid]::NewGuid().ToString();Pc=$Pc;Item=$Item.Name;Sku=$Item.Sku;Qty=$Qty;UnitPrice=(ConvertTo-CcBarDecimalValue $Item.Price);Total=(ConvertTo-CcBarDecimalValue $Item.Price)*$Qty;Status='Pending';Created=(Get-Date).ToString('s')};$orders+=$o;Save-CcBarOrders $orders;Write-CcLog "Bar order created: $($o.Id) PC=$Pc item=$($o.Item)" 'INFO' 'New-CcBarOrder';return $o}catch{Write-CcError -FunctionName 'New-CcBarOrder' -Exception $_.Exception;return $null}}
function Confirm-CcBarOrder([string]$Id){try{$orders=@(Get-CcBarOrders);$o=$orders|Where-Object Id -eq $Id|Select-Object -First 1;if(-not$o){throw "Order not found: $Id"};if($o.Status -ne 'Pending'){throw "Order status is $($o.Status)"};$balances=Get-CcBarBalances;$pc=[string]$o.Pc;$balance=if($balances.ContainsKey($pc)){[decimal]$balances[$pc]}else{0};if($balance -lt [decimal]$o.Total){throw "Недостаточно средств на балансе ПК ${pc}: $balance"};$stock=Get-CcBarStock;if($o.Sku -and $stock.ContainsKey($o.Sku)){$need=[decimal]$o.Qty;if($stock[$o.Sku] -lt $need){throw "Недостаточно товара на складе: $($o.Sku)"};$stock[$o.Sku]-=$need;Save-CcBarStock $stock};$balances[$pc]=$balance-[decimal]$o.Total;Save-CcBarBalances $balances;$o.Status='Confirmed';$o.Confirmed=(Get-Date).ToString('s');Save-CcBarOrders $orders;Write-CcLog "Bar order confirmed: $Id total=$($o.Total)" 'OK' 'Confirm-CcBarOrder';return $o}catch{Write-CcError -FunctionName 'Confirm-CcBarOrder' -Exception $_.Exception;return $null}}
function Reject-CcBarOrder([string]$Id){try{$orders=@(Get-CcBarOrders);$o=$orders|Where-Object Id -eq $Id|Select-Object -First 1;if(-not$o){throw "Order not found: $Id"};$o.Status='Rejected';Save-CcBarOrders $orders;Write-CcLog "Bar order rejected: $Id" 'WARN' 'Reject-CcBarOrder';return $true}catch{Write-CcError -FunctionName 'Reject-CcBarOrder' -Exception $_.Exception;return $false}}
function Set-CcBarPrice([string]$Sku,[decimal]$Price){try{if([string]::IsNullOrWhiteSpace($Sku)){throw 'SKU не указан.'};if($Price -lt 0){throw 'Цена не может быть отрицательной.'};$c=Get-CcBarConfig;$h=@{};if(Test-Path -LiteralPath $c.Prices){$j=Get-Content -LiteralPath $c.Prices -Raw|ConvertFrom-Json;foreach($p in $j.PSObject.Properties){$h[$p.Name]=$p.Value}};$h[$Sku]=$Price;$h|ConvertTo-Json|Set-Content -LiteralPath $c.Prices -Encoding UTF8;Write-CcLog "Bar price override: $Sku=$Price" 'OK' 'Set-CcBarPrice';return $true}catch{Write-CcError -FunctionName 'Set-CcBarPrice' -Exception $_.Exception;return $false}}
