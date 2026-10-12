-- ══════════════════════════════════════════════════════════════════════════
--  研志 · 考研择校志愿填报 —— PostgreSQL 建表脚本 V1.0
--
--  架构：DDD + MVC 融合
--    · 表边界 = 聚合边界。跨聚合只存 ID 引用，不建外键级联（避免聚合耦合）。
--    · 聚合内部的值对象集合用独立表（如 exam_profile_province）或 text[]。
--    · 事实数值与演示数值分离，靠 data_nature 字段承载「数据双轨制」。
--
--  数据性质声明（硬约定，请勿删改）：
--    院校名称 / 院系 / 专业 / 专业代码 = 真实公开信息
--    复试线 / 报录比 / 复录比 / 招生计划 / 推免人数 / 学费 = 演示数值，非院校官方发布
--    → 落库时 program_year_stat.data_nature 必须为 'demo'，source_note 保留提示文案。
--
--  DB: PostgreSQL 14+
--  编码: UTF8 · 时区: Asia/Shanghai（timestamptz 存 UTC，展示层转换）
-- ══════════════════════════════════════════════════════════════════════════

create extension if not exists "pgcrypto";   -- gen_random_uuid()
create extension if not exists "pg_trgm";    -- 院校 / 专业名称模糊检索

-- ══════════════════════════════════════════════════════════════════════════
--  限界上下文 1 · Identity & Access（考生身份）
-- ══════════════════════════════════════════════════════════════════════════

comment on schema public is '研志 · 考研择校志愿填报';

create table candidate (
    id            uuid primary key default gen_random_uuid(),
    nickname      varchar(64)  not null default '',
    avatar_url    varchar(512) not null default '',
    mobile_enc    varchar(128),                       -- 手机号密文（AES-GCM），展示层脱敏
    status        smallint     not null default 1,    -- 1 正常 / 2 注销中 / 3 已注销
    last_login_at timestamptz,
    created_at    timestamptz  not null default now(),
    updated_at    timestamptz  not null default now(),
    constraint ck_candidate_status check (status in (1, 2, 3))
);
comment on table  candidate is '聚合根 · 考生（FR-10）。注销走软删除，便于审计与恢复。';
comment on column candidate.mobile_enc is '手机号密文。禁止明文落库，禁止写入日志。';

create table candidate_identity (
    id           uuid primary key default gen_random_uuid(),
    candidate_id uuid        not null references candidate (id) on delete cascade,
    provider     varchar(16) not null,                -- wechat / mobile
    open_id      varchar(64) not null,                -- 微信 openid（同小程序内唯一）
    union_id     varchar(64),                         -- 微信 unionid（跨应用唯一，可空）
    created_at   timestamptz not null default now(),
    constraint uk_identity_provider_openid unique (provider, open_id)
);
comment on table candidate_identity is '值对象 · 第三方身份绑定。session_key 不入库，缓存于 Redis（5min TTL）。';
create index idx_identity_candidate on candidate_identity (candidate_id);

create table candidate_device (                       -- 游客态：未登录也能留存方案
    id           bigserial primary key,
    candidate_id uuid references candidate (id) on delete set null,
    device_id    varchar(64) not null,
    first_seen_at timestamptz not null default now(),
    last_seen_at  timestamptz not null default now(),
    constraint uk_device unique (device_id)
);
comment on table candidate_device is '匿名设备指纹。游客生成的方案挂 device_id，登录后按 device_id 归并到 candidate。';

-- ══════════════════════════════════════════════════════════════════════════
--  限界上下文 2 · ExamProfile（考试档案：FR-01 考生信息 + FR-02 兴趣偏好）
--  聚合根 = exam_profile；score_sheet / province 集合 / preference 均为聚合内成员
-- ══════════════════════════════════════════════════════════════════════════

