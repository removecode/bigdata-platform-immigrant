# 深圳数据中心（SZ）MongoDB → Hive 同步任务映射表

来源：用户于2026-09-14提供的datax-server映射，未另行核验源仓库或现网配置。

> 数量核对：原材料标注“已定义任务全集（36个）”，但下方实际列出35项（10＋8＋2＋1＋14）。暂保留全部已提供记录，缺少的1项或总数标注需核实；不据此补造任务。

任务定义目录：`app-server/service/sz/`。

调度入口：`app-server/start.py:137-141`（`soapa_settings.location == Location.SZ`时加载`service.sz`）。

实际启用清单由仓库外文件`running_jobs.conf`决定，下表为用户提供的已定义任务清单，不代表全部当前启用。

集群别名见`app-server/conf/mongodb_conf.py`：

- `MONGO_INT_SZBWX` = `mongo-int-szbwx`（材料注明为唯一带深圳标记的集群）。
- `MONGO_TIM` / `MONGO_API` / `MONGO_OP` / `MONGO_SOAPA` / `MONGO_SEC`。

## 一、云情报 CloudLib / CloudTop（源集群 MONGO_INT_SZBWX，深圳独有）

| 任务文件 | Mongo库 | Mongo集合 | Hive路径 |
|---|---|---|---|
| `cloud_lib_c2ip_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudLibC2IP` | `/hive/ods/csc/int_scia_intelligence_cloudlibc2ip` |
| `cloud_lib_domain_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudLibDomain` | `/hive/ods/csc/int_scia_intelligence_cloudlibdomain` |
| `cloud_lib_file_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudLibFile` | `/hive/ods/csc/int_scia_intelligence_cloudlibfile` |
| `cloud_lib_ip_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudLibIP` | `/hive/ods/csc/int_scia_intelligence_cloudlibip` |
| `cloud_lib_url_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudLibURL` | `/hive/ods/csc/int_scia_intelligence_cloudliburl` |
| `cloud_top_c2ip_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudTopC2IP` | `/hive/ods/csc/int_scia_intelligence_cloudtopc2ip` |
| `cloud_top_domain_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudTopDomain` | `/hive/ods/csc/int_scia_intelligence_cloudtopdomain` |
| `cloud_top_file_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudTopFile` | `/hive/ods/csc/int_scia_intelligence_cloudtopfile` |
| `cloud_top_ip_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudTopIP` | `/hive/ods/csc/int_scia_intelligence_cloudtopip` |
| `cloud_top_url_mongo2hive.py` | `SCIA_INTELLIGENCE` | `CloudTopURL` | `/hive/ods/csc/int_scia_intelligence_cloudtopurl` |

## 二、TIM 威胁情报（源集群 MONGO_TIM，深圳独有）

| 任务文件 | Mongo库 | Mongo集合 | Hive路径 |
|---|---|---|---|
| `a1_tb_tenant_subscribe_info_mongo2hive.py` | `db_ti_context` | `tb_tenant_subscribe_info` | `/hive/ods/csc/tb_tenant_subscribe_info` |
| `aa_sync_domain_rpt_mongo2hive.py` | `db_domain_intelligence` | `tb_domain_reputation` | `/hive/ods/csc/db_domain_intelligence_tb_domain_reputation` |
| `aa_sync_url_rpt_mongo2hive.py` | `db_url_intelligence` | `tb_url_reputation` | `/hive/ods/csc/db_url_intelligence_tb_url_reputation` |
| `aa_tb_ip_reputation_mongo2hive.py` | `db_intelligence` | `tb_ip_reputation` | `/hive/ods/csc/tim_db_intelligence_tb_ip_reputation` |
| `tb_skyeye_domain_info_mongo2hive.py` | `db_unknown_intelligence` | `tb_skyeye_domain_info` | `/hive/ods/csc/tim_db_unknown_intelligence_tb_skyeye_domain_info` |
| `tb_skyeye_ip_info_mongo2hive.py` | `db_unknown_intelligence` | `tb_skyeye_ip_info` | `/hive/ods/csc/tim_db_unknown_intelligence_tb_skyeye_ip_info` |
| `tb_syn_ti_ip_network_type_mongo2hive.py` | `db_unknown_intelligence` | `tb_syn_ti_ip_network_type` | `/hive/ods/csc/tim_db_unknown_intelligence_tb_syn_ti_ip_network_type` |
| `tb_syn_tr_attack_black_ip_mongo2hive.py` | `db_known_intelligence` | `tb_syn_tr_attack_black_ip` | `/hive/ods/csc/tim_db_known_intelligence_tb_syn_tr_attack_black_ip` |

## 三、EDR 配置（源集群 MONGO_OP，深圳独有）

