# Get basic disk info
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3"

foreach ($disk in $disks) {
    $deviceID = $disk.DeviceID
    $sizeGB = [math]::Round($disk.Size / 1GB, 2)
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    $usedGB = [math]::Round($sizeGB - $freeGB, 2)
    $usedPercent = [math]::Round(($usedGB / $sizeGB) * 100, 2)

    Write-Host "Drive: $deviceID"
    Write-Host "  Total Size: $sizeGB GB"
    Write-Host "  Used Space: $usedGB GB ($usedPercent%)"
    Write-Host "  Free Space: $freeGB GB"
}

# Get disk performance (read/write bytes per second and % active time)
$counterPaths = @(
    '\PhysicalDisk(*)\Disk Read Bytes/sec',
    '\PhysicalDisk(*)\Disk Write Bytes/sec',
    '\PhysicalDisk(*)\% Disk Time'
)

$counters = Get-Counter -Counter $counterPaths -ErrorAction SilentlyContinue
$counters.CounterSamples | ForEach-Object {
    $label = $_.Path
    $value = [math]::Round($_.CookedValue, 2)
    Write-Host "$label = $value"
}