create table exam_profile (
    id               uuid primary key default gen_random_uuid(),
    candidate_id     uuid references candidate (id) on delete cascade,
    device_id        varchar(64),
    -- ── 值对象：档案快照（提交态 ExamInfo 的可持久化部分）──
    subject_code     char(6)     not null,            -- 报考科目代码，如 085401
    subject_group    varchar(32) not null,            -- 初试科目组合，如 政治+英一+数一+408
    undergrad_tier   varchar(16) not null,            -- 本科院校层次
    undergrad_major  varchar(64) not null,            -- 本科专业（可手输）
    target_school    varchar(128) not null default '',-- 目标院校，选填
    is_cross_major   boolean     not null default false,
    region           varchar(16) not null default '', -- 派生值对象：A 区 / B 区 / A、B 区
    data_version     varchar(16) not null,            -- 生成该档案时引用的数据版本
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    constraint ck_exam_subject_code check (subject_code ~ '^[0-9]{6}$')
);
comment on table exam_profile is '聚合根 · 考试档案（FR-01）。一名考生一份档案，可覆盖更新。';
comment on column exam_profile.region is '由意向省份集合推导，不单独维护，避免与 province 集合不一致。';

-- 聚合内值对象集合：意向省份（多选、有序）
create table exam_profile_province (
    exam_profile_id uuid     not null references exam_profile (id) on delete cascade,
    sort_no         smallint not null,
    province        varchar(16) not null,
    primary key (exam_profile_id, province)
);
comment on table exam_profile_province is '值对象集合 · 意向省份（A/B 区均可，可跨区累计）。';

-- 聚合内实体：成绩单（各科 + 自动汇总总分）
create table score_sheet (
    id              uuid primary key default gen_random_uuid(),
    exam_profile_id uuid     not null references exam_profile (id) on delete cascade,
    politics        smallint not null check (politics between 0 and 100),
    foreign_lang    smallint not null check (foreign_lang between 0 and 100),
    course1         smallint not null check (course1 between 0 and 150),
    course1_name    varchar(32) not null default '业务课一',
    course2         smallint not null check (course2 between 0 and 150),
    course2_name    varchar(32) not null default '业务课二',
    -- 总分由数据库生成，杜绝「声明总分 ≠ 各科之和」的脏数据（对应前端 EX-02）
    total           smallint generated always as (politics + foreign_lang + course1 + course2) stored,
    declared_total  smallint,                          -- 用户手填的总分，仅用于 EX-02 差异比对
    created_at      timestamptz not null default now(),
    constraint uk_score_exam unique (exam_profile_id)
);
comment on table  score_sheet is '聚合内实体 · 成绩单。total 为生成列，业务层不得写入。';
comment on column score_sheet.declared_total is '用户若手填总分，存此列；与 total 不等时触发 EX-02 提示。';

-- 值对象：兴趣偏好（1-1，全选填）
create table preference (
    exam_profile_id uuid primary key references exam_profile (id) on delete cascade,
    degree_type     varchar(8) not null default '',    -- 学硕 / 专硕 / 不限
    strategies      text[]     not null default '{}',  -- 求稳上岸 / 冲名校 / 地域优先 / 性价比
    regions         text[]     not null default '{}',
    directions      text[]     not null default '{}',
    careers         text[]     not null default '{}',
    updated_at      timestamptz not null default now()
);
comment on table preference is '值对象 · 偏好（FR-02）。空数组 = 未参与加权，方案页须标注「未使用偏好加权」。';

create index idx_exam_profile_candidate on exam_profile (candidate_id);
create index idx_exam_profile_device    on exam_profile (device_id);

-- ══════════════════════════════════════════════════════════════════════════
--  限界上下文 3 · ProgramCatalog（院校专业目录：FR-03）
--  只读为主。聚合根 = program（招生专业单元）
-- ══════════════════════════════════════════════════════════════════════════

create table school (
    id              uuid primary key default gen_random_uuid(),
    name            varchar(128) not null,
    province        varchar(16)  not null,
    region          varchar(8)   not null,             -- A 区 / B 区
    level_tag       varchar(16)  not null default '',  -- 985 / 211 / 双一流 / 一本 ...
    level_verified  boolean      not null default false, -- 层次是否已按官方口径核对
    created_at      timestamptz  not null default now(),
    constraint uk_school_name unique (name),
    constraint ck_school_region check (region in ('A 区', 'B 区'))
);
comment on table  school is '院校（真实公开信息）。level_tag 为通行口径标注，未核对时 level_verified=false。';
create index idx_school_name_trgm on school using gin (name gin_trgm_ops);
create index idx_school_province  on school (province);

