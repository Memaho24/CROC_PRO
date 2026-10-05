<#
CyberCroc Products - Google Sheets API v4 + local cache.
The service-account private key is read from a path outside the repository and is never logged.
#>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')

$script:CcProductsDir=Join-Path $script:CcRoot 'data'
$script:CcProductsCache=Join-Path $script:CcProductsDir 'products-cache.json'
$script:CcGoogleTokenCache=@{Token='';ExpiresUtc=(Get-Date).ToUniversalTime().AddMinutes(-1)}

function Get-CcProductsConfig {
    $cfg=Get-CcConfig
    $url=[string]$(if($cfg['PRODUCT_SHEET_URL']){$cfg['PRODUCT_SHEET_URL']}else{$cfg['BAR_SHEET_URL']})
    [pscustomobject]@{
        SheetUrl=$url
        SheetId=[string]$(if($cfg['PRODUCT_SHEET_ID']){$cfg['PRODUCT_SHEET_ID']}else{''})
        Range=[string]$(if($cfg['PRODUCT_SHEET_RANGE']){$cfg['PRODUCT_SHEET_RANGE']}else{'A:G'})
        ServiceAccountJson=[string]$(if($cfg['GOOGLE_SERVICE_ACCOUNT_JSON']){$cfg['GOOGLE_SERVICE_ACCOUNT_JSON']}else{''})
        SheetGid=[string]$(if($url -match '[?&]gid=(\d+)'){$Matches[1]}else{''})
    }
}
function Resolve-CcGoogleSheetRange([string]$Token,[string]$SheetId,[string]$ConfiguredRange,[string]$SheetGid) {
    $range=if($ConfiguredRange){$ConfiguredRange}else{'A:G'}
    if($range -match '!'){return $range}
    if(-not $SheetGid){return $range}
    try {
        $meta=Invoke-RestMethod -Uri "https://sheets.googleapis.com/v4/spreadsheets/$SheetId?fields=sheets(properties(sheetId,title))" -Headers @{Authorization="Bearer $Token"} -Method Get -TimeoutSec 20 -ErrorAction Stop
        $sheet=@($meta.sheets)|Where-Object {[string]$_.properties.sheetId -eq [string]$SheetGid}|Select-Object -First 1
        if($sheet){$title=([string]$sheet.properties.title).Replace("'","''");return "'$title'!$range"}
    } catch { Write-CcLog "Google Sheets metadata lookup failed: $($_.Exception.Message)" 'WARN' 'Resolve-CcGoogleSheetRange' }
    return $range
}
function Get-CcSheetId([string]$Url,[string]$ConfiguredId='') {
    if($ConfiguredId){return $ConfiguredId}
    if([string]::IsNullOrWhiteSpace($Url)){return ''}
    $m=[regex]::Match($Url,'/spreadsheets/d/([a-zA-Z0-9_-]+)');if($m.Success){return $m.Groups[1].Value}
    if($Url -match '^[a-zA-Z0-9_-]{20,}$'){return $Url}
    return ''
}
function ConvertTo-CcBase64Url([byte[]]$Bytes){return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+','-').Replace('/','_')}
function ConvertFrom-CcBase64([string]$Text){$s=$Text.Replace('-','+').Replace('_','/');switch($s.Length%4){2{$s+='=='}3{$s+='='}};return [Convert]::FromBase64String($s)}
function Read-DerLength([byte[]]$Data,[int]$Index,[ref]$Next){
    $b=$Data[$Index];$Index++
    if(($b -band 0x80)-eq 0){$Next.Value=$Index;return [int]$b}
    $n=$b -band 0x7f;if($n -le 0 -or $n -gt 4){throw 'Unsupported DER length.'}
    $len=0;for($i=0;$i-lt$n;$i++){$len=($len -shl 8)-bor $Data[$Index];$Index++};$Next.Value=$Index;return $len
}
function Read-DerElement([byte[]]$Data,[int]$Index,[ref]$Next) {
    $tag=$Data[$Index];$Index++
    $n=0;$len=Read-DerLength $Data $Index ([ref]$n)
    $start=$n;$end=$start+$len
    if($end -gt $Data.Length){throw 'Invalid DER element.'}
    $Next.Value=$end
    return [pscustomobject]@{Tag=$tag;Start=$start;Length=$len;End=$end}
}
function Read-DerInteger([byte[]]$Data,[ref]$Index) {
    $next=0;$e=Read-DerElement $Data $Index ([ref]$next);if($e.Tag -ne 0x02){throw 'DER integer expected.'}
    $raw=New-Object byte[] $e.Length;[Array]::Copy($Data,$e.Start,$raw,0,$e.Length)
    $Index.Value=$next
    while($raw.Length -gt 1 -and $raw[0]-eq 0){$raw=$raw[1..($raw.Length-1)]}
    return $raw
}
function ConvertFrom-CcPkcs8PrivateKey([string]$Pem) {
    $base=$Pem -replace '-----BEGIN PRIVATE KEY-----','' -replace '-----END PRIVATE KEY-----','' -replace '\s',''
    $der=[Convert]::FromBase64String($base);$i=0;$next=0;$outer=Read-DerElement $der $i ([ref]$next);if($outer.Tag -ne 0x30){throw 'PKCS#8 sequence expected.'};$i=$outer.Start
    $null=Read-DerInteger $der ([ref]$i)
    $alg=Read-DerElement $der $i ([ref]$next);$i=$next
    $oct=Read-DerElement $der $i ([ref]$next);if($oct.Tag -ne 0x04){throw 'PKCS#8 private key OCTET STRING expected.'}
    $rsa=New-Object byte[] $oct.Length;[Array]::Copy($der,$oct.Start,$rsa,0,$oct.Length)
    $i=0;$seq=Read-DerElement $rsa $i ([ref]$next);$i=$seq.Start
    $null=Read-DerInteger $rsa ([ref]$i)
    $p=[System.Security.Cryptography.RSAParameters]::new()
    $p.Modulus=Read-DerInteger $rsa ([ref]$i);$p.Exponent=Read-DerInteger $rsa ([ref]$i);$p.D=Read-DerInteger $rsa ([ref]$i);$p.P=Read-DerInteger $rsa ([ref]$i);$p.Q=Read-DerInteger $rsa ([ref]$i);$p.DP=Read-DerInteger $rsa ([ref]$i);$p.DQ=Read-DerInteger $rsa ([ref]$i);$p.InverseQ=Read-DerInteger $rsa ([ref]$i)
    return $p
}
function New-CcServiceAccountAssertion {
    param([object]$Credentials)
    if([string]::IsNullOrWhiteSpace([string]$Credentials.client_email) -or [string]::IsNullOrWhiteSpace([string]$Credentials.private_key)){throw 'Invalid service account JSON.'}
    $iat=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();$exp=$iat+3600
    $header=@{alg='RS256';typ='JWT';kid=[string]$Credentials.private_key_id}|ConvertTo-Json -Compress
    $claims=@{iss=[string]$Credentials.client_email;scope='https://www.googleapis.com/auth/spreadsheets';aud='https://oauth2.googleapis.com/token';iat=$iat;exp=$exp}|ConvertTo-Json -Compress
    $head64=ConvertTo-CcBase64Url ([Text.Encoding]::UTF8.GetBytes($header));$claims64=ConvertTo-CcBase64Url ([Text.Encoding]::UTF8.GetBytes($claims));$signing="$head64.$claims64"
    $rsa=New-Object System.Security.Cryptography.RSACryptoServiceProvider
    try{$rsa.ImportParameters((ConvertFrom-CcPkcs8PrivateKey ([string]$Credentials.private_key)));$sig=$rsa.SignData([Text.Encoding]::ASCII.GetBytes($signing),'SHA256')}finally{$rsa.Dispose()}
    return "$signing.$(ConvertTo-CcBase64Url $sig)"
}
function Get-CcGoogleAccessToken {
    try{
        $now=(Get-Date).ToUniversalTime();if($script:CcGoogleTokenCache.Token -and $script:CcGoogleTokenCache.ExpiresUtc -gt $now.AddMinutes(1)){return $script:CcGoogleTokenCache.Token}
        $c=Get-CcProductsConfig;if([string]::IsNullOrWhiteSpace($c.ServiceAccountJson)){throw 'GOOGLE_SERVICE_ACCOUNT_JSON не задан.'}
        $path=Expand-CcPath $c.ServiceAccountJson;if(-not(Test-Path -LiteralPath $path)){throw "Service account JSON not found: $path"}
        $cred=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;$jwt=New-CcServiceAccountAssertion $cred
        $body='grant_type='+[uri]::EscapeDataString('urn:ietf:params:oauth:grant-type:jwt-bearer')+'&assertion='+[uri]::EscapeDataString($jwt)
        $resp=Invoke-RestMethod -Uri 'https://oauth2.googleapis.com/token' -Method Post -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec 20 -ErrorAction Stop
        $script:CcGoogleTokenCache.Token=[string]$resp.access_token;$script:CcGoogleTokenCache.ExpiresUtc=$now.AddSeconds([int]$resp.expires_in)
        return $script:CcGoogleTokenCache.Token
    }catch{Write-CcLog "Google authentication failed: $($_.Exception.Message)" 'WARN' 'Get-CcGoogleAccessToken';return ''}
}

function ConvertTo-CcDecimal([object]$Value,[decimal]$Default=0) {
    try {
        if($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)){return $Default}
        $s=([string]$Value).Trim().Replace([char]0xA0,' ')
        $v=0m
        if([decimal]::TryParse($s,[Globalization.NumberStyles]::Any,[Globalization.CultureInfo]::InvariantCulture,[ref]$v)){return $v}
        if([decimal]::TryParse($s,[Globalization.NumberStyles]::Any,[Globalization.CultureInfo]::GetCultureInfo('ru-RU'),[ref]$v)){return $v}
        $s2=$s.Replace(' ','').Replace(',','.')
        if([decimal]::TryParse($s2,[Globalization.NumberStyles]::Any,[Globalization.CultureInfo]::InvariantCulture,[ref]$v)){return $v}
    } catch {}
    return $Default
}
function Get-CcProducts {
    param([switch]$ForceRefresh)
    try{
        if(-not(Test-Path -LiteralPath $script:CcProductsDir)){New-Item -ItemType Directory -Path $script:CcProductsDir -Force|Out-Null}
        $cfg=Get-CcProductsConfig;$sheetId=Get-CcSheetId $cfg.SheetUrl $cfg.SheetId
        $appRole=Get-CcRole
        if($appRole -ne 'admin') {
            if(Test-Path -LiteralPath $script:CcProductsCache){$cache=Get-Content -LiteralPath $script:CcProductsCache -Raw -Encoding UTF8|ConvertFrom-Json;return @($cache.Items)}
            return @()
        }
        if($sheetId -and $cfg.ServiceAccountJson){
            $token=Get-CcGoogleAccessToken
            if($token){
                $resolvedRange=Resolve-CcGoogleSheetRange $token $sheetId $cfg.Range $cfg.SheetGid;$range=[uri]::EscapeDataString($resolvedRange);$uri="https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$range"
                try{
                    $resp=Invoke-RestMethod -Uri $uri -Headers @{Authorization="Bearer $token"} -Method Get -TimeoutSec 20 -ErrorAction Stop
                    $rows=@($resp.values);if($rows.Count -gt 0){
                        $result=@();$head=@($rows[0]|ForEach-Object{[string]$_})
                        for($i=1;$i-lt$rows.Count;$i++){
                            $r=@($rows[$i]);$map=@{};for($j=0;$j-lt$head.Count;$j++){if($j-lt$r.Count){$map[$head[$j].ToLowerInvariant()]=$r[$j]}}
                            if($map.Count -gt 0 -and ($map.ContainsKey('name') -or $map.ContainsKey('товар') -or $map.ContainsKey('название') -or $map.ContainsKey('наименование'))){
                                $name=if($map.ContainsKey('name')){$map['name']}elseif($map.ContainsKey('товар')){$map['товар']}elseif($map.ContainsKey('название')){$map['название']}else{$map['наименование']};$price=if($map.ContainsKey('price')){$map['price']}elseif($map.ContainsKey('цена')){$map['цена']}else{0};$qty=if($map.ContainsKey('quantity')){$map['quantity']}elseif($map.ContainsKey('qty')){$map['qty']}elseif($map.ContainsKey('остаток')){$map['остаток']}elseif($map.ContainsKey('количество')){$map['количество']}else{0}
                                $result+=[pscustomobject]@{Name=[string]$name;Price=(ConvertTo-CcDecimal $price);Quantity=(ConvertTo-CcDecimal $qty);Row=$i+1;Sku=[string]$(if($map.ContainsKey('sku')){$map['sku']}else{$name});Category=[string]$(if($map.ContainsKey('category')){$map['category']}elseif($map.ContainsKey('категория')){$map['категория']}else{'Бар'})}
                            }
                        }
                        $cache=[pscustomobject]@{UpdatedUtc=(Get-Date).ToUniversalTime().ToString('o');Headers=$head;Rows=$rows;Items=$result;SheetId=$sheetId;Range=$resolvedRange};Write-CcJsonAtomic -Path $script:CcProductsCache -Object $cache|Out-Null;return @($result)
                    }
                }catch{Write-CcLog "Google Sheets read failed; using local cache: $($_.Exception.Message)" 'WARN' 'Get-CcProducts'}
            }
        }
        if(Test-Path -LiteralPath $script:CcProductsCache){$cache=Get-Content -LiteralPath $script:CcProductsCache -Raw -Encoding UTF8|ConvertFrom-Json;return @($cache.Items)}
        return @()
    }catch{Write-CcError -FunctionName 'Get-CcProducts' -Exception $_.Exception;return @()}
}
function Test-CcGoogleProductsConnection {
    try {
        $c=Get-CcProductsConfig;$sheetId=Get-CcSheetId $c.SheetUrl $c.SheetId
        if(-not $sheetId){throw 'Не задан Google Sheets ID/URL.'}
        if([string]::IsNullOrWhiteSpace($c.ServiceAccountJson)){throw 'Не задан путь к JSON service account.'}
        $token=Get-CcGoogleAccessToken;if(-not $token){throw 'Не удалось получить Google access token.'}
        $range=Resolve-CcGoogleSheetRange $token $sheetId $c.Range $c.SheetGid
        $uri="https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$([uri]::EscapeDataString($range))?majorDimension=ROWS"
        $resp=Invoke-RestMethod -Uri $uri -Headers @{Authorization="Bearer $token"} -Method Get -TimeoutSec 20 -ErrorAction Stop
        [pscustomobject]@{Ok=$true;SheetId=$sheetId;Range=$range;Rows=@($resp.values).Count;Message='Google Sheets подключён.'}
    } catch { Write-CcError -FunctionName 'Test-CcGoogleProductsConnection' -Exception $_.Exception;[pscustomobject]@{Ok=$false;SheetId='';Range='';Rows=0;Message=$_.Exception.Message} }
}
function Save-CcProducts {
    param([object[]]$Items)
    try{
        if(-not(Test-CcAdminAccessForData)){throw 'Режим редактирования доступен только админу.'}
        $cfg=Get-CcProductsConfig;$sheetId=Get-CcSheetId $cfg.SheetUrl $cfg.SheetId;if(-not$sheetId){throw 'PRODUCT_SHEET_URL/ID не задан.'}
        $token=Get-CcGoogleAccessToken;if(-not$token){throw 'Google Sheets недоступен.'}
        if(-not(Test-Path -LiteralPath $script:CcProductsCache)){throw 'Локальный кэш товаров отсутствует.'}
        $cache=Get-Content -LiteralPath $script:CcProductsCache -Raw -Encoding UTF8|ConvertFrom-Json;$rows=@($cache.Rows);$headers=@($cache.Headers)
        $itemsMap=@{};foreach($x in $Items){$itemsMap[[string]$x.Row]=$x}
        for($i=1;$i-lt$rows.Count;$i++){
            $row=@($rows[$i]);$nameIndex=-1;$priceIndex=-1;$qtyIndex=-1
            for($j=0;$j-lt$headers.Count;$j++){switch(([string]$headers[$j]).ToLowerInvariant()){'name'{$nameIndex=$j} 'товар'{$nameIndex=$j} 'price'{$priceIndex=$j} 'цена'{$priceIndex=$j} 'quantity'{$qtyIndex=$j} 'qty'{$qtyIndex=$j} 'остаток'{$qtyIndex=$j}}
            }
            $rowNum=$i+1;if($itemsMap.ContainsKey([string]$rowNum)){$it=$itemsMap[[string]$rowNum];if($nameIndex-ge0){while($row.Count-le$nameIndex){$row+='' };$row[$nameIndex]=$it.Name};if($priceIndex-ge0){while($row.Count-le$priceIndex){$row+='' };$row[$priceIndex]=([decimal]$it.Price).ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)};if($qtyIndex-ge0){while($row.Count-le$qtyIndex){$row+='' };$row[$qtyIndex]=([decimal]$it.Quantity).ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)};$rows[$i]=,$row}
        }
        $body=@{range=$cfg.Range;majorDimension='ROWS';values=$rows}|ConvertTo-Json -Depth 20
        $writeRange=if($cache.Range){[string]$cache.Range}else{Resolve-CcGoogleSheetRange $token $sheetId $cfg.Range $cfg.SheetGid};$uri="https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$([uri]::EscapeDataString($writeRange))?valueInputOption=USER_ENTERED"
        Invoke-RestMethod -Uri $uri -Headers @{Authorization="Bearer $token"} -Method Put -ContentType 'application/json' -Body $body -TimeoutSec 30 -ErrorAction Stop|Out-Null
        $cache.Rows=$rows;$cache.Items=@($Items);$cache.UpdatedUtc=(Get-Date).ToUniversalTime().ToString('o');Write-CcJsonAtomic -Path $script:CcProductsCache -Object $cache|Out-Null
        Write-CcLog "Products synchronized to Google Sheets: $(@($Items).Count) items" 'OK' 'Save-CcProducts';return $true
    }catch{Write-CcError -FunctionName 'Save-CcProducts' -Exception $_.Exception;return $false}
}
function Set-CcProduct {
    param([int]$Row,[string]$Name,[decimal]$Price,[decimal]$Quantity,[string]$Category='')
    $items=@(Get-CcProducts);$x=$items|Where-Object Row -eq $Row|Select-Object -First 1;if(-not$x){return $false};if($Name){$x.Name=$Name};$x.Price=$Price;$x.Quantity=$Quantity;if($Category){$x.Category=$Category};return (Save-CcProducts $items)
}

