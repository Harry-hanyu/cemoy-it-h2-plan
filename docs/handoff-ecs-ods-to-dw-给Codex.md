# Handoff：ECS 已落 ODS → DataWorks 后续加工 — 给 Codex

> 交接人：Cursor（本机）→ Codex（另一台）  
> 日期：2026-11-26  
> 仓库：**本仓 `hanlu-odps-sync`（采集主仓）** + 规划仓 `cemoy-it-h2-plan`（字典/排期；路径历史前缀，非前东家部署）  
> 目的：ECS→MaxCompute 的 ODS **已在跑**；**DataWorks 侧尚未建齐 ODS 声明节点 / DWD / DIM / 调度依赖**，无法在 DW 上继续加工。请 Codex **只做 DW 粘贴包与工作流**，不要重做 ECS 采集。

---

## 0. 范围铁律

### 要做（DataWorks / MaxCompute 加工层）

1. 在 DW 工作空间 **「业财一体」**、MC 项目 **`hanlu_odps`** 内，按平台建目录与节点（建议：`ODS/…`、`DWD/…`、`DIM/…`、`ADS/…`、`SYS`）。
2. 用本仓 `sql/ods/**` DDL（及必要时从 `ensure_table` 已存在的线上表 `DESC`）**登记/对齐 ODS 表**；COMMENT **必须中文**（见既有 OA 规范）。
3. 按业财字典 **v3** 优先落地 **聚水潭 / 领猫 → 成本与库存 DWD**；跨境平台 ODS→DWD 可并行但勿阻塞批发链路。
4. 钉钉 OA：已有粘贴包 `dataworks/oa_reimburse/`，以**补齐线上节点/依赖/fee_detail**为主，勿推倒重来。
5. 产出仍落本仓 `dataworks/<域>/` + 更新本仓与 `cemoy-it-h2-plan` 的 `progress.md`，**commit + push**。

### 禁止

- **禁止**把韩路工作写进任何 `cemoy-*` 业务系统 / 旧 DataWorks / 旺店通链路。  
- **禁止**「旺店通」纳入本仓：韩路采集是 **聚水潭 + 领猫 + 跨境平台 + 钉钉 OA + TikTok Ads**；旺店通属前东家，本 handoff **不交付**。  
- **禁止**改 ECS 日批默认策略去「顺便重拉全历史」；回补有单独脚本/口径文档。  
- **禁止**密钥 / `*.local.env` / `secrets/*.env` / `platform-api.json` 进 Git。  
- **禁止**旧口径「大贸」或「15 天平滑成本」；统一 **批发/跨境**，成本 **按天、次日生效**。

### 权威口径

- 字典 v3：桌面 `~/Desktop/韩路/财务需求/规则定义/V3/业财一体化-数据字典与取数规则-v3.xlsx`  
  仓内副本：`cemoy-it-h2-plan/docs/…-v3.xlsx`  
- 蓝图：`docs/ods-领猫聚水潭接入蓝图.md`、`docs/dim11-采购价与资料包价规则.md`、`docs/ods-回补与调度口径.md`、`docs/jushuitan-仓与供货口径.md`

---

## 1. 分工（已拍板，勿颠倒）

| 层 | 谁负责 | 现状（2026-11-26） |
|----|--------|-------------------|
| API → ODS（Tunnel / PyODPS 写分区） | **ECS cron**（本仓 `scripts/run_*_daily.py`） | **已上线**（见 §2） |
| ODS 表物理存在 | ECS `ensure_table` 首次写入时自动建 | **多数已在 `hanlu_odps`**；DW 目录可能仍空 |
| ODS DDL 声明 / 质检 / 依赖 | **DataWorks** | **缺口：请 Codex 补** |
| DWD / DIM / ADS / 中间表 | **DataWorks** | **仅钉钉 OA 有粘贴包；其余几乎空白** |
| 调度 | ECS 管采集时刻；DW 管 T+1 清洗（读 ODS `ds`） | 采集 cron 已装；DW 工作流待建 |

---

## 2. 两台 ECS（采集拓扑）

| 角色 | 实例 | IP | 目录 | 写 MC | 跑什么 |
|------|------|-----|------|-------|--------|
| **杭州主采集** | `i-bp1fh39fq2qo2le4n1e5` | `118.178.99.35` | `/opt/hanlu-odps-sync` | VPC 内网 endpoint + RAM `ecs-maxcompute-writer` | Ozon / WB / Amazon / TikTok **店铺** / 聚水潭 / 领猫 / 钉钉 OA |
| **香港（官网）** | `i-j6c9ad3tdqv8nwe7wltl` | `47.238.76.36` | `/opt/hanlu-odps-sync`（精简 runtime） | **公网** `https://service.cn-hangzhou.maxcompute.aliyun.com/api` + 同名 RAM 角色 | **仅 TikTok Ads**（Marketing API 杭州不可达） |

