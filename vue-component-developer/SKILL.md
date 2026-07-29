---
name: vue2-development-guide
description: Vue 2 Options API 开发规范与最佳实践，含 Playwright 端到端测试。当用户编写 Vue 2 组件、页面、状态管理、API 接口等代码时使用此 skill，包括但不限于：写 Vue 组件、写页面、写 Vuex、写 store、写 mixins、写 computed、写 watch、写生命周期钩子、Vue 最佳实践、Options API 写法、Vue2 怎么写、组件通信、props 定义、$emit 事件、Vue 路由页面、Vue 过滤器、Vue 指令等。完成功能开发后自动编写 Playwright 测试脚本验证功能正确性。适用于所有 Vue 2 项目。
---

# Vue 2 开发规范

## 触发场景

当用户在 Vue 2 项目中进行以下工作时使用此 skill：
- 编写或修改 Vue 组件
- 添加 Vuex 状态管理
- 添加 API 接口
- 配置路由
- 需要遵循 Vue 2 最佳实践的任何代码编写

## 工作流程总览

每次功能开发或修改的完整流程：

1. **编码阶段**：按照本规范编写 Vue 2 代码，组件中关键交互元素添加 `data-testid`
2. **测试环境检查**：确认项目是否已安装 Playwright，未安装则自动安装并初始化配置
3. **编写测试**：在 `e2e/` 目录编写对应功能的 Playwright 测试脚本
4. **运行测试**：执行测试脚本验证功能正确性
5. **失败分析**：如果测试失败，分析是功能代码问题还是测试脚本问题，分别修复
6. **确认通过**：所有相关测试通过后，开发完成

## 核心原则

1. **状态可预测**：保持单一数据源，尽量用 computed 派生状态，不存储冗余 data
2. **数据流显式**：Props 向下传递，Events 向上冒泡，避免隐式的跨组件通信
3. **组件职责单一**：每个组件只做一件事——要么负责渲染展示，要么负责逻辑编排
4. **避免不必要的重渲染**：正确使用 computed 和 watch，模板中不做复杂计算
5. **可读性优先**：写清晰的、自文档化的代码，宁可多几行也不要晦涩的简写

## 编码前确认

1. 明确需求影响的文件范围：组件、store、API、路由、i18n
2. 规划组件边界：明确每个组件的单一职责，定义好 props/events 契约
3. 确认是否需要响应式适配（PC/移动端）
4. 确认是否涉及多语言

## 组件结构规范

### SFC 模板

```vue
<template>
  <div class="component-name">
    <!-- 模板内容 -->
  </div>
</template>

<script>
export default {
  name: "ComponentName",
  components: {},
  props: {},
  data() {
    return {};
  },
  computed: {},
  watch: {},
  created() {},
  mounted() {},
  beforeDestroy() {},
  methods: {},
};
</script>

<style lang="scss" scoped>
.component-name {
}
</style>
```

### Options 选项顺序

按以下顺序排列，只写需要用到的选项：

1. `name`
2. `components`
3. `mixins`（如使用）
4. `props`
5. `data()`
6. `computed`
7. `watch`
8. `beforeCreate` / `created` / `beforeMount` / `mounted`
9. `beforeUpdate` / `updated`
10. `beforeDestroy` / `destroyed`
11. `methods`

### 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 组件文件名 | PascalCase | `UserProfile.vue` |
| 组件 name | PascalCase | `name: "UserProfile"` |
| props | camelCase | `userName` |
| events（$emit） | kebab-case | `this.$emit('update-value')` |
| methods | camelCase | `handleClick()` |
| data 字段 | camelCase | `isLoading` |
| CSS 类名 | kebab-case | `.user-profile` |
| 常量 | SCREAMING_SNAKE_CASE | `MAX_RETRY_COUNT` |

## Options API 常见陷阱

### 禁止使用箭头函数

**methods、computed、watch、lifecycle hooks 中绝不能使用箭头函数**，箭头函数不绑定 `this`，导致无法访问组件实例。

