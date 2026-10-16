# Oozie-SZ 项目数据流文档

> 生成日期: 2026-06-10

## 项目概述

本项目是基于 Oozie 调度的大数据安全日志处理平台，分为 **FLKF（法兰克福）** 和 **ShenZhen（深圳）** 两个环境区域，共 **6 个 Coordinator 任务**。数据从 ClickHouse 数据湖 / Kafka 源表，经过 ODS 层入湖、DW/DWB 层加工，最终输出到 HDFS/Hive 和 MongoDB。

---

## 整体数据流水线

```
ClickHouse (SODL数据湖)
      |
      | [sodl_ods_info_new - 每小时第7分]
      v
Hive ODS层 (sodl.* 表, HDFS /hive/ods/sodl/)
      |
      | [sodl_dwb_info - 每天02:30]
      v
Hive DWB层 (sodl.dwb_sodl_* 表, HDFS /hive/dwb/sodl/)
      |
      | [topthreat_hot_stat - 每小时第7分]
      v
MongoDB (db_statistic.tb_original_*_stat)


另外一条独立流水线 (深圳旧架构):

Kafka/log_audit_source + log_stats_source
      |
      | [log_compress - 每天00:30]
      v
Hive ODS层 (csc.ods_csc_log_audit/stats)
      |
      v
Hive DWB层 (default.dwb_*_info, HDFS /hive/dwb/default/)
      |
      | [merge_data.sh]
      v
合并审计数据到DWB分区 (log_audit子目录)
```

---

## 任务总表

| 任务名 | 环境 | 调度频率 | 时区 | 说明 |
|--------|------|---------|------|------|
| sodl_ods_info_new | ShenZhen | 每小时第7分 (`07 * * * *`) | Asia/Shanghai | SODL数据湖ODS层小时级抽取 |
| log_compress | ShenZhen | 每天00:30 (`30 00 * * *`) | Asia/Shanghai | 日志压缩/DW层加工 |
| sodl_dwb_info | ShenZhen | 每天02:30 (`30 02 * * *`) | Asia/Shanghai | SODL数据湖DWB层日级加工 |
| topthreat_hot_stat | ShenZhen | 每小时第7分 (`07 * * * *`) | Asia/Shanghai | 热点威胁统计(Hive->MongoDB) |
| create_hive_partition | ShenZhen | 每天12:30/15:30/18:30 (`30 12,15,18 * * *`) | Asia/Shanghai | Hive分区预创建 |
| secevent_analyse | FLKF | 每小时第7分 (`07 * * * *`) | Europe/Berlin | 安全事件Spark批处理入库 |

---

## 各任务详细说明

### 1. sodl_ods_info_new — SODL ODS 层小时级抽取

**调度**: 每小时第7分钟
**数据源**: ClickHouse (`http://opck.datalake.novalocal:4433/`)
**目标**: HDFS `/hive/ods/sodl/{表名}/year=.../month=.../day=.../hour=.../`
**机制**: Python 脚本 (`sodl_to_hdfs.py`) 从 ClickHouse HTTP 接口查询数据，按 Parquet 格式流式写入 HDFS，校验文件完整性（PAR1 魔数），自动删除7天前旧数据

6 个子任务并行执行：

| 子任务 | 源表(ClickHouse) | 目标HDFS路径 | 分片步长(分钟) |
|---|---|---|---|
| dns_log | `sodl.dns_log` | `/hive/ods/sodl/dns_log/` | 10 |
| endpoint_security_log | `sodl.endpoint_security_log` | `/hive/ods/sodl/endpoint_security_log/` | 60 |
| http_log | `sodl.http_log` (仅NGAF/AF/VNGAF) | `/hive/ods/sodl/http_log/` | 30 |
| network_security_log | `sodl.network_security_log` | `/hive/ods/sodl/network_security_log/` | 20 |
| sip_iocstat_log | `sodl.sip_iocstat_log` | `/hive/ods/sodl/sip_iocstat_log/` | 60 |
| url_log | `sodl.url_log` | `/hive/ods/sodl/url_log/` | 20 |

**Workflow DAG**:
```
fork-start --> dns_log ------------> start-join --> End
           --> endpoint_security_log -->
           --> http_log --------------->
           --> network_security_log --->
           --> sip_iocstat_log -------->
           --> url_log --------------->
```

---

### 2. log_compress — 日志压缩 + DW层构建

**调度**: 每天00:30
**机制**: 两个阶段串并行处理，SQL通过 `run_sql.sh`（Kerberos认证 + beeline）执行

**阶段一 — ODS 入库（并行 fork）**:

