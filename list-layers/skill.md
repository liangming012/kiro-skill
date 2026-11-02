---
name: list-layers
description: 读取 Photoshop PSD/PSB 文件的图层结构，输出为 JSON 格式
triggers:
  - 图层
  - 图层结构
  - 图层列表
  - 查看图层
  - 列出图层
  - 读取图层
  - psd图层
  - psb图层
  - layer
  - layers
  - list layers
  - photoshop 图层
  - 图层信息
  - 图层路径
---

# List Layers Skill

读取 Photoshop PSD/PSB 文件的完整图层结构（包括隐藏图层），输出为 JSON 文件。

## 功能说明

该 skill 包含三个脚本协同工作：

1. **list-layers.ps1** — Windows PowerShell 入口脚本，负责连接 Photoshop、打开文件、调用 JSX 脚本、输出 JSON 文件
2. **list-layers.sh** — macOS 入口脚本，通过 AppleScript 完成与 ps1 相同的事情
3. **list-layers.jsx** — Photoshop JSX 脚本，负责遍历所有图层并生成 JSON 数据。Windows 和 macOS 共用

## 前置条件

### Windows

- Windows 系统
- Adobe Photoshop 已安装并至少启动过一次（需要 COM 接口）
- PowerShell 执行策略允许运行脚本

### macOS

- macOS
- Adobe Photoshop 已安装。脚本会优先连接已经在运行的版本；没运行时按 `com.adobe.Photoshop` 启动
- 首次调用需要在「系统设置 → 隐私与安全性 → 自动化」中允许终端控制 Photoshop
- 使用 `list-layers.sh`，不要在 macOS 上执行 `list-layers.ps1`

## 使用方式

### Windows

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File "<skill_dir>\list-layers.ps1" "<PSD/PSB文件路径>"
```

其中 `<skill_dir>` 为本 skill 所在目录：
```
C:\Users\yanliangming.OASOFFICE\.kiro\skills\list-layers
```

### macOS

```bash
# macOS
bash "<skill_dir>/list-layers.sh" "<PSD/PSB文件路径>"
```

其中 `<skill_dir>` 为本 skill 所在目录：
```
~/.kiro/skills/list-layers
```

### 示例

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File "C:\Users\yanliangming.OASOFFICE\.kiro\skills\list-layers\list-layers.ps1" "G:\1.psb"
```

```bash
# macOS
bash ~/.kiro/skills/list-layers/list-layers.sh "/path/to/1.psb"
```

## 输出

- 输出文件位于源文件同目录，文件名格式为 `<源文件名>_layers.json`
- Windows 示例：输入 `G:\1.psb`，输出 `G:\1_layers.json`
- macOS 示例：输入 `/path/to/1.psb`，输出 `/path/to/1_layers.json`
- 两个系统都写出 UTF-8 无 BOM 的 JSON

## JSON 结构

```json
{
  "document": "文件名.psb",
  "layers": [
    {
      "path": "Header",
      "name": "Header",
      "type": "Group",
      "visible": true,
      "children": [
        {
          "path": "Header/banner",
          "name": "banner",
          "type": "NORMAL",
          "visible": true
        },
        {
          "path": "Header/title",
          "name": "title",
          "type": "TEXT",
          "visible": true,
          "textStyle": {
            "fontSize": "24px",
            "fontName": "ArialMT",
            "fauxBold": false,
            "fauxItalic": false,
            "color": "#ffffff",
            "justification": "CENTER",
            "leading": "auto",
            "tracking": 0,
            "contents": "Hello World"
          }
        }
      ]
    }
  ]
}
```

## 字段说明

| 字段 | 说明 |
|------|------|
| `path` | 图层完整路径，可直接用于 ps-export.ps1（Windows）或 ps-export.sh（macOS）的 -Hide / -Show / -Export 参数 |
| `name` | 图层名称 |
| `type` | 图层类型（Group / NORMAL / TEXT 等） |
| `visible` | 图层是否可见 |
| `children` | 子图层数组（仅 Group 类型） |
| `textStyle` | 文本样式对象（仅 TEXT 类型图层） |

### textStyle 子字段（仅 TEXT 图层）

| 字段 | 说明 |
|------|------|
| `fontSize` | 字号，单位 px（如 `"24px"`） |
| `fontName` | 字体 PostScript 名称（如 `"ArialMT"`、`"NotoSansCJKsc-Bold"`） |
| `fauxBold` | 是否启用仿粗体（`true` / `false`） |
| `fauxItalic` | 是否启用仿斜体（`true` / `false`） |
| `color` | 文字颜色，十六进制格式（如 `"#ffffff"`） |
| `justification` | 对齐方式（`LEFT` / `CENTER` / `RIGHT`） |
| `leading` | 行距，单位 px；自动行距时为 `"auto"` |
| `tracking` | 字间距（整数值，0 为默认） |
| `contents` | 文本内容 |

## 注意事项

- Windows 上脚本会通过 COM 自动连接 Photoshop，如果 Photoshop 未运行会自动启动
- macOS 上脚本会通过 AppleScript 自动连接 Photoshop，如果 Photoshop 未运行会自动启动。装了多个版本时，优先使用已经打开的那一个
- 打开文件时会保留所有图层，不会弹出对话框
- 支持 .psd 和 .psb 格式
- 输出文件使用 UTF-8 无 BOM 编码
