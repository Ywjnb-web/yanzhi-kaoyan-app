# 研志 · 考研择校志愿填报 —— 后端接口契约 V1.0

| 项 | 内容 |
|---|---|
| 文档版本 | V1.0 |
| 更新日期 | 2026-10-12 |
| 后端架构 | **DDD + MVC 融合** · Spring Boot 3 · Java 17 · MyBatis-Plus · PostgreSQL 14+ |
| 对应前端 | `app/`（uni-app x · uvue · UTS · pnpm · Tailwind 4） |
| 对应 PRD | `deliverables/product-strategy/PRD-考研择校志愿填报-App-V1.0.md` |
| 建表脚本 | `deliverables/backend/schema-v1.0.sql` |
| 覆盖范围 | FR-01 ~ FR-10 |

---

## 一、架构：DDD 与 MVC 怎么融合

两者不冲突，是**同一套代码的两个切面**：MVC 规定了「请求怎么进来、响应怎么出去」，DDD 规定了「业务规则放在哪、边界怎么划」。

| MVC 角色 | 在 DDD 中的落点 | 职责与红线 |
|---|---|---|
| **C**ontroller | `interfaces/rest/` | 只做协议转换、鉴权、参数校验。**禁止出现 if-else 业务判断**，禁止直接调 Mapper |
| **M**odel | `domain/` | 不是贫血 DTO，而是充血领域模型：聚合根 / 实体 / 值对象 / 领域服务。零框架依赖 |
| **V**iew | 本仓库的 `app/` | 前后端分离下「视图外移」到小程序端。后端只出 JSON，不产出 HTML/模板 |
| （MVC 没有的那层） | `application/` | 用例编排层。负责事务边界、跨聚合协作、领域事件投递 |

### 分层与依赖方向

```
        ┌──────────────────────────────────────────────────────┐
        │  interfaces/rest          ← MVC 的 Controller         │
        │  dto / assembler / advice（全局异常→统一响应包）        │
        └───────────────────────┬──────────────────────────────┘
                                │ 只能向下调用
        ┌───────────────────────▼──────────────────────────────┐
        │  application/             ← 用例编排（事务边界在此）   │
        │  ExamProfileAppService / PlanAppService / ...        │
        └───────────────────────┬──────────────────────────────┘
                                │
        ┌───────────────────────▼──────────────────────────────┐
        │  domain/                  ← DDD 核心，零框架依赖       │
        │  聚合根 · 实体 · 值对象 · 领域服务 · 仓储接口 · 领域事件 │
        └───────────────────────▲──────────────────────────────┘
                                │ 实现（依赖倒置）
        ┌───────────────────────┴──────────────────────────────┐
        │  infrastructure/          ← 技术细节                   │
        │  persistence(PO/Mapper/RepositoryImpl) · llm · cache  │
        └──────────────────────────────────────────────────────┘
```

**依赖倒置**：`domain.repository` 只声明接口（如 `PlanRepository.save(Plan)`），实现放在 `infrastructure.persistence`（用 MyBatis-Plus 写库并做 `PO ↔ 领域对象` 转换）。domain 包的 import 列表里**不允许出现 `org.springframework.*` 或 `com.baomidou.*`**——这是判断 DDD 有没有做歪的唯一硬标准。

### 建议包结构

```
com.yanzhi.kaoyan
├── interfaces/
│   ├── rest/                    AuthController · ExamProfileController
│   │                            CatalogController · PlanController · MetaController
│   ├── dto/request/             LoginRequest · ExamProfileSaveRequest · GenerateRequest ...
│   ├── dto/response/            ApiResponse<T> · ExamProfileVO · PlanVO · ProgramVO ...
│   ├── assembler/               VO ↔ 领域对象 转换（纯搬运，不含业务判断）
│   └── advice/                  GlobalExceptionHandler · ApiResponseAdvice
├── application/
│   ├── exam/                    ExamProfileAppService · ExamValidateAppService
│   ├── plan/                    PlanAppService · GenerateTaskAppService
│   ├── catalog/                 CatalogQueryService（只读，可直接查读模型视图）
│   ├── feedback/                FeedbackAppService
│   └── compliance/              DisclaimerAppService
├── domain/
│   ├── exam/                    model(ExamProfile·ScoreSheet·Preference·ProvinceSet)
│   │                            repository/ · service/ExamValidator · event/
│   ├── plan/                    model(Plan·PlanGroup·PlanItem·Mark)
│   │                            repository/ · service/PlanGenerator · event/
│   ├── catalog/                 model(School·Department·Program·ProgramYearStat)
│   │                            repository/
│   ├── identity/                model(Candidate·CandidateIdentity) · repository/
│   └── shared/                  DomainException · PageResult · AggregateRoot · DataNature
└── infrastructure/
    ├── persistence/po/          CandidatePO · PlanPO ...（数据库表的一比一映射）
    ├── persistence/mapper/      MyBatis-Plus Mapper（只被 RepositoryImpl 调用）
    ├── persistence/repository/  ExamProfileRepositoryImpl implements domain 接口
    ├── llm/                     PlanRankingPort 的适配器（供应商可替换）
    ├── cache/                   Redis：session_key、任务进度、生成限流
    └── config/
```

