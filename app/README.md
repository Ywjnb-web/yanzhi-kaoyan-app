# 研志 · 考研择校志愿填报小程序（前端）

依据《PRD-考研择校志愿填报-App-V1.0》与线框图原型，1:1 落地的**小程序端**前端工程。

- **框架**：uni-app x（uvue / UTS）
- **语言**：UTS（TypeScript 语法，强类型）
- **包管理**：pnpm
- **样式**：Tailwind CSS 4（CSS-first）+ weapp-tailwindcss
- **目标端**：微信小程序（其余端条件编译可开）

---

## 一、版本要求

| 依赖        | 版本                        | 说明                                                   |
| --------- | ------------------------- | ---------------------------------------------------- |
| HBuilderX | **≥ 5.11**                | 低于此版本无法加载 ESM 依赖，Tailwind 4 接入会失败                    |
| Node.js   | `^22.18.0 \|\| >=24.11.0` | weapp-tailwindcss 5.2+ 的硬性要求                         |
| pnpm      | 10.x                      | 已在 `.npmrc` 里把 `node-linker` 设为 `hoisted`            |
| 微信基础库     | **≥ 3.8.12**              | glass-easel 运行时的最低基础库；低于 3.7.1 时 `scroll-view` 尺寸也不准 |
| 微信开发者工具   | **≥ 1.06.2308142**        | 低于此版本不支持 glass-easel，基础库会**中断渲染 → 白屏**               |

> 低于 3.7.1 的基础库不在适配范围内；HBuilderX 4.41 ~ 5.10 可以跑小程序端，  
> 但用不了本工程的 Tailwind 4 管线。

## 二、运行到微信开发者工具

> ⚠️ **uni-app x 没有 CLI，不能直接把本目录拖进微信开发者工具。**  
> 微信开发者工具只认编译后的 `wxml / wxss / js / json`，而本工程源码是  
> `.uvue` + `.uts`，必须先由 HBuilderX 编译。官方原话：  
> *HBuilderX remains the source of truth for uni-app x running and building.*

正确的链路是一条单向流水线：

```
HBuilderX 编译 ──► unpackage/dist/dev/mp-weixin ──► 微信开发者工具打开该目录
```

### ⚠️ 前置必读：微信小程序端必须开启 glass-easel

uni-app x 编译到微信小程序后走 **VDOM 渲染模式（基于 glass-easel 组件框架）**。

- 页面/组件的注册入口是 `wx.createPage` / `wx.createComponent`，由 **uni-app x 运行时**  
  在 `common/vendor.js` 中挂到 `wx` 上（`wx.createPage = createPage`），其内部调用  
  glass-easel 的 `Component(...)` 完成注册。
- 同时 WXML 由 **glass-easel 编译器**产出（含 `change:*` 指令与 `uniView.wxs`）。

两者必须配套：`manifest.json` 的 `mp-weixin` 需开  
`componentFramework: "glass-easel"` + `glassEaselWebview: true`，否则 WXML 编译器与  
运行时框架不一致，页面不会被创建 —— 现象是**编译成功、控制台无红字、模拟器纯白屏**。

> 本工程是手写脚手架生成的，未继承 HBuilderX「新建 uni-app x 项目」模板  
> 里的默认值，因此初版漏了这一项，首跑即白屏。已修复（见 `manifest.json`）。

```json
"mp-weixin": {
  "componentFramework": "glass-easel",
  "glassEaselWebview": true
}
```

配套底限：微信基础库 **≥ 3.8.12**、微信开发者工具 **≥ 1.06.2308142**。

### 0. 本机环境现状

| 组件        | 状态                                                                                 |
| --------- | ---------------------------------------------------------------------------------- |
| Node.js   | ✅ v22.22.2 / v24.17.0，满足 `^22.18.0 \|\| >=24.11.0`                                 |
| pnpm      | ✅ 10.15.0                                                                          |
| 项目依赖      | ✅ 已 `pnpm install`（219 个包，`node-linker=hoisted` 已生效）                               |
| 微信开发者工具   | ✅ 已升级至 **v2.02.2608080**（远高于 glass-easel 要求的 `1.06.2308142`）；路径 `E:\VX\微信web开发者工具` |
| HBuilderX | ✅ 已安装，版本 **5.26**（≥ 5.11，满足 Tailwind 4 管线要求）                                       |

