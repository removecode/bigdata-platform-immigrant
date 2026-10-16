-- 旧平台 SQL 转 StarRocks 草稿
-- 来源：/workspace/all.sql
-- 当次没有给出新平台库表名。下面每张表都保留原名，并标明「缺少新平台表名」。
-- 这不是生产语句，也没有在生产 StarRocks 执行。
-- DEC-009：目标字段按 VARCHAR 落地。本次没有字段实际编码，数值比较、聚合和时间范围只标出位置，不猜 CAST。
-- 本机实验表仍是 ACT-034 的 INT/BIGINT/VARCHAR，所以下面语句按实验库物理类型执行。
--
-- 本机占位符（来自 all.sql 注释和 lab/build_bulk_data.py，不是生产参数）：
--   {AGO_OID} = 69cdb1800000000000000000
--   {DAYS} = 实验库已有分区，不是 2021-12 至 2026-12 的全部周三：20260819, 20260826, 20260902, 20260909, 20260916, 20260923, 20260925, 20260926, 20260927, 20260928, 20260929, 20260930, 20261001
--   {LAST_HOUR}/{NOW_HOUR} = 2026100200 / 2026100201（handle_info_log 的 inserttimestamp 都落在这一小时）
--   {TENANT_IDS} = 'tenantA','tenantB','tenantC'
--   {START_TIME}/{END_TIME} = 20260915 / 20261001
--   {LAST_TS}/{END_TS} = 1790901000 / 1790901600
--   {RUN_TIME_MS} = 1790901600000
--   {SKYEYE_UPDATE_MS} = 1759365600000
--   ${day}/${hour} = 20261001 / 0
--
-- 旧表到新表对照
--   csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync    缺少新平台表名
--   default.log_audit_source    缺少新平台表名
--   sodl.dwb_sodl_domain_info    缺少新平台表名
--   sri.ods_sri_hashinfo    缺少新平台表名
--   csc.ods_csc_business_data    缺少新平台表名
--   csc.ods_csc_ioc_vertex    缺少新平台表名
--   sodl.handle_info_log    缺少新平台表名
--   default.dwb_domain_info    缺少新平台表名
--   default.ods_custom_upload_data    缺少新平台表名
--   default.dwb_md5_info    缺少新平台表名
--   sodl.dwb_sodl_md5_info    缺少新平台表名
--   sodl.network_security_log    缺少新平台表名
--   csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync    缺少新平台表名
--   sodl.dwb_sodl_ip_info    缺少新平台表名
--   business.ti_domain_reputation_info    缺少新平台表名
--   business.ti_ip_reputation_info    缺少新平台表名
--   business.tb_tenant_subscribe_info    缺少新平台表名
--   business.ti_network_security_log    缺少新平台表名
--   sodl.operation_rdp_event_log    缺少新平台表名
--   sodl.dns_log    缺少新平台表名
--   sodl.url_log    缺少新平台表名
--   csc.ods_csc_log_stats    缺少新平台表名
--   csc.ods_csc_tim_db_unknown_intelligence_tb_skyeye_ip_info_sync    缺少新平台表名
--   sodl.sip_iocstat_log    缺少新平台表名

-- 语句 1
-- 应用：filter-layout-ip-seg-stat-prc  (CIPD/IP)
-- 方言：LATERAL VIEW explode 改为 unnest；Hive 数组下标从 0 起，StarRocks 从 1 起；正则字面量的反斜杠按 StarRocks 字符串转义加倍；rlike 改为 REGEXP；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync（缺少新平台表名），default.log_audit_source（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：>= 5
WITH rpt AS (
  SELECT DISTINCT regexp_extract(ip, '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_seg
  FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
  WHERE direction='2' AND reputation='0'
),
resp_data AS (
  SELECT DAY AS date_day,
         split(get_json_object(resp, '$.ip'), ':')[1] AS ip,
         regexp_extract(split(get_json_object(resp, '$.ip'), ':')[1], '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_c_seg
  FROM `default`.log_audit_source , unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~\\]', ''), '\\}\\,\\{', '\;\{'),'\"','"'), ';')) AS exploded_table(resp)
  WHERE log_app_id='ip-proxy-svc' AND DAY BETWEEN 20260925 AND 20261001
    AND module_id='ip-proxy-svc' AND str5 REGEXP 'cf'
    AND get_json_object(resp, '$.threat.reputation')='2'
    AND get_json_object(resp, '$.threat.direction')='2'
),
agg_data AS (
  SELECT ip_c_seg,
         count(DISTINCT date_day) AS day_unique,
         count(DISTINCT ip) AS ip_unique,
         count(*)/(count(DISTINCT date_day)+1) AS total
  FROM resp_data
  GROUP BY ip_c_seg
)
SELECT ip_c_seg, day_unique, ip_unique, total
FROM agg_data
WHERE day_unique >= 5
  AND NOT EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg);

-- 语句 2
-- 应用：domain-heat-stats-cron-job  (CIPD/BDPD)
-- 分段：second_level_domain.sql
-- 方言：== 改为 =；rlike 改为 REGEXP
-- 表：sodl.dwb_sodl_domain_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(log_num)；DAY =；=20260930；= 0；>10
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_num
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =20260930
     AND DOMAIN != ''
     AND locate(':',DOMAIN) = 0
     AND locate('_',DOMAIN) = 0
     AND locate('*',DOMAIN) = 0
     AND DOMAIN NOT REGEXP '[0-9]$'
     AND DOMAIN NOT REGEXP '.arpa$'
   GROUP BY DOMAIN,
            MANAGE),
     t2 AS
  (SELECT SUBSTRING_INDEX(DOMAIN,'.',-2) AS sld,
          sum(log_num) AS log_sum,
          count(DISTINCT MANAGE) AS dev_cnt
   FROM t
   GROUP BY SUBSTRING_INDEX(DOMAIN,'.',-2))
SELECT sld AS domain,
       log_sum AS log_cnt,
       dev_cnt
FROM t2
where log_sum >10;

-- 语句 3
-- 应用：domain-heat-stats-cron-job  (CIPD/BDPD)
-- 分段：third_level_domain.sql
-- 方言：
-- 表：sodl.dwb_sodl_domain_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(log_num)；DAY =；=20260930；>10
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_num
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =20260930
   AND SUBSTRING_INDEX(DOMAIN,'.',-2) in ('com.cn','org.cn')
   GROUP BY DOMAIN,
            MANAGE),
     t2 AS
  (SELECT SUBSTRING_INDEX(DOMAIN,'.',-3) AS parent_domain,
          sum(log_num) AS log_sum,
          count(DISTINCT MANAGE) AS dev_cnt
   FROM t
   GROUP BY SUBSTRING_INDEX(DOMAIN,'.',-3))
SELECT parent_domain AS domain,
       log_sum AS log_cnt,
       dev_cnt
FROM t2
where log_sum >10;

-- 语句 4
-- 应用：domain-heat-stats-cron-job  (CIPD/BDPD)
-- 分段：cloud_domain.sql
-- 方言：
-- 表：sodl.dwb_sodl_domain_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(log_num)；sum(log_sum)；DAY =；=20260930
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_sum
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =20260930
   AND SUBSTRING_INDEX(DOMAIN,'.',-2) in ('amazonaws.com','myqcloud.com','aliyuncs.com','myhuaweicloud.com','vercel.app','netlify.app','glitch.me','edgeone.app')
   GROUP BY DOMAIN,
            MANAGE)
SELECT domain,
        sum(log_sum) AS log_cnt,
        count(DISTINCT MANAGE) AS dev_cnt
FROM t
GROUP BY domain;

-- 语句 5
-- 应用：cert-app-samplesync-country-job  (datareport)
-- 方言：占位符 {AGO_OID} 用本机实验值填入
-- 表：sri.ods_sri_hashinfo（缺少新平台表名），csc.ods_csc_business_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：file_size != «S0005» AND CAST (file_size AS INT) <；< 1048576
SELECT virus_name, file_md5 FROM sri.ods_sri_hashinfo
WHERE virus_name regexp '^Trojan|^Backdoor|^Worm|^Virus|^Rootkit|^Bootkit|^Exploit|^Hacktool|^PUP|^Riskware|^Adware|^Suspicious|^Spyware|^Ransom|^Rogue|^CoinMiner|^Infostealer'
AND oid > '69cdb1800000000000000000'
AND file_attr in (0, 2)
AND platform IN ('Android', 'AndroidOS')
AND fdfs_path != ''
AND file_size != '0' AND CAST (file_size AS INT) < 1048576
AND file_md5 NOT IN (SELECT str1 FROM csc.ods_csc_business_data)
ORDER BY file_attr ASC, oid DESC
LIMIT 2000;

-- 语句 6
-- 应用：cert-app-samplesync-job  (datareport)
-- 方言：占位符 {AGO_OID} 用本机实验值填入
-- 表：sri.ods_sri_hashinfo（缺少新平台表名），csc.ods_csc_business_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：file_size != «S0005» AND CAST (file_size AS INT) <；< 1048576
SELECT virus_name, file_md5 FROM sri.ods_sri_hashinfo
WHERE virus_name regexp '^Trojan|^Backdoor|^Worm|^Virus|^Rootkit|^Bootkit|^Exploit|^Hacktool|^PUP|^Riskware|^Adware|^Suspicious|^Spyware|^Ransom|^Rogue|^CoinMiner|^Infostealer'
AND oid > '69cdb1800000000000000000'
AND file_attr in (0, 2)
AND platform IN ('Android', 'AndroidOS')
AND fdfs_path != ''
AND file_size != '0' AND CAST (file_size AS INT) < 1048576
AND file_md5 NOT IN (SELECT str1 FROM csc.ods_csc_business_data)
ORDER BY file_attr ASC, oid DESC
LIMIT 4100;

-- 语句 7
-- 应用：ati-pdns-cache-job  (ATI)
-- 方言：占位符 {DAYS} 用本机实验值填入；key 是保留字，标识符加反引号
-- 表：csc.ods_csc_ioc_vertex（缺少新平台表名）
-- 字段编码未给出：本句没有扫到数字比较或数值聚合
SELECT `key` AS domain FROM csc.ods_csc_ioc_vertex WHERE graph_type='Domain' AND day in (20260819, 20260826, 20260902, 20260909, 20260916, 20260923, 20260925, 20260926, 20260927, 20260928, 20260929, 20260930, 20261001) AND data_source NOT IN ('pdns','ngaf_dns','sip_dns') GROUP BY `key`;