### 四条落地红线

1. **表边界 = 聚合边界**。`plan_item` 不直接持有 `program` 的字段副本，只存 `program_id`；跨聚合查询一律走读模型视图或应用层编排，不做嵌套写操作。
2. **Controller 里不出现业务分支**。校验格式可以，判断「分数够不够上某校」不行——那是领域服务的事。
3. **目录上下文（catalog）只读**。这是标准的 CQRS 倾斜：写侧由数据侧独立维护，读侧允许 `CatalogQueryService` 直接查 `v_program_current` 视图，不强制绕聚合。
4. **数值一律带双轨制标识**。任何返回分数/报录比/招生计划的响应，必须同时给 `dataNature` 与 `sourceNote`；`dataNature = "demo"` 时前端强制渲染「演示数据 / 非院校官方发布」。

---

## 二、通用约定

### 2.1 基础

| 项 | 约定 |
|---|---|
| Base URL | `https://api.yanzhi.example.com/api/v1`（本地调试 `http://localhost:8080/api/v1`） |
| 传输 | 全站 HTTPS，须在微信公众平台「开发设置 → 服务器域名」登记 request 合法域名 |
| 编码 | UTF-8；`Content-Type: application/json` |
| 时间 | ISO 8601 带时区，如 `2026-10-12T15:20:31+08:00` |
| 数值 | 分数为整数；比率为数字（`3.5` 表示 3.5:1），**不用字符串** |
| 分页 | 请求 `page`（从 1 起）、`size`（默认 20，上限 50）；响应体见 2.2 |
| 幂等 | 写接口支持 `Idempotency-Key` 请求头（UUID v4），同键 24h 内重复提交返回首次结果 |

### 2.2 统一响应包

成功：

```json
{
  "code": 0,
  "message": "ok",
  "traceId": "b7f3c1a2e9d04f6b",
  "dataVersion": "2026.10",
  "data": { }
}
```

失败：

```json
{
  "code": 42202,
  "message": "报考科目代码应为 6 位数字，如 085401",
  "traceId": "b7f3c1a2e9d04f6b",
  "data": null,
  "errors": [
    { "field": "subjectCode", "code": "FORMAT_INVALID", "message": "应为 6 位数字" }
  ]
}
```

分页 `data` 统一为：

```json
{
  "page": 1,
  "size": 20,
  "total": 137,
  "hasNext": true,
  "list": [ ]
}
```

### 2.3 鉴权

- `Authorization: Bearer <accessToken>`，access 有效期 **2 小时**，refresh **30 天**。
- **游客态可用的接口**：`/auth/*`、`/meta/*`、`/catalog/*`、`/exam-profile/validate`、`/plans/generate`、`/plans/*`（以 `X-Device-Id` 标识归属）、`/compliance/*`。
- 游客身份靠请求头 `X-Device-Id`（客户端生成并持久化的 UUID）识别，服务端在 `candidate_device` 表登记。
- 登录后，服务端按 `device_id` 把游客期产生的方案/档案**归并**到 candidate，归并策略见 §5.7。

### 2.4 错误码表

