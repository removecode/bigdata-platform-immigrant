-- 目前可迁移任务的 StarRocks 语句（本机已执行，结果见 outputs/migratable-tasks-starrocks-results.tsv）
-- 范围：ACT-048、ACT-049 之后的可迁移清单 —— 排除 default.ods_custom_upload_data 与 csc.ods_csc_ioc_vertex 未同步的任务，
--       排除 DWB 未交付、可下线、待确认的任务（DEC-012、DEC-025）。
-- 转换规则：docs/StarRocks语句转换规则.md（DEC-014 至 DEC-024）。本文件没有用户当次之外的新表名；缺少新平台表名的对象保留原名。
-- 本文件是语句草稿，不表示已在你的 StarRocks 或生产执行，也不表示可以切流。
-- 每条语句前的 `-- @stmt` 行供 lab/run_migratable.py 解析。

-- @stmt 1 | filter-layout-ip-seg-stat-prc | hive_sql
-- 表：csc.ods_csc_log_audit；ti.ods_ti_db_intelligence_tb_ip_reputation_sync
-- DEC-014 表名；DEC-015 app_id；DEC-024 以 all.sql 转义为准并加 query_timeout
-- csc.ods_csc_log_audit 的 day、module_id、str5、str10 缺少新平台字段名，保留旧名
-- DEC-009：day 的 BETWEEN、day_unique >= 5 的比较需要按实际编码转换，未加 CAST
WITH rpt AS (
  SELECT DISTINCT regexp_extract(ip, '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_seg
  FROM ti.ods_ti_db_intelligence_tb_ip_reputation_sync
  WHERE direction = '2' AND reputation = '0'
),
resp_data AS (
  SELECT day AS date_day,
         split(get_json_object(resp, '$.ip'), ':')[1] AS ip,
         regexp_extract(split(get_json_object(resp, '$.ip'), ':')[1], '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_c_seg
  FROM csc.ods_csc_log_audit,
       unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~\\]', ''), '\\}\\,\\{', '\;\{'), '\"', '"'), ';')) AS exploded_table(resp)
  WHERE app_id = 'ip-proxy-svc' AND day BETWEEN 20260925 AND 20261001
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
    AND get_json_object(resp, '$.threat.reputation') = '2'
    AND get_json_object(resp, '$.threat.direction') = '2'
),
agg_data AS (
  SELECT ip_c_seg,
         count(DISTINCT date_day) AS day_unique,
         count(DISTINCT ip) AS ip_unique,
         count(*) / (count(DISTINCT date_day) + 1) AS total
  FROM resp_data
  GROUP BY ip_c_seg
)
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 3600) */ ip_c_seg, day_unique, ip_unique, total
FROM agg_data
WHERE day_unique >= 5
  AND NOT EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg);

