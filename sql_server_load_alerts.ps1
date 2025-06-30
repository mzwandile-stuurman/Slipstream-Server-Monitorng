Add-Type -AssemblyName System.Data

# SQL Server connection string
$connectionString = "Server=SLIP-CPT-MZWAND;Database=server_monitoring;Integrated Security=True;"
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$connection.Open()

# Alert thresholds
$cpuThreshold = 90       # CPU usage > 90%
$memThreshold = 90       # RAM usage > 90%
$diskThreshold = 90      # Disk usage > 90%

# Email configuration
$smtpServer = "smtp.yourdomain.com"  # e.g., smtp.office365.com or smtp.gmail.com
$smtpPort = 587
$from = "monitor@yourdomain.com"
$to = "you@example.com"
$subject = "ALERT: Server Resource Usage Exceeded"
$smtpUser = "yourusername@yourdomain.com"
$smtpPass = ConvertTo-SecureString "yourpassword" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($smtpUser, $smtpPass)

# Excluded processes
$excludedProcesses = @("Idle", "System", "svchost", "wininit", "csrss", "services", "lsass",
                        "smss", "winlogon", "conhost", "fontdrvhost", "WUDFHost", 
                        "WmiPrvSE", "dllhost")

# Get CPU count once
$cpuCount = (Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors

# Track when the last truncate happened
$lastTruncate = Get-Date
$insertCount = 0

while ($true) {
    $now = Get-Date
    $timestamp = $now.ToString("yyyy-MM-dd HH:mm:ss")
    $logDate = $now.ToString("yyyy-MM-dd")
    $machine = $env:COMPUTERNAME

    # TRUNCATE every 1 hour(s)
    $elapsed = ($now - $lastTruncate).TotalHours
    if ($elapsed -ge 1) {
        Write-Host "Truncating tables at $now"
        $truncateCmd = $connection.CreateCommand()
        $truncateCmd.CommandText = @"
            TRUNCATE TABLE dbo.system_metrics;
            TRUNCATE TABLE dbo.process_monitor;
"@
        $truncateCmd.ExecuteNonQuery() | Out-Null
        $lastTruncate = $now
    }

    # SYSTEM METRICS
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor
    $cpuName = $cpuInfo.Name
    $cpuLoad = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue, 2)
    $cpuCores = $cpuInfo.NumberOfLogicalProcessors
    $maxClock = $cpuInfo.MaxClockSpeed
    $currentClock = $cpuInfo.CurrentClockSpeed

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1024, 2)
    $freeMem = [math]::Round($os.FreePhysicalMemory / 1024, 2)
    $usedMem = [math]::Round($totalMem - $freeMem, 2)
    $memPercentUsed = [math]::Round(($usedMem / $totalMem) * 100, 2)

    $numProcesses = (Get-Process).Count
    $totalThreads = (Get-Process | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum
    $totalHandles = (Get-Process | Measure-Object -Property Handles -Sum).Sum

    $lastBootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptime = (New-TimeSpan -Start $lastBootTime -End $now).TotalSeconds

    $netSent = (Get-Counter '\Network Interface(*)\Bytes Sent/sec').CounterSamples | Measure-Object -Property CookedValue -Sum
    $netRecv = (Get-Counter '\Network Interface(*)\Bytes Received/sec').CounterSamples | Measure-Object -Property CookedValue -Sum
    $bytesSent = [math]::Round($netSent.Sum)
    $bytesRecv = [math]::Round($netRecv.Sum)

    $wifiInfo = netsh wlan show interfaces
    $wifiSignal = ($wifiInfo | Where-Object { $_ -match "^\s*Signal\s*:\s*\d+" }) -replace "^\s*Signal\s*:\s*", "" -replace "%", ""
    $wifiSignal = [int]($wifiSignal | Select-Object -First 1)
    $linkSpeed = ($wifiInfo | Where-Object { $_ -match "^\s*Receive rate\s*:\s*\d+" }) -replace "^\s*Receive rate\s*:\s*", ""
    $linkSpeedMbps = [int]($linkSpeed | Select-Object -First 1)

    $logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3"
    $totalDiskGB = 0
    $totalFreeGB = 0
    foreach ($disk in $logicalDisks) {
        $totalDiskGB += $disk.Size / 1GB
        $totalFreeGB += $disk.FreeSpace / 1GB
    }
    $usedDiskGB = [math]::Round($totalDiskGB - $totalFreeGB, 2)
    $totalDiskGB = [math]::Round($totalDiskGB, 2)
    $totalFreeGB = [math]::Round($totalFreeGB, 2)
    $diskUsedPercent = [math]::Round(($usedDiskGB / $totalDiskGB) * 100, 2)

    # Alert logic
    $alerts = @()
    if ($cpuLoad -ge $cpuThreshold) { $alerts += "CPU load is $cpuLoad%" }
    if ($memPercentUsed -ge $memThreshold) { $alerts += "RAM usage is $memPercentUsed%" }
    if ($diskUsedPercent -ge $diskThreshold) { $alerts += "Disk usage is $diskUsedPercent%" }

    if ($alerts.Count -gt 0) {
        $body = @"
The following resource thresholds have been exceeded on $machine at $timestamp :

$($alerts -join "`n")
"@
        Send-MailMessage -From $from -To $to -Subject $subject -Body $body -SmtpServer $smtpServer -Port $smtpPort -UseSsl -Credential $cred
        Write-Host "ALERT SENT: $body"
    }

    # Insert into system_metrics
    $cmdSys = $connection.CreateCommand()
    $cmdSys.CommandText = @"
INSERT INTO dbo.system_metrics (
    timestamp, log_date, cpu_count, total_physical_memory,
    total_net_sent, total_net_received, total_memory_mb, free_memory_mb,
    used_memory_mb, ram_percent_used, machine_name, cpu_name, cpu_load,
    max_clock_mhz, current_clock_mhz, process_count, thread_count, handle_count,
    system_uptime_seconds, signal_strength, link_speed_mbps, disk_total_gb,
    disk_used_gb, disk_free_gb
) VALUES (
    '$timestamp', '$logDate', $cpuCores, $($os.TotalVisibleMemorySize * 1024),
    $bytesSent, $bytesRecv, $totalMem, $freeMem, $usedMem, $memPercentUsed,
    '$machine', '$cpuName', $cpuLoad, $maxClock, $currentClock, $numProcesses,
    $totalThreads, $totalHandles, $uptime, $wifiSignal, $linkSpeedMbps,
    $totalDiskGB, $usedDiskGB, $totalFreeGB
)
"@
    $cmdSys.ExecuteNonQuery() | Out-Null

    # PROCESS METRICS
    $initialTimes = @{}
    Get-Process | ForEach-Object { $initialTimes[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds }
    Start-Sleep -Milliseconds 1000
    $finalTimes = @{}
    Get-Process | ForEach-Object { $finalTimes[$_.Id] = $_.TotalProcessorTime.TotalMilliseconds }

    $processes = Get-Process | Where-Object {
        $_.Name -notin $excludedProcesses -and $_.CPU -gt 0 -and $_.WorkingSet -gt 1MB
    }

    foreach ($p in $processes) {
        try {
            $delta = if ($finalTimes.ContainsKey($p.Id) -and $initialTimes.ContainsKey($p.Id)) {
                $finalTimes[$p.Id] - $initialTimes[$p.Id]
            } else { 0 }

            $cpuPercent1sec = [math]::Round(($delta / (1000 * $cpuCount)) * 100, 2)
            $uptime = ($now - $p.StartTime).TotalSeconds
            $cpuPercent = if ($uptime -gt 0) {
                [math]::Round(($p.TotalProcessorTime.TotalSeconds / $uptime) * 100, 2)
            } else { 0 }

            $escapedName = $p.Name -replace "'", "''"

            $cmdProc = $connection.CreateCommand()
            $cmdProc.CommandText = @"
INSERT INTO dbo.process_monitor (
    name, ram, cpu, timestamp, log_date, cpu_percent
) VALUES (
    '$escapedName', $($p.WorkingSet), $cpuPercent1sec,
    '$timestamp', '$logDate', $cpuPercent
)
"@
            $cmdProc.ExecuteNonQuery() | Out-Null
        } catch {
            Write-Host "Error inserting process $($p.Name): $($_.Exception.Message)"
        }
    }

    # Logging insert
    $insertCount++
    Write-Host "Insert number $insertCount at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    Start-Sleep -Seconds 1
}