| code | HTTP | 含义 | 前端应有行为 |
|---|---|---|---|
| `0` | 200 | 成功 | — |
| `40001` | 400 | 参数校验失败 | 按 `errors[].field` 定位到表单字段高亮 |
| `40002` | 400 | 请求体格式错误 | 上报日志，提示「请求异常」 |
| `40101` | 401 | 未登录 | 触发静默登录（`wx.login` → `/auth/wechat/login`） |
| `40102` | 401 | access token 过期 | 用 refresh 换新后**自动重试一次** |
| `40103` | 401 | refresh 失效 | 清本地凭证，回落游客态，不清用户数据 |
| `40301` | 403 | 无权访问该资源 | 提示「无权访问」并返回上一级 |
| `40401` | 404 | 资源不存在 | 若为方案：提示「方案已删除」，返回我的方案列表 |
| `40901` | 409 | 状态冲突（同幂等键任务进行中） | 复用已有 `taskId` 继续轮询，不报错 |
| `42201` | 422 | 成绩超出满分 | 高亮对应科目（EX-01 延伸） |
| `42202` | 422 | 科目代码格式非法 | 高亮 `subjectCode` |
| `42203` | 422 | 意向省份为空 | 高亮省份选择区 |
| `42901` | 429 | 触发限流 | 生成接口按用户维度限 10 次/小时，提示稍后重试 |
| `50001` | 500 | 服务内部错误 | 通用兜底提示 + traceId 展示，便于报障 |
| `50301` | 503 | 院校数据源不可用 | 提示「数据源维护中」，**不展示任何降级数字** |
| `50302` | 503 | 大模型不可用 | **降级为纯规则方案**，响应带 `degraded: true`，前端须标注 |
| `50401` | 504 | 生成超时 | 保留任务态，允许在「我的方案」里稍后查看 |

---

## 三、限界上下文一 · Identity & Access（FR-10）

### 3.1 `POST /auth/wechat/login` — 微信登录

游客也可调用；首次调用创建 candidate。

**Request**
```json
{ "code": "081Xyz...", "deviceId": "5f2b9c1e-...", "nickname": "", "avatarUrl": "" }
```

**Response `data`**
```json
{
  "accessToken": "eyJhbGciOi...",
  "refreshToken": "eyJhbGciOi...",
  "expiresIn": 7200,
  "candidate": { "id": "uuid", "nickname": "考研的同学", "avatarUrl": "", "mobileMasked": "" },
  "merged": { "plans": 3, "examProfile": true }
}
```

| 说明 | 内容 |
|---|---|
| `code` | `wx.login()` 返回的一次性 code，服务端换 openid。**禁止客户端持有 session_key** |
| `merged` | 游客数据归并结果统计，前端可提示「已同步 3 份方案到账号」 |
| 落库 | `candidate` + `candidate_identity(provider='wechat')` + `candidate_device` |

### 3.2 `POST /auth/refresh` — 刷新令牌

**Request** `{ "refreshToken": "..." }` → **Response** 同 3.1 的 token 三件套。

### 3.3 `POST /auth/logout`
失效当前 access + refresh。**只清凭证，不动用户数据。**

### 3.4 `GET /candidates/me`
返回当前考生资料与数据概览（方案数、档案是否完整、最近生成时间）。

### 3.5 `DELETE /candidates/me/data` — 删除我的数据（FR-10）

| 说明 | 内容 |
|---|---|
| 行为 | 逻辑删除 candidate（`status=3`）并级联清理 exam_profile / plan / mark / feedback |
| 二次确认 | 服务端要求请求体带 `{ "confirm": "DELETE_ALL" }`，防误触 |
| 响应 | `{ "deletedAt": "...", "retentionDays": 15 }` |
| 合规 | 15 天冷静期后物理清除；期间用户重新登录可撤销（恢复 status=1） |

### 3.6 `GET /candidates/me/export` — 数据可携带（FR-10）
返回该考生的全部数据 JSON（档案 / 方案 / 标记 / 反馈），供用户下载留存。

---

## 四、限界上下文二 · ExamProfile（FR-01 / FR-02）

### 4.1 `GET /meta/dictionaries` — 字典下发

前端 `constants/dictionary.uts` 的线上来源，**改字典无需发版**。

```json
{
  "version": "2026.10",
  "provinces": {
    "A 区": ["北京", "天津", "河北", "...", "陕西"],
    "B 区": ["内蒙古", "广西", "...", "新疆"]
  },
  "subjectGroups": [
    { "label": "政治+英一+数一+408", "course1Name": "数学（一）", "course2Name": "计算机学科专业基础" }
  ],
  "subjectCodes": [ { "code": "085401", "label": "新一代电子信息技术" } ],
  "majors": ["计算机科学与技术", "软件工程", "..."],
  "tiers": ["985", "211", "双一流", "一本", "二本", "其他"],
  "degreeTypes": ["学硕", "专硕", "不限"],
  "strategies": ["求稳上岸优先", "冲名校优先", "地域优先", "性价比优先"]
}
```

