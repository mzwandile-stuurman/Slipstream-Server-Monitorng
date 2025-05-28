# Run netsh and capture output
$wifiInfo = netsh wlan show interfaces

# Extract signal strength (percent)
$wifiSignal = ($wifiInfo | Where-Object { $_ -match "^\s*Signal\s*:\s*\d+" }) -replace "^\s*Signal\s*:\s*", "" -replace "%", ""
$wifiSignal = [int]($wifiSignal | Select-Object -First 1)

# Extract link speed (Receive rate in Mbps)
$linkSpeed = ($wifiInfo | Where-Object { $_ -match "^\s*Receive rate\s*:\s*\d+" }) -replace "^\s*Receive rate\s*:\s*", ""
$linkSpeedMbps = [int]($linkSpeed | Select-Object -First 1)
Write-Host "Wi-Fi Signal Strength: $wifiSignal%"
Write-Host "Wi-Fi Link Speed: $linkSpeedMbps Mbps"

