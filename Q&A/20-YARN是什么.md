# YARN 是什么

**问：** YARN 又是什么平台？

## 答

**YARN 不是与 Hadoop、Oozie 并列的又一套业务平台**，而是 Hadoop 集群里的**资源调度层**（Yet Another Resource Negotiator）：负责把 CPU、内存等资源分配给 Spark、Hive/Tez、MapReduce 等计算任务。

> 通用概念；Hadoop 生态归纳见 `Q&A/07-Hadoop是什么.md`

### 在本项目文档中的出现

| 场景 | 文档记载 |
|------|---------|
| FLKF Spark 任务 | `secevent_analyse` 通过 `spark-submit` 提交，**Spark on YARN client** 模式 |
| 热门威胁统计 | Hive SQL 提交到 **`etl` 队列**（`YARN_QUEUE_NAME = "etl"`） |

> 来源：`log/DATA_FLOW.md` L224；`log/TOPTHREAT_HOT_STAT_DETAIL.md` L126

**推断：** 任务清单 xlsx（`outputs/项目数据来源及输出_全集join.xlsx`）中大量下游服务标注 `云脑_queue`（如 `default`、`business`、`operation`、`etl`），这些队列运行在 YARN 上；`log/` 主文档未逐一写明。

### 与 Oozie 的分工

| 角色 | 做什么 |
|------|--------|
| **Oozie** | 排班：何时触发哪个 workflow（6 个 Coordinator） |
| **YARN** | 调度资源：任务占多少 CPU/内存、进哪个队列 |
| **Spark / Hive** | 实际计算：读 HDFS、写 Hive 表 |

```text
Oozie 触发 shell / Hive SQL / spark-submit
  → 任务进入 YARN 队列（如 etl）
    → 在集群节点上跑 Spark / Tez / MR
      → 读写 HDFS / Hive 表
```

### 易混淆点

- **Hadoop** = 生态总称（含 HDFS、YARN、Hive 等）
- **YARN** = 其中一层，只管资源，不管业务逻辑
- **Oozie** = 工作流调度，本身不替代 YARN

### 文档未覆盖

- 各 YARN 队列（`default` / `business` / `operation` / `etl` / `oozie`）的容量与优先级策略
- `log_compress` 的 Hive SQL 是否走 YARN/Tez（文档只写 beeline + `run_sql.sh`，未写队列名）