### 4.2 `GET /meta/data-version`

```json
{ "dataVersion": "2026.10", "publishedAt": "2026-10-01T00:00:00+08:00",
  "dataNature": "demo", "sourceNote": "演示数据，非院校官方发布",
  "notice": "院校名称为真实公开信息；分数线、报录比等数值为演示数据。" }
```

### 4.3 `POST /exam-profile/validate` — 表单校验（EX-01）

把 `validateExam` 从端上搬到服务端做二次校验，端上保留本地快速校验以免每次输入都打网络。

**Request**
```json
{
  "provinces": ["江苏", "浙江"],
  "subjectCode": "085401",
  "subjectGroup": "政治+英一+数一+408",
  "tier": "211",
  "major": "计算机科学与技术",
  "targetSchool": "南京大学",
  "isCross": false,
  "politics": "72", "foreign": "68", "course1": "118", "course2": "105"
}
```

**Response**
```json
{ "valid": false,
  "errors": [
    { "field": "course2", "code": "EXCEEDS_FULL_MARK", "message": "业务课二成绩超过满分 150 分" }
  ],
  "computed": { "total": 363 } }
```

### 4.4 `PUT /exam-profile` — 保存档案（upsert）

**Request**：同 4.3 的字段，另可带 `"declaredTotal": 365`（用户手填总分，仅用于 EX-02 比对）。

**Response `data`** → `ExamInfoVO`（与前端 `types/models.uts` 的 `ExamInfo` 一一对应）

```json
{
  "region": "A 区",
  "provinces": ["江苏", "浙江"],
  "subjectCode": "085401",
  "subjectGroup": "政治+英一+数一+408",
  "tier": "211",
  "major": "计算机科学与技术",
  "targetSchool": "南京大学",
  "isCross": false,
  "politics": 72, "foreign": 68,
  "course1": 118, "course1Name": "数学（一）",
  "course2": 105, "course2Name": "计算机学科专业基础",
  "total": 363,
  "totalMismatch": 2,
  "dataVersion": "2026.10"
}
```

> `total` 由数据库生成列算出，服务端与端上都不会出现「各科之和与总分不一致」的脏数据；`totalMismatch` 非 0 时前端提示 EX-02。

### 4.5 `GET /exam-profile` / `PUT /exam-profile/preference` / `GET /exam-profile/preference`

偏好请求体即前端 `Preference`：

```json
{ "strategies": ["求稳上岸优先"], "regions": ["江浙沪"], "directions": ["人工智能"],
  "careers": ["互联网大厂"], "degreeType": "专硕" }
```

> 全空数组表示用户跳过偏好 → 方案侧 `weighted=false`，**方案页必须标注「未使用偏好加权」**（PRD FR-02）。

---

## 五、限界上下文三 · ProgramCatalog（FR-03）

### 5.1 `GET /catalog/chips` — 检索筛选项

```json
{ "chips": ["全部", "计算机", "江苏", "985"], "total": 15 }
```

### 5.2 `GET /catalog/programs` — 院校专业检索

| 参数 | 必填 | 说明 |
|---|---|---|
| `keyword` | 否 | 匹配院校名 / 专业名 / 院系名 / 省份 |
| `chip` | 否 | 快捷筛选项，默认「全部」 |
| `province` | 否 | 精确省份 |
| `majorCode` | 否 | 专业代码精确匹配 |
| `majorClass` | 否 | 专业大类 |
| `degreeType` | 否 | 专硕 / 学硕 |
| `targetSchool` | 否 | 只返回该院校下的专业 |
| `page` / `size` | 否 | 分页 |

**Response `list[]`** → 前端 `SearchItem`：

```json
{
  "id": "P001",
  "university": "南京大学 · 江苏",
  "province": "江苏",
  "region": "A 区",
  "major": "计算机科学与技术 · 专硕",
  "degreeType": "专硕",
  "quota": "统考 18 人",
  "scoreLine": "复试线 375（2025）",
  "applyRatio": "报录比 4.1:1",
  "noData": false,
  "dataNature": "demo",
  "sourceNote": "演示数据，非院校官方发布"
}
```

