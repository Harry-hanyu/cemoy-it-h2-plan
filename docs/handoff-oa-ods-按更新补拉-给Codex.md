# Handoff：钉钉 OA ODS「先建单后打款」漏状态 — 给 Codex

> 交接人：Cursor（本机）→ Codex（另一台）  
> 日期：2026-11-24（修订：强调**最小代价**，禁止全量重拉/全量重跑 LLM）  
> 仓库：`hanlu-odps-sync`（本文件所在仓）  
> **只改采集向前策略 + 小范围补漏；业财口径仍以数据字典 v3 为准。**

---

## 0. 范围铁律（最小代价 — 必须遵守）

### 要做

1. **改日批向前**：之后每天能刷新「近期创建且后来才打款」的单（lookback 小窗口，默认 **14 天**）。  
2. **只补近期受影响**：对 lookback 窗内、或明确点名的样例单，刷新 ODS → 仅对这些单涉及的 **pay_date** 补跑 pay（及必要时 mid/fee）。  
3. **LLM（mid）**：仅对**本次新进入 pay、或 op/明细相对旧 mid 有实质变化**的实例打标；能复用已有 `mid_dt_oa_llm_tag_di` 行则**不要重打**。

### 禁止（用户明确要求）

- **禁止**从 Q-01 / 全历史 ODS 再拉一遍钉钉。  
- **禁止**对历史已入账、状态已正确的 pay/fee **整表重算**。  
- **禁止**对历史 mid **全量再跑一遍 DeepSeek/LLM**（费钱费时，且与本次无关）。  
- **禁止**「为了整齐」把 109 个支付日 LLM+fee 全部重刷。

历史里已经对、且不受「后打款」影响的数据：**不动**。

---

## 1. 问题（已核实）

样例业务单号：`202611211338000318307`（水滴报销，吴秋芳）

| 层 | 结果 |
|---|---|
| 钉钉源 | 现为 `COMPLETED`（后打款） |
| ODS `ds=20261121` | **有**头+4 行明细+4 步 op；落库时 `status=RUNNING`，`pay_time` 空；op 仅到「财务审核 AGREE」，**无打款人** |
| `dwd_dt_oa_pay_event_di` / fee | **无**（规则正确：未打款不入账） |

根因：ECS 日批按**创建时间单日窗**拉列表；创建日之后才打款时，后续日批扫不到 → ODS 陈旧 → DWD 进不去。  
**不是**要否定历史全量；只是向前采集策略缺「刷新」。

---

## 2. 目标行为

1. **向前**：日批 lookback（如 14 天）重拉并**按 pid 覆盖** ODS 对应创建日分区中的行。  
2. **补漏**：对 lookback 内新出现打款的单，只补其 pay_date 的 pay →（缺 mid 才 LLM）→ fee。  
3. **样例验收**：`202611211338000318307` 能进 pay（若源已打款）。

---

## 3. 推荐方案（最小代价落地）

钉钉 `instanceIds/query` 的时间窗**多是创建时间**，不要死等 updateTime API。

### 日批（向前，主改）

**A1（主推）**：`--lookback-days` 默认 **14**（不要默认 90/365）。

- 对 `d in [today-lookback, today-1]` list → 去重 pid → get_instance  
- ODS `ds` 仍 = **创建/发起日**  
- 写回：对涉及分区 **合并覆盖同 pid**（读旧分区 → 替换本批 pid → 写回），禁止误删同分区其它单  

**可选 A2（更省 API）**：T-1 增量 + 仅重拉近 N 天 ODS 中「未打款/未完结」pid。可与 A1 二选一或组合；**仍限制在近 N 天**。

### 一次性补漏（只做小窗，不做全史）

1. 用新日批逻辑跑 **一次** `--lookback-days 14`（或 30，上线时与用户确认，**禁止**无上限全史）。  
2. 对比刷新前后：哪些 pid **新出现**打款人 AGREE / pay_time。  
3. **仅对这些 pid**：
   - 跑 pay 写入对应 `pay_date` 分区（用现有 merge 逻辑，勿 wipe 全表）  
   - mid：若该 `(pid, line_no, pay_ds)` 已有 mid **跳过 LLM**；仅缺的才调 DeepSeek  
   - fee：仅重跑这些 `pay_date` 分区（或按支付日脚本只跑命中日）  
4. 样例单若 lookback 含 `20261121`，应被覆盖；否则可 **单 pid 定点** get_instance 覆盖，不要为此扩大到全史。

### LLM 费用控制

| 场景 | 是否调 LLM |
|------|------------|
| 历史 mid 已存在且 line 文本未变 | **否** |
| 本次新进 pay 的实例 | **是**（仅这些） |
| 仅 status/pay_time/op 变、明细行未变 | **优先复用 mid**，不要整单重打 |

---

## 4. 要改的代码 / ECS

本机：`~/Projects/hanlu-odps-sync`  
ECS：`/opt/hanlu-odps-sync`

| 文件 | 改什么 |
|------|--------|
| `collectors.py` / `run_dingtalk_oa_daily.py` | lookback + 按 pid 合并覆盖；CLI `--lookback-days` 默认 14 |
| `docs/ods-钉钉OA报销接入.md` | 写明创建窗 + 回看刷新 + **不做全史重拉** |
| `progress.md` | 完成后更新 |

**DW**：不必改口径。补数时只对**命中的 pay_date** 跑实例/补数据，禁止工作流「全历史重跑」。

### ECS 操作

1. git pull / 同步改动到 `/opt/hanlu-odps-sync`  
2. cron 仍 05:00；确认带 lookback（或代码默认 14）  
3. **一次**小窗试跑：`python3 -u scripts/run_dingtalk_oa_daily.py --lookback-days 14`  
4. 日志：`/var/log/hanlu-dingtalk-oa-daily.log`  
5. 验收样例 `202611211338000318307` → ODS 打款信息 → 仅相关 pay_date 进 DWD  

---

## 5. 分区口径（勿混）

| 对象 | 含义 |
|------|------|
| ODS `ds` | 发起/创建日；回看是为刷新该分区内行 |
| DW `bizdate=$[yyyymmdd-1]` | 调度 T-1 |
| pay/fee `ds` | **支付归属日** |
| pay.`biz_date` | ODS 发起日，供 fee 回联 |

---

## 6. 验收清单

- [ ] 日批 lookback=14 上线，cron 正常  
- [ ] 样例单 ODS 刷新且能进 pay（源已打款前提下）  
- [ ] **未**触发全历史 ODS 重拉  
- [ ] **未**全量重跑 mid LLM（API 调用量应接近「新增打款单数」量级）  
- [ ] 历史已正确的 pay/fee 分区无被整分区无故清空  
- [ ] 更新 `progress.md`

---

## 7. 不要做的事（再强调）

- 全历史 `backfill_dingtalk_oa --since 20250101` 当成本次解法  
- `backfill_oa_dwd.py --phase all` / 全支付日 LLM  
- 未打款强行入 pay_event  
- `ensure_table` 因列序整表删除  

---

## 8. 建议提交说明

```
fix(oa-ods): lookback-14 refresh late payments (no full rebackfill)

Forward daily re-pull last 14d and overwrite by pid; backfill only
recent newly-paid instances. Do not re-run historical LLM tags.
```