### 1. 安装 HBuilderX（≥ 5.11）

到 <https://www.dcloud.io/hbuilderx.html> 下载 **App 开发版**（已含 uni-app x 编译插件；  
标准版需再手动安装「uni-app x」插件）。绿色包，解压即用，不必安装。

> 必须 ≥ 5.11。更低版本的 HBuilderX 自带 Node 过旧，加载不了  
> weapp-tailwindcss 5.3 的 ESM 依赖，Tailwind 会静默失效。

### 2. 打通 HBuilderX ↔ 微信开发者工具

两个方向都要配，缺一个就卡住：

1. **微信开发者工具** → `设置` → `安全设置` → 打开 **服务端口**。  
   不开这一步，HBuilderX 会报「运行到微信开发者工具失败」。
2. **HBuilderX** → `工具` → `设置` → `运行配置` → 「微信开发者工具路径」填  
   `E:\VX\微信web开发者工具`。

### 3. 填 AppID

`manifest.json` → `mp-weixin.appid` 填自己的小程序 AppID。  
暂时没有也行：留空，微信开发者工具弹窗里选「测试号」即可预览。

### 4. 运行

HBuilderX → `文件` → `打开目录` → 选 **`E:\Datum\Demo\app`**（选本工程目录，不要选仓库根目录），然后：

```
运行 → 运行到小程序模拟器 → 微信开发者工具
```

首次编译 1–3 分钟。产物落在 `unpackage/dist/dev/mp-weixin`，微信开发者工具会自动  
打开这个目录；此后改代码自动热更新。

### 5. 验证 Tailwind 是否真的接上了

编译成功后随便看一页。**若版式全乱、只有默认字体没有颜色间距**，说明 Tailwind 管线  
没跑起来，按第九章最后两条排查（`@theme` → `@theme inline`）。

### 备选：先用 H5 快速自查

`运行` → `运行到浏览器` → `Chrome`。比小程序端快得多，适合先确认代码本身没问题，  
再去调小程序端的平台差异。

### 关于图标

`utils/icons.uts` 里的 17 个图标已经生成好，**正常情况不需要再跑**。  
只有改了 `scripts/gen-icons.mjs` 或要新增图标时，才执行 `pnpm gen:icons`。

`uni-app x` 的编译器由 HBuilderX 内置提供，因此 `package.json` 里**不需要**  
（也不应该）声明 `@dcloudio/*` 依赖 —— 版本与 IDE 不匹配会直接装失败。

## 三、目录结构

```
app/
├── App.uvue                  应用根组件，唯一入口：@import './main.css'
├── main.uts                  createSSRApp
├── main.css                  ★ Tailwind CSS 4 入口 + 设计令牌（@theme）
├── pages.json                路由 + easycom + globalStyle(custom 导航)
├── manifest.json             多端配置（微信小程序 appid 待填）
├── vite.config.ts            weapp-tailwindcss uniAppX preset
├── types/models.uts          领域模型（对齐 PRD 第十章实体关系）
├── constants/dictionary.uts  文案与选项字典、分档元信息、异常清单
├── mock/programs.uts         院校数据库 Mock（★ 院校名为真实公开信息，数值为演示数据）
├── services/plan-engine.uts  规则引擎：分档 / 概率估算 / 推荐理由
├── api/                      数据访问层，五文件分工见「八、后端接口预留」
│   ├── index.uts             同步实现：本地假数据 + 本地缓存（断网时的降级路径）
│   ├── config.uts            ★ 环境开关 USE_MOCK / BASE_URL、设备 ID、令牌读写
│   ├── endpoints.uts         接口路径常量（与后端契约 §8 一一对应）
│   ├── http.uts              统一请求封装：解包 / 错误码翻译 / 401 自动刷新重试
│   └── remote.uts            异步接口层（接真后端时页面改调这里）
├── store/app.uts             跨页会话状态
├── utils/format.uts          格式化
├── utils/nav.uts             返回上一级（含「页面栈只剩一页」兜底）
├── utils/icons.uts           图标表（由 scripts/gen-icons.mjs 生成，勿手改）
├── components/               11 个通用组件（easycom 自动注册）
├── pages/                    13 个页面
└── scripts/gen-icons.mjs     图标代码生成器
```

> 后端产物（契约与建表脚本）不在本工程内，位于 `../deliverables/backend/`。

## 四、设计令牌

