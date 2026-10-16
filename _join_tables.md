
## 原始层

| 服务 | 云脑状态 | 来源表状态 | 优先级 | 负责人 | 业务分类 | 计算 | 作用 | 主要来源 | 输出 | 依赖标记 |
|---|---|---|---|---|---|---|---|---|---|---|
|ati-relations-loader-job|保留|-|-|肖扬|-|spark|融合后的关系数据，spark任务提交Job|深二Kafka|深二大数据平台；csc.ods_csc_vertex；csc.ods_csc_edge；Nebula图数据库|-|
|cloud-display-manager-prc|保留|-|-|肖扬|云鉴页面|spark|云鉴防护运营数据管理APP|深二Kafka|深二MongoDB；深二Redis；HDFS目录 /backup/cloud_display/statistic/{yy|-|
|create_hive_partition|保留|-|-|刘树文|-|MAPREDUCE|创建Hive分区|无|- Hive表分区：多个Hive表的日分区和小时分区；- HDFS目录结构：按时间维度组织的目录结构；- 主要涉及的Hi|-|
|datax-server|保留|-|高|王绪寒|情报信誉mongodb同步hive|/|mongodb表同步hive|深二MongoDB|HDFS目录；/hive/ods/ngaf/assetinfo/ - 资产信息数据（SZ）；/hive/ods/csc/|-|
|dns-intelligence-dispatch-prc|保留|-|高|王绪寒|云情报网关-数据分发|pulsar|数据湖未知上报dns分发|深二数据湖Pulsar；深二Kafka|深二Kafka|-|
|ip-intelligence-dispatch-prc|保留|-|高|王绪寒|云情报网关-数据分发|pulsar|数据湖未知上报c2 ip分发|深二数据湖Pulsar|深二Kafka|-|
|soapa-logger-stream-prc|保留|-|高|刘俊|-|flink|日志系统从kafka转发数据到ES、HDFS|深二Kafka|ES集群；HDFS目录；基础路径：hdfs://{cluster_name}/soapa_logs/；Dev日志目录：`|-|
|sodl_ods_info|保留|-|-|王绪寒|数据湖数据同步|MAPREDUCE|数据同步（拉取数据湖数据）|深二数据湖ClickHouse；sodl.dns_log - DNS日志表；sodl.endpoint_security_log - 端点安全日志表；sodl.http_log -|深二大数据平台(存储在`/hive/ods/sodl/`目录)；sodl.dns_log - DNS日志表；sodl.e|sodl ODS|
|sync-mongo2hive-job|保留|-|-|王坤|-|spark|文件云查同步到hive|深二MongoDB|深二大数据平台；sri.ods_sri_hashinfo(全量表)；sri.ods_sri_hashinfo_incre|-|
|ti-hot-data-detection-fusing-prc|保留|-|高|肖扬|aes检测|ck|从数据湖获取aES上报MD5|深二数据湖ClickHouse；sodl.handle_info_log|深二Kafka|-|
|ti-ip-detection-send-prc|保留|-|高|肖扬|aes检测|ck|从数据湖获取aES上报IP|深二数据湖ClickHouse；sodl.handle_info_log|深二Kafka；Prometheus指标|-|
|top-visit-host-produce-job|保留|-|高|王绪寒|云情报网关-过滤包生产|tez|访问TOP库建设(云情报网关过滤包)|default.log_audit_source；sodl.dns_log；sodl.url_log|深二Redis|sodl ODS|
|url-intelligence-dispatch-prc|保留|-|高|王绪寒|云情报网关-数据分发|pulsar|数据湖未知上报url分发|深二数据湖Pulsar；深二Kafka|深二Kafka|-|
|secevent-to-hive-partition-pruned-cron-job|待确认|-|-|王绪寒|-|spark|spark-SQL分区定时修剪|HDFS目录/real-time/config/secevent-to-hive-stream/config.json配置文件|预加载Hive表的分区数据|-|
|secevent-to-hive-stream-prc|待确认|-|-|明瞻|-|flink|安全事件实时入hive库进程服务|深二Kafka|HDFS目录；/real-time/out/ -输出数据目录；/real-time/dirty-data/ -脏数据目录|-|

## 中间层

| 服务 | 云脑状态 | 来源表状态 | 优先级 | 负责人 | 业务分类 | 计算 | 作用 | 主要来源 | 输出 | 依赖标记 |
|---|---|---|---|---|---|---|---|---|---|---|
|log_compress|保留|-|-|刘树文|-|MAPREDUCE|日志压缩|csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync；csc.ods_csc_db_url_intelligen|深二大数据平台；压缩日志表；csc.ods_csc_log_audit；csc.ods_csc_log_stats；旧中|旧DWB|
|sodl_dwb_info|保留|-|-|王绪寒|-|MAPREDUCE|中间表|csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync；csc.ods_csc_db_url_intelligen|深二大数据平台；新中间表；sodl.dwb_sodl_md5_info - MD5信息表，存储在/hive/dwb/so|新DWB,sodl ODS|

## 业务层

| 服务 | 云脑状态 | 来源表状态 | 优先级 | 负责人 | 业务分类 | 计算 | 作用 | 主要来源 | 输出 | 依赖标记 |
|---|---|---|---|---|---|---|---|---|---|---|
|active-domain-elt-job|保留|-|高|王绪寒|域名情报生产-主动降误报|tez|活跃域名回扫|csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync；default.dwb_domain_info；defau|深二Redis|新旧DWB|
|ati-pdns-cache-job|保留|-|高|肖扬|图数据库-dns信息更新|tez|数据接入过滤模块|csc.ods_csc_ioc_vertex|深二MongoDB；深二Redis|-|
|attack-ip-analysis-cronjob|保留|-|高|王绪寒|攻击者IP情报生产|tez|攻击者IP情报生产|csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync；csc.ods_csc_tim_db_unknown_intellige|深二MongoDB；深二Redis；深二Kafka|sodl ODS|
|black-ti-context-produce-prc|保留|-|高|王绪寒|情报上下文-攻击次数统计|tez|恶意IOC活跃次数统计|csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync；csc.ods_csc_tb_tenant_subscri|深二MongoDB；深二Redis|新旧DWB|
|cert-app-samplesync-country-job|保留|-|-|肖扬|-|tez|蓝军 cert数据上报|csc.ods_csc_business_data；sri.ods_sri_hashinfo|HDFS目录/hive/ods/csc/business_data/cert_report/；SCP目标服务器|-|
|cert-app-samplesync-job|保留|-|-|肖扬|-|tez|蓝军 cert数据上报|csc.ods_csc_business_data；sri.ods_sri_hashinfo|HDFS目录/hive/ods/csc/business_data/cert_report/[日期]/|-|
|cipd-product-resource-monitor-prc|保留|-|中|王绪寒|云情报网关监控-设备数量|tez|云情报网关设备数量监控|csc.ods_csc_log_stats；深二Redis|Prometheus指标|-|
|ctig-report-data-analysis-prc|保留|-|高|王绪寒|云情报网关-报告分析|tez|云情报网关报告分析|csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync；csc.ods_csc_db_url_intelligen|深二Kafka|新DWB|
|dashboard-stats-job|保留|-|高|王绪寒|情报公司大屏展示|tez|公司大屏|default.ods_devicemanager_deviceinfo；sodl.endpoint_security_log；sodl.network_security_log|深二MongoDB|sodl ODS|
|domain-hit-devnum-cronjob|保留|-|高|王绪寒|域名情报生产-降误报|tez|域名命中设备数统计（降误报）|default.dwb_domain_info；default.ods_custom_upload_data|深二MongoDB|旧DWB|
|domain-security-log-etl-prc|保留|-|高|王绪寒|域名情报生产-安全日志|tez|基于网络安全告警日志规则鉴定域名|sodl.network_security_log|深二MongoDB|sodl ODS|
|filter-layout-ip-seg-stat-prc|保留|-|高|王绪寒|云情报网关-C段过滤|tez|ip C端统计|csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync；csc.ods_csc_log_audit|深二Redis|-|
|gnn-domain-hive-query-cronjob|保留|-|高|王绪寒|域名情报生产-图神经网络|tez|查询图数据库域名|csc.ods_csc_ioc_vertex|深二Redis|-|
|ip-security-log-etl-prc|保留|-|高|王绪寒|C2 IP情报生产-安全日志|tez|基于安全告警日志规则鉴定C2 IP|sodl.network_security_log|深二Redis|sodl ODS|
|online-dev-warehousing-prc|保留|-|-|段宁强|-|flink|实时在线设备统计|深二Kafka|深二MongoDB|-|
|topthreat_hot_stat|保留|-|-|王绪寒|-|MAPREDUCE|文件MD5、URL统计表、域名统计表入库|default.log_audit_source；sodl.network_security_log；sodl.sip_iocstat_log|深二MongoDB|sodl ODS|
|asset-discovery-task|可下线|-|-|肖扬|-|spark|资产发现任务|ngaf.ods_ngaf_dns；ngaf.ods_ngaf_seclog_dos；深二MongoDB|深二MongoDB；HDFS目录/apps/hive/warehouse|ngaf已无库|
|vuln-assert-analysis|可下线|-|-|-|-|spark|资产关联漏洞分析|ngaf.ods_ngaf_seclog_pvs；深二MongoDB|深二MongoDB；HDFS目录/apps/hive/warehouse|ngaf已无库|
|apt-hunting-monitor-process-job|待确认|可下线|-|段宁强|-|tez|持续监控定时任务|csc.ods_csc_apt_hunting；default.dwb_domain_info；default.dwb_ip_info；default.dwb_md5_info；d|HDFS目录/hive/ods/csc/apt_hunting/{task_id}/{ioc_type}/related|新旧DWB,读旧IP宽表,读新URL宽表|
|black-file-clean-cronjob|待确认|-|-|王绪寒|-|tez|黑文件去误报|default.dwb_md5_info；sodl.dwb_sodl_md5_info|Hive查询作为VT查询输入数据，输出为白文件MD5列表同步到文件云系统|新旧DWB|
|domain-heat-stats-cron-job|待确认|-|高|彭宜|GPT钓鱼联动封锁-降误报|tez|域名热度库统计生产|sodl.dwb_sodl_domain_info|深二MongoDB|新DWB|
|phishing-url-operation-prc|待确认|-|-|彭宜|-|tez|URL漏报自动化运营|csc.ods_csc_log_audit；深二MongoDB|深二MongoDB|-|
|svd-activity-stat-job|待确认|-|-|王绪寒|-|tez|通过设备上报日志统计漏洞及规则的活跃度|sodl.network_security_log；深二MongoDB|深二MongoDB|sodl ODS|

## 无层级（仅云脑CSV）

| 服务 | 云脑状态 | 来源表状态 | 优先级 | 负责人 | 业务分类 | 计算 | 作用 | 主要来源 | 输出 | 依赖标记 |
|---|---|---|---|---|---|---|---|---|---|---|
|secevent-to-hive-batch|已下线|-|-|明瞻|-|spark|压缩产品线上报日志|-|-|-|
|secevent_analyse|已下线|-|-|王绪寒|-|MAPREDUCE|-|-|-|-|
|thug-task-monitor-prc|已下线|-|-|彭宜|-|tez|thug任务队列监控|-|-|-|
|sp-old-update-report-cron-job|待确认|-|-|-|-|tez|sp数据采集升级反馈上报中台|-|-|-|
|yara-sample-query-job|待确认|-|-|段宁强|-|tez|样本查询|-|-|-|

## 仅云脑CSV、来源表无记录

- `secevent-to-hive-batch` 云脑状态=已下线 作用=压缩产品线上报日志 备注=最近一次修改在4年前，疑似有流处理方案（？
- `secevent_analyse` 云脑状态=已下线 作用= 备注=
- `sp-old-update-report-cron-job` 云脑状态=待确认 作用=sp数据采集升级反馈上报中台 备注=
- `thug-task-monitor-prc` 云脑状态=已下线 作用=thug任务队列监控 备注=分区一直是20240401，且一天执行大约1500次；
下线的是thug-task-monitor-hive-source-prc这个容器
- `yara-sample-query-job` 云脑状态=待确认 作用=样本查询 备注=编译即结束，没向tez提交任务