| 子任务 | 源表 | 目标表 | 过滤条件 |
|---|---|---|---|
| insert_audit | `default.log_audit_source` | `csc.ods_csc_log_audit` | 排除 app_id='configserver' |
| insert_stats | `default.log_stats_source` | `csc.ods_csc_log_stats` | 排除 app_id='configserver'，length(log_app_id)<128 |

**阶段二 — DW 审计数据（audit 完成后 fork）**:

| 子任务 | 源表 | 目标HDFS | 关联维度表 |
|---|---|---|---|
| dw_md5_info_audit | `csc.ods_csc_log_audit` (analysis-proxy-api, file_hash/file_scan) | `/hive/dwb/default/md5_info_audit/${mday}` | `sri.ods_sri_hashinfo`, `default.ods_devicemanager_deviceinfo` |
| dw_url_info_audit | `csc.ods_csc_log_audit` (cloudcheck + cloud-check-handler, urls/url) | `/hive/dwb/default/url_info_audit/${mday}` | `csc.ods_csc_db_url_intelligence_tb_url_reputation_sync`, `default.ods_devicemanager_deviceinfo` |
| dw_domain_info_audit | `csc.ods_csc_log_audit` (cloudcheck + cloud-check-handler, domains/domain) | `/hive/dwb/default/domain_info_audit/${mday}` | `csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync`, `sri.ods_sri_ti_tags`, `default.ods_devicemanager_deviceinfo` |

**阶段三 — 数据合并（join 后串行）**:

`merge_data.sh` 将 audit 数据合并到主 DWB 目录：
- `domain_info_audit/*` → `domain_info/{mday}/log_audit/`
- `url_info_audit/*` → `url_info/{mday}/log_audit/`
- `md5_info_audit/*` → `md5_info/{mday}/log_audit/`

**Workflow DAG**:
```
fork-start --> insert_audit --> fork-dw --> dw_md5_info_audit --> dw-join --> start-join --> merge_action --> End
           --> insert_stats --> start-join                dw_url_info_audit -->
                                             dw_domain_info_audit -->

(已注释掉的旧action: dw_md5_info, dw_url_info, dw_domain_info, dw_ip_info)
```

**旧（注释）DW层的数据源**（供参考）：

| DW表 | 数据源 |
|---|---|
| dw_md5_info | `ngaf.ods_ngaf_seclog_virus`, `ngaf.ods_ngaf_oprreportsave`, `ac.ods_ac_secevent`, `edr.ods_edr_oprdata`, `edr.ods_edr_virus`, `sip.ods_sip_iocstat`, `sip.ods_sip_filethreat_result`, `edr.ods_edr_webshell`, `ngaf.ods_ngaf_seclog_mail` |
| dw_url_info | `ngaf.ods_ngaf_seclog_utm`, `ngaf.ods_ngaf_url`, `ac.ods_ac_url`, `ac.ods_ac_secevent`, `sip.ods_sip_iocstat`, `ngaf.ods_ngaf_urlsingle`, `ngaf.ods_ngaf_http` |
| dw_domain_info | `ngaf.ods_ngaf_seclog_utm`, `ngaf.ods_ngaf_dns`, `sip.ods_sip_dns`, `ac.ods_ac_secevent`, `sip.ods_sip_iocstat`, `ngaf.ods_ngaf_dnssingle`, `edr.ods_edr_botnet_all`, `ac.ods_ac_url` |
| dw_ip_info | `ngaf.ods_ngaf_seclog_utm/waf/ips`, `ngaf.ods_ngaf_dns`, `ngaf.ods_ngaf_url`, `ac.ods_ac_secevent`, `ac.ods_ac_url`, `sip.ods_sip_dns`, `ngaf.ods_ngaf_http`, `sip.ods_sip_iocstat` |

---

### 3. sodl_dwb_info — SODL DWB 层日级加工

**调度**: 每天02:30
**机制**: 从 SODL ODS 表多源 UNION ALL 聚合，JOIN 威胁情报维度表和设备信息维度表，输出 Parquet 到 HDFS 并添加 Hive 分区

3 个子任务并行（`dwb_sodl_url_info` 已注释暂停）：

