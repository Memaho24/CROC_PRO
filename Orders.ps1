<# CyberCroc orders + admin calls, backed by local JSON and UDP transport. #>
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'Network.ps1')
. (Join-Path $PSScriptRoot 'Queue.ps1')

$script:CcOrderDir=Join-Path $script:CcRoot 'data'
$script:CcOrdersFile=Join-Path $script:CcOrderDir 'orders.json'
$script:CcCallsFile=Join-Path $script:CcOrderDir 'calls.json'

function Initialize-CcOperations {
    try {
        if(-not(Test-Path -LiteralPath $script:CcOrderDir)){New-Item -ItemType Directory -Path $script:CcOrderDir -Force|Out-Null}
        if(-not(Test-Path -LiteralPath $script:CcOrdersFile)){Write-CcJsonAtomic -Path $script:CcOrdersFile -Object @()|Out-Null}
        if(-not(Test-Path -LiteralPath $script:CcCallsFile)){Write-CcJsonAtomic -Path $script:CcCallsFile -Object @()|Out-Null}
    }catch{Write-CcError -FunctionName 'Initialize-CcOperations' -Exception $_.Exception}
}
function Get-CcOrders {Initialize-CcOperations;try{$raw=Get-Content -LiteralPath $script:CcOrdersFile -Raw -Encoding UTF8;return @($raw|ConvertFrom-Json)}catch{return @()}}
function Save-CcOrders([object[]]$Items){Write-CcJsonAtomic -Path $script:CcOrdersFile -Object @($Items)|Out-Null}
function Get-CcCalls {Initialize-CcOperations;try{$raw=Get-Content -LiteralPath $script:CcCallsFile -Raw -Encoding UTF8;return @($raw|ConvertFrom-Json)}catch{return @()}}
function Save-CcCalls([object[]]$Items){Write-CcJsonAtomic -Path $script:CcCallsFile -Object @($Items)|Out-Null}
function Get-CcOrderGoogleConfig {`n    try {`n        $cfg=Get-CcConfig`n        $id=[string]$cfg['PRODUCT_SHEET_ID']; if([string]::IsNullOrWhiteSpace($id)){$id=[string]$cfg['BAR_SHEET_ID']}`n        $url=[string]$cfg['PRODUCT_SHEET_URL']; if([string]::IsNullOrWhiteSpace($url)){$url=[string]$cfg['BAR_SHEET_URL']}`n        $tab=[string]$cfg['ORDER_SHEET_NAME']; if([string]::IsNullOrWhiteSpace($tab)){$tab='Orders'}`n        [pscustomobject]@{SpreadsheetId=$id;SpreadsheetUrl=$url;SheetName=$tab}`n    }catch{Write-CcError -FunctionName 'Get-CcOrderGoogleConfig' -Exception $_.Exception;return $null}`n}`nfunction Write-CcOrderToGoogle {`n    param([object]$Order)`n    try {`n        if((Get-CcRole) -ne 'admin'){return $false}`n        if(-not (Get-Command Get-CcGoogleAccessToken -ErrorAction SilentlyContinue)){return $false}`n        $gc=Get-CcOrderGoogleConfig;if($null -eq $gc -or [string]::IsNullOrWhiteSpace($gc.SpreadsheetId)){return $false}`n        $token=Get-CcGoogleAccessToken;if([string]::IsNullOrWhiteSpace([string]$token)){return $false}`n        $base="https://sheets.googleapis.com/v4/spreadsheets/$($gc.SpreadsheetId)"`n        $headers=@{Authorization="Bearer $token"}`n        $meta=Invoke-RestMethod -Uri $base -Headers $headers -Method Get -ErrorAction Stop`n        $sheet=$meta.sheets|Where-Object {$_.properties.title -eq $gc.SheetName}|Select-Object -First 1`n        if($null -eq $sheet){`n            $body=@{requests=@(@{addSheet=@{properties=@{title=$gc.SheetName}}})}|ConvertTo-Json -Depth 10`n            Invoke-RestMethod -Uri $base+':batchUpdate' -Headers $headers -Method Post -ContentType 'application/json' -Body $body -ErrorAction Stop|Out-Null`n        }`n        $values=@(@($Order.order_id,$Order.timestamp,$Order.client_pc,$Order.sku,$Order.item_name,$Order.quantity,$Order.unit_price,$Order.total,$Order.payment_type,$Order.status))`n        $range=[uri]::EscapeDataString("$($gc.SheetName)!A:J")`n        $body=@{values=$values}|ConvertTo-Json -Depth 10`n        Invoke-RestMethod -Uri "$base/values/$range:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS" -Headers $headers -Method Post -ContentType 'application/json' -Body $body -ErrorAction Stop|Out-Null`n        return $true`n    }catch{Write-CcError -FunctionName 'Write-CcOrderToGoogle' -Exception $_.Exception;return $false}`n}`nfunction New-CcOrder {
    param([object]$Item,[decimal]$Quantity=1,[ValidateSet('Cash','Card')][string]$PaymentType='Cash',[string]$PcId='')
    try {
        if($null -eq $Item){throw 'Товар не выбран.'}; if($Quantity -le 0){throw 'Количество должно быть больше нуля.'}
        $id=(Get-CcNodeIdentity).PcId;if($PcId){$id=$PcId}
        $price=[decimal]$Item.Price;$o=[pscustomobject]@{order_id=[guid]::NewGuid().ToString();sku=[string]$(if($Item.PSObject.Properties.Name -contains 'Sku'){$Item.Sku}else{$Item.Name});item_name=[string]$Item.Name;quantity=$Quantity;unit_price=$price;total=($price*$Quantity);payment_type=$PaymentType;client_pc=$id;timestamp=(Get-Date).ToUniversalTime().ToString('o');status='new';google_sync='pending'}
        $orders=@(Get-CcOrders);$orders+=$o;Save-CcOrders $orders
        Enqueue-CcOperation -Type 'order' -ReferenceId $o.order_id -Payload $o|Out-Null
        $o.status='queued';$orders=@(Get-CcOrders);($orders|Where-Object order_id -eq $o.order_id|Select-Object -First 1).status='queued';Save-CcOrders $orders|Out-Null
        $adminOnline=@(Get-CcKnownNodes|Where-Object {$_.Role -eq 'admin' -and $_.Online}).Count -gt 0
        if($adminOnline){[void](Send-CcUdpMessage ([pscustomobject]@{type='order';order_id=$o.order_id;item_name=$o.item_name;quantity=$o.quantity;payment_type=$o.payment_type;client_pc=$o.client_pc;timestamp=$o.timestamp;sku=$o.sku;unit_price=$o.unit_price;total=$o.total}))}
        Write-CcLog "Order created: $($o.order_id) item=$($o.item_name) pc=$($o.client_pc)" 'INFO' 'New-CcOrder'
        return $o
    }catch{Write-CcError -FunctionName 'New-CcOrder' -Exception $_.Exception;return $null}
}
function Register-CcIncomingOrder([object]$Message) {
    try{
        if([string]::IsNullOrWhiteSpace([string]$Message.order_id)){return $null}
        $orders=@(Get-CcOrders);$existing=$orders|Where-Object order_id -eq $Message.order_id|Select-Object -First 1
        if($existing){return $existing}
        $o=[pscustomobject]@{order_id=[string]$Message.order_id;sku=[string]$(if($Message.sku){$Message.sku}else{$Message.item_name});item_name=[string]$Message.item_name;quantity=[decimal]$Message.quantity;unit_price=[decimal]$(if($Message.unit_price){$Message.unit_price}else{0});total=[decimal]$(if($Message.total){$Message.total}else{0});payment_type=[string]$Message.payment_type;client_pc=[string]$Message.client_pc;timestamp=[string]$Message.timestamp;status='new';google_sync='pending';received_utc=(Get-Date).ToUniversalTime().ToString('o')}
        $orders+=$o;Save-CcOrders $orders`n        if((Get-CcRole) -eq 'admin'){
            if(Write-CcOrderToGoogle $o){
                $o.google_sync='synced'
                $orders=@(Get-CcOrders)
                $saved=$orders|Where-Object order_id -eq $o.order_id|Select-Object -First 1
                if($saved){$saved.google_sync='synced'}
                Save-CcOrders $orders|Out-Null

                # Google Sheet is the authoritative stock. Decrease it only after
                # the order itself was successfully recorded in Google.
                if(Get-Command Update-CcProductStock -ErrorAction SilentlyContinue){
                    if(Update-CcProductStock -Sku $o.sku -Delta (-1*[decimal]$o.quantity)){
                        $o.stock_sync='synced'
                        $orders=@(Get-CcOrders)
                        $saved=$orders|Where-Object order_id -eq $o.order_id|Select-Object -First 1
                        if($saved){$saved.stock_sync='synced'}
                        Save-CcOrders $orders|Out-Null
                    } else {
                        $o.stock_sync='pending'
                        $orders=@(Get-CcOrders)
                        $saved=$orders|Where-Object order_id -eq $o.order_id|Select-Object -First 1
                        if($saved){$saved.stock_sync='pending'}
                        Save-CcOrders $orders|Out-Null
                    }
                }
            }
        }`n        Write-CcLog "Incoming order: $($o.order_id) pc=$($o.client_pc) google=$($o.google_sync)" 'OK' 'Register-CcIncomingOrder';return $o
    }catch{Write-CcError -FunctionName 'Register-CcIncomingOrder' -Exception $_.Exception;return $null}
}
function Set-CcOrderStatus([string]$OrderId,[ValidateSet('new','preparing','delivered','rejected')][string]$Status){try{$items=@(Get-CcOrders);$o=$items|Where-Object order_id -eq $OrderId|Select-Object -First 1;if(-not$o){return $false};$o.status=$Status;$o.updated_utc=(Get-Date).ToUniversalTime().ToString('o');Save-CcOrders $items;return $true}catch{Write-CcError -FunctionName 'Set-CcOrderStatus' -Exception $_.Exception;return $false}}
function Send-CcOrderAck([string]$OrderId,[string]$RemoteAddress,[int]$RemotePort){Send-CcUdpMessage ([pscustomobject]@{type='ack';ack_type='order';reference_id=$OrderId;timestamp=(Get-Date).ToUniversalTime().ToString('o')}) $RemoteAddress 50505}
function New-CcAdminCall {
    param([ValidateSet('problem','question','other')][string]$Reason='problem',[string]$PcId='')
    try{
        $id=(Get-CcNodeIdentity).PcId;if($PcId){$id=$PcId};$c=[pscustomobject]@{call_id=[guid]::NewGuid().ToString();client_pc=$id;reason=$Reason;timestamp=(Get-Date).ToUniversalTime().ToString('o');status='new'}
        $calls=@(Get-CcCalls);$calls+=$c;Save-CcCalls $calls
        Enqueue-CcOperation -Type 'admin_call' -ReferenceId $c.call_id -Payload $c|Out-Null
        $c.status='queued';$calls=@(Get-CcCalls);($calls|Where-Object call_id -eq $c.call_id|Select-Object -First 1).status='queued';Save-CcCalls $calls|Out-Null
        $adminOnline=@(Get-CcKnownNodes|Where-Object {$_.Role -eq 'admin' -and $_.Online}).Count -gt 0
        if($adminOnline){[void](Send-CcUdpMessage ([pscustomobject]@{type='admin_call';call_id=$c.call_id;client_pc=$c.client_pc;reason=$c.reason;timestamp=$c.timestamp}))}
        return $c
    }catch{Write-CcError -FunctionName 'New-CcAdminCall' -Exception $_.Exception;return $null}
}
function Register-CcIncomingCall([object]$Message){try{$calls=@(Get-CcCalls);if($calls|Where-Object call_id -eq $Message.call_id|Select-Object -First 1){return};$c=[pscustomobject]@{call_id=[string]$Message.call_id;client_pc=[string]$Message.client_pc;reason=[string]$Message.reason;timestamp=[string]$Message.timestamp;status='new';received_utc=(Get-Date).ToUniversalTime().ToString('o')};$calls+=$c;Save-CcCalls $calls;return $c}catch{Write-CcError -FunctionName 'Register-CcIncomingCall' -Exception $_.Exception}}
function Set-CcCallStatus([string]$CallId,[ValidateSet('new','going','resolved','rejected')][string]$Status){try{$items=@(Get-CcCalls);$c=$items|Where-Object call_id -eq $CallId|Select-Object -First 1;if(-not$c){return $false};$c.status=$Status;$c.updated_utc=(Get-Date).ToUniversalTime().ToString('o');Save-CcCalls $items;return $true}catch{return $false}}
function Send-CcCallAck([string]$CallId,[string]$RemoteAddress,[int]$RemotePort){Send-CcUdpMessage ([pscustomobject]@{type='ack';ack_type='admin_call';reference_id=$CallId;timestamp=(Get-Date).ToUniversalTime().ToString('o')}) $RemoteAddress 50505}
function Acknowledge-CcOrder([string]$OrderId){try{$items=@(Get-CcOrders);$o=$items|Where-Object order_id -eq $OrderId|Select-Object -First 1;if($o -and $o.status -eq 'queued'){$o.status='new';$o.ack_utc=(Get-Date).ToUniversalTime().ToString('o');Save-CcOrders $items}}catch{Write-CcError -FunctionName 'Acknowledge-CcOrder' -Exception $_.Exception}}
function Acknowledge-CcCall([string]$CallId){try{$items=@(Get-CcCalls);$c=$items|Where-Object call_id -eq $CallId|Select-Object -First 1;if($c -and $c.status -eq 'queued'){$c.status='new';$c.ack_utc=(Get-Date).ToUniversalTime().ToString('o');Save-CcCalls $items}}catch{Write-CcError -FunctionName 'Acknowledge-CcCall' -Exception $_.Exception}}
function Resend-CcQueuedOperations {
    try {
        foreach($q in @(Get-CcQueueItems)) {
            $sent=$false
            if($q.Type -eq 'order') { $sent=Send-CcUdpMessage ([pscustomobject]@{type='order';order_id=$q.Payload.order_id;item_name=$q.Payload.item_name;quantity=$q.Payload.quantity;payment_type=$q.Payload.payment_type;client_pc=$q.Payload.client_pc;timestamp=$q.Payload.timestamp;sku=$q.Payload.sku;unit_price=$q.Payload.unit_price;total=$q.Payload.total}) }
            elseif($q.Type -eq 'admin_call') { $sent=Send-CcUdpMessage ([pscustomobject]@{type='admin_call';call_id=$q.Payload.call_id;client_pc=$q.Payload.client_pc;reason=$q.Payload.reason;timestamp=$q.Payload.timestamp}) }
            if(-not$sent){Touch-CcQueueFailure -Id $q.Id -ErrorText 'UDP unavailable'}
        }
    }catch{Write-CcError -FunctionName 'Resend-CcQueuedOperations' -Exception $_.Exception}
}
Initialize-CcOperations
