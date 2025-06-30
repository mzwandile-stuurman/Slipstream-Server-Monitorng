Add-Type -AssemblyName System.Data

# SQL authentication details
$server = "34.250.17.80"
$database = "server_monitoring"
$username = "Slipstream_adm"
$password = "Slip2020!"

# Connection string with SQL auth
$connectionString = "Server=$server;Database=$database;User ID=$username;Password=$password;Encrypt=True;TrustServerCertificate=True;"

# Open SQL connection
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$connection.Open()
Write-Host "Connected to SQL Server at $server"
