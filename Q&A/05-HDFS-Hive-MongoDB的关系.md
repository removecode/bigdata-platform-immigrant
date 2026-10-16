# HDFS、Hive 表、MongoDB 的关系

**问：** 三者如何理解？

## 答

```text
HDFS（文件）  ←── 元数据指向 ──  Hive 表（逻辑）
                              │
                              │ SQL 聚合后写入
                              ▼
                         MongoDB（部分结果）
```

| 组件 | 角色 | 项目中的例子 |
|------|------|-------------|
| **HDFS** | 物理存储 Parquet 等文件 | `/hive/ods/sodl/dns_log/year=.../hour=.../` |
| **Hive 表** | 库.表名 + 字段 + 分区规则 | `sodl.dns_log`、`default.dwb_md5_info` |
| **MongoDB** | 独立文档库，存聚合小结果 | `db_statistic.tb_original_domain_stat` |

### 典型流程

1. `sodl_ods_info_new` 写 Parquet 到 HDFS
2. Hive 表 `sodl.dns_log` 指向这些文件
3. `topthreat_hot_stat` 用 Hive SQL 聚合后 `bulk_write` 到 MongoDB

> 来源：`log/DATA_FLOW.md` L65–67、L173–175；`log/TOPTHREAT_HOT_STAT_DETAIL.md` L99–117

### 注意

ClickHouse 的 `sodl.dns_log` 与 Hive 的 `sodl.dns_log` **不是同一张表**，前者是源，后者是抽取后的副本。

> 来源：`log/DATA_FLOW.md` L71–73