本机助手：

- 杭州：`scripts/chrome_ecs_run.py`（需 Chrome 已开杭州实例控制台）  
- 香港：`scripts/hk_ecs_run.py`（需 Chrome 已开香港实例控制台）

### 杭州 cron（中国时，要点）

| 时刻 | 脚本 |
|------|------|
| 04:00 | `run_lingmao_daily.py` |
| 04:20 | `run_jushuitan_daily.py` |
| 05:12 | `run_dingtalk_oa_daily.py --lookback-days 14` |
| 各平台跨境 | `run_ozon/wb/amazon/tiktok_daily.py`（见 `scripts/install_cron_*.sh`；店铺 TikTok 约 15:00） |

### 香港 cron

| 时刻 | 脚本 |
|------|------|
| 15:30 | `run_tiktok_ads_daily.py --lookback 2 --since-ds 20261118` |

凭据在 ECS `secrets/`（聚水潭/领猫/OA/platform-api.json/tiktok-ads.env），**勿拉取进仓**。

---

## 3. ODS 表清单（ECS 已定义；DW 需对齐）

分区字段统一 **`ds STRING`（业务日 yyyyMMdd）**。写入语义：清分区 + append。

### 3.1 聚水潭（杭州）— 业财批发主链

DDL：`sql/ods/jushuitan/ddl_all_jushuitan_ods.sql`

| 表 | 用途（v3） |
|----|------------|
| `ods_jst_shop_df` / `ods_jst_warehouse_df` | 店/仓维 |
| `ods_jst_sku_inc` | 子 SKU |
| `ods_jst_purchase_inc` | 采购在途 |
| `ods_jst_purchasein_inc` | **采购入库（移动加权主素材）** |
| `ods_jst_allocate_inc` | 批发→跨境调拨（起算 ≥20260826） |
| `ods_jst_order_inc` / `ods_jst_order_out_inc` | 订单 / 销售出库 |
| `ods_jst_inventory_inc` / `ods_jst_inventory_df` | 库存变更 / **日终快照** |
| `ods_sku_map_df` | 领猫↔聚水潭映射（规则待补，先占位） |

### 3.2 领猫（杭州）— 资料包价 / SCM

DDL：`sql/ods/lingmao/ddl_all_lingmao_ods.sql`

| 表 | 用途 |
|----|------|
| `ods_lm_product_inc` / `ods_lm_sku_inc` | 款 / SKU（商品主键） |
| `ods_lm_std_bom_pkgfee_inc` | **资料包价权威（DIM11 D2/U5）** |
| `ods_lm_std_bom_material_inc` / `ods_lm_std_bom_imgfile_inc` | 物料 / 图样 |
| `ods_lm_req_order_inc` / `ods_lm_req_purchase_inc` | RO / 采购需求 |
| `ods_lm_outsource_inc` / `ods_lm_pdt_purchase_inc` | MO / 成品采购 |
| `ods_lm_storage_in_inc` | SCM 成品入库（核对） |
| `ods_lm_stock_inc` / `ods_lm_stock_df` | 库存变更 / 日终快照 |

### 3.3 钉钉 OA（杭州）— 唯一已有 DW 包

DDL：`sql/ods/dingtalk/ddl_oa_reimburse.sql`  
DW：`dataworks/oa_reimburse/`（`00_ddl_once` → pay → mid LLM → fee）

| ODS | DWD / mid（已有脚本） |
|-----|----------------------|
| `ods_dt_oa_reimburse_inc` | `dwd_dt_oa_pay_event_di` |
| `ods_dt_oa_reimburse_line_inc` | `mid_dt_oa_llm_tag_di` |
| `ods_dt_oa_reimburse_op_inc` | `dwd_dt_oa_fee_detail_di` |

采集 lookback=14 已在 main（`4d1d1d0`）；旧 handoff `docs/handoff-oa-ods-按更新补拉-给Codex.md` 的「改日批」**已完成**，勿重复造采集。

### 3.4 TikTok Ads（香港）

DDL：`sql/ods/tiktok/ddl_tiktok_ads_ods.sql`

| 表 | 说明 |
|----|------|
| `ods_tiktok_ads_campaigns_df` | 推广系列日快照（已冒烟有数） |
| `ods_tiktok_ads_advertiser_inc` | 广告主日消耗 |
| `ods_tiktok_ads_campaign_inc` | 系列日消耗 |

冒烟窗内可能无 spend（测广告禁用 / 新计划）；表与分区仍应在 DW 登记。

### 3.5 跨境店铺 ODS（杭州）— 已有 DDL，DWD 大多未建