create table department (
    id        uuid primary key default gen_random_uuid(),
    school_id uuid         not null references school (id) on delete cascade,
    name      varchar(128) not null,                   -- 院系名称（真实公开信息）
    constraint uk_department unique (school_id, name)
);
comment on table department is '院系。隶属院校，同一院校下院系名唯一。';

create table program (
    id             varchar(16) primary key,            -- 业务主键，沿用 P001 形态
    department_id  uuid         not null references department (id) on delete restrict,
    major_name     varchar(128) not null,              -- 专业名称（真实公开信息）
    major_code     char(6)      not null,              -- 专业代码（真实公开信息）
    major_class    varchar(32)  not null,              -- 计算机类 / 电子信息类 ...
    degree_type    varchar(8)   not null,              -- 专硕 / 学硕
    duration       varchar(16)  not null,              -- 3 年
    tuition        varchar(32)  not null,              -- 演示数值
    direction_tags text[]       not null default '{}',
    region_tags    text[]       not null default '{}',
    status         smallint     not null default 1,    -- 1 在招 / 2 停招 / 3 待更新
    created_at     timestamptz  not null default now(),
    updated_at     timestamptz  not null default now(),
    constraint ck_program_major_code check (major_code ~ '^[0-9]{6}$'),
    constraint ck_program_status check (status in (1, 2, 3))
);
comment on table program is '聚合根 · 招生专业单元。与考生填写的「报考科目代码」同属专业代码体系。';
create index idx_program_major_code  on program (major_code);
create index idx_program_major_class on program (major_class);
create index idx_program_department  on program (department_id);

-- 逐年数值表：所有会随时间变化的数字都放这里，绝不上提到 program
create table program_year_stat (
    id                bigserial primary key,
    program_id        varchar(16)  not null references program (id) on delete cascade,
    stat_year         smallint     not null,
    score_line        smallint,                        -- 复试线
    apply_ratio       numeric(6,2),                    -- 报录比
    re_exam_ratio     numeric(6,2),                    -- 复录比
    plan_total        smallint,                        -- 招生计划总数
    recommended_quota smallint,                        -- 推免录取数
    -- ── 数据双轨制落点 ──
    data_nature       varchar(16)  not null default 'demo',
    source_note       varchar(255) not null default '演示数据，非院校官方发布',
    published_at      date,
    created_at        timestamptz  not null default now(),
    constraint uk_stat_program_year unique (program_id, stat_year),
    constraint ck_stat_nature check (data_nature in ('demo', 'official'))
);
comment on table  program_year_stat is '逐年数值。data_nature 决定前端是否强制展示「演示数据」标识。';
comment on column program_year_stat.data_nature is 'demo=演示虚构数值（当前唯一取值）；official=院校官方发布（取得授权后方可置位）。';

create index idx_stat_program_year on program_year_stat (program_id, stat_year desc);

-- 读模型视图：把「最新一年」拍平，供检索列表直接读，避免应用层拼装
create view v_program_current as
select p.id                                        as program_id,
       s.id                                        as school_id,
       s.name                                      as university,
       s.province,
       s.region,
       s.level_tag,
       d.name                                      as department,
       p.major_name                                as major,
       p.major_code,
       p.major_class,
       p.degree_type,
       p.duration,
       p.tuition,
       p.direction_tags,
       p.region_tags,
       cur.stat_year,
       cur.score_line,
       cur.apply_ratio,
       cur.re_exam_ratio,
       cur.plan_total,
       cur.recommended_quota,
       coalesce(cur.plan_total, 0) - coalesce(cur.recommended_quota, 0) as exam_quota,
       coalesce(cur.data_nature, 'demo')           as data_nature,
       coalesce(cur.source_note, '演示数据，非院校官方发布') as source_note,
       -- 数值缺失即置真，前端据此渲染「暂无数据」（EX-03），后端不做任何估算
       (cur.score_line is null or cur.plan_total is null) as no_data
from program p
         join department d on d.id = p.department_id
         join school s on s.id = d.school_id
         left join lateral (select st.*
                            from program_year_stat st
                            where st.program_id = p.id
                            order by st.stat_year desc
                            limit 1) cur on true
where p.status = 1;