-- 语句 8
-- 应用：ti-hot-data-detection-fusing-prc  (FCC)
-- 方言：占位符 {LAST_HOUR} 用本机实验值填入；占位符 {NOW_HOUR} 用本机实验值填入；ClickHouse formatDateTime/toDateTime 改为 date_format(from_unixtime(...))
-- 表：sodl.handle_info_log（缺少新平台表名）
-- 字段编码未给出：本句没有扫到数字比较或数值聚合
SELECT fileMd5, deviceId, virusName FROM sodl.handle_info_log WHERE date_format(from_unixtime(insertTimestamp), '%Y%m%d%H') >= '2026100200' AND date_format(from_unixtime(insertTimestamp), '%Y%m%d%H') < '2026100201' AND engineInfo LIKE '%IsHotspot%' AND detectEngine = '4';

-- 语句 9
-- 应用：domain-hit-devnum-cronjob  (ATI / IOC-PRODUCT)
-- 方言：`default` 在 StarRocks 是保留字，库名加反引号
-- 表：default.dwb_domain_info（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：DAY>=20260902 and DAY<=；>=20260902；<=20261002；> 10
SELECT DOMAIN,devnum,total_times FROM (SELECT DOMAIN,COUNT(DISTINCT devid) AS devnum,COUNT(devid) as total_times FROM `default`.dwb_domain_info WHERE DAY>=20260902 and DAY<=20261002 AND devid NOT IN (SELECT str1 AS dev FROM `default`.ods_custom_upload_data WHERE part1='test_dev' AND part2='test_devid') GROUP BY DOMAIN) subquery WHERE devnum > 10 LIMIT 15000000;

-- 语句 10
-- 应用：black-file-clean-cronjob  (FCC)
-- 方言：`default` 在 StarRocks 是保留字，库名加反引号
-- 表：default.dwb_md5_info（缺少新平台表名），sodl.dwb_sodl_md5_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；threatclass=；threattype!=；file_attr=；=20261001；=32；=209；!=13
SELECT DISTINCT lower(md5)
FROM `default`.dwb_md5_info
WHERE day=20261001
  AND src_log='log_audit'
  AND attr='0'
  AND length(md5)=32
UNION
SELECT DISTINCT lower(filehash)
FROM sodl.dwb_sodl_md5_info
WHERE day=20261001
  AND producttype='EDR'
  AND src_log='endpoint_security_log'
  AND threatclass=209
  AND threattype!=13 
  AND file_attr='0'
  AND length(filehash)=32;

-- 语句 11
-- 应用：ip-security-log-etl-prc  (CIPD/IP/C2IP-TMP)
-- 方言：regexp_extract 两参数补上组号 1，对应第一个捕获组
-- 表：sodl.network_security_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：DAY=；severity >；threatsubtype as String)) =；=20261001；> 50
select
    distinct dstip
from sodl.network_security_log
where DAY=20261001
    AND regexp_extract(dstip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
    AND regexp_extract(dstip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
    AND engine not in ('premise_ioc', 'cloud_ioc', 'sase_ioc')
    AND severity > 50
    AND (threatclass in (209, 208, 216, 214,  203, 40)
        or concat_ws('-',cast(threatclass as String),
                        cast(threattype as String),
                        cast(threatsubtype as String)) = '212-10-0')
limit 100000;

-- 语句 12
-- 应用：active-domain-elt-job  (CIPD/DOMAIN/PRE)
-- 分段：INFO_EXIST_CHECK_SQL
-- 方言：`default` 在 StarRocks 是保留字，库名加反引号
-- 表：default.dwb_domain_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；=20261001
SELECT 1 FROM `default`.dwb_domain_info WHERE day=20261001 LIMIT 1;

-- 语句 13
-- 应用：active-domain-elt-job  (CIPD/DOMAIN/PRE)
-- 分段：INFO_EXIST_CHECK_SQL
-- 方言：方言无需改写
-- 表：sodl.dwb_sodl_domain_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；=20261001
SELECT 1 FROM sodl.dwb_sodl_domain_info WHERE day=20261001 LIMIT 1;

-- 语句 14
-- 应用：active-domain-elt-job  (CIPD/DOMAIN/PRE)
-- 分段：ACTIVE_DOMAIN_SQL
-- 方言：`default` 在 StarRocks 是保留字，库名加反引号
-- 表：csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名），sodl.dwb_sodl_domain_info（缺少新平台表名），default.dwb_domain_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：deleted_time=；day=；=0；=20261001
WITH black_dns AS (
SELECT domain,
       regexp_extract(labels, 'category=([^,]+)', 1) AS category,
       regexp_extract(labels, 'family=([^,]+)', 1) AS family,
       regexp_extract(label_details, 'source=([^,]+)', 1) AS source,
       regexp_extract(label_details, 'rule=([^,]+)', 1) AS rule,
       add_time AS addtime
FROM csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync
WHERE deleted_time=0
  AND reputation='0'),
     test_dev AS (
SELECT str1 AS dev1
FROM `default`.ods_custom_upload_data
WHERE part1='test_dev'
  AND part2='test_devid')

SELECT blackdns,
       addtime,
       category,
       family,
       source,
       rule,
       count(DISTINCT dev) AS devcn
FROM
  (SELECT a.row_key AS blackdns,
          b.addtime,
          b.category,
          b.family,
          b.source,
          b.rule,
          a.manage AS dev
   FROM sodl.dwb_sodl_domain_info a
   JOIN black_dns b ON (a.row_key=b.domain)
   WHERE a.day=20261001
     AND a.row_key IS NOT NULL
     AND a.manage NOT IN
       (SELECT *
        FROM test_dev)

   UNION ALL

   SELECT a.row_key AS blackdns,
          b.addtime,
          b.category,
          b.family,
          b.source,
          b.rule,
          a.devid AS dev
   FROM `default`.dwb_domain_info a
   JOIN black_dns b ON (a.row_key=b.domain)
   WHERE a.day=20261001
     AND a.row_key IS NOT NULL
     AND a.devid NOT IN
       (SELECT *
        FROM test_dev) )t
GROUP BY blackdns,
         addtime,
         category,
         family,
         source,
         rule;

-- 语句 15
-- 应用：domain-security-log-etl-prc  (CIPD/DOMAIN/PRE)
-- 分段：INFO_EXIST_CHECK_SQL
-- 方言：方言无需改写
-- 表：sodl.network_security_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；=20261001
SELECT 1 FROM sodl.network_security_log WHERE day=20261001 LIMIT 1;

-- 语句 16
-- 应用：domain-security-log-etl-prc  (CIPD/DOMAIN/PRE)
-- 分段：DOMAIN_SECURITY_LOG_EXTRACT_SQL
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set；sort_array 改为 array_sort；rlike 改为 REGEXP；REGEXP 模式中的反斜杠按 StarRocks 字符串转义加倍
-- 表：sodl.network_security_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：DAY=；severity >；threatsubtype AS STRING)) =；action =；=20261001；> 50；= 2
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
   WHERE DAY=20261001
     AND engine NOT IN ('premise_ioc', 'cloud_ioc', 'sase_ioc')
     AND severity > 50
     AND (threatclass IN (209, 208, 216, 214, 203, 40)
          OR CONCAT(CAST(threatclass AS STRING), '-', CAST(threattype AS STRING), '-',
          CAST(threatsubtype AS STRING)) = '212-10-0')
     AND action = 2) s
WHERE NOT (DOMAIN REGEXP '\\d+\\.\\d+\\.\\d+\\.\\d+$' OR DOMAIN REGEXP ':')
GROUP BY DOMAIN;

-- 语句 17
-- 应用：black-ti-context-produce-prc  (TIBAE)
-- 分段：INFO_EXIST_CHECK_SQL
-- 方言：方言无需改写
-- 表：sodl.dwb_sodl_domain_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；=20261001
SELECT 1 FROM sodl.dwb_sodl_domain_info WHERE day=20261001 LIMIT 1;

-- 语句 18
-- 应用：black-ti-context-produce-prc  (TIBAE)
-- 分段：INFO_EXIST_CHECK_SQL
-- 方言：方言无需改写
-- 表：sodl.dwb_sodl_ip_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；=20261001
SELECT 1 FROM sodl.dwb_sodl_ip_info WHERE day=20261001 LIMIT 1;

