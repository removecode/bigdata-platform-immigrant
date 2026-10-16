# 云脑大数据平台 YARN 任务迁移顺序

**文档日期：** 2026-09-08  
**用途：** 新大数据平台迁移时，业务任务「迁哪些、按什么顺序迁」  
**材料：** 两份 CSV 对照，并与 `log/`、`Q&A/` 交叉核对

---

## 1. 结论

按「**先减负，再按原始层 → 中间层 → 业务层**」迁；同一层内按数据依赖再拆波次。过渡期**双跑新旧 DWB**，不要假设任意一侧都有 MD5 / 域名 / URL / IP 四类表。

```text
第 0 波  不迁：已下线 / 可下线 / 确认后仍废弃
第 1 波  原始层 · 入湖与分区（Kafka/ClickHouse/Mongo → Hive）
第 2 波  原始层 · 旁路分发与 AES（可不依赖 DWB）
第 3 波  中间层：log_compress、sodl_dwb_info
第 4 波  业务层 · 读 ODS / 维表 / 图（不强制等齐 DWB）
第 5 波  业务层 · 读 DWB 的情报与热度
第 6 波  其余保留与待确认（验证仍在用再迁）
```

两份 CSV 去重后：**来源表 40 个项目 = 云脑清单中有数据血缘的部分**；云脑清单另有 5 个仅出现在任务表、来源表无记录（其中 3 个已下线）。

---

## 2. 两份材料怎么合

| 文件 | 回答什么 |
|------|----------|
| `大数据平台YARN上的任务梳理-云脑大数据平台.csv` | 迁不迁（保留/待确认/可下线/已下线）、优先级、负责人、队列、计算类型 |
| `大数据平台YARN上的任务梳理-项目数据来源及输出.csv` | 属于哪一层（原始/中间/业务）、读哪些表、写到哪里 |

云脑 CSV 表头处置规则：

- **保留**：迁，并检查能否优化 SQL
- **可下线**：不迁，下线服务
- **待确认**：先确认是否还用；再用则迁，不用则下线
- **已下线**：不迁

**去重：** 云脑表里同一底座会同时出现 Oozie 行与 Tez 行（如 `log_compress` 与 `*log_compress(oozie)`）。下文按**一个业务**计。

本文件说的「迁移」是 **YARN/下游任务上新平台**。需求文档 §5 的「迁移顺序」是运营 23 条查询场景的交付批次，不是这份任务清单。  
来源：`docs/大数据平台需求分析-v4-抽象版.md` §5.2。

---

## 3. 原则

1. **先减负再搬。** 已下线、可下线、来源表已标废弃的，不进新集群。
2. **按来源表的三层走。** 原始层 15 → 中间层 2 → 业务层 23。同层内仍要看表依赖（例如 `top-visit-host-produce-job` 虽标原始层，但读 `default.log_audit_source` 与 `sodl.*`，须等入湖先通）。
3. **双跑再切读。** 新集群先写出可对账分区，下游改读后再停旧任务。
4. **过渡期接受双数据体系。** 新链路缺 URL DWB，旧链路缺 IP DWB。  
   来源：`Q&A/16-新旧链路四张DWB表.md`；`log/DATA_FLOW.md` L277–280。
5. **Pulsar / ClickHouse / DataX 不是 YARN 作业。** 按各自中间件迁，不要塞进 Spark/Tez 清单。

---

## 4. 第 0 波：不迁

### 4.1 已下线（云脑 CSV）

| 服务 | 备注（云脑 CSV） |
|------|------------------|
| `secevent-to-hive-batch` / `(oozie)` | 四年未改；来源表无记录 |
| `secevent_analyse(oozie)` | FLKF 独立任务，云脑标已下线 |
| `thug-task-monitor-prc` | 分区停在 20240401；一天约 1500 次 |

### 4.2 可下线（云脑 CSV）

| 服务 | 来源表记载 | 说明 |
|------|------------|------|
| `asset-discovery-task` | 读 `ngaf.ods_ngaf_dns` 等 | 云脑备注全部 FAILED；来源表写「没有 ngaf 库了」 |
| `vuln-assert-analysis` | 读 `ngaf.ods_ngaf_seclog_pvs` | 同上，旧 ngaf ODS |

### 4.3 两表结论不一致，建议按不迁处理

| 服务 | 云脑 CSV | 来源表 | 建议 |
|------|----------|--------|------|
| `apt-hunting-monitor-process-job` | 待确认 / 段宁强 | **可下线**，确认人刘俊，备注「历史废弃业务」 | 默认不迁；若段宁强仍要用，须书面推翻 |