> **EX-03 约定**：`noData=true` 时 `quota` / `scoreLine` / `applyRatio` 一律返回空串，前端渲染「暂无数据」。**服务端不做任何插值或估算**——这是产品红线，不是技术选择。

### 5.3 `GET /catalog/programs/{programId}` — 专业详情（S06 数据表）

```json
{
  "id": "P001", "university": "南京大学", "province": "江苏", "region": "A 区",
  "department": "计算机学院", "major": "计算机科学与技术", "majorCode": "085404",
  "majorClass": "计算机类", "degreeType": "专硕", "duration": "3 年", "tuition": "1.8 万/年",
  "planTotal": 42, "recommendedQuota": 24, "examQuota": 18,
  "history": [
    { "year": "2025", "scoreLine": "375", "applyRatio": "4.1:1", "reExamRatio": "1.3:1", "quota": "18" },
    { "year": "2024", "scoreLine": "372", "applyRatio": "3.8:1", "reExamRatio": "1.25:1", "quota": "17" },
    { "year": "2023", "scoreLine": "368", "applyRatio": "3.5:1", "reExamRatio": "1.2:1", "quota": "16" }
  ],
  "dataNature": "demo", "sourceNote": "演示数据，非院校官方发布", "noData": false
}
```

### 5.4 `GET /catalog/schools` — 目标院校检索（FR-01 选填项）

| 参数 | 说明 |
|---|---|
| `keyword` | 模糊匹配院校名；空则返回全部收录院校 |
| `limit` | 默认 20 |

```json
{ "list": [ { "university": "南京大学", "province": "江苏", "region": "A 区", "level": "985" } ] }
```

> **只返回院校库内已收录的院校**。召回为空 = 该院校暂无数据，前端提示 EX-03，**绝不臆造**。
> 前端 `suggestSchools()` 与 `findSchool()` 都对接这一支接口（后者用 `keyword` 精确名 + `exact=true` 参数）。

---

## 六、限界上下文四 · PlanGeneration（FR-04 / FR-05 / FR-06 / FR-07）

### 6.1 为什么生成要走异步任务

大模型排序耗时不可控（3~30s），而且 S04「生成中」页面本身就要分三段展示进度。若用同步接口，要么长连接挂起（微信端易被判超时），要么端上假进度。**故：提交 → 拿 taskId → 轮询进度。**

### 6.2 `POST /plans/generate` — 提交生成

**Request**
```json
{
  "exam": { "provinces": ["江苏"], "subjectCode": "085401", "subjectGroup": "...",
             "tier": "211", "major": "计算机科学与技术", "targetSchool": "南京大学",
             "isCross": false, "politics": 72, "foreign": 68, "course1": 118, "course2": 105 },
  "preference": { "strategies": [], "regions": [], "directions": [], "careers": [], "degreeType": "专硕" },
  "marks": [ { "programId": "P004", "value": "ignore" } ],
  "planId": "plan_20261012_1531_a1b2"
}
```

请求头：`Idempotency-Key: <uuid>`（防用户连点两次生成）。

**Response（HTTP 202）**
```json
{ "taskId": "8f1c...", "status": "pending", "estimatedSeconds": 12 }
```

| 错误 | 处理 |
|---|---|
| `40901` | 已有同幂等键任务在跑 → 响应体直接返回既有 `taskId`，前端继续轮询，**不报错** |

### 6.3 `GET /plans/generate-tasks/{taskId}` — 轮询进度

```json
{
  "taskId": "8f1c...", "status": "running",
  "stageNo": 2, "stageLabel": "校验分数线与统考名额", "stageDetail": "数据库 2026.10 版",
  "percent": 66,
  "plan": null, "error": null, "degraded": false
}
```

- `status`: `pending` / `running` / `succeeded` / `failed` / `canceled`
- 轮询建议：**1.2s 一次，最多 30 次**，超时后提示「生成较慢，可在我的方案中查看」（对应 50401）
- `succeeded` 时 `plan` 字段直接给完整 `PlanVO`，**避免二次请求**
- `degraded=true`（大模型不可用降级为纯规则方案）→ 前端须显式标注

### 6.4 `GET /plans` — 我的方案列表

| 参数 | 说明 |
|---|---|
| `page` / `size` | 分页 |
| `source` | `app` / `imported` / `regenerated` |