```javascript
// ❌ 错误
export default {
  methods: {
    handleClick: () => {
      this.visible = true; // this 是 undefined
    },
  },
  created: () => {
    this.fetchData(); // this 是 undefined
  },
};

// ✅ 正确
export default {
  methods: {
    handleClick() {
      this.visible = true;
    },
  },
  created() {
    this.fetchData();
  },
};
```

### 禁止直接修改 Props

子组件中永远不要直接修改 props，通过 emit 事件通知父组件。

```javascript
// ❌ 错误
this.value = newValue;

// ✅ 正确 — 使用 .sync 修饰符模式
this.$emit('update:value', newValue);

// ✅ 正确 — 自定义事件
this.$emit('change', newValue);
```

### v-if vs v-show

- `v-if`：条件为假时完全不渲染 DOM，适合初始不显示或不频繁切换的元素
- `v-show`：始终渲染 DOM，通过 CSS display 切换，适合频繁切换的元素

### v-for 必须配合 :key

使用 `v-for` 时必须提供唯一且稳定的 `:key`，避免使用 index（除非列表是纯展示且不会增删重排）。

```vue
<!-- ✅ 使用唯一标识 -->
<div v-for="item in list" :key="item.id">{{ item.name }}</div>

<!-- ❌ 列表会变动时避免用 index -->
<div v-for="(item, index) in list" :key="index">{{ item.name }}</div>
```

### 禁止 v-if 和 v-for 同时使用

Vue 2 中 `v-for` 优先级高于 `v-if`，同时使用会导致每次渲染都遍历整个列表。应使用 computed 过滤：

```javascript
computed: {
  activeList() {
    return this.list.filter(item => item.isActive);
  },
},
```

### computed vs methods

- **computed**：有缓存，依赖不变时不重新计算。用于模板中展示派生数据
- **methods**：每次调用都执行。用于响应事件或需要传参的逻辑

模板中展示数据用 computed，不要用 `{{ getXxx() }}` 调方法。

### data 必须是函数

组件的 `data` 必须是返回对象的函数，不能直接写对象（否则多实例间共享数据）。

```javascript
// ❌ 错误
data: {
  count: 0,
}

// ✅ 正确
data() {
  return {
    count: 0,
  };
},
```

## Vuex 状态管理规范

### 核心规则

- **State**：存放共享数据，字段用 camelCase 命名
- **Mutations**：同步修改 state 的唯一途径，使用 SCREAMING_SNAKE_CASE 命名
- **Actions**：处理异步操作，调用 API 后 commit mutation，使用 camelCase 命名
- **Getters**：派生状态，类似 computed，使用 camelCase 命名

### 模式

```javascript
// Mutation — 同步、原子性
SET_USER_INFO(state, userInfo) {
  state.userInfo = userInfo;
},

// Action — 异步逻辑
async fetchUserInfo({ commit }) {
  const res = await getUserInfo();
  commit('SET_USER_INFO', res.data);
},
```

### 组件中使用

```javascript
import { mapState, mapGetters, mapActions } from "vuex";

export default {
  computed: {
    ...mapState(['userInfo']),
    ...mapGetters(['formattedName']),
  },
  methods: {
    ...mapActions(['fetchUserInfo']),
  },
};
```

或直接访问：
- 读取：`this.$store.state.xxx` / `this.$store.getters.xxx`
- 修改：`this.$store.commit('MUTATION_NAME', payload)`
- 异步：`this.$store.dispatch('actionName', payload)`

## API 接口规范

### 封装原则

- 统一封装 axios 实例，配置 baseURL、timeout、拦截器
- 请求拦截器：附加 token、添加时间戳防缓存
- 响应拦截器：统一错误处理（登录过期、网络异常等）
- 接口函数独立文件导出，按模块组织

### 接口定义示例

```javascript
import { get, post } from "./request";

export const getUserInfo = (params) => get("/api/user/info", params);
export const submitOrder = (data) => post("/api/order/submit", data);
```

### 组件中调用

优先在 Vuex actions 中调用 API 并更新 state；简单的一次性请求可以在组件 methods 中直接调用。

## 避免内存泄漏