-- @stmt 2 | ip-security-log-etl-prc | C2_IP_SECURITY_LOG_SQL
-- 表：sodl.network_security_log（缺少新平台表名，截图未列出 sodl 表）
-- DEC-016：DAY=20261001 改为 insertdate = '2026-10-01'
-- 方言：regexp_extract 两参数补组号 1
-- DEC-009：severity > 50、threatclass in (...) 的比较需要按实际编码转换，未加 CAST
SELECT distinct dstip
FROM sodl.network_security_log
WHERE insertdate = '2026-10-01'
    AND regexp_extract(dstip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
    AND regexp_extract(dstip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
    AND engine not in ('premise_ioc', 'cloud_ioc', 'sase_ioc')
    AND severity > 50
    AND (threatclass in (209, 208, 216, 214,  203, 40)
        OR concat_ws('-', cast(threatclass as String),
                          cast(threattype as String),
                          cast(threatsubtype as String)) = '212-10-0')
limit 100000;

-- @stmt 3 | domain-security-log-etl-prc | INFO_EXIST_CHECK_SQL
-- 表：sodl.network_security_log（缺少新平台表名）
-- DEC-016：day=20261001 改为 insertdate = '2026-10-01'
SELECT 1 FROM sodl.network_security_log WHERE insertdate = '2026-10-01' LIMIT 1;

-- @stmt 4 | domain-security-log-etl-prc | DOMAIN_SECURITY_LOG_EXTRACT_SQL
-- 表：sodl.network_security_log（缺少新平台表名）
-- DEC-016 日期；方言：collect_set 改为 array_agg(DISTINCT ...)，sort_array 改为 array_sort，rlike 改为 REGEXP，反斜杠加倍
-- DEC-009：severity > 50、action = 2、threatclass in (...) 的比较需要按实际编码转换，未加 CAST
SELECT DOMAIN,
       array_agg(DISTINCT producttype) AS producttype_list,
       array_agg(DISTINCT CONCAT(CAST(threatclass AS STRING), '-', CAST(threattype AS STRING),
       '-', CAST(threatsubtype AS STRING))) AS type_list,
       array_sort(array_agg(DISTINCT engine)) AS engine_list,
       COUNT(DISTINCT engine) AS engine_num
FROM
  (SELECT regexp_extract(url, '^(?:https?://)?(?:www\\.)?([^/]+)', 1) AS DOMAIN,
          *
   FROM sodl.network_security_log
   WHERE insertdate = '2026-10-01'
     AND engine NOT IN ('premise_ioc', 'cloud_ioc', 'sase_ioc')
     AND severity > 50
     AND (threatclass IN (209, 208, 216, 214, 203, 40)
          OR CONCAT(CAST(threatclass AS STRING), '-', CAST(threattype AS STRING), '-',
          CAST(threatsubtype AS STRING)) = '212-10-0')
     AND action = 2) s
WHERE NOT (DOMAIN REGEXP '\\d+\\.\\d+\\.\\d+\\.\\d+$' OR DOMAIN REGEXP ':')
GROUP BY DOMAIN;

-- @stmt 5 | topthreat_hot_stat | black_domain_stat
-- 表：csc.ods_csc_log_audit；sodl.network_security_log；sodl.sip_iocstat_log（sodl 表缺少新平台表名）
-- DEC-014/015/016/017/020/021/022/023：详见 outputs/topthreat-hot-stat-starrocks.sql 头部
-- UDF `default`.format_json_list 原样保留（DEC-023）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */ domain,
       sum(domain_num) AS domain_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT domain,
          devid,
          count(1) AS domain_num
   FROM
     (SELECT lower(get_json_object(str10_tmp, '$.domain')) AS domain,
             str2 AS devid
      FROM csc.ods_csc_log_audit,
           unnest(`default`.format_json_list(regexp_replace(str10, '\\\\+"', '"'))) AS str10_tbl(str10_tmp)
      WHERE app_id IN ('domain-proxy-svc', 'cloudcheck')
        AND module_id IN ('domain-proxy-svc', 'CloudCheck')
        AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
                     'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
                     'EDR_CLOUD_IDENTIFY', 'EDR_PK')
        AND long1 = 0
        AND get_json_object(str10_tmp, '$.info.attr') = '0'
        AND day = 20261001
        AND hour = 0) a
   WHERE domain IS NOT NULL
     AND domain NOT IN ('', '-')
   GROUP BY domain, devid

   UNION ALL

   SELECT domain,
          devid,
          count(1) AS domain_num
   FROM
     (SELECT split(split(url, '//')[cardinality(split(url, '//'))], '/')[1] AS domain,
             deviceId AS devid
      FROM sodl.network_security_log
      WHERE url IS NOT NULL
        AND url NOT IN ('', '-')
        AND insertdate = '2026-10-01'
        AND hour(from_unixtime(inserttimestamp)) = 0) t
   WHERE domain IS NOT NULL
     AND domain != ''
   GROUP BY domain, devid

   UNION ALL

   SELECT ioc AS domain,
          deviceId AS devid,
          sum(record_count) AS domain_num
   FROM sodl.sip_iocstat_log
   WHERE ioc_type = 'domain'
     AND ioc IS NOT NULL
     AND ioc NOT IN ('', '-')
     AND insertdate = '2026-10-01'
     AND hour(from_unixtime(inserttimestamp)) = 0
   GROUP BY ioc, deviceId) t
GROUP BY domain, devid
ORDER BY domain_num DESC
LIMIT 100000;

