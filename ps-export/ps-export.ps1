# ps-export.ps1
# ============================================================
# PowerShell 脚本：打开 PSD/PSB 文件并调用 Photoshop 导出 PNG
# ============================================================
#
# 使用示例：
#   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb"
#   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb" -Hide "Header/watermark","Footer/old"
#   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb" -Show "Header/new logo"
#   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb" -Export "Header/banner","Content/icon"
#   powershell -ExecutionPolicy Bypass -File "G:\ps-export.ps1" "G:\1.psb" -Hide "Header/watermark" -Export "Header/banner"
#
# 参数说明：
#   PsdPath  （必填）- PSD/PSB 文件路径
#   -Hide    （可选）- 导出前要隐藏的图层路径，多个用英文逗号分隔
#   -Show    （可选）- 导出前要显示的图层路径，多个用英文逗号分隔
#   -Export  （可选）- 要单独导出的图层路径，多个用英文逗号分隔
#                      如果不指定，则导出完整页面
#
# 图层路径格式：
#   "组名/子组名/图层名" - 精确路径
#   "图层名"             - 顶层图层
#
# 输出文件（保存在源文件同目录下）：
#   完整页面模式：export.png
#   单独图层模式：Header_banner.png、Content_icon.png 等
#
# 前提条件：
#   - 本机已安装 Adobe Photoshop
#   - ps-export.jsx 与本脚本在同一目录下
#
# ============================================================

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$PsdPath,
    [string[]]$Hide = @(),
    [string[]]$Show = @(),
    [string[]]$Export = @(),
    [int]$Timeout = 300
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- 超时看门狗 ---
# 启动一个独立的后台 PowerShell 进程来监控超时
# 当超时触发时，后台进程会杀掉本脚本进程
$currentPid = $PID
$watchdogProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -Command `"Start-Sleep -Seconds $Timeout; Stop-Process -Id $currentPid -Force -ErrorAction SilentlyContinue`"" -WindowStyle Hidden -PassThru
Write-Host "Timeout set to $Timeout seconds (watchdog PID: $($watchdogProc.Id))." -ForegroundColor Gray

if (-not (Test-Path $PsdPath)) {
    Write-Error "File not found: $PsdPath"
    exit 1
}

# --- 校验支持的文件格式 ---
$ext = [System.IO.Path]::GetExtension($PsdPath).ToLower()
if ($ext -ne ".psd" -and $ext -ne ".psb") {
    Write-Error "Unsupported file format: $ext (only .psd and .psb are supported)"
    exit 1
}

$jsxPath = Join-Path $PSScriptRoot "ps-export.jsx"

if (-not (Test-Path $jsxPath)) {
    Write-Error "ps-export.jsx not found, make sure it is in the same folder as this script"
    exit 1
}

$PsdPath = (Resolve-Path $PsdPath).Path
$jsxPath = (Resolve-Path $jsxPath).Path