| 任务文件 | Mongo库 | Mongo集合 | Hive路径 |
|---|---|---|---|
| `edr_config_rtp_mongo2hive.py` | `SCIA_EDR_CFG` | `tb_edr_log_rtpconfig` | `/hive/ods/edr/rtp_config` |
| `edr_config_scan_mongo2hive.py` | `SCIA_EDR_CFG` | `tb_edr_log_scanconfig` | `/hive/ods/edr/scan_config` |

## 四、其他深圳独有任务

| 任务文件 | 源集群 | Mongo库 | Mongo集合 | Hive路径 |
|---|---|---|---|---|
| `manual_reports_reply_mongo2hive.py` | `MONGO_API` | `SCIA_ANALYSIS` | `ManualReportsReply` | `/hive/ods/csc/api_scia_analysis_manual_reports_reply` |

## 五、广州侧存在同名任务（按目录区分城市）

| 任务文件 | 源集群 | Mongo库 | Mongo集合 | Hive路径 |
|---|---|---|---|---|
| `apidb_scia_nta_events_mongo2hive.py` | `MONGO_API` | `SCIA_NTA` | `nta_events` | `/hive/ods/sri/nta_event` |
| `reputation_black_ip_mongo2hive.py` | `MONGO_SOAPA` | `secproxydb` | `SynTrReputationBlackIP` | `/hive/ods/sri/syn_tr_reputation_black_ip` |
| `sec_order_system_mongo2hive.py` | `MONGO_SEC` | `secdb` | `SecOrderSystem` | `/hive/ods/sri/sec_order_system` |
| `sec_wiki_info_file_mongo2hive.py` | `MONGO_SEC` | `secdb` | `SecWikiInfoFile` | `/hive/ods/sri/wiki_info_file` |
| `secdb_wikilogs_mongo2hive.py` | `MONGO_SEC` | `secdb` | `WikiLogs` | `/hive/ods/sri/sec_wikilogs` |
| `syn_ti_ioc_mongo2hive.py` | `MONGO_SOAPA` | `secproxydb` | `SynTiIOC` | `/hive/ods/sri/ti_ioc` |
| `syn_ti_tags_mongo2hive.py` | `MONGO_API` | `SCIA_ANALYSIS` | `SynTiTags` | `/hive/ods/sri/ti_tags` |
| `syn_tr_malice_link_black_link_mongo2hive.py` | `MONGO_SOAPA` | `secproxydb` | `SynTrMaliceLinkBlackLink` | `/hive/ods/csc/soapa_secproxydb_syntrmalicelinkblacklink_sync` |
| `syn_tr_utm_black_dns_mongo2hive.py` | `MONGO_SOAPA` | `secproxydb` | `SynTrUTMBlackDNS` | `/hive/ods/csc/soapa_secproxydb_syntrutmblackdns_sync` |
| `sync_assetsinfo_mongo2hive.py` | `MONGO_API` | `customerassets` | `AssetInfo` | `/hive/ods/ngaf/assetinfo` |
| `sync_customerdeviceinfo_mongo2hive.py` | `MONGO_API` | `customerassets` | `SynCustomerDeviceInfo` | `/hive/ods/sri/syncustomerdeviceinfo` |
| `sync_dnsmapping_mongo2hive.py` | `MONGO_SOAPA` | `secproxydb` | `MgDNSMapping` | `/hive/ods/sri/secproxydb_mgdnsmapping/{date_str}` |
| `sync_snort_rules_mongo2hive.py` | `MONGO_SOAPA` | `SVD_DATA` | `SnortRules` | `/hive/ods/sri/snort_rules` |
| `sync_vuln_info_mongo2hive.py` | `MONGO_SOAPA` | `SVD_DATA` | `VulnInfo` | `/hive/ods/sri/vuln_info` |

## 备注

- 上述Hive路径均为`HIVE_PATH`；每个任务另有`HIVE_BACKUP_PATH`（路径尾部加`_bak`，个别为`bak`，如`cloud_*`系列）。`sync_dnsmapping`例外：使用`HIVE_TBL_NAME = sri.ods_sri_secproxydb_mgdnsmapping`且路径带日期分区。
- 原材料备注列出`sync_ti_tags`、`reputation_black_ip`、`sec_order_system`、`sec_wiki_info_file`、`secdb_wikilogs`、`sync_dnsmapping`等在广州目录下也有同名文件，源集群/目标表可能一致，城市由所在目录决定。
- 名称待核对：上表文件名为`syn_ti_tags_mongo2hive.py`，原材料备注写作`sync_ti_tags`，两种写法均保留记录，需以仓库文件为准。
- 每个文件的具体字段（`reader.add_column` / `writer.add_column`）未在本表列出，字段级映射需另行展开。
- 本表多数目标仅明确HDFS路径，不能仅凭路径推定准确Hive表名；与消费者表名的绑定需进一步核对DDL及配置。
