# Hive到StarRocks任务分类与迁移边界

日期：2026-09-09。依据：用户最新确认、两份任务CSV、现有SQL快照及加工说明。

## 1. 最新背景和责任范围

- 数据湖部门负责Hive到StarRocks的平台迁移及原始数据接入，已按audit先、stat后的顺序迁移两类原始数据，当前没有压缩表和中间表。具体表名、历史范围与可验收状态需按交付清单核对。
- 我方不负责大数据平台维护，负责依赖平台的业务生产任务和消费任务：SQL/连接适配、必要业务加工、外部输出、校验与业务切换。
- “数据生产任务”包括为业务生成中间结果、图数据、维表的任务，不等于所有入湖与平台运维都归我方。旧任务归属必须逐项与数据湖部门交接。
- 三区Mongo等业务依赖缺失仍需协调，但仅阻塞相关任务。旧平台全局下线由平台负责人统筹，我方提供本业务范围无依赖的证据。
- 本文是前期计划的范围修订；旧文档中的“仅audit已迁”“默认重建全部模型”“我方负责平台整体退出”不作为当前实施假设。

## 2. 分类方法

主分类已按最新约定调整为“平台数据接入、平台内数据加工、业务消费与同步”，数量、逐项归类及承接边界见[迁移任务三类职责汇总](迁移任务三类职责汇总.md)。本节以下A～J保留为输入依赖与范围标签，用于分析具体迁移前置，不再作为职责主分类。

每项另外标记“保留/待确认/已下线/可下线”和“仅改源/字段映射/SQL适配/业务加工/移交平台/待确认”。状态来自历史清单，不能代表现网最新结论。

下面按既有去重映射覆盖45个任务，每项归入一个主类别；跨类别依赖在输入说明中保留。Oozie和Tez执行记录合并后按业务任务统计，不按Application条数计。

### A. 直接读取压缩日志表的消费者（3）

| 任务 | 状态 | 输入与输出 | 迁移判断 |
|---|---|---|---|
| `filter-layout-ip-seg-stat-prc` | 保留 | audit压缩表 + IP信誉 → Redis | 原始audit映射与IP信誉具备后，优先SQL适配和读回校验 |
| `phishing-url-operation-prc` | 待确认 | audit压缩表 + Mongo → Mongo | 先确认保留，不能漏掉Mongo输入；新旧选数和文档写入均需验证 |
| `cipd-product-resource-monitor-prc` | 保留 | stats压缩表 + Redis → Prometheus | 原始stat适配，保留Redis依赖；核对设备统计和实际指标 |

此类是本期优先试点。压缩表消失不必然要求重建物理表，可以直接改读原始数据或用普通视图/SQL模板表达字段与必要过滤规则。

### B. 读取旧审计DWB的消费者（5）

| 任务 | 状态 | 主要依赖 | 迁移判断 |
|---|---|---|---|
| `domain-hit-devnum-cronjob` | 保留 | 旧Domain DWB、自定义上传 → Mongo | 明确需要域名设备统计结果，先确定从原始audit生成等价结果的方案 |
| `active-domain-elt-job` | 保留 | 新旧Domain、信誉、上传、Mongo → Redis | 混合输入；不能用新audit替代所有来源 |
| `black-ti-context-produce-prc` | 保留 | 旧MD5、SODL多类DWB、信誉、订阅、Pulsar、EDS → Mongo/Redis | 按实际模块拆输入，验证后汇总整任务验收 |
| `black-file-clean-cronjob` | 待确认 | 新旧MD5 → 外部查询/文件云 | 先确认去留，保留则校验选数及外部结果 |
| `apt-hunting-monitor-process-job` | 状态冲突 | 新旧多类DWB、其他表 → HDFS | 来源表标历史废弃；完成业务确认，不直接排开发 |

此类成本取决于所需聚合结果是否已有替代。不必默认每个消费者重写全部DWB逻辑；可由一个业务生产任务统一提供必要结果，也可对少数消费者内联所需逻辑，依据复用量与性能选择。

