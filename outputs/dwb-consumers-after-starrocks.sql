-- 剩余 4 个依赖中间表的任务：改造后（StarRocks，读合并表 paimon.ti.dwb_ti_*）
-- 改造前见 outputs/dwb-consumers-before-hive.sql（与本文件按 @stmt 编号一一对应）
-- 日期取 all.sql 注释里解出的值：domain-heat 20260930；domain-hit 20260902–20261002；active-domain、black-ti 20261001
--
-- 假设（未获文档直接确认，需要用户或 @dwb 2 的结果确认）：
--   [A1] 旧 sodl 来源分区的 src_log 值沿用旧名：network_security_log、endpoint_security_log、
--        sip_iocstat_log、dns_log、url_log、http_log（log/ODS_TO_DWB_DETAIL.md L238-245）
--   [A2] 旧 default.dwb_domain_info（audit 链）对应 src_log='domain-proxy-svc'（推断，依据用户的 audit INSERT）
--   [A3] default.ods_custom_upload_data → paimon.ti.ods_ti_db_custom_upload_tb_custom_upload_sync（2026-11-26 用户确认，DEC-031）；
--        仅确认表名，列 part1、part2、str1 沿用旧名，缺少新平台字段名，待用户核对
-- 类型：合并表 day、log_num、attack_count 为 BIGINT，threatclass 为 INT，数值比较无需 CAST。

-- @stmt 1 black-ti-context-produce-prc / INFO_EXIST_CHECK_SQL（domain）
-- 改动：表改为 paimon.ti.dwb_ti_domain_info；合并表含 audit 行，加 [A1] 的 sodl 来源过滤，否则 audit 数据会让检查误通过
SELECT 1 FROM paimon.ti.dwb_ti_domain_info
WHERE `day` = 20261001
  AND src_log IN ('network_security_log', 'dns_log', 'sip_iocstat_log', 'endpoint_security_log', 'url_log')
LIMIT 1;

-- @stmt 2 black-ti-context-produce-prc / INFO_EXIST_CHECK_SQL（ip）
SELECT 1 FROM paimon.ti.dwb_ti_ip_info
WHERE `day` = 20261001
  AND src_log IN ('network_security_log', 'dns_log', 'url_log', 'http_log', 'sip_iocstat_log')
LIMIT 1;