线框图的色板 / 字号 / 圆角全部落在 `main.css` 的 `@theme` 块里，页面只引用语义化的  
类名（`text-ink2`、`rounded-card`、`text-h2`），不出现裸十六进制色值。

| 线框图       | Tailwind 类                         | 值                                                  |
| --------- | ---------------------------------- | -------------------------------------------------- |
| 正文 / 主操作底 | `text-ink` `bg-ink`                | `#1F2329`                                          |
| 次级文字      | `text-ink2`                        | `#646A73`                                          |
| 说明 / 占位   | `text-ink3`                        | `#A6ABB3`                                          |
| 主分隔线      | `border-line`                      | `#E5E7EB`                                          |
| 控件描边      | `border-line2`                     | `#D5D8DD`                                          |
| 内容块底      | `bg-fill`                          | `#F2F3F5`                                          |
| 注释层 / 强调  | `text-brand` `bg-brandsoft`        | `#2B6CF6` / `#EAF1FE`                              |
| 字号        | `text-micro` … `text-h1`           | 10 / 11 / 12 / 13 / 14 / 15 / 16 / 18 / 22 / 26 px |
| 圆角        | `rounded-cell/btn/card/panel/chip` | 10 / 12 / 14 / 16 / full                           |

**单位策略**：`rem2rpx: true`，Tailwind 的间距刻度全部换算为 `rpx` 以跟随屏幕宽度；  
但设计稿中需要与视觉严格对齐的**固定高度**（按钮 52px、chip 38px、数据行 46px 等）  
一律用任意值类名 `h-[52px]` 锁死，避免换算出 4% 左右的累积偏差。

## 五、页面 ↔ 需求映射

| 屏             | 路由                              | 对应需求                          |
| ------------- | ------------------------------- | ----------------------------- |
| S00 首页 / 启动   | `pages/index/index`             | FR-10、FR-08                   |
| S01 生成前免责声明确认 | `pages/disclaimer/disclaimer`   | FR-08                         |
| S02 考生信息采集    | `pages/exam-info/exam-info`     | FR-01、EX-01、EX-02、EX-03、EX-08 |
| S03 兴趣偏好采集    | `pages/preference/preference`   | FR-02                         |
| S04 方案生成中     | `pages/generating/generating`   | FR-05（加载态）                    |
| S05 择校方案总览    | `pages/plan/plan`               | FR-04、FR-05、EX-07             |
| S06 推荐项依据详情   | `pages/plan-detail/plan-detail` | FR-04、FR-09                   |
| S07 调整与重新生成   | `pages/adjust/adjust`           | FR-06                         |
| S08 我的方案      | `pages/my-plans/my-plans`       | FR-07、FR-10                   |
| S09 方案导出 / 分享 | `pages/export/export`           | FR-07                         |
| S10 院校专业检索    | `pages/search/search`           | FR-03、EX-03                   |
| S11 异常与边界态    | `pages/state/state`             | 第十二章                          |
| 我的（Tab 落点）    | `pages/mine/mine`               | FR-10、第十一章                    |

### 主链路

```
S00 首页 →「开始择校」→ S02 考生信息 → S03 兴趣偏好
   →（首次）S01 免责声明确认 → S04 生成中 → S05 择校方案
   → S06 依据详情 → S07 调整重生成 → S04 → S05
   →「保存并导出」→ S09 导出 / 分享

底部胶囊 Tab（同级切换，各自保留导航栈）：
   首页 S00  ↔  检索 S10  ↔  方案 S08  ↔  我的
```

## 六、相对线框图的三处刻意偏离

这三处不是实现偏差，是**设计判断**，请一并评审：

1. **S09「包含免责声明」由勾选框改为锁定项。**  
   线框图把它画成可勾选，但 FR-07 的验收标准要求导出物**必须**含免责声明与  
   来源年份。给用户一个能关掉合规信息的开关，等于把红线做成可选项。  
   现在渲染为已勾选且右侧标注「必需」。
2. **S02 的省份选择改为自绘底部浮层（不再走系统 ActionSheet）。**  
   两个理由：`uni.showActionSheet` 的 `itemList` 上限是 6 项，31 个省级行政区铺不开；  
   更关键的是它**无法表达「已选中」状态**，做不了多选。现在改为  
   「先分 A / B 区 → 滚动列表勾选」：切换区域不清空已选，可跨区累计，  
   选中项在列表内与字段下方双重回显，跨区时区域标签如实显示为「A / B 区」。