它同时读新旧四类 DWB（含旧 `default.dwb_ip_info`、新 `sodl.dwb_sodl_url_info`）。即便要留，也依赖文档记载为**缺口/已注释**的表，不适合作为迁仓试点。  
来源：来源表该行；`Q&A/16`。

### 4.4 待确认、且无来源表记录（先问人）

| 服务 | 负责人 | 云脑备注 |
|------|--------|----------|
| `yara-sample-query-job` | 段宁强 | 编译即结束，没向 Tez 提交 |
| `sp-old-update-report-cron-job` | （空） | 无血缘 |

---

## 5. 推荐波次（要迁的）

### 第 1 波：原始层 · 入湖与分区

没有源数据，中间表和情报全空。建议顺序：

| 序 | 服务 | 云脑 | 来源 → 输出（来源表） |
|----|------|------|------------------------|
| 1.1 | `soapa-logger-stream-prc` | 保留 / 高 / 刘俊 / 常驻 Flink | Kafka → ES + HDFS `/soapa_logs/` |
| 1.2 | `sodl_ods_info` | 保留 / 王绪寒 | ClickHouse `sodl.*` → Hive `/hive/ods/sodl/` |
| 1.3 | `create_hive_partition` | 保留 / 刘树文 | 为 SODL、`log_audit/stats`、`csc.ods_csc_vertex/edge` 等预建分区 |
| 1.4 | `sync-mongo2hive-job` | 保留 / 王坤 / 常驻 | Mongo → `sri.ods_sri_hashinfo`（维表） |
| 1.5 | `datax-server` | 保留 / 高 / 王绪寒 | Mongo → Hive ODS（含 `/hive/ods/ngaf/assetinfo/` 等）；CSV 注明非 YARN |
| 1.6 | `ati-relations-loader-job` | 保留 / 肖扬 / 常驻 Spark | Kafka → `csc.ods_csc_vertex` / `csc.ods_csc_edge` + Nebula |

`create_hive_partition` 即使失败也到 End，分区问题会延迟暴露。迁完要单独验分区是否真建出。  
来源：`log/DATA_FLOW.md` L186–216。

**文档未写死：** Kafka → `default.log_audit_source` 是否就是 `soapa-logger-stream-prc`。`Q&A/18` 标为推断。迁 1.1 时与刘俊确认目标路径。

### 第 2 波：原始层 · 旁路（可不先等 DWB）

与第 1 波可部分并行，但 Pulsar/AES 依赖数据湖侧已有数据。

| 服务 | 云脑 | 来源 → 输出 |
|------|------|-------------|
| `ip-intelligence-dispatch-prc` | 保留 / 高 | 数据湖 Pulsar → Kafka |
| `dns-intelligence-dispatch-prc` | 保留 / 高 | 数据湖 Pulsar + Kafka → Kafka |
| `url-intelligence-dispatch-prc` | 保留 / 高 | 数据湖 Pulsar + Kafka → Kafka |
| `ti-ip-detection-send-prc` | 保留 / 高 / AES | ClickHouse `sodl.handle_info_log` → Kafka |
| `ti-hot-data-detection-fusing-prc` | 保留 / 高 / AES | ClickHouse `sodl.handle_info_log` → Kafka |
| `secevent-to-hive-stream-prc` | **待确认** / 明瞻 | Kafka → HDFS `/real-time/out/` |
| `secevent-to-hive-partition-pruned-cron-job` | **待确认** / 王绪寒 | 分区预加载；四年未改 |

AES 两条在 `docs/bigdata-platform.md` 列为对外影响面，确认仍用则不要拖到最后。

`top-visit-host-produce-job` 虽标**原始层**，但读 `default.log_audit_source` + `sodl.dns_log` / `sodl.url_log`，应放在 **1.1 + 1.2 通了之后**，不要和第 2 波 Pulsar 混为一谈。

### 第 3 波：中间层（运营日批底座）

19/23 条运营查询依赖旧链路 `log_compress` 的 audit/stats。  
来源：`Q&A/12-业务上有哪些任务.md`；`docs/大数据平台需求分析-v3.md` L44。

| 服务 | 读什么 | 写出什么 |
|------|--------|----------|
| `log_compress` | `log_audit_source` + 域名/URL 信誉维表等 | `csc.ods_csc_log_audit/stats` → 旧 DWB `default.dwb_*`（现行 audit 路径） |
| `sodl_dwb_info` | `sodl` ODS + 维表 | 新 DWB `sodl.dwb_sodl_md5/domain/ip_info` |

