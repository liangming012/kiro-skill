---
name: image-sizing-guide
description: 图片尺寸设置规范。当用户编写前端代码涉及图片时使用此 skill，包括但不限于：添加 img 标签、设置图片 width/height、编写图片相关 CSS/SCSS 样式、使用 background-image/background-size、在 Vue 模板中使用图片、引入图片资源并设置尺寸、移动端 rem 适配、PC 端图片样式、图片自适应、图片响应式、图片比例、图片拉伸变形、图片模糊、retina 适配、2倍图 3倍图、重新设置图片尺寸、调整图片大小、图片怎么设置大小、改图片宽高、图片尺寸不对、图片显示不正常等。适用于所有前端项目。
---

# 图片尺寸设置规范

## 触发场景

当用户进行以下**任何一项**工作时，必须使用此 skill：
- 在页面中添加、修改或替换图片元素（img 标签、background-image 等）
- 设置图片的 width、height、max-width、min-width 等尺寸属性
- 编写包含图片的 CSS/SCSS/Less 样式
- 在 Vue/HTML 模板中使用 img 标签或图片组件
- 设置 background-size、background 相关的尺寸
- 编写图片容器的样式（用于包裹图片的 div/span 等）
- 进行 PC 端或移动端（WAP）的图片适配
- 使用内联样式 style 设置图片尺寸
- 在代码中引入图片资源（import/require）并需要设置其显示尺寸

## 核心规则

### 1. 单位规则

| 端 | 单位 | 计算方式 |
|------|------|------|
| 移动端（WAP） | `rem` | 图片实际像素尺寸 ÷ 100 |
| PC 端 | `px` | 图片实际像素尺寸，直接使用 |

### 2. 尺寸计算方式

- **移动端**：获取图片文件的实际宽高像素值，除以 100，得到 rem 值
  - 例：图片实际宽度 300px → CSS 中写 `width: 3rem`
  - 例：图片实际高度 150px → CSS 中写 `height: 1.5rem`

- **PC 端**：获取图片文件的实际宽高像素值，直接作为 px 值使用
  - 例：图片实际宽度 300px → CSS 中写 `width: 300px`
  - 例：图片实际高度 150px → CSS 中写 `height: 150px`

### 3. 默认行为

当无法判断当前代码属于 PC 端还是移动端时，**默认使用 PC 端的 px 单位**。

## 操作流程

**强制约束：必须先获取图片实际尺寸，再编写样式代码。禁止凭记忆或估算填写尺寸值。**

设置图片尺寸时，按以下步骤执行：

### 第一步：获取图片实际尺寸

使用终端命令获取图片文件的实际宽高像素值：

```bash
# macOS
sips -g pixelWidth -g pixelHeight 图片路径

# Linux
file 图片路径
# 或
identify 图片路径   # 需要 ImageMagick
```

```powershell
# Windows PowerShell
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile("图片绝对路径")
Write-Host "pixelWidth: $($img.Width)"
Write-Host "pixelHeight: $($img.Height)"
$img.Dispose()
```

### 第二步：判断所属端

根据文件路径、组件名称、样式上下文判断是 PC 端还是移动端：

| 判断依据 | 归属 |
|----------|------|
| 文件名或路径包含 `Pc`、`pc`、`desktop` | PC 端 |
| 文件名或路径包含 `wap`、`mobile`、`m-` | 移动端 |
| 图片资源位于 `pc/` 目录下 | PC 端 |
| 图片资源位于 `wap/`、`mobile/` 目录下 | 移动端 |
| 当前组件/文件的样式中已有 rem 尺寸且符合 ÷100 规律 | 移动端 |
| 以上均无法判断 | **默认 PC 端** |

### 第三步：计算并设置尺寸

- 移动端：实际像素值 ÷ 100 = rem 值
- PC 端：实际像素值 = px 值

## 示例

### 移动端 — CSS class 样式

假设图片 `banner.png` 实际尺寸为 750×200 像素：

```scss
.banner {
  width: 7.5rem;    // 750 ÷ 100
  height: 2rem;     // 200 ÷ 100
}
```

### 移动端 — 内联样式（Vue 模板）

```html
<img :src="bannerImg" :style="{ width: '7.5rem', height: '2rem' }" />
```

### PC 端 — CSS class 样式

假设图片 `banner.png` 实际尺寸为 1200×300 像素：

```scss
.banner {
  width: 1200px;
  height: 300px;
}
```

### PC 端 — 内联样式（Vue 模板）

```html
<img :src="bannerImg" :style="{ width: '1200px', height: '300px' }" />
```

### 背景图片

```scss
// 移动端 — 背景图实际尺寸 600×400
.bg-section {
  width: 6rem;
  height: 4rem;
  background: url('~@/assets/wap/bg.png') no-repeat center;
  background-size: 6rem 4rem;
}

// PC 端 — 背景图实际尺寸 600×400
.bg-section {
  width: 600px;
  height: 400px;
  background: url('~@/assets/pc/bg.png') no-repeat center;
  background-size: 600px 400px;
}
```

## 注意事项

- 始终以图片文件的实际物理像素尺寸为准，不要凭感觉估算
- 移动端除以 100 的规则基于设计稿基准宽度 750px 的 rem 适配方案（1rem = 根字体大小，html font-size 按屏幕宽度动态计算）
- 如果只需要设置宽度或高度其中之一，另一个维度使用 `auto` 保持比例（推荐优先只设宽度）
- 大多数场景推荐只设置 `width`，让 `height: auto` 自适应，避免图片变形；仅在明确需要固定高度（如背景图容器、固定尺寸头像）时才同时设置宽高
- 背景图片的 `background-size` 同样遵循此规则
- 设置尺寸时注意保持宽高比，避免图片变形
