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

该 skill 包含两个脚本协同工作：

1. **list-layers.ps1** — PowerShell 入口脚本，负责连接 Photoshop、打开文件、调用 JSX 脚本、输出 JSON 文件
2. **list-layers.jsx** — Photoshop JSX 脚本，负责遍历所有图层并生成 JSON 数据

## 前置条件

- Windows 系统
- Adobe Photoshop 已安装并至少启动过一次（需要 COM 接口）
- PowerShell 执行策略允许运行脚本

## 使用方式

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_dir>\list-layers.ps1" "<PSD/PSB文件路径>"
```

其中 `<skill_dir>` 为本 skill 所在目录：
```
C:\Users\yanliangming.OASOFFICE\.kiro\skills\list-layers
```

### 示例

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\yanliangming.OASOFFICE\.kiro\skills\list-layers\list-layers.ps1" "G:\1.psb"
```

## 输出

- 输出文件位于源文件同目录，文件名格式为 `<源文件名>_layers.json`
- 例如输入 `G:\1.psb`，输出 `G:\1_layers.json`

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
        }
      ]
    }
  ]
}
```

## 字段说明

| 字段 | 说明 |
|------|------|
| `path` | 图层完整路径，可直接用于 ps-export.ps1 的 -Hide / -Show / -Export 参数 |
| `name` | 图层名称 |
| `type` | 图层类型（Group / NORMAL / TEXT 等） |
| `visible` | 图层是否可见 |
| `children` | 子图层数组（仅 Group 类型） |

## 注意事项

- 脚本会通过 COM 自动连接 Photoshop，如果 Photoshop 未运行会自动启动
- 打开文件时会保留所有图层，不会弹出对话框
- 支持 .psd 和 .psb 格式
- 输出文件使用 UTF-8 无 BOM 编码
