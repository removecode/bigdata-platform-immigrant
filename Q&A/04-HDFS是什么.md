# HDFS 是什么

**问：** HDFS 是什么？

## 答

**HDFS**（Hadoop Distributed File System）是 Hadoop 生态里的**分布式文件系统**，在集群多台机器上存海量文件。

### 特点

- 分布式、高容错、适合大文件与批量读写
- 与 Hive 配合：表数据通常落在 HDFS 路径上

### 在本项目中的用途

| 用途 | 路径示例 |
|------|---------|
| SODL ODS | `/hive/ods/sodl/dns_log/...` |
| DWB | `/hive/dwb/sodl/md5_info/`、`/hive/dwb/default/...` |
| Oozie 部署 | `/user/oozie/oozie_jobs_auto/` |

写入格式多为 **Parquet**（`sodl_ods_info_new` 等）。

> 来源：`log/DATA_FLOW.md` L18–22、L66–67、L269

### 与 Hive 的关系

- **HDFS** = 真实文件在哪
- **Hive 表** = 逻辑表结构 + 分区元数据指向 HDFS 目录
