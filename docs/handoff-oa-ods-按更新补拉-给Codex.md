# Handoff：钉钉 OA ODS「先建单后打款」漏状态 — 给 Codex

> 交接人：Cursor（本机）→ Codex（另一台）  
> 日期：2026-11-24  
> 仓库：`hanlu-odps-sync`（本文件所在仓）  
> **只改采集/分区回写策略；业财口径仍以数据字典 v3 为准（批发/跨境等与本单无关）。**

---

## 1. 问题（已核实）

样例业务单号：`202611211338000318307`（水滴报销，吴秋芳）

| 层 | 结果 |
|---|---|
| 钉钉源 | 现为 `COMPLETED`（后打款） |
| ODS `ds=20261121` | **有**头+4 行明细+4 步 op；落库时 `status=RUNNING`，`pay_time` 空；op 仅到「财务审核 AGREE」，**无打款人** |
| `dwd_dt_oa_pay_event_di` / fee | **无**（规则正确：未打款不入账） |

根因：**ECS 日批按「自然日创建/发起时间窗」拉 `instanceIds/query`，写入对应 `ds`。**  
创建日之后才打款时，后续日批不会再扫到该实例 → ODS 状态陈旧 → DWD 永远进不去。

**不是** pay_event 少算；是 **ODS 不再刷新**。

---

## 2. 目标行为

每天跑完后，凡「近期有状态变化（尤其打款）」的单，ODS 头/明细/op 应被**覆盖成最新**，使次日 DW：

`ready → pay_event → mid → fee_detail`

能看到打款人 AGREE / 付款时间 / 多次付款评论。

---

## 3. 推荐方案（给 Codex 落地）

钉钉 `POST /v1.0/workflow/processes/instanceIds/query` 的 `startTime/endTime` **一般是按创建时间**，多数账号**没有可靠的「按更新时间」列表滤镜**。  
因此不要死等「updateTime API」；用下面组合：

### 方案 A（主推，好落地）

**日批 = 回看窗口重拉 + 按实例覆盖写 ODS**

1. 每天仍跑 `run_dingtalk_oa_daily.py`，但不要只拉「昨天创建」：
   - `lookback_days` 默认建议 **14～30**（可 env / CLI 配置，先 14）
   - 对每个自然日 `d in [today-lookback, today-1]`（或含今天，按现有 `--ds` 习惯对齐）调用现有 `list_instance_ids(process_code, start_ms, end_ms)`
   - **去重** `process_instance_id` 后逐个 `get_instance` 拉详情
2. **写入策略改掉「整分区只代表创建日快照」的语义冲突**（二选一，推荐 A2）：

#### A1 — 分区仍=创建日，但允许日后覆盖该分区里的行

- `ds` 仍用实例创建日（或申请日）`yyyyMMdd`
- 对回看窗扫到的每个实例：写入其**创建日分区**，**覆盖该 `process_instance_id` 的旧行**（头/行/op 整单替换），而不是「只在首次出现时写」
- 实现注意：当前是 `reset_partition` + 全日重写；回看多日时应对**每个涉及的创建日分区**做「读出其他实例 + 合并本批更新实例 + 写回」，或按 pid 删后 append

#### A2 — 更干净：增加「未完结/无打款」显式重拉

- 日批仍拉 T-1 创建窗（保增量）
- 额外：从 MC 扫近 N 天 ODS 头表，筛 `status != COMPLETED` 或 `pay_time` 空或 op 无打款人 AGREE 的 `process_instance_id`，**强制再 get_instance 覆盖**
- 与 A1 回看可同时用（回看保「已完结但创建很早、窗外」的边界；未完结表保窗内状态推进）

**建议 Codex 先做：A1 回看 14 天 + 按创建日分区覆盖整单；再视需要加 A2。**

### 方案 B（若官方确认有更新时间）

若联调发现 query 支持按更新时间 / 或有事件订阅：改为 `modified` 窗拉取，写入时仍按**创建日**定位分区并覆盖。以实测为准，不要假设。

---

## 4. 要改的代码 / 文件（ECS 同源）

本机路径：`~/Projects/hanlu-odps-sync`  
ECS 路径：`/opt/hanlu-odps-sync`（改完需同步到 ECS，cron 已指向此处）

| 文件 | 改什么 |
|------|--------|
| `src/hanlu_sync/platforms/dingtalk_oa/collectors.py` | `collect_reimburse_bundle` / 新增 `collect_reimburse_lookback`：多日 list → 去重 → detail；写回时带「覆盖同 pid」语义 |
| `src/hanlu_sync/platforms/dingtalk_oa/client.py` | 一般不用改；若加参数（statuses 等）在此扩展 |
| `scripts/run_dingtalk_oa_daily.py` | 增加 `--lookback-days`（默认 14）；调用新采集；**禁止**对回看多日简单 `reset_partition` 只留当天新单 |
| `scripts/backfill_dingtalk_oa.py`（若有） | 与日批策略对齐说明 |
| `docs/ods-钉钉OA报销接入.md` | 写明：列表窗=创建时间；日批=回看覆盖；分区 `ds` 含义 |
| `progress.md` | 完成后更新状态 |