在 `beforeDestroy` 中清理以下资源：
- `addEventListener` 添加的 DOM 事件监听
- `setInterval` / `setTimeout` 定时器
- 第三方库实例（图表、动画、编辑器等）
- EventBus 的 `$on` 监听

```javascript
export default {
  data() {
    return { timer: null };
  },
  mounted() {
    this.timer = setInterval(this.poll, 5000);
    window.addEventListener('resize', this.onResize);
  },
  beforeDestroy() {
    clearInterval(this.timer);
    window.removeEventListener('resize', this.onResize);
  },
};
```

## 组件通信模式

| 场景 | 推荐方式 |
|------|----------|
| 父 → 子 | Props |
| 子 → 父 | `$emit` 事件 |
| 父 ↔ 子双向绑定 | `.sync` 修饰符或 `v-model` |
| 兄弟组件 | 通过共同父组件中转，或 Vuex |
| 跨多层级 | Vuex，或 `provide/inject`（慎用） |
| 全局状态 | Vuex |

**避免使用**：
- EventBus（难追踪、易内存泄漏）
- `$parent` / `$children` 直接访问（强耦合）
- `$refs` 跨组件通信（应仅用于调用子组件方法或获取 DOM）

## 性能优化

### 适用于本项目场景的优化

- **computed 缓存**：凡是模板中用到的派生数据都用 computed，不在模板中写复杂表达式
- **v-once**：纯静态内容使用 `v-once` 只渲染一次
- **Object.freeze()**：不需要响应式的大对象（如配置常量）使用 `Object.freeze()` 避免 Vue 递归劫持
- **异步组件**：大型非首屏组件使用异步加载：
  ```javascript
  components: {
    HeavyComponent: () => import('./HeavyComponent.vue'),
  },
  ```
- **事件修饰符**：使用 `@click.stop`、`@click.prevent`、`@scroll.passive` 而非手动调用

### data() 中的响应式控制

不需要响应式追踪的数据不要放在 `data()` 中：

```javascript
export default {
  data() {
    return {
      list: [], // 需要响应式
    };
  },
  created() {
    // 不需要响应式的放在 this 上但不经过 data
    this.cachedMap = new Map();
  },
};
```

## 错误处理

### 统一拦截 vs 组件处理

- **axios 拦截器**：处理通用错误（401/403 跳转登录、网络超时、服务器 5xx）
- **组件层**：只处理业务逻辑（如表单校验失败、特定业务状态码）

### 数据保护

使用 `v-if` 保护可能为空的数据，避免渲染崩溃：

```vue
<div v-if="detail && detail.items">
  <span v-for="item in detail.items" :key="item.id">{{ item.name }}</span>
</div>
```

## 代码风格

- 使用项目配置的缩进（通常 2 空格）
- 字符串引号风格与 Prettier/ESLint 配置保持一致
- 文件末尾保留空行
- 模板中避免复杂表达式，提取到 computed
- 使用 early return 减少嵌套
- 优先使用模板事件修饰符（`.stop`、`.prevent`、`.once`）
- 组件模板根元素的 class 与组件名对应（kebab-case）

## Playwright 端到端测试规范

### 核心原则

**每次完成功能开发或修改后，必须编写或更新对应的 Playwright 测试脚本**，确保功能正确可用。测试是开发流程的一部分，不是可选步骤。

### 环境准备

完成功能代码后，检查项目是否已安装 Playwright：

1. 检查 `package.json` 中是否有 `@playwright/test` 依赖
2. 检查项目根目录是否存在 `playwright.config.ts` 或 `playwright.config.js`
3. 检查是否存在 `e2e/` 目录

如果项目未安装 Playwright，执行以下步骤：

```bash
# 安装 Playwright
npm install -D @playwright/test

# 安装浏览器
npx playwright install chromium
```

在项目根目录创建 `playwright.config.ts`：

```typescript
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  timeout: 30000,
  retries: 1,
  use: {
    baseURL: "http://localhost:8080", // 根据项目实际端口调整
    headless: true,
    screenshot: "only-on-failure",
    trace: "on-first-retry",
  },
  webServer: {
    command: "npm run serve", // 根据项目实际启动命令调整
    port: 8080, // 根据项目实际端口调整
    reuseExistingServer: true,
  },
});
```

