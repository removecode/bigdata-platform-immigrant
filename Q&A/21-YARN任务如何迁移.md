# YARN 上的业务任务应如何迁移

**问：** 新大数据平台要迁移，这些业务怎么迁、顺序是什么？

## 答

### 结论

按「**先减负，再原始层 → 中间层 → 业务层**」迁；读 DWB 的情报任务放在中间表双跑对账之后。已下线、可下线、来源表已标废弃的不进新集群。过渡期双跑新旧 DWB，不能假设四类 IOC 在任意一侧齐全。

完整对照表与波次清单见：[`docs/YARN任务迁移顺序.md`](../docs/YARN任务迁移顺序.md)。

### 顺序（摘要）

```text
第 0 波  不迁：已下线 / 可下线 / apt-hunting（来源表：历史废弃）
第 1 波  入湖：soapa-logger、sodl_ods_info、分区、Mongo→Hive、图 vertex/edge
第 2 波  旁路：Pulsar 分发、AES ti-*（待确认的 secevent 流式先问人）
第 3 波  中间层：log_compress、sodl_dwb_info
第 4 波  业务层（读 ODS/图）：域名/IP ETL、attack-ip、dashboard、topthreat、TOP 库
第 5 波  业务层（读 DWB）：active-domain、domain-hit、black-ti-context、ctig-report
第 6 波  验证后再迁：云鉴、在线设备、cert、待确认任务
```

### 必须先处理的口径点

| 点 | 记载 |
|----|------|
| 新链路无 URL DWB、旧链路无 IP DWB | `Q&A/16`；`log/DATA_FLOW.md` L277–280 |
| `active-domain-elt-job` 同时读新旧域名 DWB | 来源表该行；`Q&A/19` |
| `domain-hit-devnum-cronjob` 只读旧域名 DWB | 来源表 |
| `apt-hunting-monitor-process-job` 云脑「待确认」、来源表「可下线」 | 两份 CSV 冲突，建议不迁 |

### 两份 CSV 的分工

| 文件 | 用途 |
|------|------|
| 云脑大数据平台.csv | 保留/待确认/可下线/已下线、优先级、队列 |
| 项目数据来源及输出.csv | 原始层 15 / 中间层 2 / 业务层 23，以及表级输入输出 |

### 不要和需求文档 §5 混为一谈

需求文档的迁移顺序是 **23 条运营查询场景的交付批次**（先日批 19，再热度），不是 YARN 任务搬迁顺序。  
来源：`docs/大数据平台需求分析-v4-抽象版.md` §5.2。

## 来源

- `docs/YARN任务迁移顺序.md`
- `大数据平台YARN上的任务梳理-云脑大数据平台.csv`
- `大数据平台YARN上的任务梳理-项目数据来源及输出.csv`
- `log/DATA_FLOW.md` L277–280
- `Q&A/12`、`Q&A/16`、`Q&A/19`