-- 语句 19
-- 应用：black-ti-context-produce-prc  (TIBAE)
-- 分段：C2_IP_ACTIVE_STAT_SQL
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set；regexp_extract 两参数补上组号 1，对应第一个捕获组
-- 表：csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync（缺少新平台表名），sodl.dwb_sodl_ip_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(attack_count)；SUM(attack_count)；SUM(ris.attack_count)；port=；DAY=；=0；=20261001
WITH reputation_ip_stat AS
  (SELECT
      ip,
      port,
      direction,
      expire_time,
      deleted_time,
      attack_count,
      devid,
      '其他' as industry,
      '其他' as country,
      '其他' as province,
      src_log
   FROM
   (
    SELECT
        ip,
        port,
        direction,
        expire_time,
        deleted_time
    FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
    WHERE direction='2'
        AND port=0
    ) black_reputation_ip
   JOIN
     (SELECT sum(attack_count) as attack_count,
             MANAGE AS devid,
             COALESCE(CAST(threatclass AS STRING), '0') AS src_log,
             dstip AS dip
      FROM sodl.dwb_sodl_ip_info
      WHERE DAY=20261001
        and src_log in ('sip_iocstat_log', 'network_security_log')
        and dstip !=''
        and dstip not in ('8.8.8.8', '8.8.4.4','114.114.114.114', '114.114.115.115', '119.29.29.29', '223.5.5.5', '223.6.6.6', '1.1.1.1', '1.0.0.1')
        and regexp_extract(dstip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
        and regexp_extract(dstip, '^(0\\.|127\\.|10\\.|172\\.1[6-9]\\.|172\\.2[0-9]\\.|172\\.3[01]\\.|192\\.168\\.|169\\.254\\.|192\\.0\\.0\\.|192\\.88\\.99\\.|198\\.18\\.|198\\.19\\.|198\\.51\\.100\\.|203\\.0\\.113\\.|224\\.|240\\.|255\\.)', 1) = ''
      group by dstip, MANAGE, threatclass
        ) b ON black_reputation_ip.ip=b.dip
),
industry_stats AS (
  SELECT ip, industry, SUM(attack_count) AS industry_attack_count
  FROM reputation_ip_stat GROUP BY ip, industry
),
region_stats AS (
  SELECT ip, country, province, SUM(attack_count) AS region_attack_count
  FROM reputation_ip_stat GROUP BY ip, country, province
),
log_stats AS (
  SELECT ip, src_log, SUM(attack_count) AS log_attack_count
  FROM reputation_ip_stat GROUP BY ip, src_log
)
SELECT
    ris.ip,
    ris.port,
    ris.direction,
    ris.expire_time,
    ris.deleted_time,
    SUM(ris.attack_count) AS attack_count,
    array_agg(DISTINCT CONCAT(ris.devid)) AS devids,
    array_agg(DISTINCT CONCAT(ris.industry, '@', ins.industry_attack_count)) AS industry_count,
    array_agg(DISTINCT CONCAT(ris.country, '@', ris.province, '@', rs.region_attack_count)) AS region_count,
    array_agg(DISTINCT CONCAT(ris.src_log, '@', ls.log_attack_count)) AS src_log_count
FROM
    reputation_ip_stat ris
JOIN industry_stats ins ON ris.ip=ins.ip AND ris.industry=ins.industry
JOIN region_stats rs ON ris.ip=rs.ip AND ris.country=rs.country AND ris.province=rs.province
JOIN log_stats ls ON ris.ip=ls.ip AND ris.src_log=ls.src_log
GROUP BY ris.ip,
         ris.port,
         ris.direction,
         ris.expire_time,
         ris.deleted_time;

-- 语句 20
-- 应用：black-ti-context-produce-prc  (TIBAE)
-- 分段：ATTACK_IP_ACTIVE_STAT_SQL
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set
-- 表：csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync（缺少新平台表名），sodl.dwb_sodl_ip_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：SUM(attack_count)；port=；DAY=；=0；= 0；=20261001
WITH black_reputation_ip AS (
    SELECT
        ip,
        port,
        direction,
        expire_time,
        deleted_time
    FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
    WHERE direction='1'
        AND port=0
),
reputation_ip_stat AS
  (SELECT ip,
          port,
          direction,
          expire_time,
          deleted_time,
          attack_count,
          devid,
          industry,
          country,
          province,
          src_log
   FROM
     black_reputation_ip
   JOIN
     (SELECT attack_count,
             MANAGE AS devid,
             CASE
                 WHEN industry IS NULL
                      OR length(industry) = 0 THEN '其他'
                 ELSE industry
             END AS industry,
             CASE
                 WHEN country IS NULL
                      OR length(country) = 0 THEN '其他'
                 ELSE country
             END AS country,
             CASE
                 WHEN province IS NULL
                      OR length(province) = 0 THEN '其他'
                 ELSE province
             END AS province,
             COALESCE(CAST(threatclass AS STRING), '0') AS src_log,
             srcip AS sip
      FROM sodl.dwb_sodl_ip_info
      WHERE DAY=20261001
        ) b ON black_reputation_ip.ip=b.sip
   )
SELECT ip,
       port,
       direction,
       expire_time,
       deleted_time,
       attack_count,
       devids,
       industry_count,
       region_count,
       src_log_count
FROM
    (SELECT ip,
            port,
            direction,
            expire_time,
            deleted_time,
            SUM(attack_count) AS attack_count,
            array_agg(DISTINCT CONCAT(devid)) AS devids,
            array_agg(DISTINCT CONCAT(industry, '@', industry_attack_count)) AS industry_count,
            array_agg(DISTINCT CONCAT(country, '@', province, '@', region_attack_count)) AS region_count,
            array_agg(DISTINCT CONCAT(src_log, '@', log_attack_count)) AS src_log_count
     FROM
       (SELECT ip,
               port,
               direction,
               expire_time,
               deleted_time,
               attack_count,
               devid,
               industry,
               country,
               province,
               src_log,
               SUM(attack_count) OVER (PARTITION BY ip, industry) AS industry_attack_count,
               SUM(attack_count) OVER (PARTITION BY ip, country, province) AS region_attack_count,
               SUM(attack_count) OVER (PARTITION BY ip, src_log) AS log_attack_count
        FROM reputation_ip_stat) t
     GROUP BY ip,
              port,
              direction,
              expire_time,
              deleted_time) b;

-- 语句 21
-- 应用：black-ti-context-produce-prc  (TIBAE)
-- 分段：DOMAIN_ACTIVE_STAT_SQL
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set
-- 表：csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync（缺少新平台表名），sodl.dwb_sodl_domain_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(attack_count)；SUM(attack_count)；SUM(ds.attack_count)；DAY=；=20261001
WITH domain_stat AS
(SELECT black_reputation_domain.domain,
      black_reputation_domain.deleted_time,
      attack_count,
      devid,
      '其他' as industry,
      '其他' as country,
      '其他' as province,
      src_log
FROM
 (
    SELECT domain, deleted_time
      FROM csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync
      where reputation = '0'
 ) black_reputation_domain
JOIN
 (SELECT sum(attack_count) as attack_count,
         MANAGE AS devid,
         COALESCE(CAST(threatclass AS STRING), '0') AS src_log,
         domain
  FROM sodl.dwb_sodl_domain_info
      WHERE DAY=20261001
      and row_key!=''
  group by domain, MANAGE, threatclass
      ) b ON black_reputation_domain.domain=b.domain
),
industry_stats AS (
  SELECT domain, industry, SUM(attack_count) AS industry_attack_count
  FROM domain_stat GROUP BY domain, industry
),
region_stats AS (
  SELECT domain, country, province, SUM(attack_count) AS region_attack_count
  FROM domain_stat GROUP BY domain, country, province
),
log_stats AS (
  SELECT domain, src_log, SUM(attack_count) AS log_attack_count
  FROM domain_stat GROUP BY domain, src_log
)
SELECT ds.domain,
       ds.deleted_time,
       SUM(ds.attack_count) AS attack_count,
       array_agg(DISTINCT CONCAT(ds.devid)) AS devids,
       array_agg(DISTINCT CONCAT(ds.industry, '@', ins.industry_attack_count)) AS industry_count,
       array_agg(DISTINCT CONCAT(ds.country, '@', ds.province, '@', rs.region_attack_count)) AS region_count,
       array_agg(DISTINCT CONCAT(ds.src_log, '@', ls.log_attack_count)) AS src_log_count
FROM
    domain_stat ds
JOIN industry_stats ins ON ds.domain=ins.domain AND ds.industry=ins.industry
JOIN region_stats rs ON ds.domain=rs.domain AND ds.country=rs.country AND ds.province=rs.province
JOIN log_stats ls ON ds.domain=ls.domain AND ds.src_log=ls.src_log
GROUP BY ds.domain, ds.deleted_time;

-- 语句 22
-- 应用：black-ti-context-produce-prc  (TIBAE)
-- 分段：MD5_ACTIVE_STAT_SQL
-- 方言：collect_list 改为 array_agg；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：sodl.dwb_sodl_md5_info（缺少新平台表名），default.dwb_md5_info（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(attack_count)；file_attr=；DAY=；=20261001；= 0
WITH md5_stat AS
  (SELECT filehash AS md5,
          manage AS devid,
                    attack_count,
                    industry,
                    country,
                    province
   FROM sodl.dwb_sodl_md5_info
   WHERE src_log='endpoint_security_log'
     AND file_attr='0'
     AND DAY=20261001
   UNION ALL SELECT md5,
                    devid,
                    attack_count,
                    industry,
                    country,
                    province
   FROM `default`.dwb_md5_info
   WHERE src_log='log_audit'
     AND SOURCE='file_hash'
     AND attr='0'
     AND DAY=20261001)
SELECT base_stat.md5,
       base_stat.attack_count,
       base_stat.devids,
       industry_count,
       region_count
FROM
  (SELECT md5,
          sum(attack_count) AS attack_count,
          array_agg(concat(devid)) AS devids
   FROM md5_stat
   GROUP BY md5) base_stat
JOIN
  (SELECT md5,
          array_agg(concat(industry, '@', attack_count)) AS industry_count
   FROM
     (SELECT md5,
             CASE
                 WHEN industry IS NULL
                      OR length(industry) = 0 THEN '其他'
                 ELSE industry
             END AS industry,
             sum(attack_count) AS attack_count
      FROM md5_stat
      GROUP BY md5,
               industry) industry_temp
   GROUP BY md5) industry_stat ON base_stat.md5 = industry_stat.md5
JOIN
  (SELECT md5,
          array_agg(concat(country, '@', province, '@', attack_count)) AS region_count
   FROM
     (SELECT md5,
             CASE
                 WHEN country IS NULL
                      OR length(country) = 0 THEN '其他'
                 ELSE country
             END AS country,
             CASE
                 WHEN province IS NULL
                      OR length(province) = 0 THEN '其他'
                 ELSE province
             END AS province,
             sum(attack_count) AS attack_count
      FROM md5_stat
      GROUP BY md5,
               country,
               province) region_temp
   GROUP BY md5) region_stat ON base_stat.md5 = region_stat.md5;

-- 语句 23
-- 应用：ctig-report-data-analysis-prc  (CIPD/BDPD)
-- 方言：占位符 {TENANT_IDS} 用本机实验值填入；占位符 {START_TIME} 用本机实验值填入；占位符 {END_TIME} 用本机实验值填入
-- 表：business.ti_domain_reputation_info（缺少新平台表名），business.ti_ip_reputation_info（缺少新平台表名），business.tb_tenant_subscribe_info（缺少新平台表名），business.ti_network_security_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：SUM(alarmCount)；deleted_time =；port = 0 AND deleted_time =；= 0
WITH black_domain AS (
    SELECT
        domain AS ioc,
        concat_ws(',',
                  regexp_extract(CAST(labels AS STRING), '"category": "([a-zA-Z0-9_]+)"', 1),
                  regexp_extract(CAST(labels AS STRING), '"family": "([a-zA-Z0-9_]+)"', 1)
        ) AS label,
        threat_level,
        add_time
    FROM business.ti_domain_reputation_info
    WHERE reputation = '0' AND deleted_time = 0
),
black_ip AS (
    SELECT
        ip AS ioc,
        concat_ws(',',
                regexp_extract(CAST(labels AS STRING), '"category": "([a-zA-Z0-9_]+)"', 1),
                regexp_extract(CAST(labels AS STRING), '"family": "([a-zA-Z0-9_]+)"', 1)
        ) AS label,
        threat_level,
        add_time
    FROM business.ti_ip_reputation_info
    WHERE reputation = '0' AND direction = '2' AND port = 0 AND deleted_time = 0
),
black_list AS (
    SELECT 'domain' AS ioc_type, ioc, label, threat_level, add_time FROM black_domain
    UNION ALL
    SELECT 'ip' AS ioc_type, ioc, label, threat_level, add_time FROM black_ip
),
tenant_device AS (
    SELECT DISTINCT tenant_id, device_id
    FROM business.tb_tenant_subscribe_info
    WHERE tenant_id IN ('tenantA', 'tenantB', 'tenantC')
),
log_base AS (
    SELECT
        t.tenant_id,
        t.device_id,
        log.alarmDate AS day,
        log.srcIp AS srcip,
        log.intelligence AS ioc,
        log.alarmCount,
        bl.label,
        bl.threat_level,
        bl.add_time
    FROM business.ti_network_security_log log
            INNER JOIN tenant_device t ON log.manage = t.device_id
            INNER JOIN black_list bl ON log.intelligence = bl.ioc
    WHERE log.alarmDate BETWEEN '20260915' AND '20261001'
),
day_stat AS (
    SELECT tenant_id, day, SUM(alarmCount) AS log_num
    FROM log_base
    GROUP BY tenant_id, day
),
log_stat AS (
    SELECT
        tenant_id, srcip, device_id, ioc,
        SUM(alarmCount) AS log_num,
        add_time, label, threat_level
    FROM log_base
    GROUP BY tenant_id, srcip, device_id, ioc, add_time, label, threat_level
)
SELECT
    t1.tenant_id,
    t2.log_stat_arr,
    t1.day_stat_arr
FROM (
         SELECT tenant_id, ARRAY_AGG(concat_ws('|', CAST(day AS STRING), CAST(log_num AS STRING))) AS day_stat_arr
         FROM day_stat
         GROUP BY tenant_id
     ) t1
         JOIN (
    SELECT tenant_id,
           ARRAY_AGG(concat_ws('|', srcip, device_id, ioc, CAST(log_num AS STRING),
                               CAST(add_time AS STRING), label, threat_level)) AS log_stat_arr
    FROM log_stat
    GROUP BY tenant_id
) t2 ON t1.tenant_id = t2.tenant_id;

-- 语句 24
-- 应用：ti-ip-detection-send-prc  (CIPD/IP)   [Go app]
-- 方言：占位符 {LAST_TS} 用本机实验值填入；占位符 {END_TS} 用本机实验值填入；ClickHouse splitByChar/JSONExtractString 改为 split/get_json_string；ClickHouse ARRAY JOIN 改为 unnest(parse_json(...))；Hive 数组下标从 0 起，StarRocks 从 1 起
-- 表：sodl.operation_rdp_event_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：insertTimestamp >= 1790901000 AND insertTimestamp <；>= 1790901000；< 1790901600
SELECT DISTINCT
    split(get_json_string(element, '$.ip'), ':')[2] AS ip_address,
    split(get_json_string(element, '$.ip'), ':')[3] AS port,
    insertTimestamp
FROM
    sodl.operation_rdp_event_log
, unnest(ifnull(cast(parse_json(businessContent) AS ARRAY<JSON>), [])) AS element_tbl(element)
WHERE
    businessType = '21'
    AND insertTimestamp >= 1790901000 AND insertTimestamp < 1790901600 limit 2000000;

-- 语句 25
-- 应用：top-visit-host-produce-job  (CIPD/BDPD)  -- 3 jobs: domain / ip / url
-- 分段：DNS_LOG_STAT_SQL
-- 方言：方言无需改写
-- 表：sodl.dns_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(log_num)；day =；qr=；= 20261001；=0；> 3；!= 0
SELECT queries as domain,
       sum(log_num) AS num
FROM sodl.dns_log
WHERE day = 20261001
  AND producttype in ('AF', 'NGAF', 'VNGAF')
  AND qr=0
  AND length(queries) > 3
  AND locate('.', queries) != 0
GROUP BY queries;

-- 语句 26
-- 应用：top-visit-host-produce-job  (CIPD/BDPD)  -- 3 jobs: domain / ip / url
-- 分段：IP_LOG_STAT_SQL
-- 方言：LATERAL VIEW explode 改为 unnest；Hive 数组下标从 0 起，StarRocks 从 1 起；split 分隔符在 StarRocks 是字面量，正则 '\.' 改为 '.'；正则字面量的反斜杠按 StarRocks 字符串转义加倍；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：default.log_audit_source（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day =；= 20261001；!= 0
with ip_stat as (
SELECT concat(split(ip, '.')[1], '.', split(ip, '.')[2], '.', split(ip, '.')[3]) AS c_segment
FROM
    (SELECT get_json_object(replace(str4, '\\', ''), '$[*].ip') AS ip_list
      FROM `default`.log_audit_source
      WHERE day = 20261001
        AND log_app_id='ip-proxy-svc'
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

-- 语句 27
-- 应用：top-visit-host-produce-job  (CIPD/BDPD)  -- 3 jobs: domain / ip / url
-- 分段：URL_LOG_STAT_SQL
-- 方言：方言无需改写
-- 表：sodl.url_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(log_num)；day =；= 20261001；!= 0
SELECT host,
       sum(log_num) AS num
FROM sodl.url_log
WHERE day = 20261001
  AND host is not null
  AND locate('.', host)  != 0
  AND producttype in ('AF', 'NGAF', 'VNGAF')
GROUP BY host;

-- 语句 28
-- 应用：cipd-product-resource-monitor-prc  (CIPD/COMMON)
-- 分段：STAT_LOG_CHECK
-- 方言：方言无需改写
-- 表：csc.ods_csc_log_stats（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；=20261001
select 1
from csc.ods_csc_log_stats
where day=20261001
and app_id = 'ip-realtime-identify-etl-prc'
limit 1;

-- 语句 29
-- 应用：cipd-product-resource-monitor-prc  (CIPD/COMMON)
-- 分段：DOMAIN_DEVICE_COUNT_STAT
-- 方言：方言无需改写
-- 表：csc.ods_csc_log_stats（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(long1)；day=；=20261001
select str4, sum(long1)
from csc.ods_csc_log_stats
where day=20261001
and app_id = 'dns-intelligence-dispatch-prc'
and str1 = 'cig_subscribe'
and str2 = 'dl_dns_log'
group by str4;

-- 语句 30
-- 应用：cipd-product-resource-monitor-prc  (CIPD/COMMON)
-- 分段：CLOUDGATEWAY_IP_DEVICE_COUNT_STAT
-- 方言：方言无需改写
-- 表：csc.ods_csc_log_stats（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(long1)；day=；=20261001
select str5, sum(long1)
from csc.ods_csc_log_stats
where day=20261001
and app_id = 'ip-realtime-identify-etl-prc'
and str1 = 'etl_size'
and str2 = 'kafka_poll_size'
and str3 = 'CLOUD_INTELLIGENCE_GATEWAY'
group by str5;

-- 语句 31
-- 应用：cipd-product-resource-monitor-prc  (CIPD/COMMON)
-- 分段：CLOUDCHECK_IP_DEVICE_COUNT_STAT
-- 方言：方言无需改写
-- 表：csc.ods_csc_log_stats（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(long1)；day=；=20261001
select str5, sum(long1)
from csc.ods_csc_log_stats
where day=20261001
and app_id = 'ip-realtime-identify-etl-prc'
and str1 = 'filter_size'
and str2 = 'valid_devid'
and str3 = 'CLOUDCHECK_C2IP_CF'
group by str5;

-- 语句 32
-- 应用：cipd-product-resource-monitor-prc  (CIPD/COMMON)
-- 分段：DOMAIN_DEVICE_STAT
-- 方言：方言无需改写
-- 表：csc.ods_csc_log_stats（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day>=20260925 and day<=；>=20260925；<=20261001
select distinct str4
from csc.ods_csc_log_stats
where day>=20260925 and day<=20261001
and app_id = 'dns-intelligence-dispatch-prc'
and str1 = 'cig_subscribe'
and str2 = 'dl_dns_log';

-- 语句 33
-- 应用：cipd-product-resource-monitor-prc  (CIPD/COMMON)
-- 分段：CLOUDGATEWAY_IP_DEVICE_STAT
-- 方言：方言无需改写
-- 表：csc.ods_csc_log_stats（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day>=20260925 and day<=；>=20260925；<=20261001
select distinct str5
from csc.ods_csc_log_stats
where day>=20260925 and day<=20261001
and app_id = 'ip-realtime-identify-etl-prc'
and str1 = 'etl_size'
and str2 = 'kafka_poll_size'
and str3 = 'CLOUD_INTELLIGENCE_GATEWAY';

-- 语句 34
-- 应用：cipd-product-resource-monitor-prc  (CIPD/COMMON)
-- 分段：CLOUDCHECK_IP_DEVICE_STAT
-- 方言：方言无需改写
-- 表：csc.ods_csc_log_stats（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day>=20260925 and day<=；>=20260925；<=20261001
select distinct str5
from csc.ods_csc_log_stats
where day>=20260925 and day<=20261001
and app_id = 'ip-realtime-identify-etl-prc'
and str1 = 'filter_size'
and str2 = 'valid_devid'
and str3 = 'CLOUDCHECK_C2IP_CF';

-- 语句 35
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：1a)
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set；collect_list 改为 array_agg；Hive 字符串 || 改为 concat；StarRocks 的 || 不是拼接；regexp_extract 两参数补上组号 1，对应第一个捕获组；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：sodl.network_security_log（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(if(log_num=0, 1, log_num)；avg(severity)；stddev_pop(attack_count)；DAY=；log_num=；=20261001；=0
WITH attack_security_log AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename, '((cve-\\d+-\\d+)|(CVE-\\d+-\\d+)|(cnnvd-\\d+-\\d+)|(CNNVD-\\d+-\\d+))', 1) AS bug_id,
          producttype,
          severity
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) NOT IN ('30-10-0','30-999-0','90-5-1','90-5-2','90-7-1','90-7-2','90-7-3','90-7-4','90-7-5','90-7-6','90-7-8','90-7-999','90-9-0','94-2-1','94-2-2','94-2-3','94-2-999','94-4-1','94-4-7','94-4-999','94-5-1','212-1-0','212-5-0','212-9-1','212-9-2','212-9-3','216-6-0','216-7-1','216-10-1','216-10-2','216-11-1','216-12-0','216-999-0','204-2-12','204-2-999')
     AND manage NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
     AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
     AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
     AND cast(reqruleid AS string) NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='low_trusted_ips_id' OR part2='low_trusted_waf_id'))),
     trusted_sid_stat AS
  (SELECT srcip,
          count(distinct(reqruleid)) AS trusted_rule_count
   FROM attack_security_log
   WHERE reqruleid IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
   bug_id_stat AS
  (SELECT srcip,
          array_agg(concat(bug_id, '@', num)) AS bug_sum
   FROM
     (SELECT srcip,
             cast(bug_id AS string) AS bug_id,
             cast(count(bug_id) AS string) AS num
      FROM attack_security_log
      GROUP BY srcip,
               bug_id) bug_s
   GROUP BY srcip),
   attack_type_stat AS
  (SELECT srcip,
          array_agg(concat(attack_type, '@', num)) AS attack_type_sum
   FROM
     (SELECT srcip,
             cast(attack_type AS string) AS attack_type,
             cast(count(attack_type) AS string) AS num
      FROM attack_security_log
      GROUP BY srcip,
               attack_type) attack_s
   GROUP BY srcip),
     log_stat AS
  (SELECT s.*,
        coalesce(trusted_sid_stat.trusted_rule_count, 0) AS trusted_rule_count,
        std.attack_std,
        bug_id_stat.bug_sum AS bug_sum,
        attack_type_stat.attack_type_sum AS attack_type_sum
   FROM (SELECT srcip,
              count(distinct(reqruleid)) AS rule_count,
              sum(if(log_num=0, 1, log_num)) AS attack_count,
              count(distinct(manage)) AS devid_count,
              array_agg(DISTINCT reqruleid) AS rule_id_list,
              array_agg(DISTINCT producttype) AS source_list,
              avg(severity) as avg_severity
        FROM attack_security_log
        GROUP BY srcip) s
   LEFT JOIN trusted_sid_stat ON s.srcip = trusted_sid_stat.srcip
   LEFT JOIN attack_type_stat ON s.srcip = attack_type_stat.srcip
   LEFT JOIN bug_id_stat ON s.srcip = bug_id_stat.srcip
   LEFT JOIN
      (SELECT srcip,
              array_agg(concat(reqruleid, '@', attack_std)) AS attack_std
       FROM
         (SELECT srcip,
                 reqruleid,
                 cast(stddev_pop(attack_count) AS string) AS attack_std
          FROM
            (SELECT srcip,
                    reqruleid,
                    manage,
                    sum(if(log_num=0, 1, log_num)) AS attack_count
             FROM attack_security_log
             GROUP BY srcip,
                      reqruleid,
                      manage) a
          GROUP BY srcip,
                   reqruleid) b
       GROUP BY srcip)std ON s.srcip = std.srcip)
SELECT 'attack_security_log' AS table_name,
        srcip,
        trusted_rule_count,
        rule_count,
        attack_count,
        devid_count,
        rule_id_list,
        attack_std,
        bug_sum,
        attack_type_sum,
        source_list,
        avg_severity
FROM log_stat;

-- 语句 36
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：1b)
-- 方言：占位符 {RUN_TIME_MS} 用本机实验值填入；Hive 数组下标从 0 起，StarRocks 从 1 起；split 分隔符在 StarRocks 是字面量，正则 '\.' 改为 '.'；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：deleted_time=；expire_time>=；=0；>=1790901600000；>=5
SELECT *
FROM
  (SELECT concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3]) AS ips,
          count(1) AS num
   FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
   WHERE deleted_time=0
     AND direction='1'
     AND expire_time>=1790901600000
   GROUP BY concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3])) black_ip
