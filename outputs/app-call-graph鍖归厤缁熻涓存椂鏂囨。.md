# app-call-graph results 匹配统计临时文档

统计日期：2026-06-15

## 数据来源

- 名单来源：`/Users/jun/project/sxf/2026/bigdata/outputs/项目数据来源及输出_全集join.xlsx`
- 匹配目录：`/Users/jun/project/sxf/2026/app-call-graph/results`
- 扫描文件数：3721

## 匹配口径

- 服务名称：使用 `云脑大数据平台` 的 `服务名称`，空白服务名已向下填充。
- 项目名称：使用 `项目数据来源及输出` 的 `项目名称`。
- 清洗规则：去掉服务名前导 `*`，排除 `汇总` 这类非服务行。
- 匹配规则：优先按 `results` 文件名或 JSON `repo` 名精确匹配；若无精确命中，再按文件内容完整字符串命中统计。

## 统计结果

| 名单 | 总数 | 能匹配上 | 未匹配 |
|---|---:|---:|---:|
| 服务名称 | 50 | 37 | 13 |
| 项目名称 | 40 | 36 | 4 |
| 服务名称 ∪ 项目名称 去重全集 | 51 | 38 | 13 |

## 未匹配名称全集

```text
create_hive_partition(oozie)
log_compress
log_compress(oozie)
secevent-to-hive-batch
secevent-to-hive-batch(oozie)
secevent_analyse(oozie)
sodl_dwb_info
sodl_dwb_info(oozie)
sodl_ods_info
sodl_ods_info(oozie)
thug-task-monitor-prc 容器:thug-task-monitor-hive-source-prc
topthreat_hot_stat
topthreat_hot_stat(oozie)
```

## 项目名称中未匹配

```text
log_compress
sodl_dwb_info
sodl_ods_info
topthreat_hot_stat
```

## 已匹配服务名称

```text
active-domain-elt-job
apt-hunting-monitor-process-job
asset-discovery-task
ati-pdns-cache-job
ati-relations-loader-job
attack-ip-analysis-cronjob
black-file-clean-cronjob
black-ti-context-produce-prc
cert-app-samplesync-country-job
cert-app-samplesync-job
cipd-product-resource-monitor-prc
cloud-display-manager-prc
ctig-report-data-analysis-prc
dashboard-stats-job
datax-server
dns-intelligence-dispatch-prc
domain-heat-stats-cron-job
domain-hit-devnum-cronjob
domain-security-log-etl-prc
filter-layout-ip-seg-stat-prc
gnn-domain-hive-query-cronjob
ip-intelligence-dispatch-prc
ip-security-log-etl-prc
online-dev-warehousing-prc
phishing-url-operation-prc
secevent-to-hive-partition-pruned-cron-job
secevent-to-hive-stream-prc
soapa-logger-stream-prc
sp-old-update-report-cron-job
svd-activity-stat-job
sync-mongo2hive-job
ti-hot-data-detection-fusing-prc
ti-ip-detection-send-prc
top-visit-host-produce-job
url-intelligence-dispatch-prc
vuln-assert-analysis
yara-sample-query-job
```

## 已匹配项目名称

```text
active-domain-elt-job
apt-hunting-monitor-process-job
asset-discovery-task
ati-pdns-cache-job
ati-relations-loader-job
attack-ip-analysis-cronjob
black-file-clean-cronjob
black-ti-context-produce-prc
cert-app-samplesync-country-job
cert-app-samplesync-job
cipd-product-resource-monitor-prc
cloud-display-manager-prc
create_hive_partition
ctig-report-data-analysis-prc
dashboard-stats-job
datax-server
dns-intelligence-dispatch-prc
domain-heat-stats-cron-job
domain-hit-devnum-cronjob
domain-security-log-etl-prc
filter-layout-ip-seg-stat-prc
gnn-domain-hive-query-cronjob
ip-intelligence-dispatch-prc
ip-security-log-etl-prc
online-dev-warehousing-prc
phishing-url-operation-prc
secevent-to-hive-partition-pruned-cron-job
secevent-to-hive-stream-prc
soapa-logger-stream-prc
svd-activity-stat-job
sync-mongo2hive-job
ti-hot-data-detection-fusing-prc
ti-ip-detection-send-prc
top-visit-host-produce-job
url-intelligence-dispatch-prc
vuln-assert-analysis
```