### C. 原始审计与SODL混合消费（2）

| 任务 | 状态 | 主要依赖 | 迁移判断 |
|---|---|---|---|
| `topthreat_hot_stat` | 保留 | 原始audit、SODL安全/IOC日志 → Mongo | 文件分支仅audit，可单独验证；域名/URL分支等待SODL可用方案 |
| `top-visit-host-produce-job` | 保留 | 原始audit、SODL DNS/URL → Redis | 原始audit迁入不足以完成整任务迁移 |

### D. SODL日志或SODL DWB消费者（7）

| 任务 | 状态 | 主要依赖/输出 | 迁移判断 |
|---|---|---|---|
| `domain-security-log-etl-prc` | 保留 | network_security_log → Mongo | 等SODL输入及目标具备 |
| `ip-security-log-etl-prc` | 保留 | network_security_log → Redis | 等SODL输入及目标具备 |
| `attack-ip-analysis-cronjob` | 保留 | SODL安全日志、信誉、上传 → Mongo/Redis/Kafka | 多依赖逐项验证 |
| `dashboard-stats-job` | 保留 | SODL安全/端点日志、设备表 → Mongo | 数据与维表齐备后测试 |
| `domain-heat-stats-cron-job` | 待确认 | SODL Domain DWB → Mongo | 确认保留和模型替代 |
| `ctig-report-data-analysis-prc` | 保留 | SODL Domain/IP、信誉、订阅、hashinfo → Kafka | 校验完整输入与Kafka发布 |
| `svd-activity-stat-job` | 待确认 | SODL安全日志、Mongo → Mongo | 确认保留和输入输出 |

不因audit/stat原始表已迁就提前标记此类任务可迁。数据湖需明确SODL交付范围或过渡访问方案。

### E. 其他平台业务表消费者（4）

| 任务 | 状态 | 主要依赖/输出 | 迁移判断 |
|---|---|---|---|
| `ati-pdns-cache-job` | 保留 | ioc_vertex → Mongo/Redis | 核对ioc_vertex真正生产者及新平台对应数据 |
| `gnn-domain-hive-query-cronjob` | 保留 | ioc_vertex → Redis | 同上，不能把vertex表直接当成ioc_vertex |
| `cert-app-samplesync-job` | 保留 | business_data、hashinfo → HDFS文件 | 核对表和文件导出接口 |
| `cert-app-samplesync-country-job` | 保留 | business_data、hashinfo → HDFS/SCP | 增加外部传输校验 |

### F. 数据生产及接入任务（8）

| 任务 | 清单状态 | 旧职责 | 本次处理 |
|---|---|---|---|
| `log_compress` | 保留 | audit/stats压缩表及审计DWB加工 | 新决策取消压缩入库；业务方确认必要DWB语义，按需适配生产逻辑 |
| `sodl_dwb_info` | 保留 | SODL → DWB | 业务加工是否由我方继续承担需确认，输入未具备则阻塞 |
| `sodl_ods_info` | 保留 | ClickHouse → Hive SODL | 先确认数据湖是否接管此域，避免复制旧抽取任务 |
| `sync-mongo2hive-job` | 保留 | Mongo → hashinfo全量/增量 | 明确维表接入责任；若我方保留，适配新写入接口和增量逻辑 |
| `datax-server` | 保留 | Mongo → Hive ODS | 非YARN任务，按接入作业确认归属和目标替代 |
| `ati-relations-loader-job` | 保留 | Kafka → vertex/edge、Nebula | 有业务生产职责；分别核对平台写入与图数据库输出 |
| `soapa-logger-stream-prc` | 保留 | Kafka → audit/stats/dev HDFS及ES | 原始日志入湖交接给数据湖核实；ES/dev等其他输出不能随audit迁入一起停 |
| `secevent-to-hive-stream-prc` | 待确认 | Kafka → HDFS | 确认业务和写入归属后再定迁否 |

### G. 旧Hive平台配套任务（2）

