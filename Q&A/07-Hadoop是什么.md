# Hadoop 是什么

**问：** Hadoop 是什么？

## 答

**Hadoop** 是一套大数据**基础平台/生态**，不是单一软件。

### 核心组件

| 组件 | 作用 | 本项目 |
|------|------|--------|
| HDFS | 分布式存文件 | ODS/DWB Parquet |
| YARN | 集群资源调度 | Spark on YARN（FLKF） |
| Hive | SQL 查 HDFS 数据 | `log_compress`、`sodl_dwb_info` 等 |
| Spark | 分布式计算 | 仅 `secevent_analyse` |
| Oozie | 工作流调度 | 6 个 Coordinator |

> 来源：`log/DATA_FLOW.md` L7、L224–227、L253–257

### 与本项目的关系

深圳主链路实际干活的是 **Python + Hive SQL + Oozie**，不是 MapReduce。

平台还包括 **ClickHouse、Kafka、MongoDB**，不只有 Hadoop。

### 易混淆点

- **Hadoop** = 生态总称
- **HDFS** = 其中存储层
- **Hive** = 生态上的数仓 SQL 层，不等于 Hadoop 本身
