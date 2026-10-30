# 只列串口，不打开
$ports = [System.IO.Ports.SerialPort]::GetPortNames()
if (-not $ports) {
    Write-Host "没有检测到串口" -ForegroundColor Yellow
} else {
    foreach ($p in $ports) { Write-Host $p }
}