comment on view v_program_current is '读模型 · 院校专业当前视图（最新一年数值拍平）。检索接口直接查它。';

-- ══════════════════════════════════════════════════════════════════════════
--  限界上下文 4 · PlanGeneration（方案：FR-04 生成 / FR-05 展示 / FR-06 调整 / FR-07 保存导出）
--  聚合根 = plan；plan_group / plan_item 为聚合内成员
-- ══════════════════════════════════════════════════════════════════════════

create table plan (
    id                     varchar(32) primary key,     -- 客户端生成的业务 ID（离线可用）
    candidate_id           uuid references candidate (id) on delete cascade,
    device_id              varchar(64),                 -- 游客方案
    name                   varchar(128) not null,
    exam_summary           varchar(255) not null,       -- 列表页展示摘要
    -- 生成时的档案与偏好快照：档案后续被改动，历史方案仍可复现（审计刚需）
    exam_profile_snapshot  jsonb        not null,
    preference_snapshot    jsonb        not null default '{}'::jsonb,
    data_version           varchar(16)  not null,
    weighted               boolean      not null default false,
    below_all              boolean      not null default false,   -- 命中 EX-07
    source                 varchar(16)  not null default 'app',   -- app / imported / regenerated
    regenerated_from       varchar(32),                          -- 由哪份方案重生成而来
    created_at             timestamptz  not null default now(),
    updated_at             timestamptz  not null default now(),
    constraint ck_plan_owner check (candidate_id is not null or device_id is not null)
);
comment on table  plan is '聚合根 · 择校方案（FR-04/05）。快照字段保证历史方案可复现（审计刚需）。';
comment on column plan.exam_profile_snapshot is '生成瞬间的档案快照。档案变更后不得回写此列。';

create index idx_plan_candidate on plan (candidate_id, created_at desc);
create index idx_plan_device    on plan (device_id, created_at desc);

create table plan_group (
    id         uuid primary key default gen_random_uuid(),
    plan_id    varchar(32) not null references plan (id) on delete cascade,
    tier_key   varchar(8)  not null,        -- chong / wen / bao
    tier_name  varchar(8)  not null,        -- 冲 / 稳 / 保
    tagline    varchar(128) not null default '',
    sort_no    smallint    not null,
    constraint uk_group_plan_tier unique (plan_id, tier_key)
);
comment on table plan_group is '聚合内实体 · 分档（冲/稳/保）。tagline 为该档一句话说明。';

create table plan_item (
    id               varchar(48) primary key,
    plan_id          varchar(32) not null references plan (id) on delete cascade,  -- 冗余，便于唯一约束
    plan_group_id    uuid        not null references plan_group (id) on delete cascade,
    program_id       varchar(16) not null references program (id) on delete restrict,
    sort_no          smallint    not null,
    probability_low  smallint,              -- 录取概率区间（演示值）
    probability_high smallint,
    diff             smallint,              -- 与考生总分之差
    reasons          text[]      not null default '{}',   -- 推荐理由
    data_version     varchar(16) not null,
    source_years     varchar(32) not null default '',     -- 数据来源年份
    created_at       timestamptz not null default now(),
    constraint uk_item_plan_program unique (plan_id, program_id),
    constraint ck_probability check (
        probability_low is null or probability_high is null
            or (probability_low between 0 and 100 and probability_high between 0 and 100
                and probability_low <= probability_high))
);
create index idx_item_group   on plan_item (plan_group_id, sort_no);
create index idx_item_program on plan_item (program_id);

-- FR-06 用户标记：不考虑 / 优先考虑（与方案绑定，重生成时作为输入）
create table plan_item_mark (
    plan_id     varchar(32) not null references plan (id) on delete cascade,
    program_id  varchar(16) not null references program (id) on delete cascade,
    mark_value  varchar(16) not null,        -- ignore / prefer
    updated_at  timestamptz not null default now(),
    primary key (plan_id, program_id),
    constraint ck_mark_value check (mark_value in ('ignore', 'prefer'))
);
comment on table plan_item_mark is 'FR-06 标记。同一 (方案, 专业) 唯一，同值再点由应用层解释为取消。';