3. **底部导航自绘，未使用小程序原生 `tabBar`。**  
   原生 tabBar 无法实现「圆角胶囊 + 选中项深色填充」，且需要 4 组 PNG 图标。  
   改为自绘组件 + `uni.reLaunch`，视觉与交互完全对齐设计稿。

## 七、关键实现说明

- **事实一致率 100% 的落地方式**：`services/plan-engine.uts` 只做分档与排序，  
  所有分数线 / 报录比 / 复录比 / 统考名额都是从 `mock/programs.uts` **原样透传**，  
  推荐理由里的每一句话都必须引用库内数字。要接真后端时，把 `api/index.uts` 的  
  `generatePlan` 换成 `uni.request` 即可，页面层零改动。
- **统考名额单独建模**：`planTotal`（招生计划）与 `recommendedQuota`（推免）在数据层  
  就是两个字段，`quota = planTotal − recommendedQuota`。S06 把算式原文摊开展示，  
  直接回应 PRD P-1「名额不透明」。
- **加载态是「有内容的等待」**：S04 的三段进度对应三个真实阶段  
  （检索候选池 → 校验数据库事实 → 模型排序），跑完才跳转，不做假进度条。
- **组件事件名避开 `tap`**：小程序端自定义组件的事件名与原生事件同名时，  
  父级 `@tap` 可能同时收到「组件 emit」与「原生冒泡」两次调用，表现为跳转两次。

### S02 的控件选择（为什么不是一个 ActionSheet 打天下）

| 字段              | 控件                 | 说明                       |
| --------------- | ------------------ | ------------------------ |
| 意向省份            | 底部浮层（自绘）           | A / B 区分组 + 滚动列表多选，可跨区累计 |
| 报考科目代码          | 行内数字输入 + 常用代码 chip | 6 位数字校验；代码 → 名称实时回显      |
| 初试科目组合 / 本科院校层次 | 系统 ActionSheet     | 选项 ≤ 6 项，用系统控件最稳         |
| 本科专业 / 目标院校     | 底部浮层（自绘）           | 输入框 + 候选列表，两者都允许自由输入     |
| 四门成绩            | 行内数字输入             | 总分恒为各科之和，不可手填            |

- **目标院校的 EX-03 两种结果都要说清楚**：命中库内 → 「已匹配院校库：示例大学 · 江苏 · A 区 · 985」；  
  不在库内 → 明示「库内暂无数据，不会编造该校数字」，但**允许照常填写**，不阻断流程。
- **浮层的分层方式**：遮罩与面板是**兄弟节点**（`absolute` + `relative`），靠 z-index 分层，  
  不依赖事件冒泡拦截 —— 小程序端 `.stop` 修饰符的行为并不总可靠。  
  样式写在 `main.css` 里（与 `.bottom-bar` 同一机制），不用页面级 `<style>`。
- **`scroll-view` 必须给显式高度**（`style="height: 280px"`），且 `scroll-y` 用 `:scroll-y="true"`  
  绑定形式 —— uvue 严格类型下，静态字符串属性对布尔 prop 不友好。
- **草稿结构升级**：`loadExamDraft()` 会把旧版草稿（只有单个 `province`）归一成新结构  
  （字段全可选 + 逐项补默认值）。少了这一步，升级后旧缓存会让 `form.provinces.length` 直接抛错。  
  因此 `c-btn` / `c-chip` 统一 emit `press`。
- **异常态不返回空白页**：任何列表为空都走 `c-empty`，给出可解释文案与下一步动作。
- **返回上一级统一走 `utils/nav.uts → goBack()`**。本工程全部页面都是  
  `navigationStyle: custom`：既没有原生导航栏的返回键，**系统手势 / 返回键也随之失效**，  
  返回动作完全由页面内的 `<c-nav-bar>` 承担。由此产生一个必须自己兜的边界 ——  
  当**页面栈深度为 1** 时（开发者工具用「编译模式」直达某页，或经 `reLaunch` 落到某页），  
  裸调 `uni.navigateBack()` 会静默失败，现象是「点了返回没反应，被困在当前页」。  
  `goBack(fallback)` 先判栈深：只有一页就直接 `reLaunch` 到指定的上一步路由；  
  否则正常返回，并在 `fail` 回调里再兜一次。