-- @stmt 6 | topthreat_hot_stat | blcak_file_stat
-- 表：csc.ods_csc_log_audit；sodl.network_security_log；sodl.sip_iocstat_log（sodl 表缺少新平台表名）
-- DEC-014/015/016/017/020/021/022/023：详见 outputs/topthreat-hot-stat-starrocks.sql 头部
-- UDF `default`.format_json_list 原样保留（DEC-023）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */ md5,
       count(1) AS md5_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT lower(get_json_object(str10_tmp, '$.filemd5')) AS md5,
          get_json_object(str10_tmp, '$.info.attr') AS attr,
          str2 AS devid
   FROM csc.ods_csc_log_audit,
        unnest(`default`.format_json_list(regexp_replace(str10, '\\\\+"', '"'))) AS str10_tbl(str10_tmp)
   WHERE app_id = 'analysis-proxy-api'
     AND module_id IN ('file_hash', 'file_scan')
     AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
                  'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
                  'EDR_CLOUD_IDENTIFY', 'EDR_PK')
     AND long1 = 0
     AND day = 20261001
     AND hour = 0) a
WHERE md5 IS NOT NULL
  AND md5 NOT IN ('', '-')
  AND attr = '0'
GROUP BY md5, devid
ORDER BY md5_num DESC
LIMIT 100000;

-- @stmt 7 | topthreat_hot_stat | blcak_url_stat
-- 表：csc.ods_csc_log_audit；sodl.network_security_log；sodl.sip_iocstat_log（sodl 表缺少新平台表名）
-- DEC-014/015/016/017/020/021/022/023：详见 outputs/topthreat-hot-stat-starrocks.sql 头部
-- UDF `default`.format_json_list 原样保留（DEC-023）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */ url,
       sum(url_num) AS url_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT url,
          devid,
          count(1) AS url_num
   FROM
     (SELECT lower(get_json_object(str10_tmp, '$.url')) AS url,
             str2 AS devid
      FROM csc.ods_csc_log_audit,
           unnest(`default`.format_json_list(regexp_replace(str10, '\\\\+"', '"'))) AS str10_tbl(str10_tmp)
      WHERE app_id IN ('url-proxy-svc', 'cloudcheck')
        AND module_id IN ('url-proxy-svc', 'CloudCheck')
        AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
                     'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
                     'EDR_CLOUD_IDENTIFY', 'EDR_PK')
        AND long1 = 0
        AND get_json_object(str10_tmp, '$.info.attr') = '0'
        AND day = 20261001
        AND hour = 0) a
   WHERE url IS NOT NULL
     AND url NOT IN ('', '-')
   GROUP BY url, devid

   UNION ALL

   SELECT url,
          deviceId AS devid,
          count(1) AS url_num
   FROM sodl.network_security_log
   WHERE url IS NOT NULL
     AND url NOT IN ('', '-')
     AND insertdate = '2026-10-01'
     AND hour(from_unixtime(inserttimestamp)) = 0
   GROUP BY url, deviceId

   UNION ALL

   SELECT ioc AS url,
          deviceId AS devid,
          sum(record_count) AS url_num
   FROM sodl.sip_iocstat_log
   WHERE ioc_type = 'url'
     AND ioc IS NOT NULL
     AND ioc NOT IN ('', '-')
     AND insertdate = '2026-10-01'
     AND hour(from_unixtime(inserttimestamp)) = 0
   GROUP BY ioc, deviceId) t
GROUP BY url, devid
ORDER BY url_num DESC
LIMIT 100000;

-- @stmt 8 | top-visit-host-produce-job | DNS_LOG_STAT_SQL
-- 表：sodl.dns_log（缺少新平台表名）
-- DEC-016：day = 20261001 改为 insertdate = '2026-10-01'
-- DEC-020：sodl 没有 log_num，sum(log_num) 改为 count(1)
-- DEC-009：qr=0、length(queries) > 3 的比较需要按实际编码转换，未加 CAST
SELECT queries as domain,
       count(1) AS num
FROM sodl.dns_log
WHERE insertdate = '2026-10-01'
  AND producttype in ('AF', 'NGAF', 'VNGAF')
  AND qr=0
  AND length(queries) > 3
  AND locate('.', queries) != 0
GROUP BY queries;

