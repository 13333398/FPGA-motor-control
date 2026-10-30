# 启动本地服务器，等待服务器就绪后打开支持 Web Serial 的浏览器
$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$port = 8000
$url = "http://127.0.0.1:$port/dashboard.html"
$python = Get-Command python -ErrorAction SilentlyContinue

if (-not $python) {
    Write-Host "未找到 Python。请安装 Python 3，或手动运行本地静态服务器。" -ForegroundColor Red
    Read-Host "按回车键退出"
    exit 1
}

$browser = $null
foreach ($candidate in @(
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
)) {
    if (Test-Path -LiteralPath $candidate) {
        $browser = $candidate
        break
    }
}

$listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Host "端口 $port 已有服务运行，直接打开页面。" -ForegroundColor Cyan
    if ($browser) {
        Start-Process -FilePath $browser -ArgumentList "--new-window", $url
    } else {
        Start-Process $url
    }
    Read-Host "按回车键退出"
    exit 0
}

$openBrowser = {
    param($target, $exe)
    Start-Sleep -Seconds 1
    if ($exe) {
        Start-Process -FilePath $exe -ArgumentList "--new-window", $target
    } else {
        Start-Process $target
    }
}

$browserJob = Start-Job -ScriptBlock $openBrowser -ArgumentList $url, $browser
Write-Host "正在启动 http://127.0.0.1:$port/dashboard.html" -ForegroundColor Cyan
Write-Host "关闭本窗口即可停止服务器。" -ForegroundColor DarkGray

try {
    & $python.Source -m http.server $port --bind 127.0.0.1
} finally {
    Stop-Job $browserJob -ErrorAction SilentlyContinue
    Remove-Job $browserJob -Force -ErrorAction SilentlyContinue
}