当前暂停（迁新平台时不要默认「会自动有」）：

- 新链路 `dwb_sodl_url_info` 已注释
- 旧链路 `dw_md5/url/domain/ip_info` 已注释，只走 audit；audit **无 IP DWB**

来源：`log/DATA_FLOW.md` L125–126、L144–151、L277–280。

```text
新链路：MD5 ✅  域名 ✅  URL ❌  IP ✅
旧链路：MD5 ✅  域名 ✅  URL ✅  IP ❌
```

**推断：** 新平台若只切 SODL 并立刻停 `log_compress`，URL 审计与 19 条日批会断；若只切旧链路，IP 宽表会断。官方查法书面确认前保持双跑。

### 第 4 波：业务层 · 不强制等齐 DWB

这些读 ODS / 维表 / 图，可在第 1 波（及所需维表）就绪后迁。

| 服务 | 优先级 | 主要输入（来源表） | 输出 |
|------|--------|--------------------|------|
| `domain-security-log-etl-prc` | 高 | `sodl.network_security_log` | Mongo |
| `ip-security-log-etl-prc` | 高 | `sodl.network_security_log` | Redis |
| `attack-ip-analysis-cronjob` | 高 | IP 信誉 ODS + `sodl.network_security_log` | Mongo / Redis / Kafka |
| `dashboard-stats-job` | 高 | 设备维表 + `sodl` 安全/端点日志 | Mongo |
| `ati-pdns-cache-job` | 高 | `csc.ods_csc_ioc_vertex`（依赖 1.6） | Mongo / Redis |
| `gnn-domain-hive-query-cronjob` | 高 | `csc.ods_csc_ioc_vertex` | Redis |
| `top-visit-host-produce-job` | 高 | `log_audit_source` + `sodl.dns_log/url_log` | Redis |
| `topthreat_hot_stat` | 保留 | `log_audit_source` + `sodl.network_security_log` / `sip_iocstat_log` | Mongo 热度 |
| `filter-layout-ip-seg-stat-prc` | 高 | IP 信誉 ODS + `csc.ods_csc_log_audit` | Redis（需 `log_compress` 的 audit ODS） |

`topthreat_hot_stat` 在来源表归**业务层**，在 `log/DATA_FLOW.md` 是 Oozie 6 任务之一、混合输入。按依赖放在入湖之后、热度场景之前。

### 第 5 波：业务层 · 读 DWB（口径风险最高）

| 服务 | 云脑 | 读哪套 DWB | 输出 |
|------|------|------------|------|
| `active-domain-elt-job` | 保留 / 高 | **新旧域名** + 黑 DNS 库 + 自定义上传 | Redis |
| `domain-hit-devnum-cronjob` | 保留 / 高 | **仅旧** `default.dwb_domain_info` | Mongo |
| `black-ti-context-produce-prc` | 保留 / 高 | 旧 MD5 + 新 domain/ip/md5 + 信誉 ODS | Mongo / Redis |
| `ctig-report-data-analysis-prc` | 保留 / 高 | **新** DWB + URL/域名信誉 | Kafka |
| `domain-heat-stats-cron-job` | **待确认** / 高 / 彭宜 | **仅新** `sodl.dwb_sodl_domain_info` | Mongo |
| `black-file-clean-cronjob` | **待确认** / 王绪寒 | **新旧 MD5** | 白文件 MD5 → 文件云 |

`active-domain-elt-job` 是已记载的口径风险点：同时读 `default.dwb_domain_info` 与 `sodl.dwb_sodl_domain_info`。切流前必须规定官方表。  
来源：来源表该行；`Q&A/19-下游50个业务服务.md` L75–81。

`domain-hit-devnum-cronjob` 只绑旧域名 DWB：若新平台先停旧链路，该任务会空。

`domain-heat-stats-cron-job` 对应运营热度场景（需求文档 #16–#18 放二期），虽待确认但优先级高，**第 0 波先问彭宜，确认后并入本波**。

### 第 6 波：其余保留 / 待确认（先验证再迁）