| 平台 | DDL | 主表前缀 |
|------|-----|----------|
| Ozon | `sql/ods/ozon/ddl_all_ozon_ods.sql` | `ods_ozon_*` |
| WB | `sql/ods/wb/ddl_all_wb_ods.sql` | `ods_wb_*` |
| Amazon | `sql/ods/amazon/ddl_all_amazon_ods.sql` | `ods_amazon_*` |
| TikTok 店铺 | `sql/ods/tiktok/ddl_all_tiktok_ods.sql` | `ods_tiktok_*`（**不含** `_ads_`） |

质检样例：`sql/chk/**/chk_ods_*_rowcount.sql`（领猫/聚水潭 chk 若缺，请 Codex 按同模式补）。

---

## 4. Codex 建议任务顺序（DW）

### P0 — 让 DW「看得见」ODS

1. 在 DW 建业务流程文件夹：`ODS/聚水潭`、`ODS/领猫`、`ODS/tiktok_ads`、`ODS/ozon|wb|amazon|tiktok`、`ODS/钉钉OA`（OA 若已有则对齐）。  
2. 每个平台一个 **ODPS SQL 节点**：粘贴对应 `sql/ods/**/ddl_*.sql`（`CREATE TABLE IF NOT EXISTS`），手动跑通一次。  
3. 行数质检节点：读 `ds=${yyyymmdd}`（系统业务日=T-1），失败告警即可。  
4. **不要**在 DW 里再调开放平台 API。

### P1 — 业财主链 DWD（对齐 v3）

优先粘贴包建议新建：

```
dataworks/jushuitan_lingmao/
  00_ddl_dwd_cost_inventory.sql   # DWD 成本/在途/在仓等（字段跟字典表1/表2）
  01_dwd_purchase_in_cost.sql     # 聚水潭入库 + 领猫资料包价 D2/U5
  02_dwd_allocate_supply.sql      # 调拨供应*；起算 20260826
  03_dwd_inventory_snapshot.sql   # 批发/跨境库存双视角
  README.md                       # 节点依赖、参数 bizdate=${yyyymmdd}
```

硬规则提醒：

- 贸易类型：**批发 / 跨境**  
- 批发成本：批发仓出库完成时点 **移动加权**；销售成本单价 **按天、次日生效**  
- 跨境：内部供货价 ± 头程（分列）  
- 库存：批发=采购在途+在仓；跨境自有=在仓+采购在途；供应*=批发对跨境备货  
- 入加权前必须用 `ods_lm_std_bom_pkgfee_inc`，禁止用款式摘要价代替  

字典表号以 v3「表1/表2/表3」「规则确认」为准（DWD06/DWD07、ADS02 等）。

### P2 — 跨境 ODS→DWD / TikTok Ads

- 订单/退货/财务/广告消耗统一到业财事实表（命名跟 v3，勿自创「大贸」）。  
- TikTok Ads：先 ADS/费用侧日消耗汇总即可，不必等店铺 TikTok DWD。

### P3 — OA

- 确认线上 `fee_detail` / `biz_date` 与仓内 `dataworks/oa_reimburse/` 一致；缺节点则补粘贴，不重拉 ODS。

---

## 5. 验收清单（Codex 做完打勾）

- [ ] DW 目录下能打开并成功执行各平台 ODS DDL（IF NOT EXISTS）  
- [ ] 对 `ds=最近有数分区` 跑通至少一条 rowcount 质检（聚水潭入库 / 领猫 pkgfee / TK ads campaigns）  
- [ ] 提交 `dataworks/jushuitan_lingmao/`（或等价）DWD 初稿 + README 依赖图  
- [ ] `progress.md`（本仓 + 规划仓）写明：已粘贴节点名、阻塞、下一步  
- [ ] `git push` 后 Cursor 本机可 `git pull` 看到  

---

## 6. 给 Codex 的开场提示（可复制）

```text
你在仓库 hanlu-odps-sync。先 git pull && 读 progress.md 与
docs/handoff-ecs-ods-to-dw-给Codex.md。

ECS（杭州+香港）已把 ODS 写入 MaxCompute 项目 hanlu_odps；
你的任务是 DataWorks「业财一体」侧：登记 ODS DDL、建质检、
按数据字典 v3 做聚水潭/领猫成本与库存 DWD 粘贴包；
不要改 ECS 采集、不要碰旺店通/cemoy-*、不要提交密钥。

调度参数：业务日用 ${yyyymmdd}（日调度即 T-1）；禁止 ${yyyymmdd-1}。
COMMENT 必须中文。做完更新 progress.md 并 commit+push。
```

---

## 7. 相关 commit（main，便于对照）

| commit | 内容 |
|--------|------|
| `86049ce` / `53bd902` | TikTok Ads ODS + 香港助手 |
| `4d1d1d0` | OA lookback=14 |
| `b718409` | ECS 部署保留 secrets |
| （更早） | 聚水潭/领猫/跨境 ODS 采集与 DDL |

分支上大量 `codex/oa-*` 为 OA 实验；**DW 主链请基于 `main`**，勿被 OA 分支带跑。
