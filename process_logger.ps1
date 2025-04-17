Add-Type -AssemblyName System.Data

$connectionString = "DSN=PostgreSQL_DNS;UID=postgres;PWD=mzwandile;"
$connection = New-Object System.Data.Odbc.OdbcConnection($connectionString)
$connection.Open()

$processes = Get-Process

foreach ($p in $processes) {
    try {
        $cmd = $connection.CreateCommand()

        $escapedName = $p.Name -replace "'", "''"
        $machine = $env:COMPUTERNAME

        $cmd.CommandText = @"
INSERT INTO process_monitor (
    name, session_id, ws, vm, private_mem, working_set,
    virtual_mem, paged_mem, peak_ws, peak_vm, max_ws, cpu,
    priv_proc_time, user_proc_time, total_proc_time, processor_affinity,
    start_time, has_exited, responding, machine_name
) VALUES (
    '$escapedName', $($p.SI), $($p.WS), $($p.VM), $($p.PrivateMemorySize), $($p.WorkingSet),
    $($p.VirtualMemorySize), $($p.PagedMemorySize), $($p.PeakWorkingSet), $($p.PeakVirtualMemorySize), $($p.MaxWorkingSet), $($p.CPU),
    '$($p.PrivilegedProcessorTime)', '$($p.UserProcessorTime)', '$($p.TotalProcessorTime)', '$($p.ProcessorAffinity)',
    '$($p.StartTime)', $($p.HasExited), $($p.Responding), '$machine'
)
"@

        $cmd.ExecuteNonQuery() | Out-Null
        Write-Host "Inserted: $escapedName"
    } catch {
        Write-Host "Error inserting $($p.Name): $($_.Exception.Message)"
    }
}

$connection.Close()