$jsxPsdPath = $PsdPath.Replace('\', '/')

# --- 连接 Photoshop ---
Write-Host "Connecting to Photoshop..." -ForegroundColor Cyan

# 如果 Photoshop 未运行，先启动它
$psProcess = Get-Process -Name "Photoshop" -ErrorAction SilentlyContinue
if (-not $psProcess) {
    Write-Host "Photoshop is not running, starting it..." -ForegroundColor Yellow
    Start-Process "Photoshop"
    Start-Sleep -Seconds 10
    # 等待 Photoshop 进程出现
    $waitStart = Get-Date
    while (-not (Get-Process -Name "Photoshop" -ErrorAction SilentlyContinue)) {
        if (((Get-Date) - $waitStart).TotalSeconds -ge 60) {
            Write-Error "Photoshop process did not start within 60 seconds."
            exit 1
        }
        Start-Sleep -Seconds 3
    }
    # 额外等待 PS 完全初始化
    Write-Host "Waiting for Photoshop to initialize..." -ForegroundColor Gray
    Start-Sleep -Seconds 15
}

# 建立 COM 连接（重试机制）
$comRetry = 0
$comMaxRetry = 10
$ps = $null
while ($comRetry -lt $comMaxRetry) {
    try {
        $ps = New-Object -ComObject Photoshop.Application
        break
    } catch {
        $comRetry++
        if ($comRetry -ge $comMaxRetry) {
            Write-Error "Cannot connect to Photoshop after $comMaxRetry attempts. Make sure it is installed."
            exit 1
        }
        Write-Host "  COM connection attempt $comRetry failed, retrying in 5s..." -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

# 等待 Photoshop 响应
$waitStart = Get-Date
$maxWaitSec = 120
while ($true) {
    try {
        $null = $ps.Version
        break
    } catch {
        $elapsed = ((Get-Date) - $waitStart).TotalSeconds
        if ($elapsed -ge $maxWaitSec) {
            Write-Error "Photoshop did not become ready within $maxWaitSec seconds."
            exit 1
        }
        Start-Sleep -Seconds 3
    }
}
Write-Host "Photoshop is ready (version $($ps.Version))." -ForegroundColor Gray

# --- 打开文件（保留图层，不弹对话框）---
$openScript = 'var file = new File("' + $jsxPsdPath + '");'
$openScript += ' try { var opts = new PhotoshopOpenOptions(); opts.preserveLayers = true; app.open(file, opts); }'
$openScript += ' catch (e) { var desc = new ActionDescriptor(); desc.putPath(charIDToTypeID("null"), file);'
$openScript += ' desc.putBoolean(stringIDToTypeID("preserveLayers"), true);'
$openScript += ' app.executeAction(charIDToTypeID("Opn "), desc, DialogModes.NO); }'

Write-Host "Opening (preserve layers): $PsdPath" -ForegroundColor Cyan

try {
    $ps.DoJavaScript($openScript)
} catch {
    Write-Error "Failed to open file in Photoshop: $_"
    exit 1
}

# --- 处理参数（支持逗号分隔的写法）---
# PowerShell -File 模式下 "a","b" 可能被解析为单个字符串 "a,b"
# 这里统一按逗号拆分
$Hide = @($Hide | ForEach-Object { $_ -split "," } | Where-Object { $_.Trim() -ne "" })
$Show = @($Show | ForEach-Object { $_ -split "," } | Where-Object { $_.Trim() -ne "" })
$Export = @($Export | ForEach-Object { $_ -split "," } | Where-Object { $_.Trim() -ne "" })

# --- 构建 JSON 参数 ---
$hideJson = ($Hide | ForEach-Object { "`"$_`"" }) -join ","
$showJson = ($Show | ForEach-Object { "`"$_`"" }) -join ","
$exportJson = ($Export | ForEach-Object { "`"$_`"" }) -join ","
$argsJson = '{"hide":[' + $hideJson + '],"show":[' + $showJson + '],"export":[' + $exportJson + ']}'

# Write args to a temp file (avoids all quoting/escape issues)
$argsTempFile = Join-Path $env:TEMP "ps-export-args.json"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($argsTempFile, $argsJson, $utf8NoBom)
$argsTempFileForward = $argsTempFile.Replace('\', '/')

# Debug: show actual JSON content
Write-Host "Args JSON: $argsJson" -ForegroundColor Gray

if ($Hide.Count -gt 0) {
    Write-Host "Hide layers: $($Hide -join ', ')" -ForegroundColor Yellow
}
if ($Show.Count -gt 0) {
    Write-Host "Show layers: $($Show -join ', ')" -ForegroundColor Yellow
}
if ($Export.Count -gt 0) {
    Write-Host "Export layers: $($Export -join ', ')" -ForegroundColor Yellow
} else {
    Write-Host "Export mode: full page" -ForegroundColor Yellow
}

Write-Host "Exporting PNG..." -ForegroundColor Cyan

# --- 执行导出 ---
$jsxPathForward = $jsxPath.Replace('\', '/')
$wrapScript = 'var argsFile = new File("' + $argsTempFileForward + '"); argsFile.open("r"); argsFile.encoding = "UTF-8"; var __args = argsFile.read(); argsFile.close(); $.evalFile(new File("' + $jsxPathForward + '"));'

try {
    $result = $ps.DoJavaScript($wrapScript)
} catch {
    Remove-Item $argsTempFile -ErrorAction SilentlyContinue
    Write-Error "Photoshop script execution failed: $_"
    exit 1
}

# Clean up temp file
Remove-Item $argsTempFile -ErrorAction SilentlyContinue

# --- 处理空结果 ---
Stop-Process -Id $watchdogProc.Id -Force -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($result)) {
    Write-Error "No result returned from Photoshop. Export may have failed."
    exit 1
}

# --- 显示结果 ---
if ($result -like "ERROR:*") {
    Write-Host ""
    Write-Host $result -ForegroundColor Red
    Write-Host ""
    $listLayersPath = Join-Path $PSScriptRoot "..\list-layers\list-layers.ps1"
    Write-Host "Tip: Use list-layers.ps1 to get the correct layer paths:" -ForegroundColor Cyan
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$listLayersPath`" `"$PsdPath`"" -ForegroundColor Cyan
} else {
    $lines = $result -split "`n"
    $exported = @()
    $warns = @()
    foreach ($line in $lines) {
        if ($line -like "WARNING:*") {
            $warns += $line
        } elseif ($line.Trim() -ne "") {
            $exported += $line
        }
    }
    if ($exported.Count -gt 0) {
        Write-Host "Done! Exported to:" -ForegroundColor Green
        foreach ($p in $exported) { Write-Host "  $p" }
    }
    if ($warns.Count -gt 0) {
        Write-Host ""
        foreach ($w in $warns) { Write-Host $w -ForegroundColor Yellow }
        Write-Host ""
        $listLayersPath = Join-Path $PSScriptRoot "..\list-layers\list-layers.ps1"
        Write-Host "Tip: Use list-layers.ps1 to check layer paths:" -ForegroundColor Cyan
        Write-Host "  powershell -ExecutionPolicy Bypass -File `"$listLayersPath`" `"$PsdPath`"" -ForegroundColor Cyan
    }
}
