---
name: ps-export
description: 通过 Photoshop 导出 PSD/PSB 文件中的图层或完整页面为 PNG
---

# PS Export Skill

通过 Photoshop 导出 PSD/PSB 文件中的图层或完整页面为 PNG 图片。支持导出前隐藏/显示指定图层。

## 功能说明

该 skill 包含两个脚本协同工作：

1. **ps-export.ps1** — PowerShell 入口脚本，负责连接 Photoshop、打开文件、传递参数、调用 JSX 脚本
2. **ps-export.jsx** — Photoshop JSX 脚本，负责操作图层可见性并导出 PNG

## 前置条件

- Windows 系统
- Adobe Photoshop 已安装并至少启动过一次（需要 COM 接口）
- PowerShell 执行策略允许运行脚本

## 使用方式

```powershell
powershell -ExecutionPolicy Bypass -File "<skill_dir>\ps-export.ps1" "<PSD/PSB文件路径>" [-Hide "路径1","路径2"] [-Show "路径1"] [-Export "路径1","路径2"]
```

其中 `<skill_dir>` 为本 skill 所在目录：
```
C:\Users\yanliangming.OASOFFICE\.kiro\skills\ps-export
```

## 参数说明

| 参数 | 必填 | 说明 |
|------|------|------|
| `PsdPath` | 是 | PSD/PSB 文件路径 |
| `-Hide` | 否 | 导出前要隐藏的图层路径，多个用逗号分隔 |
| `-Show` | 否 | 导出前要显示的图层路径，多个用逗号分隔 |
| `-Export` | 否 | 要单独导出的图层路径，多个用逗号分隔。不指定则导出完整页面 |

## 图层路径格式

- 精确路径：`"组名/子组名/图层名"`
- 顶层图层：`"图层名"`
- 路径分隔符：`/`
- 路径可通过 list-layers skill 获取

## 示例

### 导出完整页面

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\yanliangming.OASOFFICE\.kiro\skills\ps-export\ps-export.ps1" "G:\1.psb"
```

### 隐藏图层后导出完整页面

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\yanliangming.OASOFFICE\.kiro\skills\ps-export\ps-export.ps1" "G:\1.psb" -Hide "Header/watermark","Footer/old"
```

### 显示图层后导出完整页面

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\yanliangming.OASOFFICE\.kiro\skills\ps-export\ps-export.ps1" "G:\1.psb" -Show "Header/new logo"
```

### 导出指定图层为单独 PNG

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\yanliangming.OASOFFICE\.kiro\skills\ps-export\ps-export.ps1" "G:\1.psb" -Export "Header/banner","Content/icon"
```

### 组合使用：隐藏图层 + 导出指定图层

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\yanliangming.OASOFFICE\.kiro\skills\ps-export\ps-export.ps1" "G:\1.psb" -Hide "Header/watermark" -Export "Header/banner"
```

## 执行逻辑

1. 执行 -Hide：隐藏指定图层
2. 执行 -Show：显示指定图层
3. 判断 -Export 参数：
   - 没有：合并所有可见图层，导出完整页面为 `export.png`
   - 有：逐个导出指定图层为单独 PNG（文件名为图层路径，`/` 替换为 `_`）
   - 如果指定的图层路径不存在，报错并中止
4. 还原所有图层的可见性到脚本执行前的状态

## 输出文件

输出文件保存在源 PSD/PSB 文件同目录下：

| 模式 | 输出文件名 |
|------|-----------|
| 完整页面 | `export.png` |
| 单独图层 | `Header_banner.png`、`Content_icon.png` 等 |

## 注意事项

- 脚本会通过 COM 自动连接 Photoshop，如果 Photoshop 未运行会自动启动
- 打开文件时会保留所有图层，不会弹出对话框
- 导出完成后会自动还原所有图层可见性
- 支持 .psd 和 .psb 格式
- 单独导出图层时会自动裁剪透明区域
- 建议先用 list-layers skill 获取正确的图层路径
- 支持 `-Timeout` 参数（默认 300 秒），超时后自动终止脚本

## AI 调用注意事项

- 脚本通过后台进程执行，Photoshop 操作（打开文件、导出图层）耗时较长，属于正常现象
- **检查输出频率：每隔 5 秒读取一次终端输出即可，不要连续密集轮询**
- 对于大型 PSB 文件（数百图层），打开文件可能需要 1-3 分钟，导出单个图层需要 30 秒到 2 分钟
- 脚本完成的标志是输出中出现 `Done!`（成功）或 `ERROR:`（失败）或进程退出
- 如果长时间（超过 Timeout 值）没有新输出，说明 Photoshop 可能卡死，看门狗会自动终止脚本