WHERE num>=5
  AND ips NOT IN
    (SELECT str1
     FROM `default`.ods_custom_upload_data
     WHERE part1='attack_ip_analysis'
       AND part2='attack_ip_filter' );

-- 语句 37
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：1c)
-- 方言：占位符 {RUN_TIME_MS} 用本机实验值填入；Hive 数组下标从 0 起，StarRocks 从 1 起；split 分隔符在 StarRocks 是字面量，正则 '\.' 改为 '.'；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：deleted_time=；expire_time<；=0；<1790901600000；>=10
SELECT *
FROM
  (SELECT concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3]) AS ips,
          count(1) AS num
   FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
   WHERE deleted_time=0
     AND direction='1'
     AND expire_time<1790901600000
   GROUP BY concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3])) black_ip
WHERE num>=10
  AND ips NOT IN
    (SELECT str1
     FROM `default`.ods_custom_upload_data
     WHERE part1='attack_ip_analysis'
       AND part2='attack_ip_filter' );

-- 语句 38
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：1d)
-- 方言：占位符 {RUN_TIME_MS} 用本机实验值填入；Hive 数组下标从 0 起，StarRocks 从 1 起；split 分隔符在 StarRocks 是字面量，正则 '\.' 改为 '.'；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：deleted_time=；expire_time>=；expire_time<；=0；>=1790901600000；<1790901600000；>=10
WITH black_ips AS
  (SELECT concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3]) AS ips,
          count(1) AS num
   FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
   WHERE deleted_time=0
     AND direction='1'
     AND expire_time>=1790901600000
   GROUP BY concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3]))
