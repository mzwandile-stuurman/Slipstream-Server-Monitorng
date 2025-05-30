Add-Type -AssemblyName System.Data

# DB connection
$connectionString = "DSN=PostgreSQL_DNS;UID=postgres;PWD=mzwandile;"
$connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)
$connection.Open()

# Excluding background data
$excludedProcesses = @(
    "Idle", "System", "svchost", "wininit", "csrss", "services", "lsass", "smss",
    "winlogon", "conhost", "fontdrvhost", "WUDFHost", "WmiPrvSE", "dllhost"
)

# Timestamp
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$logDate = (Get-Date).ToString("yyyy-MM-dd")
$machine = $env:COMPUTERNAME

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


# INSERT SYSTEM METRICS
$sysCmd = $connection.CreateCommand()
$sysCmd.CommandText = @"
INSERT INTO system_metrics (
    timestamp, log_date, cpu_count, total_physical_memory,
    total_net_sent, total_net_received,
    total_memory_mb, free_memory_mb, used_memory_mb, ram_percent_used,
    machine_name, cpu_name, cpu_load, max_clock_mhz, current_clock_mhz, 
    process_count, thread_count, handle_count, system_uptime_seconds, signal_strength,
    link_speed_mbps,disk_total_gb, disk_used_gb, disk_free_gb
) VALUES (
    '$timestamp', '$logDate', $cpuCores, $($os.TotalVisibleMemorySize * 1024),
    $bytesSent, $bytesRecv,
    $totalMem, $freeMem, $usedMem, $memPercentUsed,
    '$machine', '$cpuName', $cpuLoad, $maxClock, $currentClock, $numProcesses,
    $totalThreads, $totalHandles, $uptimeSeconds, $wifiSignal, $linkSpeedMbps, $totalDiskGB,
    $usedDiskGB, $totalFreeGB
)
"@

$sysCmd.ExecuteNonQuery() | Out-Null

# COLLECT PROCESS METRICS (Cleaned version)
$processes = Get-Process | Where-Object {
    $_.Name -notin $excludedProcesses -and
    $_.CPU -gt 0 -and
    $_.WorkingSet -gt 1MB
}

foreach ($p in $processes) {
    try {
        $cmd = $connection.CreateCommand()
        
        $escapedName = $p.Name -replace "'", "''"
        $workingSet = $p.WorkingSet
        $cpu = if ($p.CPU) { $p.CPU } else { 0 }
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $logDate = (Get-Date).ToString("yyyy-MM-dd")
        
        # CPU % estimate
        $uptime = (Get-Date) - $p.StartTime
        $uptimeSecs = $uptime.TotalSeconds
        $cpuPercent = if ($uptimeSecs -gt 0) {
            [math]::Round(($p.TotalProcessorTime.TotalSeconds / $uptimeSecs) * 100, 2)
        } else {
            0
        }

        $cmd.CommandText = @"
INSERT INTO process_monitor (
    name, working_set, cpu,
    timestamp, log_date, cpu_percent
) VALUES (
    '$escapedName', $workingSet, $cpu,
    '$timestamp', '$logDate',  $cpuPercent
)
"@
        $cmd.ExecuteNonQuery() | Out-Null
        Write-Host "Inserted: $escapedName"
    } catch {
        Write-Host "Error inserting $($p.Name): $($_.Exception.Message)"
    }
}

$connection.Close()
