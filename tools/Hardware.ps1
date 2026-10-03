Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')
function Get-CcHardware {
    try{
        $os=Get-CimInstance Win32_OperatingSystem
        $cs=Get-CimInstance Win32_ComputerSystem
        $cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
        $gpu=Get-CimInstance Win32_VideoController|Select-Object -First 1
        $disk=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $ramFree=[math]::Round(($os.FreePhysicalMemory/1MB),1)
        $ramTotal=[math]::Round(($cs.TotalPhysicalMemory/1GB),1)
        $temp=$null
        try{
            $tz=Get-CimInstance -Namespace root/wmi -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop|Select-Object -First 1
            if($tz.CurrentTemperature){$temp=[math]::Round(($tz.CurrentTemperature/10)-273.15,1)}
        }catch{}
        [pscustomobject]@{
            ComputerName=$env:COMPUTERNAME;OS=$os.Caption;CPU=$cpu.Name;GPU=$gpu.Name
            RAM="$ramFree GB free / $ramTotal GB";Disk="$([math]::Round($disk.FreeSpace/1GB,1)) GB free / $([math]::Round($disk.Size/1GB,1)) GB"
            CpuTemp=if($temp){ "$temp °C" }else{'N/A'}
        }
    }catch{Write-CcError -FunctionName 'Get-CcHardware' -Exception $_.Exception;return $null}
}
function Get-CcInventory {
    try{
        $cs=Get-CimInstance Win32_ComputerSystem
        $bios=Get-CimInstance Win32_BIOS
        $cpu=Get-CimInstance Win32_Processor|Select-Object -First 1
        $gpu=Get-CimInstance Win32_VideoController|Select-Object -First 1
        $ram=[math]::Round($cs.TotalPhysicalMemory/1GB,1)
        [pscustomobject]@{Computer=$env:COMPUTERNAME;Manufacturer=$cs.Manufacturer;Model=$cs.Model;Serial=$bios.SerialNumber;CPU=$cpu.Name;GPU=$gpu.Name;RAMGB=$ram}
    }catch{Write-CcError -FunctionName 'Get-CcInventory' -Exception $_.Exception;return $null}
}