SELECT ip
FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
WHERE deleted_time=0
  AND direction='1'
  AND expire_time<1790901600000
  AND concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3]) IN
    (SELECT ips
     FROM black_ips
     WHERE num>=10)
  AND concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3]) NOT IN
    (SELECT str1
     FROM `default`.ods_custom_upload_data
     WHERE part1='attack_ip_analysis'
       AND part2='attack_ip_filter');

-- 语句 39
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：SUB-JOB 2/6
-- 方言：占位符 {SKYEYE_UPDATE_MS} 用本机实验值填入；collect_set(distinct(...)) 改为 array_agg(DISTINCT ...)；collect_list 改为 array_agg；Hive 字符串 || 改为 concat；StarRocks 的 || 不是拼接；Hive 数组下标从 0 起，StarRocks 从 1 起；split 分隔符在 StarRocks 是字面量，正则 '\.' 改为 '.'；regexp_extract 两参数补上组号 1，对应第一个捕获组；`default` 在 StarRocks 是保留字，库名加反引号；原文在 log_stat 闭合前重复了 bug_id_stat，括号对不上；这是 all.sql 原文问题
-- 表：sodl.network_security_log（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名），csc.ods_csc_tim_db_unknown_intelligence_tb_skyeye_ip_info_sync（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(if(log_num=0, 1, log_num)；DAY=；update_time>=；log_num=；=20261001；>=1759365600000；=0；>=100
WITH skyeye_attack_security_log AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename, '((cve-\\d+-\\d+)|(CVE-\\d+-\\d+)|(cnnvd-\\d+-\\d+)|(CNNVD-\\d+-\\d+))', 1) AS bug_id
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) NOT IN ('30-10-0','30-999-0','90-5-1','90-5-2','90-7-1','90-7-2','90-7-3','90-7-4','90-7-5','90-7-6','90-7-8','90-7-999','90-9-0','94-2-1','94-2-2','94-2-3','94-2-999','94-4-1','94-4-7','94-4-999','94-5-1','212-1-0','212-5-0','212-9-1','212-9-2','212-9-3','216-6-0','216-7-1','216-10-1','216-10-2','216-11-1','216-12-0','216-999-0','204-2-12','204-2-999')
     AND manage NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_test_device_id'
          AND part2='attack_ip_analysis')
     AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
     AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
     AND cast(reqruleid AS string) NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='low_trusted_ips_id' OR part2='low_trusted_waf_id'))),
     skyeye_ip AS
  (SELECT ips,
          count(1) AS num
   FROM
     (SELECT ip,
             concat(split(ip, '.')[1] , '.', split(ip, '.')[2], '.', split(ip, '.')[3]) AS ips
      FROM csc.ods_csc_tim_db_unknown_intelligence_tb_skyeye_ip_info_sync
      WHERE update_time>=1759365600000
      GROUP BY ip) t
   WHERE ips NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='attack_ip_analysis'
          AND part2='attack_ip_filter')
   GROUP BY ips),
     trusted_sid_stat AS
  (SELECT srcip,
          count(distinct(reqruleid)) AS trusted_rule_count
   FROM skyeye_attack_security_log
   WHERE reqruleid IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
    bug_id_stat AS
  (SELECT srcip,
          array_agg(concat(bug_id, '@', num)) AS bug_sum
   FROM
     (SELECT srcip,
             cast(bug_id AS string) AS bug_id,
             cast(count(bug_id) AS string) AS num
      FROM skyeye_attack_security_log
      GROUP BY srcip,
               bug_id) bug_s
   GROUP BY srcip),
   attack_type_stat AS
  (SELECT srcip,
          array_agg(concat(attack_type, '@', num)) AS attack_type_sum
   FROM
     (SELECT srcip,
             cast(attack_type AS string) AS attack_type,
             cast(count(attack_type) AS string) AS num
      FROM skyeye_attack_security_log
      GROUP BY srcip,
               attack_type) attack_s
   GROUP BY srcip),
     log_stat AS
  (SELECT s.*,
          coalesce(trusted_sid_stat.trusted_rule_count, 0) AS trusted_rule_count,
          bug_id_stat.bug_sum AS bug_sum,
          attack_type_stat.attack_type_sum AS attack_type_sum
   FROM
     (SELECT srcip,
             count(distinct(reqruleid)) AS rule_count,
             sum(if(log_num=0, 1, log_num)) AS attack_count,
             count(distinct(manage)) AS devid_count,
             array_agg(DISTINCT reqruleid) AS rule_id_list
   FROM skyeye_attack_security_log
   WHERE reqruleid IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
    bug_id_stat AS
  (SELECT srcip,
          array_agg(concat(bug_id, '@', num)) AS bug_sum
   FROM
     (SELECT srcip,
             cast(bug_id AS string) AS bug_id,
             cast(count(bug_id) AS string) AS num
      FROM skyeye_attack_security_log
      GROUP BY srcip,
               bug_id) bug_s
   GROUP BY srcip),
   attack_type_stat AS
  (SELECT srcip,
          array_agg(concat(attack_type, '@', num)) AS attack_type_sum
   FROM
     (SELECT srcip,
             cast(attack_type AS string) AS attack_type,
             cast(count(attack_type) AS string) AS num
      FROM skyeye_attack_security_log
      GROUP BY srcip,
               attack_type) attack_s
   GROUP BY srcip),
     log_stat AS
  (SELECT s.*,
          coalesce(trusted_sid_stat.trusted_rule_count, 0) AS trusted_rule_count,
          bug_id_stat.bug_sum AS bug_sum,
          attack_type_stat.attack_type_sum AS attack_type_sum
   FROM
     (SELECT srcip,
             count(distinct(reqruleid)) AS rule_count,
             sum(if(log_num=0, 1, log_num)) AS attack_count,
             count(distinct(manage)) AS devid_count,
             array_agg(DISTINCT reqruleid) AS rule_id_list
      FROM skyeye_attack_security_log
      GROUP BY srcip) s
   LEFT JOIN trusted_sid_stat ON s.srcip = trusted_sid_stat.srcip
   LEFT JOIN attack_type_stat ON s.srcip = attack_type_stat.srcip
   LEFT JOIN bug_id_stat ON s.srcip = bug_id_stat.srcip)
SELECT *
FROM log_stat
WHERE concat(split(srcip, '.')[1] , '.', split(srcip, '.')[2], '.', split(srcip, '.')[3]) IN
    (SELECT ips
     FROM skyeye_ip
     WHERE num>=100)
  OR (concat(split(srcip, '.')[1] , '.', split(srcip, '.')[2], '.', split(srcip, '.')[3]) IN
        (SELECT ips
         FROM skyeye_ip
         WHERE num>=30)
      AND trusted_rule_count > 0)
  OR (srcip IN
        (SELECT ip
         FROM csc.ods_csc_tim_db_unknown_intelligence_tb_skyeye_ip_info_sync
         WHERE update_time>=1759365600000)
      AND trusted_rule_count > 0);

-- 语句 40
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：3a)
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set；collect_list 改为 array_agg；Hive 字符串 || 改为 concat；StarRocks 的 || 不是拼接；regexp_extract 两参数补上组号 1，对应第一个捕获组；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：sodl.network_security_log（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：DAY=；day=；=20261001
WITH attack_security_log_rce AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename, '((cve-\\d+-\\d+)|(CVE-\\d+-\\d+)|(cnnvd-\\d+-\\d+)|(CNNVD-\\d+-\\d+))', 1) AS bug_id,
          producttype
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND manage NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
        ),
   bug_id_stat AS
  (SELECT srcip,
          array_agg(concat(bug_id, '@', num)) AS bug_sum
   FROM
     (SELECT srcip,
             cast(bug_id AS string) AS bug_id,
             cast(count(bug_id) AS string) AS num
      FROM attack_security_log_rce
      GROUP BY srcip,
               bug_id) bug_s
   GROUP BY srcip),

   rule_id_stat AS
  (SELECT srcip,
          array_agg(concat(reqruleid, '@', num)) AS reqruleid_sum
   FROM
     (SELECT srcip,
             cast(reqruleid AS string) AS reqruleid,
             cast(count(reqruleid) AS string) AS num
      FROM attack_security_log_rce
      GROUP BY srcip,
               reqruleid) reqruleid_s
   GROUP BY srcip),

   attack_type_stat AS
  (SELECT srcip,
          array_agg(concat(attack_type, '@', num)) AS attack_type_sum
   FROM
     (SELECT srcip,
             cast(attack_type AS string) AS attack_type,
             cast(count(attack_type) AS string) AS num
      FROM attack_security_log_rce
      GROUP BY srcip,
               attack_type) attack_s
   GROUP BY srcip),

   keyword_stat AS (
      SELECT srcip, array_agg(DISTINCT keyword) AS hit_keywords
    FROM (
      SELECT srcip, keyword
      FROM (
        SELECT srcip, regexp_extract(requesthead, 'eval\\(|assert\\(|preg_replace\\(|call_user_func\\(|call_user_func_array\\(|create_function\\(|array_map\\(|system\\(|passthru\\(|exec\\(|pcntl_exec\\(|shell_exec\\(|popen\\(|proc_open\\(|ob_start\\(|ProcessBuilder\\(|runtime\\.exec\\(|Runtime\\.getRuntime\\(\\)\\.exec\\(|os\\.system\\(|os\\.popen\\(|subprocess\\.Popen\\(|cat \\/etc\\/passwd ', 0) AS keyword
        FROM sodl.network_security_log
        where day=20261001
        UNION
        SELECT srcip, regexp_extract(url, 'eval\\(|assert\\(|preg_replace\\(|call_user_func\\(|call_user_func_array\\(|create_function\\(|array_map\\(|system\\(|passthru\\(|exec\\(|pcntl_exec\\(|shell_exec\\(|popen\\(|proc_open\\(|ob_start\\(|ProcessBuilder\\(|runtime\\.exec\\(|Runtime\\.getRuntime\\(\\)\\.exec\\(|os\\.system\\(|os\\.popen\\(|subprocess\\.Popen\\(|cat \\/etc\\/passwd ', 0) AS keyword
        FROM sodl.network_security_log
        where day=20261001
      ) t
      WHERE keyword != ''
    ) t2
    GROUP BY srcip
   ),
     rce_stat AS
  (
     select keyword_stat.srcip, keyword_stat.hit_keywords, bug_id_stat.bug_sum, rule_id_stat.reqruleid_sum,
     attack_type_stat.attack_type_sum from keyword_stat
     left join bug_id_stat on keyword_stat.srcip = bug_id_stat.srcip
     left join rule_id_stat on keyword_stat.srcip = rule_id_stat.srcip
     left join attack_type_stat on keyword_stat.srcip = attack_type_stat.srcip
    )
