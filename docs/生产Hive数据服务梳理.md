# 生产Hive数据的服务梳理

统计日期：2026-09-17。范围：原始45项服务，不展开DataX内部每条同步脚本。按输出为Hive可查询数据、HDFS待接入目录、Hive分区维护三种职责分别统计；历史任务状态不代表现网启用。

## 一、明确生产Hive表或Hive ODS/DWB数据：6项

| 服务 | 输入 | Hive表/数据输出 | 证据与状态 |
|---|---|---|---|
| `sync-mongo2hive-job` | Mongo文件云查数据 | `sri.ods_sri_hashinfo`全量、`sri.ods_sri_hashinfo_increment`增量 | 手工来源/输出清单明确；旧材料保留，现网配置待核 |
| `ati-relations-loader-job` | Kafka及图关系数据 | 原清单列`csc.ods_csc_vertex`、`csc.ods_csc_edge`；用户于2026-09-17补充确认IOC点表`csc.ods_csc_ioc_vertex`、边表`csc.ods_csc_ioc_edge`；另写Nebula图数据库 | IOC点/边表为用户确认，均未列在原清单输出栏；写入子任务、物理映射和现网版本待核 |
| `sodl_ods_info` | 数据湖ClickHouse六张SODL日志 | Hive侧`sodl.dns_log`、`endpoint_security_log`、`http_log`、`network_security_log`、`sip_iocstat_log`、`url_log`，落于`/hive/ods/sodl/` | 手工清单及SQL支持；Oozie详细文档称`sodl_ods_info_new`，现网版本关系待核 |
| `sodl_dwb_info` | SODL ODS日志及信誉、设备等维表 | `sodl.dwb_sodl_md5_info`、`dwb_sodl_domain_info`、`dwb_sodl_ip_info`等必要中间结果 | 手工清单列出URL在内的四类表；详细链路文档注明URL子任务被注释，不能据清单推断四类现网都在生产 |
| `log_compress` | `default.log_audit_source`、`log_stats_source`及维表 | `csc.ods_csc_log_audit`、`ods_csc_log_stats`和旧`default.dwb_*`结果 | 旧链路任务；新平台取消压缩过程，保留消费者必要逻辑仍须承接；旧DW非audit子任务有注释情况 |
| `datax-server` | 多个Mongo集合 | Hive ODS使用的HDFS目录，如`/hive/ods/ngaf/assetinfo/`、`/hive/ods/csc/int_scia_intelligence_cloudlibip/`等 | 已定义子任务清单及手工输出；具体启用由仓库外配置决定，目标逻辑表名需逐项确认 |

以上为服务数，不是表数。`ati-relations-loader-job`的IOC点/边表目标由用户确认；尚无可引用的写入SQL或DDL来独立核验，不把它们误写为由旧清单的`csc.ods_csc_vertex/edge`派生。现有消费SQL只明确引用IOC点表，尚未在这份清单里确认IOC边表的直接消费服务。

## 二、写入HDFS接入/中转目录：2项，是否直接成为Hive表待核

| 服务 | 明确写入位置 | 核实重点 |
|---|---|---|
| `soapa-logger-stream-prc` | `/soapa_logs/dev_stream/`、`stats_stream/`、`audit_stream/`及ES | 有HDFS日志输出；材料未写明是该任务直接写`default.log_audit_source`或由其他接入环节登记为Hive表 |
| `secevent-to-hive-stream-prc` | `/real-time/out/`和脏数据目录 | 用途标安全事件实时入Hive；原始材料仅给HDFS路径，目标Hive表及上游分区登记待核，任务去留待确认 |

目录存在或被写入，不等于Hive表已创建、分区已登记或SQL可查。

## 三、维护Hive分区，不生产业务行数据：2项

| 服务 | 作用 | 核实重点 |
|---|---|---|
| `create_hive_partition` | 提前创建日/小时Hive分区和HDFS目录 | 属旧Hive结构维护，不能作为日志生产任务计入6项；需按仍在写入的旧表决定退出时机 |
| `secevent-to-hive-partition-pruned-cron-job` | 原清单标注预加载Hive分区数据/分区定时修剪 | 具体动作与保留必要性需查现网代码配置；不据名称判断是业务数据写入者 |

## 四、其他HDFS文件输出，不据路径计为Hive表生产者

`cloud-display-manager-prc`写备份统计目录，`apt-hunting-monitor-process-job`写关联结果目录，两个`cert-app-samplesync*`任务写报告文件/SCP；`asset-discovery-task`和`vuln-assert-analysis`的手工来源写有`/apps/hive/warehouse`但未给出目标表及写入SQL，且原材料标为可下线。这些均需确认DDL、目录绑定和实际写入逻辑后才能算为新增Hive表生产者。`topthreat_hot_stat`主要是**读Hive、写Mongo**，不计入生产Hive表6项。

## 迁移对齐要点

- 对6项按具体目标表拆分去留和责任：表不需要则不迁；保留消费者需要则落实新平台交付和验证。不要把整服务与内部子任务数量混算。
- 对新增确认的IOC点表和边表，分别核对`ati-relations-loader-job`的写入子任务、DDL/视图关系、写入窗口、消费者及StarRocks交付方案；已识别的`gnn-domain-hive-query-cronjob`、`ati-pdns-cache-job`读取点表，边表消费者待查。
- 对2项HDFS接入链路核对目标Hive表、分区登记和是否由数据湖直接承接；对2项维护任务确认旧消费者退出后再停。
- `secevent-to-hive-batch`和`secevent_analyse`在旧材料中标为已下线，缺少目标表/现网写入证据，不计入当前明确的6项；需核实是否有残留实例。

依据：[任务来源与输出清单](../大数据平台YARN上的任务梳理-项目数据来源及输出.csv)、[YARN任务清单及SQL](../大数据平台YARN上的任务梳理-云脑大数据平台.csv)、[Oozie链路说明](../log/DATA_FLOW.md)、[DataX同步映射](./datax-server-SZ-MongoDB到Hive同步任务映射.md)及用户2026-09-17关于IOC节点表的补充确认。