列表项为精简结构（不带 `groups.items`），避免首屏拉取过大：

```json
{ "list": [ { "id": "plan_...", "name": "南京大学 · 计算机技术 择校方案",
              "createdAt": "2026-10-12T15:31:02+08:00", "examSummary": "总分 363 · 085401 · 江苏",
              "dataVersion": "2026.10", "weighted": false, "itemCount": 9, "belowAll": false } ] }
```

### 6.5 `GET /plans/{planId}` — 方案详情

`data` → 完整 `PlanVO`，与前端 `types/models.uts` 结构一致：

```json
{
  "id": "plan_...", "name": "...", "createdAt": "...",
  "examSummary": "总分 363 · 085401 · 江苏",
  "dataVersion": "2026.10", "weighted": false, "belowAll": false,
  "groups": [
    {
      "tierKey": "chong", "tierName": "冲", "tagline": "略高于当前竞争力，可尝试",
      "items": [
        {
          "id": "item_...", "programId": "P004", "tierKey": "chong", "tierName": "冲",
          "university": "东南大学", "province": "江苏", "region": "A 区",
          "department": "计算机科学与工程学院", "major": "计算机技术", "majorCode": "085404",
          "majorClass": "计算机类", "degreeType": "专硕", "duration": "3 年", "tuition": "1.8 万/年",
          "scoreLineTrend": "368 / 372 / 375", "applyRatio": "4.1:1", "reExamRatio": "1.3:1",
          "planTotal": 42, "recommendedQuota": 24, "quota": 18,
          "history": [ { "year": "2025", "scoreLine": "375", "applyRatio": "4.1:1",
                         "reExamRatio": "1.3:1", "quota": "18" } ],
          "probabilityLow": 30, "probabilityHigh": 45, "diff": -12,
          "reasons": ["近三年复试线稳定", "统考名额充足"],
          "dataVersion": "2026.10", "sourceYears": "2023-2025",
          "mark": "prefer",
          "dataNature": "demo", "sourceNote": "演示数据，非院校官方发布"
        }
      ]
    },
    { "tierKey": "wen", "tierName": "稳", "tagline": "...", "items": [] },
    { "tierKey": "bao", "tierName": "保", "tagline": "...", "items": [] }
  ]
}
```

### 6.6 `POST /plans/import` — 游客本地方案上云

登录时把端上攒的方案批量推上来（FR-10 的资产不丢）。

**Request**
```json
{ "plans": [ { "id": "plan_...", "name": "...", "createdAt": "...", "examSummary": "...",
               "dataVersion": "2026.10", "weighted": false, "belowAll": false, "groups": [] } ],
  "strategy": "skip_existing" }
```

`strategy`：`skip_existing`（默认，同 ID 跳过）/ `overwrite` / `keep_both`

**Response** `{ "imported": 3, "skipped": 1, "conflicts": [] }`

> 端上本地缓存**继续保留**作为离线兜底，不是搬走了就删。

### 6.7 `PUT /plans/{planId}/marks` — 设置标记（FR-06）

**Request** `{ "programId": "P004", "value": "ignore" }` → `value` ∈ `ignore` / `prefer`
**Response** `{ "programId": "P004", "value": "ignore", "ignoreCount": 2, "preferCount": 1 }`

`DELETE /plans/{planId}/marks/{programId}` 取消标记。

### 6.8 `POST /plans/{planId}/regenerate` — 调整并重新生成（FR-06）

**Request**
```json
{ "exam": { "...": "可只传变更字段" },
  "preference": { "...": "..." },
  "marks": [ { "programId": "P004", "value": "ignore" } ],
  "keepMarks": true }
```

**Response**：同 6.2，返回新 `taskId`；新方案 `source='regenerated'`、`regeneratedFrom=<原 planId>`。

### 6.9 `DELETE /plans/{planId}` — 删除方案
**Response** `{ "deleted": true, "planId": "..." }`

### 6.10 `POST /plans/{planId}/export` — 导出（FR-07）

**Request** `{ "format": "pdf", "includeDataTable": true, "includeDisclaimer": true }`

**Response** `{ "exportId": "exp_...", "status": "processing" }`

`GET /plans/{planId}/export/{exportId}` 轮询 → `{ "status": "succeeded", "fileUrl": "https://.../x.pdf", "expiresAt": "..." }`

