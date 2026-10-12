# 研志 · 考研择校志愿填报

> 一款面向考研人群的**择校与志愿填报**辅助产品：先做「数据检索 + 匹配推荐」跑通主链路，再延伸到调剂决策、情报社区与服务连接。
>
> 本仓库包含两部分：**小程序端前端工程**（`app/`）与**产品 / 后端交付文档**（`deliverables/`）。

---

## 一、技术栈

| 层 | 选型 |
| --- | --- |
| 框架 | **uni-app x**（uvue / UTS，编译到微信小程序走 glass-easel） |
| 语言 | UTS（TypeScript 语法，强类型） |
| 包管理 | **pnpm**（`.npmrc` 已设 `node-linker=hoisted`） |
| 样式 | **Tailwind CSS 4**（CSS-first + `@theme`）+ weapp-tailwindcss |
| 目标端 | 微信小程序（其余端条件编译可开） |
| 后端（预留） | Spring Boot 3 · Java 17 · MyBatis-Plus · PostgreSQL 14+，MVC + DDD 融合 |

> 当前前端为**纯前端 + 本地 mock**：`mock/` 假数据、`services/` 本地匹配引擎、`api/` 纯透传层。后端接口契约已预留，接入后只需替换 `api/` 层，页面层零改动。

---

## 二、仓库结构

```
yanzhi-kaoyan-app/
├── app/                          # 小程序端前端工程（uni-app x）
│   ├── pages/                     # 13 个页面（S00–S11）
│   ├── components/                # 11 个通用组件（easycom 自动注册）
│   ├── api/                       # 数据访问层 + 后端接口预留（config/endpoints/http/remote）
│   ├── mock/                      # 院校数据库 Mock（院校名为真实公开信息，数值为演示数据）
│   ├── services/                  # 规则引擎：分档 / 概率估算 / 推荐理由
│   ├── store/  types/  constants/ utils/
│   ├── main.css                   # Tailwind 4 设计令牌（@theme 唯一来源）
│   ├── manifest.json  pages.json  project.config.json
│   └── README.md                  # ★ 前端详细运行文档（必读）
└── deliverables/                  # 产品 / 后端交付文档
    ├── product-strategy/
    │   ├── PRD-考研择校志愿填报-App-V1.0.md          # 产品需求文档（15 段标准结构）
    │   └── brainstorm-kaoyan-school-choice-2026-10-12.md  # 头脑风暴记录
    └── backend/
        ├── API-契约-研志-V1.0.md                   # 后端 REST 接口契约（31 个接口）
        └── schema-v1.0.sql                         # PostgreSQL 建表脚本
```
<img width="554" height="1211" alt="image" src="https://github.com/user-attachments/assets/17b9bfcf-9f6e-4b81-b541-bbea392414a6" />
<img width="520" height="1026" alt="image" src="https://github.com/user-attachments/assets/4974a7e9-f135-45ef-98ed-5ac316c427fa" />
<img width="552" height="1147" alt="image" src="https://github.com/user-attachments/assets/58693ae2-f370-4e2e-acb8-7942212ca9f0" />

---

## 三、快速开始（前端）

> uni-app x **没有 CLI**，不能直接把目录拖进微信开发者工具。必须由 **HBuilderX** 编译 → 产物目录 → 微信开发者工具打开。完整步骤见 [`app/README.md`](app/README.md)。

环境门槛（低于则白屏 / Tailwind 失效）：

| 依赖 | 版本 | 说明 |
| --- | --- | --- |
| HBuilderX | **≥ 5.11** | 低于此版本无法加载 ESM 依赖，Tailwind 4 接入失败 |
| Node.js | `^22.18.0 \|\| >=24.11.0` | weapp-tailwindcss 5.2+ 硬性要求 |
| 微信基础库 | **≥ 3.8.12** | glass-easel 运行时最低基础库 |
| 微信开发者工具 | **≥ 1.06.2308142** | 低于此版本不支持 glass-easel，渲染中断 → 白屏 |

链路：

```
HBuilderX 编译 ──► app/unpackage/dist/dev/mp-weixin ──► 微信开发者工具打开该目录
```

---

## 四、后端接口预留

后端采用 **MVC + DDD 融合**架构（限界上下文 = 聚合边界），技术栈 Spring Boot 3 + MyBatis-Plus + PostgreSQL。

- **接口契约**：[`deliverables/backend/API-契约-研志-V1.0.md`](deliverables/backend/API-契约-研志-V1.0.md) —— 31 个接口，覆盖 FR-01~FR-10，含统一响应包、17 条错误码、DTO、同步函数→接口对照表。
- **建表脚本**：[`deliverables/backend/schema-v1.0.sql`](deliverables/backend/schema-v1.0.sql) —— 五大聚合（`candidate` / `exam_profile` / `program` / `plan` / `feedback`）+ 逐年数值表 + 字典表 + 事务性发件箱。
- **前端预留层**：`app/api/` 下 `config`（开关）/ `endpoints`（路径）/ `http`（封装）/ `remote`（异步接口），接后端唯一开关为 `config.uts` 的 `USE_MOCK`。

关键设计：生成走**异步任务**（轮询进度，文案由服务端下发）；总分用 PostgreSQL **生成列**杜绝脏数据；数值双轨制（`data_nature` = `demo`/`official`）落库。

---

## 五、数据合规声明（重要）

本项目严格执行**双轨制**：

| 内容 | 性质 |
| --- | --- |
| 院校名称 / 院系 / 专业 / 专业代码 | **真实公开信息** |
| 复试线 / 报录比 / 复录比 / 招生计划 / 推免人数 / 学费 | **演示数值，非院校官方发布** |

凡是展示数字的页面均带「演示数据 · 非院校官方发布」标识。本产品不提供任何录取保证；上岸概率为基于历史数据的估算区间，非承诺。

---

## 六、贡献与协作

- 唯一接后端的开关在 `app/api/config.uts` 的 `USE_MOCK`，合并前请确认无人改动 `app/api/`。
- `app/project.config.json` 的 `appid` 一律留空，**真实 AppID 绝不入库**。
- 微信小程序 AppID 属公开标识，本仓库历史中曾短暂包含，最新提交已清除。

---

## 七、文档索引

| 文档 | 路径 |
| --- | --- |
| 前端运行文档（必读） | [app/README.md](app/README.md) |
| 产品需求文档 PRD | [deliverables/product-strategy/PRD-考研择校志愿填报-App-V1.0.md](deliverables/product-strategy/PRD-考研择校志愿填报-App-V1.0.md) |
| 头脑风暴记录 | [deliverables/product-strategy/brainstorm-kaoyan-school-choice-2026-10-12.md](deliverables/product-strategy/brainstorm-kaoyan-school-choice-2026-10-12.md) |
| 后端接口契约 | [deliverables/backend/API-契约-研志-V1.0.md](deliverables/backend/API-契约-研志-V1.0.md) |
| 后端建表脚本 | [deliverables/backend/schema-v1.0.sql](deliverables/backend/schema-v1.0.sql) |