SELECT 'attack_security_log_rce' AS table_name,
        srcip,
        hit_keywords,
        bug_sum,
        reqruleid_sum,
        attack_type_sum
FROM rce_stat
where regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
     AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != '';

-- 语句 41
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：3b)
-- 方言：RE2 不支持前瞻/后顾，User-Agent 提取改为捕获组；collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set；collect_list 改为 array_agg；Hive 字符串 || 改为 concat；StarRocks 的 || 不是拼接；regexp_extract 两参数补上组号 1，对应第一个捕获组；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：sodl.network_security_log（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：DAY=；=20261001
WITH attack_security_log_ua AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename, '((cve-\\d+-\\d+)|(CVE-\\d+-\\d+)|(cnnvd-\\d+-\\d+)|(CNNVD-\\d+-\\d+))', 1) AS bug_id,
          regexp_extract(lower(requesthead), 'user-agent: ([^\\r\\n]*)', 1) as user_agent
   FROM sodl.network_security_log
   WHERE DAY=20261001
    and requesthead != ''
    and regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
     AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
     AND manage NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
        ),
    bug_id_stat AS
  (SELECT srcip,
          array_agg(concat(bug_id, '@', num)) AS bug_sum
   FROM
     (SELECT srcip,
             cast(bug_id AS string) AS bug_id,
             cast(count(bug_id) AS string) AS num
      FROM attack_security_log_ua
      GROUP BY srcip,
               bug_id) bug_s
   GROUP BY srcip),

   rule_id_stat AS
  (SELECT srcip,
          array_agg(concat(reqruleid, '@', num)) AS reqruleid_sum
   FROM
     (SELECT srcip,
             cast(reqruleid AS string) AS reqruleid,
             cast(count(reqruleid) AS string) AS num
      FROM attack_security_log_ua
      GROUP BY srcip,
               reqruleid) reqruleid_s
   GROUP BY srcip),

   attack_type_stat AS
  (SELECT srcip,
          array_agg(concat(attack_type, '@', num)) AS attack_type_sum
   FROM
     (SELECT srcip,
             cast(attack_type AS string) AS attack_type,
             cast(count(attack_type) AS string) AS num
      FROM attack_security_log_ua
      GROUP BY srcip,
               attack_type) attack_s
   GROUP BY srcip),

   ua_hit_record as
   (
    select srcip, array_agg(DISTINCT mal_ua) AS hit_mal_ua
    from (
     SELECT srcip, regexp_extract(user_agent, 'zgrab|datacha0s|masscan|morfeus fucking scanner|netsparker|nessus|nmap scripting engine|openvas|sqlmap|wordpress hash grabber|wpscan|struts\\-pwn|detectify|dirbuster|\\(hydra\\)|\\.nasl|absinthe|advanced email extractor|arachni\\/|autogetcontent|bilbo|brutus|bsqlbf|cgichk|cisco\\-torch|commix|core\\-project\\/1\\.0|crimscanner\\/|domino hunter|dotdotpwn|email extractor|fhscan core 1\\.|floodgate|f\\-secure radar|get\\-minimal|gobuster|gootkit auto\\-rooter scanner|grabber|grendel\\-scan|havij|inspath|internet ninja|jaascois|zmeu|Jorgee|metis|mysqloit|n\\-stealth|nikto|nmap nse|nmap\\-nse|nsauditor|pangolin|paros|pmafind|prog\\.customcrawler|qualys was|s\\.t\\.a\\.l\\.k\\.e\\.r\\.|security scan|springenwerk|sql power injector|sqlninja|sysscan|teh forest lobster|this is an exploit|toata dragostea|toata dragostea mea pentru diavola|uil2pn|vega\\/|voideye|w3af\\.sf\\.net|w3af\\.sourceforge\\.net|w3af\\.org|webbandit|webinspect|webshag|webtrends security analyzer|webvulnscan|whatweb|whcc\\/|xmlrpc exploit ', 0)
     AS mal_ua
     FROM attack_security_log_ua
     where user_agent != '') ua_agg
     where mal_ua != ''
     group by srcip
   ),


   ua_stat as (
     select ua_hit_record.srcip, ua_hit_record.hit_mal_ua, bug_id_stat.bug_sum, rule_id_stat.reqruleid_sum,
     attack_type_stat.attack_type_sum from ua_hit_record
     left join bug_id_stat on ua_hit_record.srcip = bug_id_stat.srcip
     left join rule_id_stat on ua_hit_record.srcip = rule_id_stat.srcip
     left join attack_type_stat on ua_hit_record.srcip = attack_type_stat.srcip
   )
     SELECT 'attack_security_log_ua' AS table_name,
            srcip,
            hit_mal_ua,
            bug_sum,
            reqruleid_sum,
            attack_type_sum
  FROM ua_stat;