- **每个非 Tab 页面都必须有返回入口**。13 个页面里 4 个是 Tab 页  
  （首页 / 检索 / 我的方案 / 我的），保留 `<c-status-bar>`；其余 9 个一律使用  
  `<c-nav-bar lead="back|close" @lead="…">`，并通过 `goBack()` 指向逻辑上的上一步  
  （而不是硬依赖 `navigateBack` 的栈顺序）。

## 八、后端接口预留

后端采用 **DDD + MVC 融合** 架构（Spring Boot 3 · Java 17 · MyBatis-Plus · PostgreSQL）。
契约与建表脚本在工作区上一级：

| 文件 | 内容 |
| --- | --- |
| `deliverables/backend/API-契约-研志-V1.0.md` | 31 个接口清单、DTO、错误码表、分层落法 |
| `deliverables/backend/schema-v1.0.sql` | 建表脚本（聚合边界即表边界）、索引、视图 |

### 8.1 api/ 目录的五文件分工

| 文件 | 职责 |
| --- | --- |
| `config.uts` | **接入真后端的唯一开关**：`USE_MOCK`、`BASE_URL`、超时、设备 ID、令牌读写 |
| `endpoints.uts` | 31 个路径常量 + 带参路径构造器，页面里不出现裸 URL |
| `http.uts` | 注入 `Authorization` / `X-Device-Id` / `Idempotency-Key`；解包统一响应体；错误码翻译成中文；40102 自动刷新令牌并重试一次 |
| `remote.uts` | 异步接口层，返回类型与 `types/models.uts` 对齐 |
| `index.uts` | 同步实现（本地假数据 + 本地缓存）。**接后端后不要删** —— 断网时它是页面唯一的降级路径 |

### 8.2 切换步骤

1. `api/config.uts`：`USE_MOCK` 置 `false`，`BASE_URL` 填真实网关。
2. 微信公众平台「开发设置 → 服务器域名」登记 `request` 合法域名（必须 HTTPS）。
3. 逐页把同步调用换成 `await` 异步版，建议顺序：**检索页 → 生成链路 → 我的方案 → 反馈**。
   从只读的开始换，写链路留最后，避免中途出现半同步半异步的难查问题。

### 8.3 同步函数 → 接口对照

| 现状（同步） | 替换为 | 备注 |
| --- | --- | --- |
| `generatePlan` | `POST /plans/generate` + 轮询 | 改异步任务；大模型耗时不可控，且 S04 要分三段展示进度 |
| `generateStages` | 轮询响应 | 直接读服务端 `stageLabel` / `stageDetail`，端上不再硬编码文案 |
| `searchPrograms` | `GET /catalog/programs` | 改分页 + `await` |
| `suggestSchools` / `findSchool` | `GET /catalog/schools` | 调用点加 300ms 防抖 |
| `listPlans` / `savePlan` / `removePlan` | `GET` / `POST` / `DELETE /plans` | 本地缓存**保留**为离线兜底，网络优先 |
| `submitFeedback` | `POST /feedbacks` | 失败入本地队列重试，不弹错误打断用户 |
| `validateExam` | `POST /exam-profile/validate` | 本地快速校验保留，提交前再调服务端二次校验 |
| `saveExamDraft` / `loadExamDraft` | 无（仍本地） | 弱网草稿不依赖网络；登录后由 `PUT /exam-profile` 同步 |
| `constants/dictionary.uts` | `GET /meta/dictionaries` | 首次启动拉取并缓存，失败回落硬编码常量 |
| `mock/programs.uts` | 院校目录只读接口 | — |
| `manifest.json → mp-weixin.appid` | — | 填你的小程序 AppID |

### 8.4 三条不能破的约定

1. **`dataVersion` 必须随反馈一起上报**。没有它就分不清是数据错还是模型排序错。
2. **`noData = true` 时不做任何估算**。服务端返回空串，页面渲染「暂无数据」（EX-03）。
   这是产品红线，不是技术选择。
3. **数值响应必须带 `dataNature` / `sourceNote`**。`demo` 期间页面强制展示
   「演示数据 · 非院校官方发布」；取得院校授权后才能置 `official`。

> `urlCheck: false` 仅为本地调试；上线前必须改回严格域名校验。

## 九、已知平台约束与排错

