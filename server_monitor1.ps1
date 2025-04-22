Add-Type -AssemblyName System.Data

# DB connection
$connectionString = "DSN=PostgreSQL_DNS;UID=postgres;PWD=mzwandile;"
$connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)
$connection.Open()

# System Info (for KPI table)
$cpuCount = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
$totalRAM = (Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$machine = $env:COMPUTERNAME

# Use Get-Counter for network stats
$netSent = (Get-Counter '\Network Interface(*)\Bytes Sent/sec').CounterSamples | Measure-Object -Property CookedValue -Sum
$netRecv = (Get-Counter '\Network Interface(*)\Bytes Received/sec').CounterSamples | Measure-Object -Property CookedValue -Sum

$bytesSent = [math]::Round($netSent.Sum)
$bytesRecv = [math]::Round($netRecv.Sum)



# Insert System KPIs
$sysCmd = $connection.CreateCommand()
$sysCmd.CommandText = @"
INSERT INTO system_metrics (
    timestamp, cpu_count, total_physical_memory, total_net_sent, total_net_received, machine_name
) VALUES (
    '$timestamp', $cpuCount, $totalRAM, $bytesSent, $bytesRecv, '$machine'
)
"@
$sysCmd.ExecuteNonQuery() | Out-Null

# Per-process collection
$processes = Get-Process
foreach ($p in $processes) {
    try {
        $cmd = $connection.CreateCommand()

        $escapedName = $p.Name -replace "'", "''"
        $machine = $env:COMPUTERNAME
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

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

        $startTime =  $p.StartTime.ToString("yyyy-MM-dd HH:mm:ss")
        $hasExited = $p.HasExited
        $responding = $p.Responding

        $readBytes = if ($p.IO) { $p.IO.ReadTransferCount } else { 0 }
        $writeBytes = if ($p.IO) { $p.IO.WriteTransferCount } else { 0 }
        $otherBytes = if ($p.IO) { $p.IO.OtherTransferCount } else { 0 }
        $totalDiskIO = $readBytes + $writeBytes + $otherBytes

        $cmd.CommandText = @"
INSERT INTO process_monitor (
    name, session_id, ws, vm, private_mem, working_set,
    virtual_mem, paged_mem, peak_ws, peak_vm, max_ws, cpu,
    priv_proc_time, user_proc_time, total_proc_time, processor_affinity,
    start_time, has_exited, responding, machine_name,
    read_bytes, write_bytes, other_bytes, total_disk_io, timestamp
) VALUES (
    '$escapedName', $si, $ws, $vm, $privMem, $workingSet,
    $virtMem, $pagedMem, $peakWS, $peakVM, $maxWS, $cpu,
    $privSecs, $userSecs, $totalSecs, '$affinity',
    '$startTime', '$hasExited', '$responding', '$machine',
    $readBytes, $writeBytes, $otherBytes, $totalDiskIO, '$timestamp'
)
"@
        $cmd.ExecuteNonQuery() | Out-Null
        Write-Host "Inserted: $escapedName"
    } catch {
        Write-Host "Error inserting $($p.Name): $($_.Exception.Message)"
    }
}


$connection.Close()
