# Gmail SMTP configuration (without 2FA)
$smtpServer = "smtp.gmail.com"
$smtpPort = 587
$from = "stuurmanmzwandile@gmail.com"
$to = "mzwandile.stuurman@slipstreamdata.co.za"  # or recipient address
$subject = "ALERT: Server Resource Usage Exceeded"
$smtpUser = "stuurmanmzwandile@gmail.com"
$smtpPass = ConvertTo-SecureString "stuurmanmzwandile@gmail.com" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($smtpUser, $smtpPass)

Send-MailMessage -From $from -To $to -Subject "Test Email" -Body "This is a test from PowerShell" `
    -SmtpServer $smtpServer -Port $smtpPort -UseSsl -Credential $cred