| 子任务 | 数据源 | 目标 | 关联维度表 |
|---|---|---|---|
| dwb_sodl_md5_info | `sodl.network_security_log` (filehash), `sodl.endpoint_security_log` (filemd5), `sodl.sip_iocstat_log` (ioc_type='file') | `/hive/dwb/sodl/md5_info/` → `sodl.dwb_sodl_md5_info` | `sri.ods_sri_hashinfo`, `default.ods_devicemanager_deviceinfo` |
| dwb_sodl_domain_info | `sodl.network_security_log` (domain from url), `sodl.dns_log` (queries), `sodl.sip_iocstat_log` (ioc_type='domain'), `sodl.endpoint_security_log` (domain), `sodl.url_log` (host) | `/hive/dwb/sodl/domain_info/` → `sodl.dwb_sodl_domain_info` | 黑DNS库, `sri.ods_sri_ti_tags`, `default.ods_devicemanager_deviceinfo` |
| dwb_sodl_ip_info | `sodl.network_security_log`, `sodl.dns_log`, `sodl.url_log`, `sodl.http_log`, `sodl.sip_iocstat_log` (ioc_type='ip') | `/hive/dwb/sodl/ip_info/` → `sodl.dwb_sodl_ip_info` | 黑IP库, `sri.ods_sri_ti_tags`, `default.ods_devicemanager_deviceinfo` |
| ~~dwb_sodl_url_info~~ | ~~network_security_log + url_log + sip_iocstat_log(url) + http_log~~ | ~~已暂停~~ | — |

**Workflow DAG**:
```
fork-start --> dwb_sodl_md5_info ----> start-join --> End
           --> dwb_sodl_domain_info -->
           --> dwb_sodl_ip_info ----->
           (dwb_sodl_url_info -- 已注释暂停)
```

---

### 4. topthreat_hot_stat — 热点威胁统计

**调度**: 每小时第7分钟
**机制**: 通过 `storage` 框架（Python），执行 YAML 中定义的 Hive SQL，结果批量写入 MongoDB
**处理数据**: 前2小时的数据

3 个子任务并行：

| 子任务 | 脚本 | 配置文件 | 统计维度 | 目标MongoDB |
|---|---|---|---|---|
| domain_stat | `black_domain_stat.sh` | `black_domain_stat.yaml` | 黑域名热度 | `mongo-int.db_statistic.tb_original_domain_stat` |
| url_stat | `black_url_stat.sh` | `blcak_url_stat.yaml` | 黑URL热度 | `mongo-int.db_statistic.tb_original_url_stat` |
| file_stat | `black_file_stat.sh` | `black_file_stat.yaml` | 黑文件MD5热度 | `mongo-int.db_statistic.tb_original_file_stat` |

**Workflow DAG**:
```
fork-topthreat-stat --> domain_stat --> start-join --> End
                    --> url_stat -->
                    --> file_stat -->
```

---

### 5. create_hive_partition — Hive 分区预创建

**调度**: 每天12:30/15:30/18:30
**机制**: Python 脚本提前为 T+2 日期创建 Hive 分区和 HDFS 目录

三步操作：
1. `createPartitionDaily.yaml` — 执行 ALTER TABLE ADD PARTITION 语句（日分区表）
2. `createDirHourly.yaml` — 在 HDFS 上创建小时级目录
3. `createPartitionHourly.yaml` — 执行 ALTER TABLE ADD PARTITION 语句（小时分区表）

**日分区表**:
- `cloudeye.ods_cloudeye_tamper`, `cloudeye.ods_cloudeye_vuln`
- `sri.ods_sri_nta_business/ioccustom/ipgroup/riskbusiness/riskevent/riskterminal/secevent/terminal/weakpasswd`
- `sri.ods_sri_save_featureinfo`, `sri.ods_sri_save_summaryinfo`

**小时分区表**:
- `sri.ods_sri_nta_cleartext`
- `csc.ods_csc_vertex` (graph_type: domain/url/ip/file/email/person/organization/phone/article/hacker)
- `csc.ods_csc_edge` (graph_type: downloaded/dropped/contacted/resolutions/underlings/registered/reference/property)
- `default.log_audit_source`, `default.log_stats_source`
- `sodl.dns_log`, `sodl.endpoint_security_log`, `sodl.http_log`, `sodl.network_security_log`, `sodl.sip_iocstat_log`, `sodl.url_log`

**HDFS目录创建**:
- `/real-time/out/hive/ods/sri_nta_cleartext/...`
- `/real-time/out/hive/ods/csc_vertex/...` (多种 graph_type)
- `/real-time/out/hive/ods/csc_edge/...` (多种 graph_type)
- `/soapa_logs/stats_stream/...`, `/soapa_logs/audit_stream/...`

**Workflow DAG**:
```
create_hive_partition --> End (即使失败也到End)
```

---

### 6. secevent_analyse — FLKF 安全事件 Spark 批处理

**调度**: 每小时第7分钟（Europe/Berlin 时区）
**机制**: 通过 spark-submit 提交 `secevent-to-hive-batch-flkf.jar`（Spark on YARN client模式）
**处理数据**: 前1小时的数据

