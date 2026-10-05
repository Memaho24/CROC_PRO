Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'Core.ps1')

function Get-CcHardware {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $cpu = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1)[0]
        $gpu = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1)[0]
        $disk = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue | Select-Object -First 1)[0]

        $ramFree = [math]::Round(([double]$os.FreePhysicalMemory / 1MB), 1)
        $ramTotal = [math]::Round(([double]$cs.TotalPhysicalMemory / 1GB), 1)

        $cpuName = if ($cpu) { [string]$cpu.Name } else { 'N/A' }
        $gpuName = if ($gpu) { [string]$gpu.Name } else { 'N/A' }
        $diskText = 'N/A'
        if ($disk) {
            $freeGb = [math]::Round(([double]$disk.FreeSpace / 1GB), 1)
            $sizeGb = [math]::Round(([double]$disk.Size / 1GB), 1)
            $diskText = "$freeGb GB free / $sizeGb GB"
        }

        $temp = $null
        try {
            $tz = @(Get-CimInstance -Namespace 'root/wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1)[0]
            if ($tz -and $null -ne $tz.CurrentTemperature) {
                $temp = [math]::Round((([double]$tz.CurrentTemperature / 10) - 273.15), 1)
            }
        } catch {}

        [pscustomobject]@{
            ComputerName = $env:COMPUTERNAME
            OS = [string]$os.Caption
            CPU = $cpuName
            GPU = $gpuName
            RAM = "$ramFree GB free / $ramTotal GB"
            Disk = $diskText
            CpuTemp = if ($null -ne $temp) { "$temp °C" } else { 'N/A' }
        }
    } catch {
        Write-CcError -FunctionName 'Get-CcHardware' -Exception $_.Exception
        return $null
    }
}

function Get-CcInventory {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $cpu = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1)[0]
        $gpu = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1)[0]

        $ram = [math]::Round(([double]$cs.TotalPhysicalMemory / 1GB), 1)

        [pscustomobject]@{
            Computer = $env:COMPUTERNAME
            Manufacturer = [string]$cs.Manufacturer
            Model = [string]$cs.Model
            Serial = [string]$bios.SerialNumber
            CPU = if ($cpu) { [string]$cpu.Name } else { 'N/A' }
            GPU = if ($gpu) { [string]$gpu.Name } else { 'N/A' }
            RAMGB = $ram
        }
    } catch {
        Write-CcError -FunctionName 'Get-CcInventory' -Exception $_.Exception
        return $null
    }
}