-- 语句 42
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：SUB-JOB 4/6
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set；collect_list 改为 array_agg；Hive 字符串 || 改为 concat；StarRocks 的 || 不是拼接；regexp_extract 两参数补上组号 1，对应第一个捕获组；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：sodl.network_security_log（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(if(log_num=0, 1, log_num)；avg(severity)；stddev_pop(attack_count)；DAY=；log_num=；=20261001；=0
WITH low_trusted_log AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename, '((cve-\\d+-\\d+)|(CVE-\\d+-\\d+)|(cnnvd-\\d+-\\d+)|(CNNVD-\\d+-\\d+))', 1) AS bug_id,
          producttype,
          severity
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) NOT IN ('30-10-0','30-999-0','90-5-1','90-5-2','90-7-1','90-7-2','90-7-3','90-7-4','90-7-5','90-7-6','90-7-8','90-7-999','90-9-0','94-2-1','94-2-2','94-2-3','94-2-999','94-4-1','94-4-7','94-4-999','94-5-1','212-1-0','212-5-0','212-9-1','212-9-2','212-9-3','216-6-0','216-7-1','216-10-1','216-10-2','216-11-1','216-12-0','216-999-0','204-2-12','204-2-999')
     AND manage NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
     AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
     AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
     ),
     trusted_sid_stat AS
  (SELECT srcip,
          count(distinct(reqruleid)) AS trusted_rule_count
   FROM low_trusted_log
   WHERE reqruleid IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
   bug_id_stat AS
  (SELECT srcip,
          array_agg(concat(bug_id, '@', num)) AS bug_sum
   FROM
     (SELECT srcip,
             cast(bug_id AS string) AS bug_id,
             cast(count(bug_id) AS string) AS num
      FROM low_trusted_log
      GROUP BY srcip,
               bug_id) bug_s
   GROUP BY srcip),
   attack_type_stat AS
  (SELECT srcip,
          array_agg(concat(attack_type, '@', num)) AS attack_type_sum
   FROM
     (SELECT srcip,
             cast(attack_type AS string) AS attack_type,
             cast(count(attack_type) AS string) AS num
      FROM low_trusted_log
      GROUP BY srcip,
               attack_type) attack_s
   GROUP BY srcip),
     log_stat AS
  (SELECT s.*,
        coalesce(trusted_sid_stat.trusted_rule_count, 0) AS trusted_rule_count,
        std.attack_std,
        bug_id_stat.bug_sum AS bug_sum,
        attack_type_stat.attack_type_sum AS attack_type_sum
   FROM (SELECT srcip,
              count(distinct(reqruleid)) AS rule_count,
              sum(if(log_num=0, 1, log_num)) AS attack_count,
              count(distinct(manage)) AS devid_count,
              array_agg(DISTINCT reqruleid) AS rule_id_list,
              array_agg(DISTINCT producttype) AS source_list,
              avg(severity) as avg_severity
        FROM low_trusted_log
        GROUP BY srcip) s
   LEFT JOIN trusted_sid_stat ON s.srcip = trusted_sid_stat.srcip
   LEFT JOIN attack_type_stat ON s.srcip = attack_type_stat.srcip
   LEFT JOIN bug_id_stat ON s.srcip = bug_id_stat.srcip
   LEFT JOIN
      (SELECT srcip,
              array_agg(concat(reqruleid, '@', attack_std)) AS attack_std
       FROM
         (SELECT srcip,
                 reqruleid,
                 cast(stddev_pop(attack_count) AS string) AS attack_std
          FROM
            (SELECT srcip,
                    reqruleid,
                    manage,
                    sum(if(log_num=0, 1, log_num)) AS attack_count
             FROM low_trusted_log
             GROUP BY srcip,
                      reqruleid,
                      manage) a
          GROUP BY srcip,
                   reqruleid) b
       GROUP BY srcip)std ON s.srcip = std.srcip)
SELECT 'low_trusted_log' AS table_name,
        srcip,
        trusted_rule_count,
        rule_count,
        attack_count,
        devid_count,
        rule_id_list,
        attack_std,
        bug_sum,
        attack_type_sum,
        source_list,
        avg_severity
FROM log_stat;

-- 语句 43
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：5a)
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set；collect_list 改为 array_agg；Hive 字符串 || 改为 concat；StarRocks 的 || 不是拼接；regexp_extract 两参数补上组号 1，对应第一个捕获组；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：sodl.network_security_log（缺少新平台表名），default.ods_custom_upload_data（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(if(log_num=0, 1, log_num)；avg(severity)；stddev_pop(attack_count)；DAY=；log_num=；=20261001；=0
WITH xss_sql_injection_log AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename, '((cve-\\d+-\\d+)|(CVE-\\d+-\\d+)|(cnnvd-\\d+-\\d+)|(CNNVD-\\d+-\\d+))', 1) AS bug_id,
          producttype,
          severity,
          action
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) IN ('90-5-1', '90-5-2')
     AND manage NOT IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
     AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
     AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
     ),
     trusted_sid_stat AS
  (SELECT srcip,
          count(distinct(reqruleid)) AS trusted_rule_count
   FROM xss_sql_injection_log
   WHERE reqruleid IN
       (SELECT str1
        FROM `default`.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
   bug_id_stat AS
  (SELECT srcip,
          array_agg(concat(bug_id, '@', num)) AS bug_sum
   FROM
     (SELECT srcip,
             cast(bug_id AS string) AS bug_id,
             cast(count(bug_id) AS string) AS num
      FROM xss_sql_injection_log
      GROUP BY srcip,
               bug_id) bug_s
   GROUP BY srcip),
   attack_type_stat AS
  (SELECT srcip,
          array_agg(concat(attack_type, '@', num)) AS attack_type_sum
   FROM
     (SELECT srcip,
             cast(attack_type AS string) AS attack_type,
             cast(count(attack_type) AS string) AS num
      FROM xss_sql_injection_log
      GROUP BY srcip,
               attack_type) attack_s
   GROUP BY srcip),
     log_stat AS
  (SELECT s.*,
        coalesce(trusted_sid_stat.trusted_rule_count, 0) AS trusted_rule_count,
        std.attack_std,
        bug_id_stat.bug_sum AS bug_sum,
        attack_type_stat.attack_type_sum AS attack_type_sum
   FROM (SELECT srcip,
              count(distinct(reqruleid)) AS rule_count,
              sum(if(log_num=0, 1, log_num)) AS attack_count,
              count(distinct(manage)) AS devid_count,
              array_agg(DISTINCT reqruleid) AS rule_id_list,
              array_agg(DISTINCT producttype) AS source_list,
              avg(severity) as avg_severity,
              array_agg(DISTINCT action) as action_list
        FROM xss_sql_injection_log
        GROUP BY srcip) s
   LEFT JOIN trusted_sid_stat ON s.srcip = trusted_sid_stat.srcip
   LEFT JOIN attack_type_stat ON s.srcip = attack_type_stat.srcip
   LEFT JOIN bug_id_stat ON s.srcip = bug_id_stat.srcip
   LEFT JOIN
      (SELECT srcip,
              array_agg(concat(reqruleid, '@', attack_std)) AS attack_std
       FROM
         (SELECT srcip,
                 reqruleid,
                 cast(stddev_pop(attack_count) AS string) AS attack_std
          FROM
            (SELECT srcip,
                    reqruleid,
                    manage,
                    sum(if(log_num=0, 1, log_num)) AS attack_count
             FROM xss_sql_injection_log
             GROUP BY srcip,
                      reqruleid,
                      manage) a
          GROUP BY srcip,
                   reqruleid) b
       GROUP BY srcip)std ON s.srcip = std.srcip)
SELECT 'xss_sql_injection_log' AS log_type,
        srcip as ip,
        trusted_rule_count,
        rule_count,
        attack_count,
        devid_count,
        rule_id_list,
        attack_std,
        bug_sum as bug_id_agg,
        attack_type_sum as attack_type_agg,
        source_list,
        avg_severity,
        action_list
FROM log_stat;

-- 语句 44
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：5b)
-- 方言：collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set；regexp_extract 两参数补上组号 1，对应第一个捕获组
-- 表：sodl.network_security_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；=20261001
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
  WHERE day=20261001
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
  WHERE day=20261001
    AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
    AND regexp_extract(srcip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
    AND concat_ws('-',cast(threatclass as String),
                        cast(threattype as String)) in ('94-4')
    and regexp_extract(requestbody, '(pwd|password)=([^&; ]+)', 2) != ''
)a
group by srcip;

-- 语句 45
-- 应用：attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- 分段：SUB-JOB 6/6
-- 方言：regexp_extract 两参数补上组号 1，对应第一个捕获组
-- 表：sodl.network_security_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：day=；=20261001；> 10
SELECT
    'network_security_log' as table_name,
    concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
    log_num as attack_count,
    manage as device_id,
    reqruleid as sid,
    srcip,
    requesthead,
    requestbody,
    day
FROM sodl.network_security_log
WHERE day=20261001
AND (length(requesthead) + length(requestbody)) > 10
AND regexp_extract(srcip, '^((0\\.0\\.0\\.0)|(127\\.0\\.0\\.1)|(localhost)|(10\\.)|(172\\.1[6-9]\\.)|(172\\.2[0-9]\\.)|(172\\.3[0-1]\\.)|(192\\.168\\.))', 1) = ''
AND (requesthead != '' OR requestbody != '')
AND (regexp_extract(requesthead, '[^a-zA-Z](wget|curl|downloadfile|downloadstring|powershell|certutil|bitsadmin|mshta|ncat|msiexec|msxsl|rundll32|regsvr32|tftp|ipc$|pubprn.vbs|wmiexec|psexec|ftp:|jndi:|ldap:|rmi:)[^a-zA-Z0-9)_;,|]', 1) != ''
    OR
    regexp_extract(requestbody, '[^a-zA-Z](wget|curl|downloadfile|downloadstring|powershell|certutil|bitsadmin|mshta|ncat|msiexec|msxsl|rundll32|regsvr32|tftp|ipc$|pubprn.vbs|wmiexec|psexec|ftp:|jndi:|ldap:|rmi:)[^a-zA-Z0-9)_;,|]', 1) != '');

-- 语句 46
-- 应用：topthreat_hot_stat — 黑域名统计 SQL
-- 分段：topthreat_hot_stat — 黑域名统计 SQL
-- 方言：占位符 ${day} 用本机实验值填入；占位符 ${hour} 用本机实验值填入；format_json_list 前面的反斜杠引号替换改为 RE2 能编译的 \\+"；default.format_json_list 改为 parse_json 后 unnest；本机 StarRocks 没有同名函数；LATERAL VIEW explode 改为 unnest；Hive 数组下标从 0 起，StarRocks 从 1 起；size() 改为 cardinality()；最后一个元素的下标改为长度本身；正则字面量的反斜杠按 StarRocks 字符串转义加倍；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：default.log_audit_source（缺少新平台表名），sodl.network_security_log（缺少新平台表名），sodl.sip_iocstat_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(domain_num)；sum(log_num)；sum(record_count)；long1 =；day =；hour =；= 0；= 20261001
SELECT domain,
       sum(domain_num) AS domain_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT domain,
          devid,
          count(1) AS domain_num
   FROM
     (SELECT lower(get_json_object(str10_tmp, '$.domain')) AS domain,
             str2 AS devid
      FROM `default`.log_audit_source , unnest(ifnull(cast(parse_json(regexp_replace(str10, '\\\\+"', '"')) AS ARRAY<JSON>), [])) AS str10_tbl(str10_tmp)
      WHERE log_app_id IN ('domain-proxy-svc' ,
                           'cloudcheck')
        AND module_id IN ('domain-proxy-svc' ,
                          'CloudCheck')
        AND str1 IN ('VNGAF' ,
                     'NGAF' ,
                     'EDR' ,
                     'EDR_BOTNET' ,
                     'SIP' ,
                     'SIP_SMTP' ,
                     'SIP_SMB' ,
                     'AC' ,
                     'VAC' ,
                     'CWPP' ,
                     'SASE' ,
                     'EDR_WEBSITE' ,
                     'EDR_NPE' ,
                     'EDR_CLOUD_IDENTIFY' ,
                     'EDR_PK')
        AND long1 = 0
        AND get_json_object(str10_tmp, '$.info.attr')='0'
        AND day = 20261001
        AND hour = 0 ) a
   WHERE domain IS NOT NULL
     AND domain NOT IN ('',
                        '-')
   GROUP BY domain,
            devid

   UNION ALL

    SELECT domain,
           devid,
           sum(log_num) AS domain_num
    FROM
      (SELECT split(split(url, '//')[cardinality(split(url, '//'))], '/')[1] AS domain,
              MANAGE AS devid,
              log_num
       FROM sodl.network_security_log
       WHERE url IS NOT NULL
         AND url NOT IN ('',
                         '-')
         AND day = 20261001
         AND hour = 0)t
    WHERE domain IS NOT NULL
      AND domain != ''
    GROUP BY domain,
             devid

   UNION ALL

   SELECT ioc AS domain,
          manage AS devid,
          sum(record_count) AS domain_num
   FROM sodl.sip_iocstat_log
   WHERE ioc_type = 'domain'
     AND ioc IS NOT NULL
     AND ioc NOT IN ('',
                     '-')
     AND day = 20261001
     AND hour = 0
   GROUP BY ioc,
            manage ) t
