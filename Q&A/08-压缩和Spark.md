# 压缩和 Spark 是什么，项目里用到了吗

**问：** 压缩和 Spark 在项目里吗？

## 答

### 「压缩」——`log_compress` 任务

文档描述为「**日志压缩 / DW 层加工**」，做的是审计日志 ODS 入库与 audit DWB 构建，**不是** gzip/zip 文件压缩。

> 来源：`log/DATA_FLOW.md` L52、L92

**Parquet** 作为存储格式自带列式压缩能力，文档未写明具体 codec（Snappy/Gzip 等）。

> 来源：`log/DATA_FLOW.md` L67、L142

### Spark

| 任务 | 是否用 Spark |
|------|-------------|
| `secevent_analyse`（FLKF） | ✅ `spark-submit`，Spark on YARN client |
| `sodl_ods_info_new` | ❌ Python |
| `sodl_dwb_info` | ❌ Hive SQL |
| `log_compress` | ❌ Hive SQL |
| `topthreat_hot_stat` | ❌ Python + Hive SQL（Tez 队列 `etl`） |
| `create_hive_partition` | ❌ Python |

> 来源：`log/DATA_FLOW.md` L221–227；`log/TOPTHREAT_HOT_STAT_DETAIL.md` L126