| 服务 | 云脑 | 建议 |
|------|------|------|
| `cloud-display-manager-prc` | 保留；备注「全部 FAILED→没在用？」 | 先查现网，失败则改可下线 |
| `online-dev-warehousing-prc` | 保留；四年未改 / 常驻 Flink | 与段宁强确认 |
| `cert-app-samplesync-job` | 保留 / 肖扬 | 蓝军上报，无优先级 |
| `cert-app-samplesync-country-job` | 保留 / 肖扬 | 同上，额外 SCP |
| `cipd-product-resource-monitor-prc` | 保留 / 中 | 读 `csc.ods_csc_log_stats`，依赖第 3 波 |
| `phishing-url-operation-prc` | 待确认 / 彭宜 | 读 `csc.ods_csc_log_audit` + Mongo |
| `svd-activity-stat-job` | 待确认 / 王绪寒 | 读 `sodl.network_security_log` + Mongo |

---

## 6. 依赖简图（来源表 + DATA_FLOW）

```text
【原始层入湖】
Kafka ──soapa-logger-stream-prc──→ ES / HDFS soapa_logs
ClickHouse ──sodl_ods_info──→ sodl.* ODS
Mongo ──sync-mongo2hive / datax──→ sri.hashinfo 等维表
Kafka ──ati-relations-loader──→ csc.vertex/edge + Nebula
create_hive_partition ──→ 上述表的分区

【中间层】
soapa + 维表 ──log_compress──→ csc.ods_csc_log_* → default.dwb_*（audit）
sodl ODS + 维表 ──sodl_dwb_info──→ sodl.dwb_sodl_md5/domain/ip_info
                                    （url 已暂停）

【业务层】
sodl.network_security_log ──→ 域名/IP 安全日志 ETL、attack-ip、dashboard
csc.ods_csc_ioc_vertex   ──→ ati-pdns-cache、gnn-domain
新旧 DWB                 ──→ active-domain、black-ti-context、domain-hit、热度、报告分析

【旁路】
数据湖 Pulsar ──dns/ip/url-dispatch──→ Kafka
ClickHouse handle_info_log ──AES ti-*──→ Kafka
```

---

## 7. 与运营一期/二期对齐

| 任务波次 | 对使用方 |
|----------|----------|
| 第 1 + 3 波完成 | 才有「昨日审计/统计可查」的前提（一期 19 条） |
| `topthreat` + 确认后的 `domain-heat-stats` | 热度场景 #16–#18（文档放二期） |
| 第 2 波 AES / 分发 + 第 4–5 波情报 | 网关、AES、大屏不断服 |

来源：`docs/大数据平台需求分析-v4-抽象版.md` L110–128。

---

## 8. 每波建议动作

文档没有现成 YARN 迁仓 runbook。下列为按材料归纳的操作原则，实现细节由建设方定。

1. **对照表先于切流：** 每个保留服务写清源表、目标表、队列、负责人。需求文档把「官方数据类型/链路」列为建设方须书面回复项。来源：`docs/大数据平台需求分析-v4-抽象版.md` §6。
2. **双跑再切读。**
3. **常驻单独排窗口：** `soapa-logger-stream-prc`、`ati-relations-loader-job`、`sync-mongo2hive-job`、`online-dev-warehousing-prc`。
4. **队列重新映射：** 云脑队列有 `online` / `etl` / `operation` / `business` / `default` / `cipd`；`sync-mongo2hive-job` 曾因 etl 太满跑到 operation。
5. **第 5 波先定官方表再改 SQL：** 尤其 `active-domain-elt-job`、`domain-hit-devnum-cronjob`、`black-ti-context-produce-prc`。

---

## 9. 全量对照（去重后）

状态以云脑 CSV 为准；层级、血缘以来源表为准。空表示该表无此字段。

### 9.1 原始层（15）

| 服务 | 迁否 | 优先级 | 负责人 |
|------|------|--------|--------|
| `soapa-logger-stream-prc` | 保留 · 第 1 波 | 高 | 刘俊 |
| `sodl_ods_info` | 保留 · 第 1 波 | | 王绪寒 |
| `create_hive_partition` | 保留 · 第 1 波 | | 刘树文 |
| `sync-mongo2hive-job` | 保留 · 第 1 波 | | 王坤 |
| `datax-server` | 保留 · 第 1 波 | 高 | 王绪寒 |
| `ati-relations-loader-job` | 保留 · 第 1 波 | | 肖扬 |
| `dns/ip/url-intelligence-dispatch-prc` | 保留 · 第 2 波 | 高 | 王绪寒 |
| `ti-ip-detection-send-prc` | 保留 · 第 2 波 | 高 | 肖扬 |
| `ti-hot-data-detection-fusing-prc` | 保留 · 第 2 波 | 高 | 肖扬 |
| `top-visit-host-produce-job` | 保留 · 第 4 波（等入湖） | 高 | 王绪寒 |
| `cloud-display-manager-prc` | 保留 · 第 6 波先验证 | | 肖扬 |
| `secevent-to-hive-stream-prc` | 待确认 | | 明瞻 |
| `secevent-to-hive-partition-pruned-cron-job` | 待确认 | | 王绪寒 |

