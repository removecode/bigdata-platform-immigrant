-- 剩余 4 个依赖中间表的任务：改造前（Hive / Spark SQL），原文取自 all.sql（DEC-024 以 all.sql 为准），占位符已按 all.sql 注释解出的日期填好
-- 对应改造后：outputs/dwb-consumers-after-starrocks.sql

-- ===== black-ti-context-produce-prc（all.sql L509-515, L517-594, L693-748；ATTACK_IP/MD5 两条按 DEC-030 退出，不含） =====
-- 1) INFO_EXIST_CHECK_SQL (:mday -> 20261001)  -- gates, run first
-- ---------------------------------------------------------------------------
SELECT 1 FROM sodl.dwb_sodl_domain_info WHERE day=20261001 LIMIT 1
;
SELECT 1 FROM sodl.dwb_sodl_ip_info WHERE day=20261001 LIMIT 1
;


-- ---------------------------------------------------------------------------
-- 2) C2_IP_ACTIVE_STAT_SQL  (direction="2", :mday -> 20261001)
-- ---------------------------------------------------------------------------
WITH reputation_ip_stat AS
  (SELECT
      ip,
      port,
      direction,
      expire_time,
      deleted_time,
      attack_count,
      devid,
      "其他" as industry,
      "其他" as country,
      "其他" as province,
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
    WHERE direction="2"
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
        and regexp_extract(dstip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
        and regexp_extract(dstip, '^(0\.|127\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168\.|169\.254\.|192\.0\.0\.|192\.88\.99\.|198\.18\.|198\.19\.|198\.51\.100\.|203\.0\.113\.|224\.|240\.|255\.)') = ''
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
    COLLECT_set(CONCAT(ris.devid)) AS devids,
    COLLECT_set(CONCAT(ris.industry, '@', ins.industry_attack_count)) AS industry_count,
    COLLECT_set(CONCAT(ris.country, '@', ris.province, '@', rs.region_attack_count)) AS region_count,
    COLLECT_set(CONCAT(ris.src_log, '@', ls.log_attack_count)) AS src_log_count
FROM
    reputation_ip_stat ris
JOIN industry_stats ins ON ris.ip=ins.ip AND ris.industry=ins.industry
JOIN region_stats rs ON ris.ip=rs.ip AND ris.country=rs.country AND ris.province=rs.province
JOIN log_stats ls ON ris.ip=ls.ip AND ris.src_log=ls.src_log
GROUP BY ris.ip,
         ris.port,
         ris.direction,
         ris.expire_time,
         ris.deleted_time
;


-- ---------------------------------------------------------------------------
-- 4) DOMAIN_ACTIVE_STAT_SQL  (:mday -> 20261001)
-- ---------------------------------------------------------------------------
WITH domain_stat AS
(SELECT black_reputation_domain.domain,
      black_reputation_domain.deleted_time,
      attack_count,
      devid,
      "其他" as industry,
      "其他" as country,
      "其他" as province,
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
       COLLECT_set(CONCAT(ds.devid)) AS devids,
       COLLECT_set(CONCAT(ds.industry, '@', ins.industry_attack_count)) AS industry_count,
       COLLECT_set(CONCAT(ds.country, '@', ds.province, '@', rs.region_attack_count)) AS region_count,
       COLLECT_set(CONCAT(ds.src_log, '@', ls.log_attack_count)) AS src_log_count
FROM
    domain_stat ds
JOIN industry_stats ins ON ds.domain=ins.domain AND ds.industry=ins.industry
JOIN region_stats rs ON ds.domain=rs.domain AND ds.country=rs.country AND ds.province=rs.province
JOIN log_stats ls ON ds.domain=ls.domain AND ds.src_log=ls.src_log
GROUP BY ds.domain, ds.deleted_time
;


-- ===== domain-hit-devnum-cronjob（all.sql L291-292） =====
SELECT DOMAIN,devnum,total_times FROM (SELECT DOMAIN,COUNT(DISTINCT devid) AS devnum,COUNT(devid) as total_times FROM default.dwb_domain_info WHERE DAY>=20260902 and DAY<=20261002 AND devid NOT IN (SELECT str1 AS dev FROM ods_custom_upload_data WHERE part1='test_dev' AND part2='test_devid') GROUP BY DOMAIN) subquery WHERE devnum > 10 LIMIT 15000000
;

-- ===== domain-heat-stats-cron-job（all.sql L61-135） =====
-- ---------------------------------------------------------------------------
-- 1) second_level_domain.sql   (:day_str -> 20260930)
-- ---------------------------------------------------------------------------
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_num
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =20260930
     AND DOMAIN != ''
     AND locate(":",DOMAIN) == 0
     AND locate("_",DOMAIN) == 0
     AND locate("*",DOMAIN) == 0
     AND DOMAIN NOT rlike "[0-9]$"
     AND DOMAIN NOT rlike ".arpa$"
   GROUP BY DOMAIN,
            MANAGE),
     t2 AS
  (SELECT SUBSTRING_INDEX(DOMAIN,".",-2) AS sld,
          sum(log_num) AS log_sum,
          count(DISTINCT MANAGE) AS dev_cnt
   FROM t
   GROUP BY SUBSTRING_INDEX(DOMAIN,".",-2))
SELECT sld AS domain,
       log_sum AS log_cnt,
       dev_cnt
FROM t2
where log_sum >10
;


-- ---------------------------------------------------------------------------
-- 2) third_level_domain.sql   (:day_str -> 20260930)
-- ---------------------------------------------------------------------------
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_num
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =20260930
   AND SUBSTRING_INDEX(DOMAIN,".",-2) in ("com.cn","org.cn")
   GROUP BY DOMAIN,
            MANAGE),
     t2 AS
  (SELECT SUBSTRING_INDEX(DOMAIN,".",-3) AS parent_domain,
          sum(log_num) AS log_sum,
          count(DISTINCT MANAGE) AS dev_cnt
   FROM t
   GROUP BY SUBSTRING_INDEX(DOMAIN,".",-3))
SELECT parent_domain AS domain,
       log_sum AS log_cnt,
       dev_cnt
FROM t2
where log_sum >10
;


-- ---------------------------------------------------------------------------
-- 3) cloud_domain.sql   (:day_str -> 20260930)
-- ---------------------------------------------------------------------------
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_sum
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =20260930
   AND SUBSTRING_INDEX(DOMAIN,".",-2) in ("amazonaws.com","myqcloud.com","aliyuncs.com","myhuaweicloud.com","vercel.app","netlify.app","glitch.me","edgeone.app")
   GROUP BY DOMAIN,
            MANAGE)
SELECT domain,
        sum(log_sum) AS log_cnt,
        count(DISTINCT MANAGE) AS dev_cnt
FROM t
GROUP BY domain
;

-- ===== active-domain-elt-job（all.sql L372-445） =====
-- ---------------------------------------------------------------------------
-- 1) INFO_EXIST_CHECK_SQL  (:mday -> 20261001)  -- table-exists gate, run first
-- ---------------------------------------------------------------------------
SELECT 1 FROM default.dwb_domain_info WHERE day=20261001 LIMIT 1
;
SELECT 1 FROM sodl.dwb_sodl_domain_info WHERE day=20261001 LIMIT 1
;


-- ---------------------------------------------------------------------------
-- 2) ACTIVE_DOMAIN_SQL  (:start_day -> 20261001)
-- ---------------------------------------------------------------------------
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
FROM default.ods_custom_upload_data
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
   FROM default.dwb_domain_info a
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
         rule
;