- **不要用 `gap` / `space-x-*` / `space-y-*`**。uvue 原生端不支持，本工程一律用  
  显式 `mt-*` / `ml-*`。若后续要编译到 App 端，这条必须守住。
- **`border` 必须带 `border-solid`**。Tailwind 的 preflight 在 WXSS 里不保证生效，  
  只写 `border` 会得到 `border-style: none`，边框看不见。
- **图标走 base64 SVG data URI**（`utils/icons.uts`）。若个别机型不渲染 SVG，  
  把 `c-icon.uvue` 里的 `<image :src>` 改成 `<view :style="background-image:url(...)">`  
  即可，组件已把地址收敛在 `src` 一处。
- **`:root` 变量**：Tailwind 4 默认把主题变量挂在 `:root`。weapp-tailwindcss 会做  
  选择器转换；若发现 `text-ink` 等类不生效，把 `main.css` 里的 `@theme` 改成  
  `@theme inline` 让取值内联进工具类即可。
- **`JSON.parse` 的类型断言**：`api/index.uts` 里对本地缓存的解析用了  
  `as PlanVO[]`，UTS 若对该断言报错，改为逐字段赋值构造。

### 运行阶段常见报错速查

| 现象                              | 原因                | 处理                                                                    |
| ------------------------------- | ----------------- | --------------------------------------------------------------------- |
| HBuilderX 报「运行到微信开发者工具失败」       | 微信开发者工具没开**服务端口** | 开发者工具 → 设置 → 安全设置 → 打开服务端口                                            |
| 微信开发者工具里一片空白 / 报 `app.json 未找到` | 编译未完成，或打开错目录      | 等 HBuilderX 控制台出现「编译成功」；确认打开的是 `unpackage/dist/dev/mp-weixin` 而不是源码目录 |
| **模拟器纯白屏、控制台无红字** | ① `manifest.json` 的 `mp-weixin` 缺 `componentFramework: "glass-easel"` → `wx.createPage` 未定义，页面从未创建；② **微信开发者工具 < `1.06.2308142`** → 基础库无法激活 glass-easel 运行时，**中断渲染**（本次真实根因） | ① 确认 manifest 已开 glass-easel；② **升级微信开发者工具到最新 Stable**（旧版 1.05.x 从「关于」无法自更新，需官网重新下载）；③ `工具`→`清缓存`→`全部清除`，再全量重编译 |  
| 报 `sitemap.json 未找到`，但文件确实存在 | 开发者工具在 `sitemap.json` 生成**之前**加载了项目，把校验错误缓存了下来 | `工具`→`清缓存`→`全部清除`，再 `Ctrl+B` 重编译 |  
| Tailwind 类名完全不生效 | HBuilderX < 5.11，或 `main.css` 没被 `App.uvue` 引入 | 升级 HBuilderX；确认 `App.uvue` 的 `<style>` 里有 `@import './main.css'` |  
| 控制台报 `Cannot send network request to localhost` / `ws://192.168.x.x:8090 不在以下 socket 合法域名列表中` | **不是本项目发出的请求**。这是 HBuilderX「运行日志回显」把小程序 `console` 回传 IDE 的 websocket 通道，与本工程代码无关 —— `USE_MOCK = true` 时 `api/` 是纯本地透传，**零网络调用**；`remote.uts` 也只有被页面实际调用后才会发请求 | 开发者工具 → `详情` → `本地设置` → 勾选**「不校验合法域名、web-view（业务域名）、TLS 版本以及 HTTPS 证书」**；或在 HBuilderX `设置 → 运行配置` 里关掉「运行日志回显」 |

---

## 数据性质说明（重要）

本工程遵循**数据双轨制**：

| 类别 | 字段 | 性质 |
| --- | --- | --- |
| **真实公开信息** | 院校名称、院系名称、专业名称、专业代码 | 可查证，用于标识 |
| **演示数值** | 复试线、报录比、复录比、招生计划、推免人数、学费 | **演示数据，非院校官方发布，不得用于实际报考决策** |

凡展示上述数值的页面，必须同时出现「演示数据 · 非院校官方发布」字样。
接入真后端后，该标识由接口返回的 `dataNature` / `sourceNote` 驱动（见「八、后端接口预留」）。

合规声明：本产品不提供任何录取保证；上岸概率为基于历史数据的估算区间，非承诺。
最终报考信息请以各招生单位官方发布的招生章程与专业目录为准。
