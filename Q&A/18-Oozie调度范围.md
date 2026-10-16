# 调度与日志压缩是否都由 Oozie 处理

**问：** 目前调度和日志压缩，包括新老链路都是 Oozie 来处理的吗？

## 答

### 结论

**新老链路的核心 ETL（含 `log_compress`）在文档里都由 Oozie 的 Coordinator 定时触发；但「整个平台」的调度不全是 Oozie**——上游数据入 Hive、约 50 个下游业务任务由其他机制负责，Oozie 只管文档记载的 6 个 Coordinator。

### 文档里的 6 个 Oozie Coordinator

`DATA_FLOW.md` 写明：平台基于 **Oozie 调度**，共 **6 个 Coordinator 任务**。

| 任务 | 链路 | 调度 |
|------|------|------|
| `log_compress` | **旧链路** | 每天 00:30 |
| `sodl_ods_info_new` | **新链路** ODS | 每小时第 7 分 |
| `sodl_dwb_info` | **新链路** DWB | 每天 02:30 |
| `topthreat_hot_stat` | 共用 | 每小时第 7 分 |
| `create_hive_partition` | 共用 | 12:30/15:30/18:30 |
| `secevent_analyse` | FLKF 独立 | 每小时第 7 分 |

定义路径：`oozie_projects/jobs/{ShenZhen|FLKF}/{任务名}/workflow.xml`、`coordinator.xml`。

### `log_compress` 与 Oozie 的分工

- **Oozie**：按 cron 触发 workflow，DAG 编排（`insert_audit` → audit DWB → `merge_action`）
- **实际加工**：`run_sql.sh` + beeline 执行 Hive SQL，`merge_data.sh` 移动 HDFS 文件

Oozie **不执行 SQL**，只负责何时跑、按什么顺序跑。

### 新链路也是 Oozie

`sodl_ods_info_new` 与 `sodl_dwb_info` 由两个 Oozie 任务串联（ODS→DWB）。任务清单 xlsx 标注为 `sodl_ods_info(oozie)`、`sodl_dwb_info(oozie)`、`log_compress(oozie)`。

### 不全是 Oozie 的部分

**上游入 Hive**

- 旧链路源表 `default.log_audit_source` 上游为 Kafka/soapa；6 个 Oozie 任务从**已在 Hive 的表**读写
- 新链路：Oozie 的 `sodl_ods_info_new` 从 ClickHouse **抽取**到 Hive，不负责 ClickHouse 侧写入

**下游业务**

- 约 50 个业务服务（域名/IP 情报、图数据、`soapa-logger-stream-prc` 等）多为 cronjob / Spark / Tez，不在 6 个 Coordinator 内

**推断：** Kafka → `log_audit_source` 可能由 `soapa-logger-stream-prc` 等流式任务完成；`log/` 未明确该环节调度器。

### 示意图

```text
【非 Oozie 或文档未写明】     【Oozie 6 个 Coordinator】        【多数非 Oozie】
Kafka/soapa → log_audit_source   log_compress ─────────────→  default.dwb_*
ClickHouse ─────────────────→   sodl_ods_info_new ──┐
                                sodl_dwb_info ──────┴→ sodl.dwb_sodl_*
                                topthreat_hot_stat → MongoDB
                                create_hive_partition
                                secevent_analyse (FLKF)
                                                          → ~50 个下游业务 job
```

### 简表

| 问题 | 答案 |
|------|------|
| `log_compress` 是 Oozie 调度吗？ | ✅ 是 |
| 新链路 ODS/DWB 是 Oozie 吗？ | ✅ 是 |
| 新老链路核心 ETL 都是 Oozie 吗？ | ✅ 文档记载的深圳主 ETL 是 |
| 平台所有调度都是 Oozie 吗？ | ❌ 不是 |

### 文档未覆盖

- Kafka → `log_audit_source` 具体由哪个组件调度
- ClickHouse 数据由谁写入（Oozie 只负责抽取到 Hive）

## 来源

- `log/DATA_FLOW.md` L7–8、L31–34、L47–56、L92–95、L119–123、L253–257、L288–289
- `log/LOG_COMPRESS_AUDIT_DETAIL.md` L11–17
- `log/ODS_TO_DWB_DETAIL.md` L7–9
- `log/README.md` L7–13
- `outputs/app-call-graph匹配统计临时文档.md` L29–41、L83
- `outputs/项目数据来源及输出_全集join.xlsx` sheet「仅sheet1」