> 导出文件**必须带免责声明与数据性质标注**（FR-08）；`fileUrl` 为临时签名地址，24h 失效。

---

## 七、限界上下文五 · Feedback（FR-09）与 Compliance（FR-08）

### 7.1 `POST /feedbacks`

```json
{ "planId": "plan_...", "itemId": "item_...", "kind": "inaccurate",
  "reason": "去年复试线与该院校公布不一致", "dataVersion": "2026.10" }
```

`kind` ∈ `useful` / `useless` / `inaccurate`。**`dataVersion` 必填**——没有它就无法判断是数据问题还是模型排序问题。

### 7.2 `GET /compliance/disclaimer` — 免责声明

```json
{ "version": "v1.0", "content": "...", "updatedAt": "...", "mustAccept": true }
```

### 7.3 `POST /compliance/disclaimer/accept`

```json
{ "version": "v1.0", "deviceId": "5f2b..." }
```

> 每次勾选**追加一行**留痕，不更新——这是合规审计证据。

---

## 八、接口一览表

| # | 方法 | 路径 | 鉴权 | FR | 说明 | 实现阶段 |
|---|---|---|---|---|---|---|
| 1 | POST | `/auth/wechat/login` | 游客 | FR-10 | 微信登录 | P0 |
| 2 | POST | `/auth/refresh` | 游客 | FR-10 | 刷新令牌 | P0 |
| 3 | POST | `/auth/logout` | 需登录 | FR-10 | 登出 | P0 |
| 4 | GET | `/candidates/me` | 需登录 | FR-10 | 考生资料 | P0 |
| 5 | DELETE | `/candidates/me/data` | 需登录 | FR-10 | 删除我的数据 | P1 |
| 6 | GET | `/candidates/me/export` | 需登录 | FR-10 | 数据可携带 | P1 |
| 7 | GET | `/meta/dictionaries` | 游客 | 全局 | 字典下发 | P0 |
| 8 | GET | `/meta/data-version` | 游客 | 全局 | 数据版本与性质 | P0 |
| 9 | POST | `/exam-profile/validate` | 游客 | FR-01 | 表单校验 | P0 |
| 10 | PUT | `/exam-profile` | 游客 | FR-01 | 保存档案 | P0 |
| 11 | GET | `/exam-profile` | 游客 | FR-01 | 读取档案 | P1 |
| 12 | PUT | `/exam-profile/preference` | 游客 | FR-02 | 保存偏好 | P0 |
| 13 | GET | `/exam-profile/preference` | 游客 | FR-02 | 读取偏好 | P1 |
| 14 | GET | `/catalog/chips` | 游客 | FR-03 | 筛选项 | P0 |
| 15 | GET | `/catalog/programs` | 游客 | FR-03 | 专业检索 | P0 |
| 16 | GET | `/catalog/programs/{id}` | 游客 | FR-03 | 专业详情 | P0 |
| 17 | GET | `/catalog/schools` | 游客 | FR-01/03 | 院校检索 | P0 |
| 18 | POST | `/plans/generate` | 游客 | FR-04 | 提交生成（异步） | P0 |
| 19 | GET | `/plans/generate-tasks/{id}` | 游客 | FR-04 | 生成进度 | P0 |
| 20 | GET | `/plans` | 游客 | FR-07 | 方案列表 | P0 |
| 21 | GET | `/plans/{planId}` | 游客 | FR-05 | 方案详情 | P0 |
| 22 | POST | `/plans/import` | 需登录 | FR-10 | 本地方案上云 | P1 |
| 23 | PUT | `/plans/{planId}/marks` | 游客 | FR-06 | 设置标记 | P0 |
| 24 | DELETE | `/plans/{planId}/marks/{programId}` | 游客 | FR-06 | 取消标记 | P0 |
| 25 | POST | `/plans/{planId}/regenerate` | 游客 | FR-06 | 调整重生成 | P1 |
| 26 | DELETE | `/plans/{planId}` | 游客 | FR-07 | 删除方案 | P0 |
| 27 | POST | `/plans/{planId}/export` | 游客 | FR-07 | 发起导出 | P1 |
| 28 | GET | `/plans/{planId}/export/{id}` | 游客 | FR-07 | 导出结果 | P1 |
| 29 | POST | `/feedbacks` | 游客 | FR-09 | 提交反馈 | P0 |
| 30 | GET | `/compliance/disclaimer` | 游客 | FR-08 | 免责声明 | P0 |
| 31 | POST | `/compliance/disclaimer/accept` | 游客 | FR-08 | 勾选留痕 | P0 |