function Update-CcProductStock {
    param([string]$Sku,[decimal]$Delta)
    try {
        if((Get-CcRole) -ne 'admin'){throw 'Изменять остаток может только администратор.'}
        if([string]::IsNullOrWhiteSpace($Sku)){throw 'SKU товара не задан.'}
        if($Delta -eq 0){return $true}

        $cfg=Get-CcProductsConfig
        $sheetId=Get-CcSheetId $cfg.SheetUrl $cfg.SheetId
        if(-not $sheetId){throw 'PRODUCT_SHEET_URL/ID не задан.'}
        $token=Get-CcGoogleAccessToken
        if(-not $token){throw 'Google Sheets недоступен.'}

        # Serialize stock mutations inside the admin process so two incoming UDP orders
        # cannot calculate the new quantity from the same stale local value.
        $lockPath=Join-Path $script:CcProductsDir 'stock-update.lock'
        $lockStream=$null
        try {
            $lockStream=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)

            $items=@(Get-CcProducts -ForceRefresh)
            $item=$items|Where-Object {[string]$_.Sku -eq $Sku}|Select-Object -First 1
            if(-not $item){throw "Товар с SKU '$Sku' не найден."}

            $newQty=[decimal]$item.Quantity+$Delta
            if($newQty -lt 0){throw "Недостаточно товара '$($item.Name)'. Остаток: $($item.Quantity), требуется: $([math]::Abs($Delta))."}

            $cache=Get-Content -LiteralPath $script:CcProductsCache -Raw -Encoding UTF8|ConvertFrom-Json
            $headers=@($cache.Headers)
            $qtyIndex=-1
            for($j=0;$j-lt$headers.Count;$j++){
                if(([string]$headers[$j]).Trim().ToLowerInvariant() -in @('quantity','qty','остаток')){$qtyIndex=$j;break}
            }
            if($qtyIndex -lt 0){throw 'В таблице не найден столбец остатка (Quantity/Qty/Остаток).'}

            function ConvertTo-GoogleColumnName([int]$Index) {
                $n=$Index+1;$s=''
                while($n -gt 0){$n--; $s=[char](65+($n%26))+$s; $n=[math]::Floor($n/26)}
                return $s
            }

            $resolved=if($cache.Range){[string]$cache.Range}else{Resolve-CcGoogleSheetRange $token $sheetId $cfg.Range $cfg.SheetGid}
            if($resolved -notmatch '!'){
                $resolved=Resolve-CcGoogleSheetRange $token $sheetId $cfg.Range $cfg.SheetGid
            }
            $sheetPart=if($resolved -match '^(.*)!'){ $Matches[1] } else { throw 'Не удалось определить лист Google Sheets.' }
            $col=ConvertTo-GoogleColumnName $qtyIndex
            $rowNumber=[int]$item.Row
            $a1="$sheetPart!$col$rowNumber"

            $body=@{values=@(@(([decimal]$newQty).ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)))}|ConvertTo-Json -Depth 10
            $uri="https://sheets.googleapis.com/v4/spreadsheets/$sheetId/values/$([uri]::EscapeDataString($a1))?valueInputOption=USER_ENTERED"
            Invoke-RestMethod -Uri $uri -Headers @{Authorization="Bearer $token"} -Method Put -ContentType 'application/json' -Body $body -TimeoutSec 20 -ErrorAction Stop|Out-Null

            $item.Quantity=$newQty
            $cache.Items=@($items)
            $cache.UpdatedUtc=(Get-Date).ToUniversalTime().ToString('o')
            Write-CcJsonAtomic -Path $script:CcProductsCache -Object $cache|Out-Null
            Write-CcLog "Stock updated: sku=$Sku delta=$Delta quantity=$newQty" 'OK' 'Update-CcProductStock'
            return $true
        } finally {
            if($null -ne $lockStream){$lockStream.Dispose()}
        }
    } catch {
        Write-CcError -FunctionName 'Update-CcProductStock' -Exception $_.Exception
        return $false
    }
}

function Test-CcAdminAccessForData { try { $cfg=Get-CcConfig;return [bool]($cfg['ROLE'] -eq 'admin') } catch { return $false } }