| 任务 | 状态 | 处理 |
|---|---|---|
| `create_hive_partition` | 保留 | Hive分区和目录维护，不默认移植StarRocks；由数据湖明确新表维护机制，旧平台剩余业务仍需保障 |
| `secevent-to-hive-partition-pruned-cron-job` | 待确认 | Hive分区预加载，确认旧流任务是否保留及新平台是否还需要 |

### H. 清单未显示直接读写Hive的任务或旁路业务（7）

| 任务 | 状态 | 链路 | 处理 |
|---|---|---|---|
| `dns-intelligence-dispatch-prc` | 保留 | Pulsar/Kafka → Kafka | 不因Hive到StarRocks默认改代码；核实SDK是否有隐藏查询 |
| `ip-intelligence-dispatch-prc` | 保留 | Pulsar → Kafka | 同上 |
| `url-intelligence-dispatch-prc` | 保留 | Pulsar/Kafka → Kafka | 同上 |
| `ti-ip-detection-send-prc` | 保留 | ClickHouse → Kafka/Prometheus | 按ClickHouse及跨区依赖单列 |
| `ti-hot-data-detection-fusing-prc` | 保留 | ClickHouse → Kafka | 同上 |
| `online-dev-warehousing-prc` | 保留 | Kafka → Mongo | 数据库/运行环境迁移另列，不属于Hive查询适配 |
| `cloud-display-manager-prc` | 保留但有失败备注 | Kafka → Mongo/Redis/HDFS备份 | 先确认真实使用，再处理数据库及文件备份依赖 |

### I. 已确认Hive查询，具体血缘待补（2）

| 任务 | 状态 | 处理 |
|---|---|---|
| `yara-sample-query-job` | 待确认 | 用户于2026-09-10确认通过SQL查询Hive，纳入StarRocks适配评估；暂按业务消费归类，补表名、SQL及输出职责 |
| `sp-old-update-report-cron-job` | 待确认 | 用户于2026-09-10确认通过SQL查询Hive，纳入StarRocks适配评估；暂按业务消费归类，补表名、SQL、输出职责及负责人 |

### J. 清单已下线或可下线（5）

| 任务 | 状态 | 处理 |
|---|---|---|
| `secevent-to-hive-batch` | 已下线 | 不排迁移，核对无遗留依赖 |
| `secevent_analyse` | 已下线 | 同上，注意环境/任务实例边界 |
| `thug-task-monitor-prc` | 已下线 | 不排迁移 |
| `asset-discovery-task` | 可下线 | 业务确认后退役 |
| `vuln-assert-analysis` | 可下线 | 业务确认后退役 |

## 3. 原始表与压缩表的实际适配范围

CSV中的`insert_audit`选择log_time、log_app_id、module_id、log_type、host_name、long1～5、str1～10、hour、repository_name、cluster_name，并将log_app_id映射为分区字段app_id。

`insert_stats`另包含double1～3，字符串字段为str1～5，同样映射app_id，SQL快照有length(log_app_id)<128过滤。不能直接复用audit字段清单作为stat字段清单。

两段SQL没有JSON展开、信誉关联或GROUP BY。那些逻辑主要属于下游DWB及消费SQL，前期讨论把它们笼统归为压缩表生成过程不够准确。

另有版本差异：加工说明记载排除configserver，但CSV快照的audit SQL没有这个过滤，stat快照只明确长度条件。最终以现网部署SQL和业务认可口径确定，不凭文字说明批量补过滤。

直接消费者的候选改动为：查询连接/驱动、表名、app_id与log_app_id映射、日期谓词、实际过滤规则、Hive语法/UDF。StarRocks实际字段类型及命名以数据湖DDL为准，不能假定与旧原始表完全一致。

## 4. 性能评估和处理路径

同一引擎内，分区组织更适合业务的表或预聚合结果可能更快；但本项目同时从Hive换到StarRocks，不能由表名称推导新查询更慢或更快。旧压缩表并非SQL聚合结果，表DDL、存储格式、文件组织、数据量等还需实证。