-- 异步生成任务：对应 S04「生成中」页面的三段进度
create table generate_task (
    id               uuid primary key default gen_random_uuid(),
    candidate_id     uuid references candidate (id) on delete cascade,
    device_id        varchar(64),
    status           varchar(16) not null default 'pending',  -- pending/running/succeeded/failed/canceled
    stage_no         smallint    not null default 0,          -- 0~3
    stage_label      varchar(64) not null default '',
    stage_detail     varchar(128) not null default '',
    request_snapshot jsonb       not null,                    -- 入参快照，失败可复现
    result_plan_id   varchar(32) references plan (id) on delete set null,
    error_code       varchar(32),
    idempotency_key  varchar(64),                             -- 防重复点击生成
    created_at       timestamptz not null default now(),
    started_at       timestamptz,
    finished_at      timestamptz,
    constraint ck_task_status check (
        status in ('pending', 'running', 'succeeded', 'failed', 'canceled'))
);
comment on table generate_task is '生成任务。LLM 耗时不可控，故生成走异步任务 + 轮询，而非长连接挂起。';
create unique index uk_task_idempotency on generate_task (idempotency_key)
    where idempotency_key is not null;
create index idx_task_owner on generate_task (candidate_id, created_at desc);

-- ══════════════════════════════════════════════════════════════════════════
--  限界上下文 5 · Feedback（FR-09）与 Compliance（FR-08）
-- ══════════════════════════════════════════════════════════════════════════

create table feedback (
    id           uuid primary key default gen_random_uuid(),
    candidate_id uuid references candidate (id) on delete set null,
    device_id    varchar(64),
    plan_id      varchar(32) references plan (id) on delete set null,
    item_id      varchar(48),                 -- 推荐项 ID（可空：方案级反馈）
    kind         varchar(16) not null,        -- useful / useless / inaccurate
    reason       varchar(512) not null default '',
    data_version varchar(16) not null,        -- 必填，用于归因到具体数据批次
    created_at   timestamptz not null default now(),
    constraint ck_feedback_kind check (kind in ('useful', 'useless', 'inaccurate'))
);
comment on table feedback is 'FR-09 反馈。data_version 必填，否则无法定位是数据问题还是模型问题。';
create index idx_feedback_plan on feedback (plan_id, created_at desc);

create table disclaimer_version (
    version      varchar(16) primary key,
    content      text        not null,
    is_current   boolean     not null default false,
    effective_at timestamptz not null default now()
);
comment on table disclaimer_version is 'FR-08 免责声明版本。文案改版必须新增版本，不得原地覆盖。';

-- 仅允许一个当前版本
create unique index uk_disclaimer_current on disclaimer_version (is_current) where is_current;

create table disclaimer_acceptance (
    id           bigserial primary key,
    candidate_id uuid references candidate (id) on delete cascade,
    device_id    varchar(64),
    version      varchar(16) not null references disclaimer_version (version),
    accepted_at  timestamptz not null default now()
);
comment on table disclaimer_acceptance is '勾选留痕（合规审计证据）。每次勾选追加一行，不更新。';
create index idx_acceptance_candidate on disclaimer_acceptance (candidate_id, accepted_at desc);

-- ══════════════════════════════════════════════════════════════════════════
--  支撑表 · 字典下发 与 领域事件发件箱
-- ══════════════════════════════════════════════════════════════════════════

create table dictionary_item (
    id          bigserial primary key,
    dict_type   varchar(32) not null,   -- province / subject_group / subject_code / major / tier / strategy
    code        varchar(32) not null,
    label       varchar(64) not null,
    parent_code varchar(32) not null default '',   -- 如省份归属的 A/B 区
    ext         jsonb       not null default '{}'::jsonb,
    sort_no     smallint    not null default 0,
    enabled     boolean     not null default true,
    constraint uk_dict unique (dict_type, code)
);
comment on table dictionary_item is '字典表。前端 constants/dictionary.uts 的线上来源，改字典无需发版。';
create index idx_dict_type on dictionary_item (dict_type, sort_no) where enabled;

create table domain_event_outbox (
    id             bigserial primary key,
    aggregate_type varchar(32) not null,
    aggregate_id   varchar(64) not null,
    event_type     varchar(64) not null,
    payload        jsonb       not null,
    occurred_at    timestamptz not null default now(),
    published_at   timestamptz
);
comment on table domain_event_outbox is '事务性发件箱。领域事件与业务写入同事务落库，再由投递器异步发布，保证不丢事件。';
create index idx_outbox_unpublished on domain_event_outbox (occurred_at) where published_at is null;