**Spark配置**: 4 executors, 2048M executor memory, 2048M driver memory, 2 cores

**Workflow DAG**:
```
secevent_to_hive_batch --> End
```

---

## 公共维表

以下维度表被多个数据流 JOIN 使用：

| 维度表 | 说明 | 使用者 |
|---|---|---|
| `sri.ods_sri_hashinfo` | 文件MD5情报（oid/file_attr/file_type/type/family/virus_name等） | dw_md5_info, dw_md5_info_audit, dwb_sodl_md5_info |
| `sri.ods_sri_ti_tags` | 威胁情报标签（family/category的中英文名） | dw_domain_info, dw_domain_info_audit, dwb_sodl_domain_info, dwb_sodl_ip_info |
| `csc.ods_csc_db_url_intelligence_tb_url_reputation_sync` | URL信誉库（mask/category/family/add_time） | dw_url_info, dw_url_info_audit, dwb_sodl_url_info |
| `csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync` | 域名信誉库（黑DNS，domain/labels/reputation） | dw_domain_info, dw_domain_info_audit, dwb_sodl_domain_info |
| `csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync` | IP信誉库（黑IP，ip/labels/reputation/direction） | dwb_sodl_ip_info |
| `default.ods_devicemanager_deviceinfo` | 设备+客户信息（dev_id/customer_info → city/province/country/industry/sub_industry） | 所有DW/DWB任务 |

---

## 公共基础设施

### SQL执行器 (run_sql.sh)

- Kerberos认证: `./krb-tool oozie-sz`
- beeline连接串: `jdbc:hive2://sz-abdi1-zookeeper-1/2/3.novalocal:2181/;serviceDiscoveryMode=zooKeeper;zooKeeperNamespace=hiveserver2`
- 支持重试: max_retry_times + retry_interval 参数
- 支持 --hivevar 传递动态分区参数

### 存储处理器框架 (storage)

- 入口: `python -m storage day=X hour=X conf_path=xxx.yaml`
- 流程: 解析YAML配置 → 实例化处理器 → 执行HiveSQL → 过滤脏数据 → 格式化为MongoDB UpdateOne → bulk_write
- 7种处理器模块: topthreat_domain_stat, topthreat_url_stat, black_domain_processor, black_url_processor, file_processor, url_cate_processor, white_dns_processor
- 线程池并发执行多配置任务

### 部署系统 (deploy.py)

- 上传代码到HDFS `/user/oozie/oozie_jobs_auto/`
- 替换config.xml中的模板变量 (`{{coor_name}}`, `{{wk_name}}`, `{{start_date}}`, `{{end_date}}`, `{{job_root}}`)
- 提交新的Coordinator任务
- 更新旧Coordinator的end_time使其停止
- 清理HDFS上不再运行的老代码

---

## 当前暂停的任务

- **dwb_sodl_url_info** — 在 `sodl_dwb_info` workflow 中已注释（对应分支 `feature-pause-url-info`）
- **log_compress 中4个旧DW任务** — `dw_md5_info`, `dw_url_info`, `dw_domain_info`, `dw_ip_info` 已被注释，当前只走 audit 路径

---

## 文件路径索引

| 类型 | 路径 |
|---|---|
| Workflow定义 | `oozie_projects/jobs/{ShenZhen\|FLKF}/{任务名}/workflow.xml` |
| Coordinator定义 | `oozie_projects/jobs/{ShenZhen\|FLKF}/{任务名}/coordinator.xml` |
| 任务代码 | `oozie_projects/jobs/{ShenZhen\|FLKF}/{任务名}/code/` |
| SQL文件 | `code/dw/`, `code/dw_audit/`, `code/dwb/`, `code/sodl/` 等子目录 |
| Shell脚本 | `code/run_sql.sh`, `code/merge_data.sh`, `code/sodl_to_hdfs.sh` 等 |
| Python脚本 | `code/sodl_to_hdfs.py`, `code/run/create_hive_partition.py` |
| Scala源码 | `src/scala/all-events-statistic/`, `src/scala/secevent-to-hive-batch/` |
| 公共SDK | `app-sdk/soapa-sangfor-lib/shell/`, `app-sdk/soapa-sangfor-lib/python/storage/` |
| 部署脚本 | `oozie_projects/deploy.py`, `oozie_projects/common_depends_config.py` |
| YAML配置 | `code/black_domain_stat.yaml`, `code/blcak_url_stat.yaml`, `code/black_file_stat.yaml` 等 |