**DW 节点**（`dataworks/oa_reimburse/01_*.py` / `03_*.sql`）：  
本次**不必改口径**——只要 ODS 刷新出打款，现有 pay_event（要求打款人/多次付款）自然能吃到。  
若只补 ODS 不重跑 DWD，需对涉及 `pay_date` **补跑** pay → mid → fee。

### ECS 操作步骤（Codex / 运维）

1. 本机改完并 git push  
2. 用现有方式同步到 ECS（`scripts/chrome_ecs_run.py` 上传 tgz，或你们惯用的 scp/rsync）  
   - 至少同步：`src/hanlu_sync/platforms/dingtalk_oa/**`、`scripts/run_dingtalk_oa_daily.py`  
3. 确认 cron 仍在（约 05:00）：
   ```bash
   crontab -l | grep run_dingtalk_oa_daily
   # 期望类似：
   # 0 5 * * * TZ=Asia/Shanghai cd /opt/hanlu-odps-sync && . .venv/bin/activate && \
   #   export PYTHONPATH=... && timeout 3h python3 -u scripts/run_dingtalk_oa_daily.py \
   #   >> /var/log/hanlu-dingtalk-oa-daily.log 2>&1
   ```
4. 手工试跑（建议先 dry-run / 小 lookback）：
   ```bash
   cd /opt/hanlu-odps-sync && . .venv/bin/activate && export PYTHONPATH=src
   python3 -u scripts/run_dingtalk_oa_daily.py --lookback-days 14
   # 若暂未改 CLI，按你实现的参数名为准
   ```
5. 日志：`/var/log/hanlu-dingtalk-oa-daily.log`  
6. 验收样例（必须）：
   ```text
   business_id = 202611211338000318307
   ODS 头：status 应接近钉钉最新；pay_time / op 含打款人 AGREE（若源已打款）
   再跑 pay_event（DW 补数据或 ECS scripts/dw_oa_build_pay_events.py --biz-ds 创建日）
   → dwd_dt_oa_pay_event_di 应出现该单
   ```

---

## 5. 分区与参数（勿搞混）

| 对象 | 含义 |
|------|------|
| ODS `ds` | 建议继续 = **发起/创建业务日**（单号前缀日）；回看是为了**刷新该分区里的行** |
| DW `bizdate=$[yyyymmdd-1]` | 调度 T-1 |
| pay / fee 表 `ds` | **支付归属日**（不是发起日） |
| pay 行字段 `biz_date` | 来源 ODS 发起日，供 fee SQL `l.ds = p.biz_date` 回联明细 |

fee 节点线上曾误用 `ods_biz_ds`，本地 `03_dwd_oa_fee_detail.sql` 已改为 `biz_date`——若生产未粘贴，与本次漏打款是**另一问题**。

---

## 6. 验收清单

- [ ] `202611211338000318307`：钉钉已完结打款后，日批（或手工 lookback）后 ODS 头/op 含打款信息  
- [ ] 同单进入 `dwd_dt_oa_pay_event_di`（`currency/amount` 合理）  
- [ ] 回看重跑**不删除**窗内其他未改动实例  
- [ ] cron 05:00 正常；日志无大面积 API 失败  
- [ ] 更新本仓 `progress.md`

---

## 7. 不要做的事

- 不要把密钥写进仓库（钉钉在 ECS `/root/.cursor/local/dingtalk.env`）  
- 不要把「未打款」强行写入 pay_event（规则仍是：无打款人 AGREE 且无多次付款格式 → 不入账）  
- 不要假设 list API 已是更新时间，除非抓包/文档实证  
- 不要 `ensure_table` 因列序不同整表删除（currency ADD COLUMNS 教训）

---

## 8. 相关现状摘要

- ECS 采集脚本：`scripts/run_dingtalk_oa_daily.py`  
- 采集实现：`src/hanlu_sync/platforms/dingtalk_oa/collectors.py`（`_day_ms` + `list_instance_ids`）  
- 客户端：`.../client.py` → `/v1.0/workflow/processes/instanceIds/query`  
- DW 粘贴包：`dataworks/oa_reimburse/`  
- 历史：外币/币种已修并验收 `ACCEPT_PASS`；本 handoff 专治「状态不刷新」

---

## 9. 建议 Codex 提交说明

```
fix(oa-ods): lookback refresh so late payments update ODS

DingTalk list is create-time based; re-pull last N days and
overwrite instance rows so pay_event can see 打款人 after the fact.
```