-- ══════════════════════════════════════════════════════════════════════════
--  初始化数据（演示用）
-- ══════════════════════════════════════════════════════════════════════════

insert into disclaimer_version (version, content, is_current)
values ('v1.0',
        '本产品提供的院校名称、院系与专业信息为公开信息整理；分数线、报录比、复录比、招生计划、推免人数、学费等数值均为演示数据，非院校官方发布，不得作为报考决策依据。最终请以各招生单位官方发布的招生章程与专业目录为准。',
        true)
on conflict (version) do nothing;

-- A/B 区省份字典（真实公开信息）
insert into dictionary_item (dict_type, code, label, parent_code, sort_no) values
 ('province', '北京',   '北京',   'A 区', 1),
 ('province', '天津',   '天津',   'A 区', 2),
 ('province', '河北',   '河北',   'A 区', 3),
 ('province', '山西',   '山西',   'A 区', 4),
 ('province', '辽宁',   '辽宁',   'A 区', 5),
 ('province', '吉林',   '吉林',   'A 区', 6),
 ('province', '黑龙江', '黑龙江', 'A 区', 7),
 ('province', '上海',   '上海',   'A 区', 8),
 ('province', '江苏',   '江苏',   'A 区', 9),
 ('province', '浙江',   '浙江',   'A 区', 10),
 ('province', '安徽',   '安徽',   'A 区', 11),
 ('province', '福建',   '福建',   'A 区', 12),
 ('province', '江西',   '江西',   'A 区', 13),
 ('province', '山东',   '山东',   'A 区', 14),
 ('province', '河南',   '河南',   'A 区', 15),
 ('province', '湖北',   '湖北',   'A 区', 16),
 ('province', '湖南',   '湖南',   'A 区', 17),
 ('province', '广东',   '广东',   'A 区', 18),
 ('province', '重庆',   '重庆',   'A 区', 19),
 ('province', '四川',   '四川',   'A 区', 20),
 ('province', '陕西',   '陕西',   'A 区', 21),
 ('province', '内蒙古', '内蒙古', 'B 区', 1),
 ('province', '广西',   '广西',   'B 区', 2),
 ('province', '海南',   '海南',   'B 区', 3),
 ('province', '贵州',   '贵州',   'B 区', 4),
 ('province', '云南',   '云南',   'B 区', 5),
 ('province', '西藏',   '西藏',   'B 区', 6),
 ('province', '甘肃',   '甘肃',   'B 区', 7),
 ('province', '青海',   '青海',   'B 区', 8),
 ('province', '宁夏',   '宁夏',   'B 区', 9),
 ('province', '新疆',   '新疆',   'B 区', 10)
on conflict (dict_type, code) do nothing;

-- ══════════════════════════════════════════════════════════════════════════
--  最小权限（应用侧账号不应拥有 DDL 权限）
-- ══════════════════════════════════════════════════════════════════════════

-- create role yanzhi_app login password '<从密钥管理服务注入>';
-- grant usage on schema public to yanzhi_app;
-- grant select on v_program_current, dictionary_item, disclaimer_version to yanzhi_app;
-- grant select, insert, update, delete on
--     candidate, candidate_identity, candidate_device,
--     exam_profile, exam_profile_province, score_sheet, preference,
--     plan, plan_group, plan_item, plan_item_mark, generate_task,
--     feedback, disclaimer_acceptance to yanzhi_app;
-- grant usage, select on all sequences in schema public to yanzhi_app;
-- -- 目录数据只读、且由数据侧单独账号维护
-- revoke insert, update, delete on school, department, program, program_year_stat from yanzhi_app;

-- ══════════════════════════════════════════════════════════════════════════
--  迁移说明
--   · 版本化迁移建议放 Flyway：V1__init.sql（本文件）、V2__xxx.sql ...
--   · 所有 DDL 变更必须先加字段再用、先建索引再发版，禁止直接 rename/drop 线上列。
-- ══════════════════════════════════════════════════════════════════════════