-- @stmt 9 | top-visit-host-produce-job | IP_LOG_STAT_SQL
-- 表：csc.ods_csc_log_audit
-- DEC-014 表名；DEC-015 log_app_id 改为 app_id
-- csc.ods_csc_log_audit 的 day、module_id、str1、str4、str5 缺少新平台字段名，保留旧名
-- 方言：LATERAL VIEW explode 改为 unnest；Hive 数组下标从 0 起，StarRocks 从 1 起；split 的分隔符在 StarRocks 是字面量，'\.' 改为 '.'
-- get_json_object 的 '$[*].ip' 路径在 StarRocks 是否返回与 Hive 相同的数组字符串，需在目标环境核对
with ip_stat as (
SELECT concat(split(ip, '.')[1], '.', split(ip, '.')[2], '.', split(ip, '.')[3]) AS c_segment
FROM
    (SELECT get_json_object(replace(str4, '\\', ''), '$[*].ip') AS ip_list
      FROM csc.ods_csc_log_audit
      WHERE day = 20261001
        AND app_id='ip-proxy-svc'
        AND module_id='ip-proxy-svc'
        AND str1='NGAF'
        AND str5='[cf]') s
   , unnest(split(regexp_replace(ip_list, '\\[|\\]|\\"', ''), ',')) AS exploded_table(ip)
   WHERE locate('.', ip) != 0
)
SELECT c_segment as ip,
       count(1) as num
FROM ip_stat
GROUP BY c_segment
LIMIT 500000;

-- @stmt 10 | top-visit-host-produce-job | URL_LOG_STAT_SQL
-- 表：sodl.url_log（缺少新平台表名）
-- DEC-016 日期；DEC-020 sum(log_num) 改为 count(1)
SELECT host,
       count(1) AS num
FROM sodl.url_log
WHERE insertdate = '2026-10-01'
  AND host is not null
  AND locate('.', host)  != 0
  AND producttype in ('AF', 'NGAF', 'VNGAF')
GROUP BY host;

-- @stmt 11 | dashboard-stats-job | DEVICE_STATS_SQL
-- 表：`default`.ods_devicemanager_deviceinfo（缺少新平台表名）
-- 来源：917 梳理 CSV
-- `default` 是 StarRocks 保留字，库名加反引号
SELECT product,
count(DISTINCT(dev_id)) as dev_num
FROM `default`.ods_devicemanager_deviceinfo
GROUP BY product;

-- @stmt 12 | dashboard-stats-job | IP_SECURITY_SQL
-- 表：sodl.network_security_log；`default`.ods_devicemanager_deviceinfo（均缺少新平台表名）
-- 来源：917 梳理 CSV 的 dashboard-stats-job（该任务不在 all.sql，无 all.sql 版本可对照）
-- DEC-016：t1.DAY = 20250825 与 t1.hour = 1 改为 insertdate = '2025-08-25' 与 hour(from_unixtime(t1.inserttimestamp)) = 1；日期是 CSV 里的固定值，不是调度参数
-- DEC-021：t1.manage 改为 t1.deviceId
-- default.ods_devicemanager_deviceinfo 缺少新平台表名，`default` 是 StarRocks 保留字，库名加反引号
-- DEC-009：reqruleid 的字符串比较、titype/threatclass/threattype 的数值比较需要按实际编码转换，未加 CAST
SELECT t1.threatclass as threatclass,
t1.threattype as threattype,
t1.threatsubtype as threatsubtype,
t1.producttype as producttype,
t1.url as ioc,
regexp_extract(t2.customer_info, 'city=(.*?)[,}]', 1) AS city,
regexp_extract(t2.customer_info, 'ip=(.*?)[,}]', 1) AS ip
FROM sodl.network_security_log t1
LEFT JOIN `default`.ods_devicemanager_deviceinfo t2 ON t1.deviceId = t2.dev_id
WHERE t1.reqruleid >='14000000'
AND t1.reqruleid < '14999999'
AND t1.titype = 2
AND t1.threatclass=209
AND t1.threattype NOT IN (9,
14,
15)
AND t1.producttype != 'NULL'
AND t1.deviceId != 'NULL'
AND t1.url != 'NULL'
AND t2.customer_info != 'NULL'
AND t1.insertdate = '2025-08-25'
AND hour(from_unixtime(t1.inserttimestamp)) = 1
LIMIT 1000;