在项目根目录创建 `e2e/` 目录存放所有测试脚本。

### 可测性设计原则

编写 Vue 组件时，**必须考虑 Playwright 的可测性**：

1. **添加 data-testid 属性**：关键交互元素必须添加 `data-testid`，便于测试定位

```vue
<!-- ✅ 关键按钮、输入框、容器添加 data-testid -->
<template>
  <div class="login-form" data-testid="login-form">
    <input v-model="username" data-testid="login-username" />
    <input v-model="password" type="password" data-testid="login-password" />
    <button @click="handleLogin" data-testid="login-submit">登录</button>
    <span v-if="errorMsg" data-testid="login-error">{{ errorMsg }}</span>
  </div>
</template>
```

2. **data-testid 命名规范**：`模块名-元素描述`，使用 kebab-case

| 元素类型 | 命名示例 |
|---------|---------|
| 表单容器 | `login-form`、`order-form` |
| 输入框 | `login-username`、`search-input` |
| 按钮 | `login-submit`、`order-cancel` |
| 列表项 | `user-list-item`、`product-card` |
| 弹窗 | `confirm-dialog`、`delete-modal` |
| 状态文本 | `login-error`、`loading-text` |

3. **状态可观测**：确保组件的关键状态在 DOM 中有对应的可观测标志

```vue
<!-- ✅ 加载状态可被测试检测到 -->
<div v-if="isLoading" data-testid="loading-spinner">加载中...</div>
<div v-else data-testid="content-loaded">
  <!-- 内容 -->
</div>
```

4. **避免不可测的实现**：
   - 避免纯 CSS 动画结束后才出现内容（无 DOM 标志）
   - 避免使用随机 ID 作为唯一选择器
   - 避免 `setTimeout` 后无状态变化标志

### 测试脚本编写规范

#### 文件组织

```
e2e/
├── login.spec.ts          # 登录功能测试
├── order/
│   ├── create.spec.ts     # 创建订单测试
│   └── list.spec.ts       # 订单列表测试
├── user/
│   └── profile.spec.ts    # 用户信息测试
└── helpers/
    └── auth.ts            # 测试辅助函数（如登录）
```

测试文件命名与功能模块对应，使用 `模块名.spec.ts` 格式。

#### 测试脚本模板

```typescript
import { test, expect } from "@playwright/test";

test.describe("功能模块名称", () => {
  test.beforeEach(async ({ page }) => {
    // 公共前置操作（如登录、导航到目标页面）
    await page.goto("/target-page");
  });

  test("应该正确完成某个操作", async ({ page }) => {
    // 1. 定位元素
    const submitBtn = page.getByTestId("form-submit");

    // 2. 执行操作
    await page.getByTestId("form-input").fill("测试内容");
    await submitBtn.click();

    // 3. 断言结果
    await expect(page.getByTestId("success-message")).toBeVisible();
  });

  test("输入无效数据时应显示错误提示", async ({ page }) => {
    await page.getByTestId("form-input").fill("");
    await page.getByTestId("form-submit").click();

    await expect(page.getByTestId("error-message")).toHaveText("请输入内容");
  });
});
```

#### 选择器优先级

优先使用以下选择器（从高到低）：

1. `page.getByTestId("xxx")` — 最推荐，稳定不受样式/文案变化影响
2. `page.getByRole("button", { name: "提交" })` — 语义明确的 ARIA 角色
3. `page.getByText("具体文案")` — 适合验证文本内容
4. `page.locator(".class-name")` — 最后选择，易受重构影响

#### 常用断言

```typescript
// 元素可见
await expect(locator).toBeVisible();
// 元素隐藏
await expect(locator).toBeHidden();
// 文本内容
await expect(locator).toHaveText("期望文本");
await expect(locator).toContainText("部分文本");
// 输入框值
await expect(locator).toHaveValue("期望值");
// 元素数量
await expect(page.getByTestId("list-item")).toHaveCount(5);
// URL 跳转
await expect(page).toHaveURL(/\/dashboard/);
// 元素属性
await expect(locator).toHaveAttribute("disabled", "");
await expect(locator).toHaveClass(/active/);
```

