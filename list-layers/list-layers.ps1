# list-layers.ps1
# ============================================================
# PowerShell 脚本：读取 PSD/PSB 图层信息，输出为 JSON 文件
# ============================================================
#
# 使用示例：
#   powershell -ExecutionPolicy Bypass -File "G:\list-layers.ps1" "G:\1.psb"
#
# 输出文件：
#   与源文件同目录，文件名为 "源文件名_layers.json"
#   例如：G:\1_layers.json
#
# JSON 中的 path 字段可直接复制给 ps-export.ps1 的 -Hide / -Show / -Export 参数使用
#
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$PsdPath
)

# --- 设置输出编码为 UTF-8（支持多语言字符显示）---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- 校验输入文件 ---
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

$jsxPath = Join-Path $PSScriptRoot "list-layers.jsx"

if (-not (Test-Path $jsxPath)) {
    Write-Error "list-layers.jsx not found, make sure it is in the same folder as this script"
    exit 1
}

$PsdPath = (Resolve-Path $PsdPath).Path
$jsxPath = (Resolve-Path $jsxPath).Path

$jsxPsdPath = $PsdPath.Replace('\', '/')

# --- 连接 Photoshop ---
Write-Host "Connecting to Photoshop..." -ForegroundColor Cyan

try {
    $ps = New-Object -ComObject Photoshop.Application
} catch {
    Write-Error "Cannot connect to Photoshop. Make sure it is installed and has been launched at least once."
    exit 1
}

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

# --- 读取图层信息 ---
Write-Host "Reading layers..." -ForegroundColor Cyan

# 先获取图层总数（快速）
$countScript = '(function() { var doc = app.activeDocument; function count(layers) { var n = 0; for (var i = 0; i < layers.length; i++) { n++; if (layers[i].typename === "LayerSet") n += count(layers[i].layers); } return n; } return count(doc.layers).toString(); })();'

try {
    $totalLayers = $ps.DoJavaScript($countScript)
    Write-Host "  Found $totalLayers layers, reading details..." -ForegroundColor Gray
} catch {
    Write-Host "  Counting layers failed, reading anyway..." -ForegroundColor Gray
}

try {
    $result = $ps.DoJavaScriptFile($jsxPath)
} catch {
    Write-Error "Failed to read layers: $_"
    exit 1
}

Write-Host "  Read complete." -ForegroundColor Gray

# --- 检查 JSX 返回结果 ---
if ($result -like '*"error"*') {
    Write-Host ""
    Write-Host "ERROR: Photoshop returned an error:" -ForegroundColor Red
    Write-Host $result
    exit 1
}

if ([string]::IsNullOrWhiteSpace($result)) {
    Write-Error "No result returned from Photoshop. The file may be corrupted or empty."
    exit 1
}

# --- 输出 JSON 文件 ---
$psdDir = Split-Path $PsdPath -Parent
$psdName = [System.IO.Path]::GetFileNameWithoutExtension($PsdPath)
$jsonPath = Join-Path $psdDir "$($psdName)_layers.json"

# 以 UTF-8 无 BOM 格式写入
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($jsonPath, $result, $utf8NoBom)

# --- 显示结果 ---
$fileSize = (Get-Item $jsonPath).Length
$fileSizeKB = [math]::Round($fileSize / 1024, 1)
Write-Host ""
Write-Host "Done! JSON saved to: $jsonPath ($fileSizeKB KB)" -ForegroundColor Green
Write-Host ""
Write-Host "Tip: Use the 'path' field in JSON as layer path for ps-export.ps1:" -ForegroundColor Cyan
Write-Host "  powershell -ExecutionPolicy Bypass -File `"G:\ps-export.ps1`" `"$PsdPath`" -Export `"path/to/layer`"" -ForegroundColor Cyan
