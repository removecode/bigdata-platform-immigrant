# 我们是怎么「压缩」的，Oozie 做什么

**问：** 压缩怎么做？Oozie 作用？

## 答

### `log_compress` 三阶段（业务上的「压缩」）

```text
阶段1  ODS 入库
  log_audit_source  → csc.ods_csc_log_audit
  log_stats_source  → csc.ods_csc_log_stats

阶段2  audit DWB 提取（并行）
  → md5_info_audit / url_info_audit / domain_info_audit

阶段3  merge_data.sh
  → default.dwb_*_info / {mday} / log_audit/
```

> 来源：`log/DATA_FLOW.md` L97–117；`log/LOG_COMPRESS_AUDIT_DETAIL.md` L7–17

### Oozie 的作用

**不处理数据**，负责：

- **Coordinator**：按 cron 触发（如每天 00:30）
- **Workflow**：DAG 编排——`insert_audit` 完成后才跑 audit DWB；多子任务 fork-join

实际执行：`run_sql.sh`（Kerberos + beeline）、`merge_data.sh`、Python 等。

> 来源：`log/README.md` L7–13；`log/DATA_FLOW.md` L95、L119–123、L253–257

### 分工示意

```text
Oozie（到点、排班）→ Hive SQL / Shell（干活）→ HDFS/Hive（结果）
```