### 工作流程

完成功能开发后，按以下流程执行：

#### 1. 编写/更新测试脚本

- **新增功能**：在 `e2e/` 目录创建对应的 `.spec.ts` 文件
- **修改功能**：找到对应的已有测试文件并更新

#### 2. 运行测试

```bash
# 运行某个测试文件
npx playwright test e2e/目标文件.spec.ts

# 运行某个 describe 或 test
npx playwright test -g "测试名称关键词"
```

#### 3. 分析测试失败

当测试失败时，**必须分析失败原因并判断是哪方的问题**：

| 失败场景 | 判断标准 | 处理方式 |
|---------|---------|---------|
| 元素找不到（`getByTestId` 超时） | 功能代码中缺少 data-testid 或元素未渲染 | 修改功能代码，添加 data-testid 或修复渲染逻辑 |
| 断言不匹配（文案/值变了） | 功能修改导致输出变化，但行为正确 | 更新测试脚本中的断言期望值 |
| 操作流程失败（点击无反应） | 功能代码 bug，事件未绑定或逻辑错误 | 修复功能代码 |
| 页面跳转/URL 不对 | 路由配置变更但功能正确 | 更新测试脚本中的 URL 断言 |
| 超时（等待某元素出现） | 异步请求慢或条件渲染逻辑 bug | 先确认功能是否正常，再决定改哪边 |
| 测试脚本本身逻辑错误 | 测试步骤与实际操作流程不一致 | 更新测试脚本 |

**判断原则**：
- 如果**功能本身的行为是正确的**（手动操作可正常使用），则修改测试脚本
- 如果**功能行为有误**（手动操作也有问题），则修复功能代码
- 修复后必须重新运行测试直到通过

#### 4. 确认测试通过

测试全部通过后才视为开发完成。如果有测试无法通过且无法在当前范围内解决，需要向用户说明原因。

### 测试辅助函数

对于需要登录态的测试，在 `e2e/helpers/auth.ts` 中封装登录逻辑：

```typescript
import { Page } from "@playwright/test";

export async function login(page: Page, username = "admin", password = "123456") {
  await page.goto("/login");
  await page.getByTestId("login-username").fill(username);
  await page.getByTestId("login-password").fill(password);
  await page.getByTestId("login-submit").click();
  await page.waitForURL(/\/dashboard|\/home/);
}
```

### 修改已有功能时的测试策略

当修改已有功能时：

1. **先运行该功能相关的已有测试**，确认修改前测试状态
2. 进行功能修改
3. 修改后再运行测试，根据结果判断是更新测试还是修复代码
4. 如果功能变更导致测试需要更新，同步更新测试脚本
5. 确保所有相关测试通过

```bash
# 查找相关测试文件

# macOS / Linux
find e2e -name "*.spec.ts" | xargs grep -l "相关关键词"

# Windows PowerShell
Get-ChildItem -Path e2e -Recurse -Filter "*.spec.ts" | Select-String -Pattern "相关关键词" -List | Select-Object -ExpandProperty Path

# 运行相关测试
npx playwright test e2e/相关模块.spec.ts
```

## 项目适配检查清单

使用此 skill 时，先检查当前项目的以下配置并遵循：

1. **构建工具**：Vue CLI / Vite / Webpack — 影响路径别名和构建配置
2. **CSS 方案**：SCSS / Less / CSS Modules / Tailwind — 影响样式写法
3. **i18n 方案**：vue-i18n / 自定义方案 — 影响文本引用方式
4. **状态管理**：Vuex 单文件 / Vuex modules — 影响 store 组织方式
5. **API 封装**：axios / fetch / 其他 — 影响请求写法
6. **代码规范**：ESLint + Prettier 配置 — 影响格式和风格
7. **响应式方案**：rem / vw / 媒体查询 — 影响样式单位
8. **组件库**：Element UI / Vant / 无 — 影响 UI 组件选择
9. **E2E 测试**：检查是否已安装 Playwright，是否存在 `e2e/` 目录和 `playwright.config` — 影响测试脚本编写和运行