-- @stmt 13 | dashboard-stats-job | DOMAIN_SECURITY_SQL
-- 表：sodl.network_security_log；`default`.ods_devicemanager_deviceinfo（均缺少新平台表名）
-- 来源：917 梳理 CSV 的 dashboard-stats-job（该任务不在 all.sql，无 all.sql 版本可对照）
-- DEC-016：t1.DAY = 20250825 与 t1.hour = 1 改为 insertdate = '2025-08-25' 与 hour(from_unixtime(t1.inserttimestamp)) = 1；日期是 CSV 里的固定值，不是调度参数
-- DEC-021：t1.manage 改为 t1.deviceId
-- default.ods_devicemanager_deviceinfo 缺少新平台表名，`default` 是 StarRocks 保留字，库名加反引号
-- DEC-009：reqruleid 的字符串比较、titype/threatclass/threattype 的数值比较需要按实际编码转换，未加 CAST
SELECT t1.threatclass as threatclass,
t1.threattype as threattype,
t1.threatsubtype as threatsubtype,
t1.producttype as producttype,
t1.url as ioc,
regexp_extract(t2.customer_info, 'city=(.*?)[,}]', 1) AS city,
regexp_extract(t2.customer_info, 'ip=(.*?)[,}]', 1) AS ip
FROM sodl.network_security_log t1
LEFT JOIN `default`.ods_devicemanager_deviceinfo t2 ON t1.deviceId = t2.dev_id
WHERE t1.reqruleid >='14000000'
AND t1.reqruleid < '14999999'
AND t1.titype = 0
AND t1.threatclass=209
AND t1.threattype NOT IN (9,
14,
15)
AND t1.producttype != 'NULL'
AND t1.deviceId != 'NULL'
AND t1.url != 'NULL'
AND t2.customer_info != 'NULL'
AND t1.insertdate = '2025-08-25'
AND hour(from_unixtime(t1.inserttimestamp)) = 1
LIMIT 1000;

-- @stmt 14 | dashboard-stats-job | URL_SECURITY_SQL
-- 表：sodl.network_security_log；`default`.ods_devicemanager_deviceinfo（均缺少新平台表名）
-- 来源：917 梳理 CSV 的 dashboard-stats-job（该任务不在 all.sql，无 all.sql 版本可对照）
-- DEC-016：t1.DAY = 20250825 与 t1.hour = 1 改为 insertdate = '2025-08-25' 与 hour(from_unixtime(t1.inserttimestamp)) = 1；日期是 CSV 里的固定值，不是调度参数
-- DEC-021：t1.manage 改为 t1.deviceId
-- default.ods_devicemanager_deviceinfo 缺少新平台表名，`default` 是 StarRocks 保留字，库名加反引号
-- DEC-009：reqruleid 的字符串比较、titype/threatclass/threattype 的数值比较需要按实际编码转换，未加 CAST
SELECT t1.threatclass as threatclass,
t1.threattype as threattype,
t1.threatsubtype as threatsubtype,
t1.producttype as producttype,
t1.url as ioc,
regexp_extract(t2.customer_info, 'city=(.*?)[,}]', 1) AS city,
regexp_extract(t2.customer_info, 'ip=(.*?)[,}]', 1) AS ip
FROM sodl.network_security_log t1
LEFT JOIN `default`.ods_devicemanager_deviceinfo t2 ON t1.deviceId = t2.dev_id
WHERE t1.reqruleid >='14000000'
AND t1.reqruleid < '14999999'
AND t1.titype = 1
AND t1.threatclass=214
AND t1.threattype NOT IN (2,
3)
AND t1.producttype != 'NULL'
AND t1.deviceId != 'NULL'
AND t1.dstip != 'NULL'
AND t1.url != 'NULL'
AND t2.customer_info != 'NULL'
AND t1.insertdate = '2025-08-25'
AND hour(from_unixtime(t1.inserttimestamp)) = 1
LIMIT 1000;

-- @stmt 15 | dashboard-stats-job | FILE_SECURITY_SQL
-- 表：sodl.endpoint_security_log；`default`.ods_devicemanager_deviceinfo（均缺少新平台表名）
-- 来源：917 梳理 CSV 的 dashboard-stats-job（该任务不在 all.sql，无 all.sql 版本可对照）
-- DEC-016：t1.DAY = 20250825 与 t1.hour = 1 改为 insertdate = '2025-08-25' 与 hour(from_unixtime(t1.inserttimestamp)) = 1；日期是 CSV 里的固定值，不是调度参数
-- DEC-021：t1.manage 改为 t1.deviceId
-- default.ods_devicemanager_deviceinfo 缺少新平台表名，`default` 是 StarRocks 保留字，库名加反引号
-- DEC-009：reqruleid 的字符串比较、titype/threatclass/threattype 的数值比较需要按实际编码转换，未加 CAST
SELECT t1.threatclass as threatclass,
t1.threattype as threattype,
t1.threatsubtype as threatsubtype,
t1.producttype as producttype,
t1.filemd5 as ioc,
regexp_extract(t2.customer_info, 'city=(.*?)[,}]', 1) AS city,
regexp_extract(t2.customer_info, 'ip=(.*?)[,}]', 1) AS ip
FROM sodl.endpoint_security_log t1
LEFT JOIN `default`.ods_devicemanager_deviceinfo t2 ON t1.deviceId = t2.dev_id
WHERE t1.threatclass=209
AND t1.threattype NOT IN (9,
14,
15)
AND t1.producttype != 'NULL'
AND t1.deviceId != 'NULL'
AND t1.filemd5 != 'NULL'
AND t1.filemd5 != ''
AND t2.customer_info != 'NULL'
AND t1.insertdate = '2025-08-25'
AND hour(from_unixtime(t1.inserttimestamp)) = 1
LIMIT 1000;