每种代表查询用相同时间窗口、过滤条件和结果语义比较：旧Hive压缩表、新StarRocks原始表。覆盖日查询、真实历史范围、JSON解析、JOIN、聚合、并发及入湖同时发生的情况。

记录单次及重复测试延迟（样本足够时统计P95）、扫描行/字节、CPU/内存、JOIN中间结果、超时、结果拉取耗时和目标写入耗时。验证任务不得只取LIMIT小样本就宣称生产性能达标。

| 情况 | 处理 |
|---|---|
| 改源后性能满足业务窗口 | 直接迁移，保留监控 |
| 扫描过多或谓词不生效 | 我方检查SQL、日期类型及过滤；数据湖检查分区、排序/索引等物理设计 |
| JSON解析或重复JOIN成本高 | 我方评估共享表达式及业务加工；与数据湖讨论可行的预计算能力 |
| 多个消费者反复执行同类重聚合 | 业务方确认必要模型，明确刷新、存储与维护责任后选结果表或物化能力 |
| 普通视图/SQL模板 | 可统一字段语义，但不天然缓存或减少计算，不承诺性能提升 |

是否支持某项函数、物化或写入能力，以实际StarRocks版本和数据湖提供的接口为准。本期不预设特定实现。

## 5. 原始表同步也是任务吗

原始数据进入StarRocks需要接入/同步机制，可能是持续导入作业、定时批任务或数据服务。现有材料只能看到旧端soapa写HDFS/ES、Hive分区维护等环节，无法确定新区使用哪种同步方式。

audit/stat由数据湖负责，我方无需默认迁移旧入湖任务，但必须拿到以下可验证的交付契约：

- 源数据、目标表、生产负责人、历史起点与保留时间；
- 实时或批次机制、可用截止点、延迟目标和故障通知；
- 是否仍依赖旧Hive、旧压缩任务或旧Kafka消费者；
- 数据完整性、重复处理、更新/删除、迟到与补数行为；
- 字段变更通知、访问账号、查询配额、数据就绪标记及支持接口。

我方任务按数据就绪条件执行，不仅照搬旧00:30、02:30等时刻。表能查到记录不能证明该业务日期全部数据已到齐。

## 6. 收敛后的推进顺序与验收

1. 数据湖确认audit/stat交付契约；我方完成45项分类的负责人和去留复核。同时梳理三区输入、输出实例缺口。
2. A类选audit和stat代表SQL试跑；同时检查B类中间结果的实际消费者。按验证结果区分改源、SQL适配、业务加工与缺依赖。
3. A类先做结果/性能对账，再用真实程序写影子Mongo/Redis或隔离指标并读回验收。原始输入具备时不等全部中间表。
4. 确认必要的B类加工输出，优先评估Domain、MD5；若我方承担生产，先验中间结果，再验消费者。URL按需求决定。
5. C、D、E类按SODL/业务表交付情况分批推进，F/G与数据湖明确接管或保留边界，H类只处理实际涉及的环境依赖，I/J完成盘点和退役决策。
6. 分任务切流并观察；我方确认本范围旧读写已退出，向数据湖交付证明，由平台方统筹共享任务和平台下线。

每个保留任务分别记录：输入契约确认、必要生产结果校验、消费查询/转换校验、目标读回校验、性能通过、业务签字、切流状态。只改表名不能替代验收；无中间表生产职责的任务该项标不适用。

## 7. 参考

- [任务来源及输出原始清单](../大数据平台YARN上的任务梳理-项目数据来源及输出.csv)
- [运行任务和SQL快照](../大数据平台YARN上的任务梳理-云脑大数据平台.csv)
- [审计加工说明](../log/LOG_COMPRESS_AUDIT_DETAIL.md)
- [数据流说明](../log/DATA_FLOW.md)
- [迁移实施计划](大数据平台三区迁移实施计划.md)
- [困难点台账](大数据平台迁移困难点与阻塞项.md)