-- @stmt 3 black-ti-context-produce-prc / C2_IP_ACTIVE_STAT_SQL
-- 改动：sodl.dwb_sodl_ip_info → paimon.ti.dwb_ti_ip_info；csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync → ti.ods_ti_db_intelligence_tb_ip_reputation_sync（DEC-014）；
--       collect_set → array_agg(DISTINCT)；regexp_extract 补组号 1；双引号改单引号；:mday → 20261001；src_log 过滤保留（[A1]，挡住 ip-proxy-svc）
WITH reputation_ip_stat AS
  (SELECT
      ip,
      port,
      direction,
      expire_time,
      deleted_time,
      attack_count,
      devid,
      '其他' AS industry,
      '其他' AS country,
      '其他' AS province,
      src_log
   FROM
   (
    SELECT
        ip,
        port,
        direction,
        expire_time,
        deleted_time
    FROM ti.ods_ti_db_intelligence_tb_ip_reputation_sync
    WHERE direction = '2'
        AND port = 0
    ) black_reputation_ip
   JOIN
     (SELECT sum(attack_count) AS attack_count,
             manage AS devid,
             COALESCE(CAST(threatclass AS STRING), '0') AS src_log,
             dstip AS dip
      FROM paimon.ti.dwb_ti_ip_info
      WHERE `day` = 20261001
        AND src_log IN ('sip_iocstat_log', 'network_security_log')
        AND dstip != ''
        AND dstip NOT IN ('8.8.8.8', '8.8.4.4', '114.114.114.114', '114.114.115.115', '119.29.29.29', '223.5.5.5', '223.6.6.6', '1.1.1.1', '1.0.0.1')
        AND regexp_extract(dstip, '^(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})$', 1) != ''
        AND regexp_extract(dstip, '^(0\\.|127\\.|10\\.|172\\.1[6-9]\\.|172\\.2[0-9]\\.|172\\.3[01]\\.|192\\.168\\.|169\\.254\\.|192\\.0\\.0\\.|192\\.88\\.99\\.|198\\.18\\.|198\\.19\\.|198\\.51\\.100\\.|203\\.0\\.113\\.|224\\.|240\\.|255\\.)', 1) = ''
      GROUP BY dstip, manage, threatclass
     ) b ON black_reputation_ip.ip = b.dip
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
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */
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
JOIN industry_stats ins ON ris.ip = ins.ip AND ris.industry = ins.industry
JOIN region_stats rs ON ris.ip = rs.ip AND ris.country = rs.country AND ris.province = rs.province
JOIN log_stats ls ON ris.ip = ls.ip AND ris.src_log = ls.src_log
GROUP BY ris.ip,
         ris.port,
         ris.direction,
         ris.expire_time,
         ris.deleted_time;

-- @stmt 4 black-ti-context-produce-prc / DOMAIN_ACTIVE_STAT_SQL
-- 改动：sodl.dwb_sodl_domain_info → paimon.ti.dwb_ti_domain_info；csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync → ti.ods_ti_db_domain_intelligence_tb_domain_reputation_sync；
--       collect_set → array_agg(DISTINCT)。未加 src_log 过滤：audit 域名分区 row_key 写 NULL，被 row_key != '' 排除（依据用户的 audit INSERT）
WITH domain_stat AS
(SELECT black_reputation_domain.domain,
      black_reputation_domain.deleted_time,
      attack_count,
      devid,
      '其他' AS industry,
      '其他' AS country,
      '其他' AS province,
      src_log
FROM
 (
    SELECT domain, deleted_time
      FROM ti.ods_ti_db_domain_intelligence_tb_domain_reputation_sync
      WHERE reputation = '0'
 ) black_reputation_domain
JOIN
 (SELECT sum(attack_count) AS attack_count,
         manage AS devid,
         COALESCE(CAST(threatclass AS STRING), '0') AS src_log,
         domain
  FROM paimon.ti.dwb_ti_domain_info
      WHERE `day` = 20261001
      AND row_key != ''
  GROUP BY domain, manage, threatclass
      ) b ON black_reputation_domain.domain = b.domain
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
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */
       ds.domain,
       ds.deleted_time,
       SUM(ds.attack_count) AS attack_count,
       array_agg(DISTINCT CONCAT(ds.devid)) AS devids,
       array_agg(DISTINCT CONCAT(ds.industry, '@', ins.industry_attack_count)) AS industry_count,
       array_agg(DISTINCT CONCAT(ds.country, '@', ds.province, '@', rs.region_attack_count)) AS region_count,
       array_agg(DISTINCT CONCAT(ds.src_log, '@', ls.log_attack_count)) AS src_log_count
FROM
    domain_stat ds
JOIN industry_stats ins ON ds.domain = ins.domain AND ds.industry = ins.industry
JOIN region_stats rs ON ds.domain = rs.domain AND ds.country = rs.country AND ds.province = rs.province
JOIN log_stats ls ON ds.domain = ls.domain AND ds.src_log = ls.src_log
GROUP BY ds.domain, ds.deleted_time;

-- @stmt 5 domain-hit-devnum-cronjob / hive_sql
-- 改动：default.dwb_domain_info → paimon.ti.dwb_ti_domain_info，devid → manage；加 [A2] 的 src_log = 'domain-proxy-svc'（旧表只有 audit 链数据）；
--       default.ods_custom_upload_data → paimon.ti.ods_ti_db_custom_upload_tb_custom_upload_sync（[A3]，列名沿用旧名）；窗口取 start=20260902、end=20261002
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */
       domain, devnum, total_times
FROM (
    SELECT domain,
           COUNT(DISTINCT manage) AS devnum,
           COUNT(manage) AS total_times
    FROM paimon.ti.dwb_ti_domain_info
    WHERE `day` >= 20260902 AND `day` <= 20261002
      AND src_log = 'domain-proxy-svc'
      AND manage NOT IN (
          SELECT str1 AS dev
          FROM paimon.ti.ods_ti_db_custom_upload_tb_custom_upload_sync
          WHERE part1 = 'test_dev' AND part2 = 'test_devid'
      )
    GROUP BY domain
) subquery
WHERE devnum > 10
LIMIT 15000000;

-- @stmt 6 domain-heat-stats-cron-job / second_level_domain.sql
-- 改动：sodl.dwb_sodl_domain_info → paimon.ti.dwb_ti_domain_info，加 [A1] 的 sodl 来源过滤（不含 audit 的 domain-proxy-svc）；
--       == 改 =；rlike 改 REGEXP；双引号改单引号
WITH t AS
  (SELECT domain,
           manage,
           sum(log_num) AS log_num
   FROM paimon.ti.dwb_ti_domain_info
   WHERE `day` = 20260930
     AND src_log IN ('network_security_log', 'dns_log', 'sip_iocstat_log', 'endpoint_security_log', 'url_log')
     AND domain != ''
     AND locate(':', domain) = 0
     AND locate('_', domain) = 0
     AND locate('*', domain) = 0
     AND domain NOT REGEXP '[0-9]$'
     AND domain NOT REGEXP '.arpa$'
   GROUP BY domain,
            manage),
     t2 AS
  (SELECT substring_index(domain, '.', -2) AS sld,
          sum(log_num) AS log_sum,
          count(DISTINCT manage) AS dev_cnt
   FROM t
   GROUP BY substring_index(domain, '.', -2))
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */
       sld AS domain,
       log_sum AS log_cnt,
       dev_cnt
FROM t2
WHERE log_sum > 10;

-- @stmt 7 domain-heat-stats-cron-job / third_level_domain.sql
WITH t AS
  (SELECT domain,
           manage,
           sum(log_num) AS log_num
   FROM paimon.ti.dwb_ti_domain_info
   WHERE `day` = 20260930
     AND src_log IN ('network_security_log', 'dns_log', 'sip_iocstat_log', 'endpoint_security_log', 'url_log')
     AND substring_index(domain, '.', -2) IN ('com.cn', 'org.cn')
   GROUP BY domain,
            manage),
     t2 AS
  (SELECT substring_index(domain, '.', -3) AS parent_domain,
          sum(log_num) AS log_sum,
          count(DISTINCT manage) AS dev_cnt
   FROM t
   GROUP BY substring_index(domain, '.', -3))
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */
       parent_domain AS domain,
       log_sum AS log_cnt,
       dev_cnt
FROM t2
WHERE log_sum > 10;

-- @stmt 8 domain-heat-stats-cron-job / cloud_domain.sql
WITH t AS
  (SELECT domain,
           manage,
           sum(log_num) AS log_sum
   FROM paimon.ti.dwb_ti_domain_info
   WHERE `day` = 20260930
     AND src_log IN ('network_security_log', 'dns_log', 'sip_iocstat_log', 'endpoint_security_log', 'url_log')
     AND substring_index(domain, '.', -2) IN ('amazonaws.com', 'myqcloud.com', 'aliyuncs.com', 'myhuaweicloud.com', 'vercel.app', 'netlify.app', 'glitch.me', 'edgeone.app')
   GROUP BY domain,
            manage)
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */
       domain,
       sum(log_sum) AS log_cnt,
       count(DISTINCT manage) AS dev_cnt
FROM t
GROUP BY domain;

-- @stmt 9 active-domain-elt-job / INFO_EXIST_CHECK_SQL（旧 default.dwb_domain_info）
-- 改动：→ paimon.ti.dwb_ti_domain_info，[A2] src_log = 'domain-proxy-svc'
SELECT 1 FROM paimon.ti.dwb_ti_domain_info
WHERE `day` = 20261001 AND src_log = 'domain-proxy-svc'
LIMIT 1;

-- @stmt 10 active-domain-elt-job / INFO_EXIST_CHECK_SQL（旧 sodl.dwb_sodl_domain_info）
SELECT 1 FROM paimon.ti.dwb_ti_domain_info
WHERE `day` = 20261001
  AND src_log IN ('network_security_log', 'dns_log', 'sip_iocstat_log', 'endpoint_security_log', 'url_log')
LIMIT 1;

-- @stmt 11 active-domain-elt-job / ACTIVE_DOMAIN_SQL
-- 改动：新旧两个域名表的 UNION ALL 合并为单表读取；csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync → ti.ods_ti_db_domain_intelligence_tb_domain_reputation_sync；
--       devid → manage；default.ods_custom_upload_data → paimon.ti.ods_ti_db_custom_upload_tb_custom_upload_sync（[A3]，列名沿用旧名）。
--       不加 src_log 过滤：audit 域名分区 row_key 为 NULL，被 row_key IS NOT NULL 排除，旧 default 分支在 audit 来源上不再有数据（口径变化，见交付说明）
WITH black_dns AS (
SELECT domain,
       regexp_extract(labels, 'category=([^,]+)', 1) AS category,
       regexp_extract(labels, 'family=([^,]+)', 1) AS family,
       regexp_extract(label_details, 'source=([^,]+)', 1) AS source,
       regexp_extract(label_details, 'rule=([^,]+)', 1) AS rule,
       add_time AS addtime
FROM ti.ods_ti_db_domain_intelligence_tb_domain_reputation_sync
WHERE deleted_time = 0
  AND reputation = '0'),
     test_dev AS (
SELECT str1 AS dev1
FROM paimon.ti.ods_ti_db_custom_upload_tb_custom_upload_sync
WHERE part1 = 'test_dev'
  AND part2 = 'test_devid')

SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */
       blackdns,
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
   FROM paimon.ti.dwb_ti_domain_info a
   JOIN black_dns b ON (a.row_key = b.domain)
   WHERE a.`day` = 20261001
     AND a.row_key IS NOT NULL
     AND a.manage NOT IN
       (SELECT dev1
        FROM test_dev)) t
GROUP BY blackdns,
         addtime,
         category,
         family,
         source,
         rule;