-- @stmt 16 | attack-ip-analysis-cronjob | 5b) WEAK_PASSWORD_SQL
-- 表：sodl.network_security_log（缺少新平台表名）
-- DEC-016 日期；方言：collect_set 改为 array_agg(DISTINCT ...)，regexp_extract 两参数补组号 1
-- 该语句不读 default.ods_custom_upload_data，所以不受其未同步影响
-- DEC-009：threatclass、threattype 经 cast 后比较，无需额外处理
select
  'weak_password_log' as log_type,
  srcip as ip,
  count(distinct pwd) as pwd_num,
  array_agg(DISTINCT pwd) as pwd_list
from
(
  SELECT
    srcip,
    regexp_extract(requesthead, '(pwd|password)=([^&; ]+)', 2) as pwd
  FROM sodl.network_security_log
  WHERE insertdate = '2026-10-01'
    AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
    AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
    AND concat_ws('-',cast(threatclass as String),
                        cast(threattype as String)) in ('94-4')
    and regexp_extract(requesthead, '(pwd|password)=([^&; ]+)', 2) != ''
  union
  SELECT
    srcip,
    regexp_extract(requestbody, '(pwd|password)=([^&; ]+)', 2)  as pwd
  FROM sodl.network_security_log
  WHERE insertdate = '2026-10-01'
    AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
    AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
    AND concat_ws('-',cast(threatclass as String),
                        cast(threattype as String)) in ('94-4')
    and regexp_extract(requestbody, '(pwd|password)=([^&; ]+)', 2) != ''
)a
group by srcip;

-- @stmt 17 | attack-ip-analysis-cronjob | 6) WIKI_RELATED_SQL
-- 表：sodl.network_security_log（缺少新平台表名）
-- DEC-016：day=20261001 改为 insertdate = '2026-10-01'；输出列 day 写成 insertdate AS day
-- DEC-021：manage 改为 deviceId AS device_id
-- 推断：DEC-020 只规定 sum(log_num) 改 count(1)；这里是逐行输出 log_num AS attack_count，没有聚合，暂写成 1 AS attack_count，需用户确认
-- 该语句不读 default.ods_custom_upload_data，所以不受其未同步影响
-- DEC-009：length(requesthead) + length(requestbody) > 10 为数值比较，不涉及 VARCHAR 字段比较
SELECT
    'network_security_log' as table_name,
    concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
    1 AS attack_count,
    deviceId AS device_id,
    reqruleid as sid,
    srcip,
    requesthead,
    requestbody,
    insertdate AS day
FROM sodl.network_security_log
WHERE insertdate = '2026-10-01'
AND (length(requesthead) + length(requestbody)) > 10
AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
AND (requesthead != '' OR requestbody != '')
AND (regexp_extract(requesthead, '[^a-zA-Z](wget|curl|downloadfile|downloadstring|powershell|certutil|bitsadmin|mshta|ncat|msiexec|msxsl|rundll32|regsvr32|tftp|ipc$|pubprn.vbs|wmiexec|psexec|ftp:|jndi:|ldap:|rmi:)[^a-zA-Z0-9)_;,|]', 1) != ''
    OR
    regexp_extract(requestbody, '[^a-zA-Z](wget|curl|downloadfile|downloadstring|powershell|certutil|bitsadmin|mshta|ncat|msiexec|msxsl|rundll32|regsvr32|tftp|ipc$|pubprn.vbs|wmiexec|psexec|ftp:|jndi:|ldap:|rmi:)[^a-zA-Z0-9)_;,|]', 1) != '');
