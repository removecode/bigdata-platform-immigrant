# HDFS 与 MongoDB 底层存储类比

**问：** HDFS 相当于 Mongo 的什么？分布式架构都叫 HDFS 吗？

## 答

### HDFS 在类比中的位置

| Hadoop 侧 | 大致相当于 MongoDB 的 |
|-----------|----------------------|
| HDFS | 最底层的分布式文件/块存储 |
| Hive 表 | `db` + `collection` 的逻辑定义 |
| Hive SQL | `find` / `aggregate` |
| **HDFS + Hive 合计** | 整个 MongoDB 的存储+查询体验 |

**HDFS ≠ 整个 MongoDB**，只相当于其中最底层的文件存储层。

### 分布式存储 ≠ 都叫 HDFS

HDFS 是 Hadoop 生态中的一种实现；还有 S3、Ceph、MinIO 等。本项目文档记载的数据主要在 **HDFS + Hive** 上。

### 在本项目中的分工

- **Hive/HDFS**：ODS/DWB 大批量日志与宽表
- **MongoDB**：`topthreat_hot_stat` 输出的热度 Top 10 万，供业务快速查询

> 来源：`log/DATA_FLOW.md` L26、L173–175