---

## 九、前端对接映射（`app/api/`）

| 前端现状（同步函数） | 对接接口 | 迁移动作 |
|---|---|---|
| `toScore` / `isSixDigits` | 无 | **保留本地**。纯计算，走网络只会变慢 |
| `validateExam` | `POST /exam-profile/validate` | 本地快速校验保留；提交前调服务端二次校验 |
| `composeExam` | `PUT /exam-profile` | 提交时以服务端返回的 `ExamInfoVO` 为准 |
| `generatePlan` | `POST /plans/generate` + 轮询 | 改异步 |
| `generateStages` | 轮询响应 | 直接读 `stageLabel` / `stageDetail`，**不再端上硬编码文案** |
| `searchPrograms` | `GET /catalog/programs` | 改分页 + `await` |
| `suggestSchools` / `findSchool` | `GET /catalog/schools` | 加 300ms 防抖 |
| `listPlans` / `savePlan` / `removePlan` | `GET/POST/DELETE /plans` | 本地缓存**保留为离线兜底**，网络优先 |
| `submitFeedback` | `POST /feedbacks` | 改 `await`，失败入本地队列重试 |
| `saveExamDraft` / `loadExamDraft` | 无（本地） | 弱网草稿仍本地；登录后由 `PUT /exam-profile` 同步 |
| `constants/dictionary.uts` 常量 | `GET /meta/dictionaries` | 首次启动拉取并本地缓存，失败回落硬编码常量 |

### 9.1 已预留在代码里的位置

| 文件 | 作用 |
|---|---|
| `app/api/config.uts` | `BASE_URL` / `USE_MOCK` / 超时 / 设备 ID —— **切换真后端只改这一个文件** |
| `app/api/endpoints.uts` | 31 个接口路径常量，与本文档 §8 一一对应 |
| `app/api/http.uts` | 统一请求封装：响应包解包、错误码映射、401 自动刷新重试一次 |
| `app/api/remote.uts` | 异步接口层，与本文档 DTO 对齐；未接后端时抛明确的未连接错误 |

### 9.2 切换步骤

1. `app/api/config.uts` 里把 `USE_MOCK` 置为 `false`，填入 `BASE_URL`。
2. 微信公众平台登记 `request` 合法域名（必须 HTTPS）。
3. 逐页把同步调用换成 `await` 异步版（顺序建议：检索页 → 生成链路 → 我的方案 → 反馈）。
4. 保留 `api/index.uts` 的同步实现作为**离线降级**——真正断网时页面仍可用。

---

## 十、待确认与风险

| # | 项 | 说明 | 倾向 |
|---|---|---|---|
| 1 | 生成接口是否保留同步通道 | 同步版实现简单，但大模型超时会拖死连接 | 只留异步，同步版仅测试环境用 |
| 2 | 游客方案的数据保留期 | 未登录数据挂 `device_id`，长期不清理会积压 | 90 天，过期前一周推送提醒 |
| 3 | 院校层次标签口径 | 现按通行口径填（北外 211、杭电双非一本） | 统一改「双一流」新口径需一次性刷数据 |
| 4 | `program_year_stat` 是否补 `major_code` 冗余 | 详情页数据表若要展示专业代码，视图已给可免冗余 | 先不冗余，走视图 |
| 5 | 导出文件生成方式 | 服务端渲染 PDF vs 端上截图 | 服务端渲染，便于强制加免责声明 |
| 6 | 数据真实化路径 | 数值目前全为 `demo` | 取得院校授权后按年批次置 `official`，双轨可并存 |

---

## 合规声明

本文档为产品与技术设计文档，不构成任何报考建议。

- 院校名称、院系名称、专业名称、专业代码为**真实公开信息**；
- 复试线、报录比、复录比、招生计划、推免人数、学费等数值，在 `dataNature = "demo"` 期间均为**演示数据，非院校官方发布**，不得用于实际报考决策；
- 接口设计中所有涉及个人信息的字段（手机号等）一律密文落库、脱敏返回，遵循最小必要原则；
- 最终报考信息请以各招生单位官方发布的招生章程与专业目录为准。
