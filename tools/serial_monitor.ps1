# =============================================================
#  串口监视器（不需要装任何软件）
#  用法:
#    powershell -ExecutionPolicy Bypass -File serial_monitor.ps1 -List
#    powershell -ExecutionPolicy Bypass -File serial_monitor.ps1
#    powershell -ExecutionPolicy Bypass -File serial_monitor.ps1 -Port COM5
# =============================================================
param(
    [string]$Port,
    [int]$Baud = 115200,
    [switch]$List
)

$ports = [System.IO.Ports.SerialPort]::GetPortNames()

if ($List -or -not $Port) {
    Write-Host "当前可用串口:"
    if (-not $ports) {
        Write-Host "  (没有检测到任何串口)" -ForegroundColor Yellow
        Write-Host "  检查: USB 线是否插在板子的 BL616 那个 Type-C 口;"
        Write-Host "        设备管理器 -> 端口(COM 和 LPT) 里有没有设备"
        exit 1
    }
    foreach ($p in $ports) { Write-Host "  $p" }
    if ($List) { exit 0 }
    $Port = $ports[0]
    Write-Host "自动选择: $Port" -ForegroundColor Cyan
}

try {
    $sp = New-Object System.IO.Ports.SerialPort(
        $Port, $Baud,
        [System.IO.Ports.Parity]::None,
        8,
        [System.IO.Ports.StopBits]::One)
    $sp.NewLine     = "`r`n"
    $sp.ReadTimeout = 2000
    $sp.Open()
} catch {
    Write-Host "打开 $Port 失败: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "常见原因: 端口被别的软件占用 / 选错端口 / 驱动没装"
    exit 1
}

Write-Host "已打开 $Port @ $Baud 8N1，按 Ctrl+C 退出" -ForegroundColor Green
Write-Host "期望看到:  Sxxxx Txxxx Dxxx   （16 进制）" -ForegroundColor DarkGray
Write-Host ""

try {
    while ($true) {
        try {
            $line = $sp.ReadLine()
            "{0:HH:mm:ss}  {1}" -f (Get-Date), $line.Trim()
        } catch [System.TimeoutException] {
            # 2 秒没数据就继续等
        }
    }
} finally {
    if ($sp.IsOpen) { $sp.Close() }
    Write-Host "串口已关闭"
}