GROUP BY domain,
         devid
ORDER BY domain_num DESC
LIMIT 100000;

-- 语句 47
-- 应用：topthreat_hot_stat — 黑文件统计 SQL
-- 分段：topthreat_hot_stat — 黑文件统计 SQL
-- 方言：占位符 ${day} 用本机实验值填入；占位符 ${hour} 用本机实验值填入；format_json_list 前面的反斜杠引号替换改为 RE2 能编译的 \\+"；default.format_json_list 改为 parse_json 后 unnest；本机 StarRocks 没有同名函数；LATERAL VIEW explode 改为 unnest；正则字面量的反斜杠按 StarRocks 字符串转义加倍；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：default.log_audit_source（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：long1 =；day =；hour =；= 0；= 20261001
SELECT md5,
       count(1) AS md5_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT lower(get_json_object(str10_tmp, '$.filemd5')) AS md5,
          get_json_object(str10_tmp, '$.info.attr') AS attr,
          str2 AS devid
   FROM `default`.log_audit_source , unnest(ifnull(cast(parse_json(regexp_replace(str10, '\\\\+"', '"')) AS ARRAY<JSON>), [])) AS str10_tbl(str10_tmp)
   WHERE log_app_id = 'analysis-proxy-api'
     AND module_id IN ('file_hash' ,
                       'file_scan')
     AND str1 IN ('VNGAF' ,
                  'NGAF' ,
                  'EDR' ,
                  'EDR_BOTNET' ,
                  'SIP' ,
                  'SIP_SMTP' ,
                  'SIP_SMB' ,
                  'AC' ,
                  'VAC' ,
                  'CWPP' ,
                  'SASE' ,
                  'EDR_WEBSITE' ,
                  'EDR_NPE' ,
                  'EDR_CLOUD_IDENTIFY' ,
                  'EDR_PK')
     AND long1 = 0
     AND day = 20261001
     AND hour = 0) a
WHERE md5 IS NOT NULL
  AND md5 NOT IN ('',
                  '-')
  AND attr='0'
GROUP BY md5,
         devid
ORDER BY md5_num DESC
LIMIT 100000;

-- 语句 48
-- 应用：topthreat_hot_stat — 黑URL统计 SQL
-- 分段：topthreat_hot_stat — 黑URL统计 SQL
-- 方言：占位符 ${day} 用本机实验值填入；占位符 ${hour} 用本机实验值填入；format_json_list 前面的反斜杠引号替换改为 RE2 能编译的 \\+"；default.format_json_list 改为 parse_json 后 unnest；本机 StarRocks 没有同名函数；LATERAL VIEW explode 改为 unnest；正则字面量的反斜杠按 StarRocks 字符串转义加倍；`default` 在 StarRocks 是保留字，库名加反引号
-- 表：default.log_audit_source（缺少新平台表名），sodl.network_security_log（缺少新平台表名），sodl.sip_iocstat_log（缺少新平台表名）
-- 字段编码未给出，DEC-009 需显式转换：sum(url_num)；sum(log_num)；sum(record_count)；long1 =；day =；hour =；= 0；= 20261001
SELECT url,
       sum(url_num) AS url_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT url,
          devid,
          count(1) AS url_num
   FROM
     (SELECT lower(get_json_object(str10_tmp, '$.url')) AS url,
             str2 AS devid
      FROM `default`.log_audit_source , unnest(ifnull(cast(parse_json(regexp_replace(str10, '\\\\+"', '"')) AS ARRAY<JSON>), [])) AS str10_tbl(str10_tmp)
      WHERE log_app_id IN ('url-proxy-svc' ,
                           'cloudcheck')
        AND module_id IN ('url-proxy-svc' ,
                          'CloudCheck')
        AND str1 IN ('VNGAF' ,
                     'NGAF' ,
                     'EDR' ,
                     'EDR_BOTNET' ,
                     'SIP' ,
                     'SIP_SMTP' ,
                     'SIP_SMB' ,
                     'AC' ,
                     'VAC' ,
                     'CWPP' ,
                     'SASE' ,
                     'EDR_WEBSITE' ,
                     'EDR_NPE' ,
                     'EDR_CLOUD_IDENTIFY' ,
                     'EDR_PK')
        AND long1 = 0
        AND get_json_object(str10_tmp, '$.info.attr')='0'
        AND day = 20261001
        AND hour = 0 ) a
   WHERE url IS NOT NULL
     AND url NOT IN ('',
                     '-')
   GROUP BY url,
            devid

   UNION ALL

   SELECT url,
          manage AS devid,
          sum(log_num) AS url_num
   FROM sodl.network_security_log
   WHERE url IS NOT NULL
     AND url NOT IN ('',
                     '-')
     AND day = 20261001
     AND hour = 0
   GROUP BY url,
            manage

   UNION ALL

   SELECT ioc AS url,
          manage AS devid,
          sum(record_count) AS url_num
   FROM sodl.sip_iocstat_log
   WHERE ioc_type = 'url'
     AND ioc IS NOT NULL
     AND ioc NOT IN ('',
                     '-')
     AND day = 20261001
     AND hour = 0
   GROUP BY ioc,
            manage ) t
GROUP BY url,
         devid
ORDER BY url_num DESC
LIMIT 100000;