### 9.2 中间层（2）

| 服务 | 迁否 | 负责人 |
|------|------|--------|
| `log_compress` | 保留 · 第 3 波 | 刘树文 |
| `sodl_dwb_info` | 保留 · 第 3 波 | 王绪寒 |

### 9.3 业务层（23）

| 服务 | 迁否 | DWB | 波次 |
|------|------|-----|------|
| `domain-security-log-etl-prc` | 保留 / 高 | 否，读 sodl ODS | 4 |
| `ip-security-log-etl-prc` | 保留 / 高 | 否，读 sodl ODS | 4 |
| `attack-ip-analysis-cronjob` | 保留 / 高 | 否，读 sodl ODS | 4 |
| `dashboard-stats-job` | 保留 / 高 | 否，读 sodl ODS | 4 |
| `ati-pdns-cache-job` | 保留 / 高 | 否，读 vertex | 4 |
| `gnn-domain-hive-query-cronjob` | 保留 / 高 | 否，读 vertex | 4 |
| `topthreat_hot_stat` | 保留 | 否，读源表+sodl | 4 |
| `filter-layout-ip-seg-stat-prc` | 保留 / 高 | 读 audit ODS | 4（需 compress） |
| `active-domain-elt-job` | 保留 / 高 | **新旧域名** | 5 |
| `domain-hit-devnum-cronjob` | 保留 / 高 | **仅旧域名** | 5 |
| `black-ti-context-produce-prc` | 保留 / 高 | **新旧混合** | 5 |
| `ctig-report-data-analysis-prc` | 保留 / 高 | **新** | 5 |
| `cipd-product-resource-monitor-prc` | 保留 / 中 | 读 stats ODS | 6 |
| `online-dev-warehousing-prc` | 保留 | Kafka | 6 |
| `cert-app-samplesync-job` | 保留 | hashinfo | 6 |
| `cert-app-samplesync-country-job` | 保留 | hashinfo | 6 |
| `domain-heat-stats-cron-job` | 待确认 / 高 | **仅新域名** | 先确认再进 5 |
| `black-file-clean-cronjob` | 待确认 | **新旧 MD5** | 先确认再进 5 |
| `phishing-url-operation-prc` | 待确认 | audit ODS | 6 |
| `svd-activity-stat-job` | 待确认 | sodl ODS | 6 |
| `apt-hunting-monitor-process-job` | 待确认 vs **可下线** | 新旧四类 | **不迁** |
| `asset-discovery-task` | 可下线 | ngaf | **不迁** |
| `vuln-assert-analysis` | 可下线 | ngaf | **不迁** |

### 9.4 仅云脑 CSV（5）

| 服务 | 迁否 |
|------|------|
| `secevent-to-hive-batch` | 已下线 · 不迁 |
| `secevent_analyse` | 已下线 · 不迁 |
| `thug-task-monitor-prc` | 已下线 · 不迁 |
| `yara-sample-query-job` | 待确认 · 无血缘 |
| `sp-old-update-report-cron-job` | 待确认 · 无血缘 |

---

## 10. 文档未覆盖

- 新平台目标形态：联合数据湖替换 Hive，还是换一套 Hadoop/YARN（`docs/bigdata-platform.md` 只写到技术预研）
- `soapa-logger-stream-prc` 与 `log_audit_source` 的精确链路
- 来源表 39/40 行「状态」为空，现网是否仍被调用需负责人再签
- 各服务失败告警、SLA、切流窗口
- `cloud-display-manager-prc` 现网是否仍 FAILED

---

## 11. 来源

- `大数据平台YARN上的任务梳理-云脑大数据平台.csv`（仓库根目录）
- `大数据平台YARN上的任务梳理-项目数据来源及输出.csv`（仓库根目录）
- `log/DATA_FLOW.md` L12–56、L92–151、L163–216、L277–280
- `Q&A/12`、`Q&A/15`、`Q&A/16`、`Q&A/18`、`Q&A/19`
- `docs/大数据平台需求分析-v4-抽象版.md` §5–§6
- `docs/bigdata-platform.md` L174–181、对外影响面 AES
