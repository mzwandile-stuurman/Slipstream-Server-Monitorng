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

# INSERT SYSTEM METRICS
$sysCmd = $connection.CreateCommand()
$sysCmd.CommandText = @"
INSERT INTO system_metrics (
    timestamp, log_date, cpu_count, total_physical_memory,
    total_net_sent, total_net_received,
    total_memory_mb, free_memory_mb, used_memory_mb, ram_percent_used,
    machine_name, cpu_name, cpu_load, max_clock_mhz, current_clock_mhz, 
    process_count, thread_count, handle_count, system_uptime_seconds, signal_strength,
    link_speed_mbps
) VALUES (
    '$timestamp', '$logDate', $cpuCores, $($os.TotalVisibleMemorySize * 1024),
    $bytesSent, $bytesRecv,
    $totalMem, $freeMem, $usedMem, $memPercentUsed,
    '$machine', '$cpuName', $cpuLoad, $maxClock, $currentClock, $numProcesses,
    $totalThreads, $totalHandles, $uptimeSeconds, $wifiSignal, $linkSpeedMbps
)
"@

$sysCmd.ExecuteNonQuery() | Out-Null

# COLLECT PROCESS METRICS 
$processes = Get-Process | Where-Object {
    $_.Name -notin $excludedProcesses -and
    $_.CPU -gt 0 -and
    $_.WorkingSet -gt 1MB
}

foreach ($p in $processes) {
    try {
        $cmd = $connection.CreateCommand()

        $escapedName = $p.Name -replace "'", "''"
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $logDate = (Get-Date).ToString("yyyy-MM-dd")
        $si = if ($p.SI) { $p.SI } else { 0 }
        $ws = $p.WS
        $vm = $p.VM
        $privMem = $p.PrivateMemorySize
        $workingSet = $p.WorkingSet
        $virtMem = $p.VirtualMemorySize
        $pagedMem = $p.PagedMemorySize
        $peakWS = if ($p.PeakWorkingSet) { $p.PeakWorkingSet } else { 0 }
        $peakVM = if ($p.PeakVirtualMemorySize) { $p.PeakVirtualMemorySize } else { 0 }
        $maxWS = if ($p.MaxWorkingSet) { $p.MaxWorkingSet } else { 0 }
        $cpu = if ($p.CPU) { $p.CPU } else { 0 }

        $privSecs = [math]::Round($p.PrivilegedProcessorTime.TotalSeconds, 3)
        $userSecs = [math]::Round($p.UserProcessorTime.TotalSeconds, 3)
        $totalSecs = [math]::Round($p.TotalProcessorTime.TotalSeconds, 3)
        $affinity = if ($p.ProcessorAffinity) { $p.ProcessorAffinity.ToString() -replace "'", "''" } else { "" }

        $startTime = $p.StartTime.ToString("yyyy-MM-dd HH:mm:ss")
        $hasExited = $p.HasExited
        $responding = $p.Responding

        $readBytes = if ($p.IO) { $p.IO.ReadTransferCount } else { 0 }
        $writeBytes = if ($p.IO) { $p.IO.WriteTransferCount } else { 0 }
        $otherBytes = if ($p.IO) { $p.IO.OtherTransferCount } else { 0 }
        $totalDiskIO = $readBytes + $writeBytes + $otherBytes

        # CPU % estimate
        $uptime = (Get-Date) - $p.StartTime
        $uptimeSecs = $uptime.TotalSeconds
        $cpuPercent = if ($uptimeSecs -gt 0) {
            [math]::Round(($totalSecs / $uptimeSecs) * 100, 2)
        } else {
            0
        }

        $cmd.CommandText = @"
INSERT INTO process_monitor (
    name, session_id, ws, vm, private_mem, working_set,
    virtual_mem, paged_mem, peak_ws, peak_vm, max_ws, cpu,
    priv_proc_time, user_proc_time, total_proc_time, processor_affinity,
    start_time, has_exited, responding, machine_name,
    read_bytes, write_bytes, other_bytes, total_disk_io,
    cpu_percent, timestamp, log_date
) VALUES (
    '$escapedName', $si, $ws, $vm, $privMem, $workingSet,
    $virtMem, $pagedMem, $peakWS, $peakVM, $maxWS, $cpu,
    $privSecs, $userSecs, $totalSecs, '$affinity',
    '$startTime', '$hasExited', '$responding', '$machine',
    $readBytes, $writeBytes, $otherBytes, $totalDiskIO,
    $cpuPercent, '$timestamp', '$logDate'
)
"@
        $cmd.ExecuteNonQuery() | Out-Null
        Write-Host "Inserted: $escapedName"
    } catch {
        Write-Host "Error inserting $($p.Name): $($_.Exception.Message)"
    }
}

$connection.Close()
