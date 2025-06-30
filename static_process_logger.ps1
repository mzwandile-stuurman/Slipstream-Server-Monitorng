Add-Type -AssemblyName System.Data
#Set intervals
$intervalSeconds = 1  # 1 second
$runIndefinitely = $true
$startTime = Get-Date

while ($runIndefinitely) {
    try {

        # Check if 1 hour has passed since logging started
       
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalMinutes -ge 30) {
           #Write-Host "20 minutes passed — deleting old CSV files..."

            # Delete old files
            if (Test-Path $systemMetricsCsv) { Remove-Item $systemMetricsCsv -Force }
            if (Test-Path $processMetricsCsv) { Remove-Item $processMetricsCsv -Force }

            # Reset start time for next cycle
            $startTime = Get-Date
        }


        # Excluding background data
        $excludedProcesses = @(
            "Idle", "System", "svchost", "wininit", "csrss", "services", "lsass", "smss",
            "winlogon", "conhost", "fontdrvhost", "WUDFHost", "WmiPrvSE", "dllhost"
        )

        # Timestamp
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $logDate = (Get-Date).ToString("yyyy-MM-dd")
        $machine = $env:COMPUTERNAME

        # CSV Paths
        $systemMetricsCsv = "C:\Metrics\system_metrics.csv"
        $processMetricsCsv = "C:\Metrics\process_metrics.csv"

        # Ensure the directory exists
        $csvDir = [System.IO.Path]::GetDirectoryName($systemMetricsCsv)
        if (-not (Test-Path $csvDir)) {
            New-Item -Path $csvDir -ItemType Directory | Out-Null
        }

        # CPU INFO
        $cpuInfo = Get-CimInstance -ClassName Win32_Processor
        $cpuName = $cpuInfo.Name
        $cpuLoad = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue
        $cpuLoad = [math]::Round($cpuLoad, 2)
        $cpuCores = $cpuInfo.NumberOfLogicalProcessors
        $maxClock = $cpuInfo.MaxClockSpeed
        $currentClock = $cpuInfo.CurrentClockSpeed

        # MEMORY
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1024, 2)   # in MB
        $freeMem = [math]::Round($os.FreePhysicalMemory / 1024, 2)
        $usedMem = [math]::Round($totalMem - $freeMem, 2)
        $memPercentUsed = [math]::Round(($usedMem / $totalMem) * 100, 2)

        
        # New system metrics
        $numProcesses = (Get-Process).Count
        $totalThreads = (Get-Process | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum
        $totalHandles = (Get-Process | Measure-Object -Property Handles -Sum).Sum

        $lastBootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        $uptime = (New-TimeSpan -Start $lastBootTime -End (Get-Date))
        $uptimeSeconds = [math]::Round($uptime.TotalSeconds)

        # NETWORK
        $netSent = (Get-Counter '\Network Interface(*)\Bytes Sent/sec').CounterSamples | Measure-Object -Property CookedValue -Sum
        $netRecv = (Get-Counter '\Network Interface(*)\Bytes Received/sec').CounterSamples | Measure-Object -Property CookedValue -Sum
        $bytesSent = [math]::Round($netSent.Sum)
        $bytesRecv = [math]::Round($netRecv.Sum)

        # Run netsh and capture output
        $wifiInfo = netsh wlan show interfaces

        # Extract signal strength (percent)
        $wifiSignal = ($wifiInfo | Where-Object { $_ -match "^\s*Signal\s*:\s*\d+" }) -replace "^\s*Signal\s*:\s*", "" -replace "%", ""
        $wifiSignal = [int]($wifiSignal | Select-Object -First 1)

        # Extract link speed (Receive rate in Mbps)
        $linkSpeed = ($wifiInfo | Where-Object { $_ -match "^\s*Receive rate\s*:\s*\d+" }) -replace "^\s*Receive rate\s*:\s*", ""
        $linkSpeedMbps = [int]($linkSpeed | Select-Object -First 1)

        # Get total disk size and usage (across all fixed drives)
        $logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3"
        $totalDiskGB = 0
        $totalFreeGB = 0

        foreach ($disk in $logicalDisks) {
            $totalDiskGB += $disk.Size / 1GB
            $totalFreeGB += $disk.FreeSpace / 1GB
        }

        $totalDiskGB = [math]::Round($totalDiskGB, 2)
        $totalFreeGB = [math]::Round($totalFreeGB, 2)
        $usedDiskGB = [math]::Round($totalDiskGB - $totalFreeGB, 2)
        
        # Save system metrics to CSV
        $systemMetrics = [PSCustomObject]@{
            timestamp            = $timestamp
            log_date             = $logDate
            cpu_count            = $cpuCores
            total_physical_memory = $os.TotalVisibleMemorySize * 1024
            total_net_sent       = $bytesSent
            total_net_received   = $bytesRecv
            total_memory_mb      = $totalMem
            free_memory_mb       = $freeMem
            used_memory_mb       = $usedMem
            ram_percent_used     = $memPercentUsed
            machine_name         = $machine
            cpu_name             = $cpuName
            cpu_load             = $cpuLoad
            max_clock_mhz        = $maxClock
            current_clock_mhz    = $currentClock
            process_count        = $numProcesses
            thread_count         = $totalThreads
            handle_count         = $totalHandles
            system_uptime_seconds = $uptimeSeconds
            signal_strength      = $wifiSignal
            link_speed_mbps      = $linkSpeedMbps
            disk_total_gb        = $totalDiskGB
            disk_used_gb         = $usedDiskGB
            disk_free_gb         = $totalFreeGB
        }

        $systemMetrics | Export-Csv -Path $systemMetricsCsv -Append -NoTypeInformation

        # COLLECT PROCESS METRICS (Cleaned version)
        $processes = Get-Process | Where-Object {
            $_.Name -notin $excludedProcesses -and
            $_.CPU -gt 0 -and
            $_.WorkingSet -gt 1MB
        }

        # Get CPU per 1 second interval
        $initialTimes = @{}
        Get-Process | ForEach-Object {
            $initialTimes[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds
        }

        # Initial I/O operations snapshot
        $initialIO = @{}
        Get-Process | ForEach-Object {
            $initialIO[$_.Id] = @{
                ReadOps  = $_.IOReadOperations
                WriteOps = $_.IOWriteOperations
            }
        }

        Start-Sleep -Milliseconds 1000  # 1 second sample interval
        $finalTimes = @{}
        Get-Process | ForEach-Object {
            $finalTimes[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds
        }

        # Final I/O operations snapshot
        $finalIO = @{}
        Get-Process | ForEach-Object {
            $finalIO[$_.Id] = @{
                ReadOps  = $_.IOReadOperations
                WriteOps = $_.IOWriteOperations
            }
        }

        $cpuCount = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors
        
        foreach ($p in $processes) {
            try {

                #Cpu per second metric
                if ($finalTimes.ContainsKey($p.Id) -and $initialTimes.ContainsKey($p.Id)) {
                    $delta = $finalTimes[$p.Id] - $initialTimes[$p.Id]
                    $TotcpuPercent = [math]::Round(($delta / (1000 * $cpuCount)) * 100, 2)
                } else {
                    $TotcpuPercent = 0
                }

                # Calculate per-second I/O operations
                if ($initialIO.ContainsKey($p.Id) -and $finalIO.ContainsKey($p.Id)) {
                    $readDelta  = $finalIO[$p.Id].ReadOps  - $initialIO[$p.Id].ReadOps
                    $writeDelta = $finalIO[$p.Id].WriteOps - $initialIO[$p.Id].WriteOps
                    $totalIODelta = $readDelta + $writeDelta
                } else {
                    $readDelta = 0
                    $writeDelta = 0
                    $totalIODelta = 0
                }

                $workingSet = $p.WorkingSet
                # Append process metric to CSV
                
                $procMetrics = [PSCustomObject]@{
                    name         = $p.Name
                    ram          = $workingSet
                    cpu          = $TotcpuPercent
                    io_read_ops  = $readDelta
                    io_write_ops = $writeDelta
                    io_total_ops = $totalIODelta
                    timestamp    = $timestamp
                    log_date     = $logDate
                    
                }

                $procMetrics | Export-Csv -Path $processMetricsCsv -Append -NoTypeInformation
            } 
            catch {
                Write-Host "Error inserting $($p.Name): $($_.Exception.Message)"
            }
        }
        
        Write-Host " running for $intervalSeconds second(s)..."
        Start-Sleep -Seconds $intervalSeconds
    }
    catch {
        Write-Host "Error occurred: $($_.Exception.Message)"
        Start-Sleep -Seconds $intervalSeconds
    }
}



