-- DWB 宽表消费业务 SQL 汇编
-- 来源：outputs/sql-source-audit/parsed.json（917 梳理 CSV SQL 快照）
-- 边界：仅 SELECT 快照；不含 sodl_dwb_info / log_compress 生产 SQL
-- SR 改写子集：outputs/all-starrocks.sql（domain-heat～black-ti 等；ctig 在 all-starrocks 中未用 DWB）

-- ========== active-domain-elt-job ==========
-- DWB 表：default.dwb_domain_info, sodl.dwb_sodl_domain_info

-- --- [1] INFO_EXIST_CHECK_SQL | CSV 约 line 3064 ---
-- http://code.sangfor.org/SRI/SCIA/CIPD/DOMAIN/PRE/active-domain-elt-job/blob/master/app-sdk/soapa-sangfor-lib/python/configs/sql.py
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
   WHERE a.day=:start_day
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
   WHERE a.day=:start_day
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

-- --- [2] ACTIVE_DOMAIN_SQL | CSV 约 line 3126 ---
"dwb_domain_info":
        """SELECT 1 FROM default.dwb_domain_info WHERE day=:mday LIMIT 1""",
    "dwb_sodl_domain_info":
        """SELECT 1 FROM sodl.dwb_sodl_domain_info WHERE day=:mday LIMIT 1"""


-- ========== apt-hunting-monitor-process-job ==========
-- 备注：917 更新版标可下线候选；parsed 任务元数据为待确认
-- DWB 表：default.dwb_domain_info, default.dwb_ip_info, default.dwb_md5_info, default.dwb_url_info, sodl.dwb_sodl_domain_info, sodl.dwb_sodl_ip_info, sodl.dwb_sodl_md5_info, sodl.dwb_sodl_url_info

-- --- [1] RETRO_IP_SQL | CSV 约 line 2327 ---
-- http://code.sangfor.org/SRI/SCIA/apt-hunting/apt-hunting-monitor-process-job/blob/master/cron-job/monitor_process/sql.py
-- 解析器：需复核（SQL 正文仍来自 CSV，执行前请对现场版本）
WITH apt_tbl AS
  (SELECT get_json_object(DATA, "$.source") AS SOURCE,
          get_json_object(DATA, "$.raw_ioc_type") AS raw_ioc_type,
          get_json_object(DATA, "$.related_ioc_type") AS related_ioc_type,
          get_json_object(DATA, "$.related_path") AS related_path,
          get_json_object(DATA, "$.organization_label") AS organization_label,
          get_json_object(DATA, "$.related_ioc") AS related_ioc,
          get_json_object(DATA, "$.ti_type") AS ti_type,
          get_json_object(DATA, "$.related_rule_name") AS related_rule_name,
          get_json_object(DATA, "$.raw_ioc") AS raw_ioc,
          get_json_object(DATA, "$.ioc_updater") AS ioc_updater,
          get_json_object(DATA, "$.ioc_submitter") AS ioc_submitter
   FROM csc.ods_csc_apt_hunting
   WHERE task_id=:task_id
     AND ioc_type=:ioc_type ),
     tag_device AS
  (SELECT str1 AS devid,
          str2 AS customer_type
   FROM default.ods_custom_upload_data
   WHERE part1="apt_hunting"
     AND part2="tag_device" ),
     test_device AS
  (SELECT str1 AS devid
   FROM default.ods_custom_upload_data
   WHERE part1="apt_hunting"
     AND part2="test_device" ),
     log_tbl AS
  (SELECT ioc,
          devid,
          log_day,
          collect_set(src_log) AS src_logs,
          sum(log_num) AS log_num
   FROM
     (SELECT dip AS ioc,
             devid AS devid,
             DAY AS log_day,
             src_log,
             log_num
      FROM default.dwb_ip_info LEFT SEMI
      JOIN apt_tbl ON apt_tbl.related_ioc=dwb_ip_info.dip
      WHERE DAY>=:start_day
        AND DAY<=:end_day
        AND extends IS NOT NULL
        AND src_log='log_audit'
        AND devid NOT IN
          (SELECT devid
           FROM test_device)
      UNION ALL SELECT dstip AS ioc,
                       MANAGE AS devid,
                       DAY AS log_day,
                       src_log,
                       log_num
      FROM sodl.dwb_sodl_ip_info LEFT SEMI
      JOIN apt_tbl ON apt_tbl.related_ioc=dwb_sodl_ip_info.dstip
      WHERE DAY>=:start_day
        AND DAY<=:end_day
        AND MANAGE NOT IN
          (SELECT devid
           FROM test_device) ) w1
   GROUP BY ioc,
            devid,
            log_day)
SELECT t2.raw_ioc,
       t2.raw_ioc_type,
       t2.related_ioc,
       t2.related_ioc_type,
       t2.related_rule_name,
       t2.related_path,
       t2.ti_type,
       t2.organization_label,
       t2.source,
       t2.ioc_updater,
       t2.ioc_submitter,
       t2.log_day,
       t2.devid,
       t2.src_logs,
       t2.log_num,
       t2.devids,
       regexp_extract(customer_info,'customer_name=(.+?)[,}]', 1) AS customer_name,
       regexp_extract(customer_info,'country=(.+?)[,}]', 1) AS country,
       regexp_extract(customer_info,'province=(.+?)[,}]', 1) AS province,
       regexp_extract(customer_info,'city=(.+?)[,}]', 1) AS city,
       regexp_extract(customer_info,'customer_industry=(.+?)[,}]', 1) AS customer_industry,
       if(tag_device.customer_type is null, 999, tag_device.customer_type) AS customer_type
FROM
  (SELECT devid,
          src_logs,
          log_num,
          log_day,
          SOURCE,
          raw_ioc_type,
          related_ioc_type,
          related_path,
          organization_label,
          related_ioc,
          ioc_updater,
          ioc_submitter,
          ti_type,
          related_rule_name,
          raw_ioc,
          devids
   FROM
     (SELECT log_tbl.devid,
             src_logs,
             log_num,
             log_day,
             SOURCE,
             raw_ioc_type,
             related_ioc_type,
             related_path,
             organization_label,
             related_ioc,
             ioc_updater,
             ioc_submitter,
             ti_type,
             related_rule_name,
             raw_ioc
      FROM log_tbl
      JOIN apt_tbl ON log_tbl.ioc=apt_tbl.related_ioc) t
   JOIN
     (SELECT ioc,
             count(DISTINCT devid) AS devid_num,
             collect_set(devid) AS devids
      FROM log_tbl
      GROUP BY ioc) t1 ON t.related_ioc=t1.ioc
   WHERE devid_num<=:max_dev_num

-- --- [2] RETRO_DOMAIN_SQL | CSV 约 line 2454 ---
WITH apt_tbl AS
  (SELECT get_json_object(DATA, "$.source") AS SOURCE,
          get_json_object(DATA, "$.raw_ioc_type") AS raw_ioc_type,
          get_json_object(DATA, "$.related_ioc_type") AS related_ioc_type,
          get_json_object(DATA, "$.related_path") AS related_path,
          get_json_object(DATA, "$.organization_label") AS organization_label,
          get_json_object(DATA, "$.related_ioc") AS related_ioc,
          get_json_object(DATA, "$.ti_type") AS ti_type,
          get_json_object(DATA, "$.related_rule_name") AS related_rule_name,
          get_json_object(DATA, "$.raw_ioc") AS raw_ioc,
          get_json_object(DATA, "$.ioc_updater") AS ioc_updater,
          get_json_object(DATA, "$.ioc_submitter") AS ioc_submitter
   FROM csc.ods_csc_apt_hunting
   WHERE task_id=:task_id
     AND ioc_type=:ioc_type ),
     tag_device AS
  (SELECT str1 AS devid,
          str2 AS customer_type
   FROM default.ods_custom_upload_data
   WHERE part1="apt_hunting"
     AND part2="tag_device" ),
     test_device AS
  (SELECT str1 AS devid
   FROM default.ods_custom_upload_data
   WHERE part1="apt_hunting"
     AND part2="test_device" ),
     log_tbl AS
  (SELECT ioc,
          devid,
          log_day,
          collect_set(src_log) AS src_logs,
          sum(log_num) AS log_num
   FROM
     (SELECT DOMAIN AS ioc,
             devid AS devid,
             DAY AS log_day,
             src_log,
             log_num
      FROM default.dwb_domain_info LEFT SEMI
      JOIN apt_tbl ON apt_tbl.related_ioc=dwb_domain_info.domain
      WHERE DAY>=:start_day
        AND DAY<=:end_day
        AND extends IS NOT NULL
        AND src_log='log_audit'
        AND devid NOT IN
          (SELECT devid
           FROM test_device)
      UNION ALL SELECT DOMAIN AS ioc,
                       MANAGE AS devid,
                       DAY AS log_day,
                       src_log,
                       log_num
      FROM sodl.dwb_sodl_domain_info LEFT SEMI
      JOIN apt_tbl ON apt_tbl.related_ioc=dwb_sodl_domain_info.domain
      WHERE DAY>=:start_day
        AND DAY<=:end_day
        AND MANAGE NOT IN
          (SELECT devid
           FROM test_device) ) w1
   GROUP BY ioc,
            devid,
            log_day)
SELECT t2.raw_ioc,
       t2.raw_ioc_type,
       t2.related_ioc,
       t2.related_ioc_type,
       t2.related_rule_name,
       t2.related_path,
       t2.ti_type,
       t2.organization_label,
       t2.source,
       t2.ioc_updater,
       t2.ioc_submitter,
       t2.log_day,
       t2.devid,
       t2.src_logs,
       t2.log_num,
       t2.devids,
       regexp_extract(customer_info,'customer_name=(.+?)[,}]', 1) AS customer_name,
       regexp_extract(customer_info,'country=(.+?)[,}]', 1) AS country,
       regexp_extract(customer_info,'province=(.+?)[,}]', 1) AS province,
       regexp_extract(customer_info,'city=(.+?)[,}]', 1) AS city,
       regexp_extract(customer_info,'customer_industry=(.+?)[,}]', 1) AS customer_industry,
       if(tag_device.customer_type is null, 999, tag_device.customer_type) AS customer_type
FROM
  (SELECT devid,
          src_logs,
          log_num,
          log_day,
          SOURCE,
          raw_ioc_type,
          related_ioc_type,
          related_path,
          organization_label,
          related_ioc,
          ioc_updater,
          ioc_submitter,
          ti_type,
          related_rule_name,
          raw_ioc,
          devids
   FROM
     (SELECT log_tbl.devid,
             src_logs,
             log_num,
             log_day,
             SOURCE,
             raw_ioc_type,
             related_ioc_type,
             related_path,
             organization_label,
             related_ioc,
             ioc_updater,
             ioc_submitter,
             ti_type,
             related_rule_name,
             raw_ioc
      FROM log_tbl
      JOIN apt_tbl ON log_tbl.ioc=apt_tbl.related_ioc) t
   JOIN
(SELECT ioc,
             count(DISTINCT devid) AS devid_num,
             collect_set(devid) AS devids
      FROM log_tbl
      GROUP BY ioc) t1 ON t.related_ioc=t1.ioc
   WHERE devid_num<=:max_dev_num
     OR (devid_num<=:origin_max_dev_num
         AND related_rule_name="origin") ) t2
JOIN default.ods_devicemanager_deviceinfo ON ods_devicemanager_deviceinfo.dev_id=t2.devid
LEFT JOIN tag_device ON t2.devid=tag_device.devid
WHERE ods_devicemanager_deviceinfo.dev_id!=""

-- --- [3] RETRO_MD5_SQL | CSV 约 line 2585 ---
WITH apt_tbl AS
  (SELECT get_json_object(DATA, "$.source") AS SOURCE,
          get_json_object(DATA, "$.raw_ioc_type") AS raw_ioc_type,
          get_json_object(DATA, "$.related_ioc_type") AS related_ioc_type,
          get_json_object(DATA, "$.related_path") AS related_path,
          get_json_object(DATA, "$.organization_label") AS organization_label,
          get_json_object(DATA, "$.related_ioc") AS related_ioc,
          get_json_object(DATA, "$.ti_type") AS ti_type,
          get_json_object(DATA, "$.related_rule_name") AS related_rule_name,
          get_json_object(DATA, "$.raw_ioc") AS raw_ioc,
          get_json_object(DATA, "$.ioc_updater") AS ioc_updater,
          get_json_object(DATA, "$.ioc_submitter") AS ioc_submitter
   FROM csc.ods_csc_apt_hunting
   WHERE task_id=:task_id
     AND ioc_type=:ioc_type ),
     tag_device AS
  (SELECT str1 AS devid,
          str2 AS customer_type
   FROM default.ods_custom_upload_data
   WHERE part1="apt_hunting"
     AND part2="tag_device" ),
     test_device AS
  (SELECT str1 AS devid
   FROM default.ods_custom_upload_data
   WHERE part1="apt_hunting"
     AND part2="test_device" ),
     log_tbl AS
  (SELECT ioc,
          devid,
          log_day,
          collect_set(src_log) AS src_logs,
          sum(log_num) AS log_num
   FROM
     (SELECT md5 AS ioc,
             devid AS devid,
             DAY AS log_day,
             src_log,
             log_num
      FROM default.dwb_md5_info LEFT SEMI
      JOIN apt_tbl ON apt_tbl.related_ioc=dwb_md5_info.md5
      WHERE DAY>=:start_day
        AND DAY<=:end_day
        AND extends IS NOT NULL
        AND src_log='log_audit'
        AND devid NOT IN
          (SELECT devid
           FROM test_device)
      UNION ALL SELECT filehash AS ioc,
                       MANAGE AS devid,
                       DAY AS log_day,
                       src_log,
                       log_num
      FROM sodl.dwb_sodl_md5_info LEFT SEMI
      JOIN apt_tbl ON apt_tbl.related_ioc=dwb_sodl_md5_info.filehash
      WHERE DAY>=:start_day
        AND DAY<=:end_day
        AND MANAGE NOT IN
          (SELECT devid
           FROM test_device) ) w1
   GROUP BY ioc,
            devid,
            log_day)
SELECT t2.raw_ioc,
       t2.raw_ioc_type,
       t2.related_ioc,
       t2.related_ioc_type,
       t2.related_rule_name,
       t2.related_path,
       t2.ti_type,
       t2.organization_label,
       t2.source,
       t2.ioc_updater,
       t2.ioc_submitter,
       t2.log_day,
       t2.devid,
       t2.src_logs,
       t2.log_num,
       t2.devids,
       regexp_extract(customer_info,'customer_name=(.+?)[,}]', 1) AS customer_name,
       regexp_extract(customer_info,'country=(.+?)[,}]', 1) AS country,
       regexp_extract(customer_info,'province=(.+?)[,}]', 1) AS province,
       regexp_extract(customer_info,'city=(.+?)[,}]', 1) AS city,
       regexp_extract(customer_info,'customer_industry=(.+?)[,}]', 1) AS customer_industry,
       if(tag_device.customer_type is null, 999, tag_device.customer_type) AS customer_type
FROM
  (SELECT devid,
          src_logs,
          log_num,
          log_day,
          SOURCE,
          raw_ioc_type,
          related_ioc_type,
          related_path,
          organization_label,
          related_ioc,
          ioc_updater,
          ioc_submitter,
          ti_type,
          related_rule_name,
          raw_ioc,
          devids
   FROM
     (SELECT log_tbl.devid,
             src_logs,
             log_num,
             log_day,
             SOURCE,
             raw_ioc_type,
             related_ioc_type,
             related_path,
             organization_label,
             related_ioc,
             ioc_updater,
             ioc_submitter,
             ti_type,
             related_rule_name,
             raw_ioc
      FROM log_tbl
      JOIN apt_tbl ON log_tbl.ioc=apt_tbl.related_ioc) t
   JOIN
  (SELECT ioc,
             count(DISTINCT devid) AS devid_num,
             collect_set(devid) AS devids
      FROM log_tbl
      GROUP BY ioc) t1 ON t.related_ioc=t1.ioc
   WHERE devid_num<=:max_dev_num
     OR (devid_num<=:origin_max_dev_num
         AND related_rule_name="origin") ) t2
JOIN default.ods_devicemanager_deviceinfo ON ods_devicemanager_deviceinfo.dev_id=t2.devid
LEFT JOIN tag_device ON t2.devid=tag_device.devid
WHERE ods_devicemanager_deviceinfo.dev_id!=""

-- --- [4] RETRO_URL_SQL | CSV 约 line 2716 ---
-- 解析器：需复核（SQL 正文仍来自 CSV，执行前请对现场版本）
WITH apt_tbl AS
  (SELECT get_json_object(DATA, "$.source") AS SOURCE,
          get_json_object(DATA, "$.raw_ioc_type") AS raw_ioc_type,
          get_json_object(DATA, "$.related_ioc_type") AS related_ioc_type,
          get_json_object(DATA, "$.related_path") AS related_path,
          get_json_object(DATA, "$.organization_label") AS organization_label,
          get_json_object(DATA, "$.related_ioc") AS related_ioc,
          split(get_json_object(DATA, "$.related_ioc"), "[?]")[0] AS related_ioc_deal,
          get_json_object(DATA, "$.ti_type") AS ti_type,
          get_json_object(DATA, "$.related_rule_name") AS related_rule_name,
          get_json_object(DATA, "$.raw_ioc") AS raw_ioc,
          get_json_object(DATA, "$.ioc_updater") AS ioc_updater,
          get_json_object(DATA, "$.ioc_submitter") AS ioc_submitter
   FROM csc.ods_csc_apt_hunting
   WHERE task_id=:task_id
     AND ioc_type=:ioc_type ),
     tag_device AS
  (SELECT str1 AS devid,
          str2 AS customer_type
   FROM default.ods_custom_upload_data
   WHERE part1="apt_hunting"
     AND part2="tag_device" ),
     test_device AS
  (SELECT str1 AS devid
   FROM default.ods_custom_upload_data
   WHERE part1="apt_hunting"
     AND part2="test_device" ),
     log_tbl AS
  (SELECT ioc,
          devid,
          log_day,
          collect_set(src_log) AS src_logs,
          sum(log_num) AS log_num
   FROM
     (SELECT url AS ioc,
             devid AS devid,
             DAY AS log_day,
             src_log,
             log_num
      FROM default.dwb_url_info LEFT SEMI
      JOIN apt_tbl ON apt_tbl.related_ioc=dwb_url_info.url
      WHERE DAY>=:start_day
        AND DAY<=:end_day
        AND extends IS NOT NULL
        AND src_log='log_audit'
        AND devid NOT IN
          (SELECT devid
           FROM test_device)
      UNION ALL SELECT url AS ioc,
                       MANAGE AS devid,
                       DAY AS log_day,
                       src_log,
                       log_num
      FROM sodl.dwb_sodl_url_info LEFT SEMI
      JOIN apt_tbl ON apt_tbl.related_ioc=dwb_sodl_url_info.url
      WHERE DAY>=:start_day
        AND DAY<=:end_day
        AND MANAGE NOT IN
          (SELECT devid
           FROM test_device) ) w1
   GROUP BY ioc,
            devid,
            log_day)
SELECT t2.raw_ioc,
       t2.raw_ioc_type,
       t2.related_ioc,
       t2.related_ioc_type,
       t2.related_rule_name,
       t2.related_path,
       t2.ti_type,
       t2.organization_label,
       t2.source,
       t2.ioc_updater,
       t2.ioc_submitter,
       t2.log_day,
       t2.devid,
       t2.src_logs,
       t2.log_num,
       t2.devids,
       regexp_extract(customer_info,'customer_name=(.+?)[,}]', 1) AS customer_name,
       regexp_extract(customer_info,'country=(.+?)[,}]', 1) AS country,
       regexp_extract(customer_info,'province=(.+?)[,}]', 1) AS province,
       regexp_extract(customer_info,'city=(.+?)[,}]', 1) AS city,
       regexp_extract(customer_info,'customer_industry=(.+?)[,}]', 1) AS customer_industry,
       if(tag_device.customer_type is null, 999, tag_device.customer_type) AS customer_type
FROM
  (SELECT devid,
          src_logs,
          log_num,
          log_day,
          SOURCE,
          raw_ioc_type,
          related_ioc_type,
          related_path,
          organization_label,
          related_ioc,
          ioc_updater,
          ioc_submitter,
          ti_type,
          related_rule_name,
          raw_ioc,
          devids
   FROM
     (SELECT log_tbl.devid,
             src_logs,
             log_num,
             log_day,
             SOURCE,
             raw_ioc_type,
             related_ioc_type,
             related_path,
             organization_label,
             related_ioc,
             related_ioc_deal,
             ioc_updater,
             ioc_submitter,
             ti_type,
             related_rule_name,
             raw_ioc
      FROM log_tbl
      JOIN apt_tbl ON log_tbl.ioc=apt_tbl.related_ioc_deal) t
   JOIN
     (SELECT ioc,
             count(DISTINCT devid) AS devid_num,
             collec


-- ========== black-file-clean-cronjob ==========
-- DWB 表：default.dwb_md5_info, sodl.dwb_sodl_md5_info

-- --- [1] (未命名) | CSV 约 line 2159 ---
-- http://code.sangfor.org/SRI/SCIA/FCC/black-file-clean-cronjob/blob/master/cron-job/black_file_clean/statistic.py
SELECT DISTINCT lower(md5)
FROM default.dwb_md5_info
WHERE day=20250826
AND src_log='log_audit'
AND attr='0'
AND length(md5)=32
UNION
SELECT DISTINCT lower(filehash)
FROM sodl.dwb_sodl_md5_info
WHERE day=20250826
AND producttype='EDR'
AND src_log='endpoint_security_log'
AND threatclass=209
AND threattype!=13 -- 13->botnet
AND file_attr='0'
AND length(filehash)=32


-- ========== black-ti-context-produce-prc ==========
-- DWB 表：default.dwb_md5_info, sodl.dwb_sodl_domain_info, sodl.dwb_sodl_ip_info, sodl.dwb_sodl_md5_info

-- --- [1] C2_IP_ACTIVE_STAT_SQL | CSV 约 line 3131 ---
-- http://code.sangfor.org/SRI/SCIA/TIBAE/black-ti-context-produce-prc/blob/master/app-sdk/soapa-sangfor-lib/python/active_info_update/config/active_stat_sql.py
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
      WHERE DAY=:mday
        and src_log in ('sip_iocstat_log', 'network_security_log')
        and dstip !=''
        and dstip not in ('8.8.8.8', '8.8.4.4','114.114.114.114', '114.114.115.115', '119.29.29.29', '223.5.5.5', '223.6.6.6', '1.1.1.1', '1.0.0.1')
        and regexp_extract(dstip,'^(\\\d{1,3}\\\.\\\d{1,3}\\\.\\\d{1,3}\\\.\\\d{1,3})$') != ''
        and regexp_extract(dstip, '^(0\\\.|127\\\.|10\\\.|172\\\.1[6-9]\\\.|172\\\.2[0-9]\\\.|172\\\.3[01]\\\.|192\\\.168\\\.|169\\\.254\\\.|192\\\.0\\\.0\\\.|192\\\.88\\\.99\\\.|198\\\.18\\\.|198\\\.19\\\.|198\\\.51\\\.100\\\.|203\\\.0\\\.113\\\.|224\\\.|240\\\.|255\\\.)') = ''
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

-- --- [2] ATTACK_IP_ACTIVE_STAT_SQL | CSV 约 line 3206 ---
WITH black_reputation_ip AS (
    SELECT 
        ip, 
        port,
        direction,
        expire_time,
        deleted_time
    FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
    WHERE direction="1"
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
                      OR length(industry) = 0 THEN "其他"
                 ELSE industry
             END AS industry,
             CASE
                 WHEN country IS NULL
                      OR length(country) = 0 THEN "其他"
                 ELSE country
             END AS country,
             CASE
                 WHEN province IS NULL
                      OR length(province) = 0 THEN "其他"
                 ELSE province
             END AS province,
             COALESCE(CAST(threatclass AS STRING), '0') AS src_log,
             srcip AS sip
      FROM sodl.dwb_sodl_ip_info
      WHERE DAY=:mday
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
            COLLECT_set(CONCAT(devid)) AS devids,
            COLLECT_set(CONCAT(industry, '@', industry_attack_count)) AS industry_count,
            COLLECT_set(CONCAT(country, '@', province, '@', region_attack_count)) AS region_count,
            COLLECT_set(CONCAT(src_log, '@', log_attack_count)) AS src_log_count
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
              deleted_time) b

-- --- [3] DOMAIN_ACTIVE_STAT_SQL | CSV 约 line 3297 ---
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
      WHERE DAY=:mday
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

-- --- [4] MD5_ACTIVE_STAT_SQL | CSV 约 line 3350 ---
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
     AND DAY=:mday
   UNION ALL SELECT md5,
                    devid,
                    attack_count,
                    industry,
                    country,
                    province
   FROM default.dwb_md5_info
   WHERE src_log='log_audit'
     AND SOURCE='file_hash'
     AND attr='0'
     AND DAY=:mday)
SELECT base_stat.md5,
       base_stat.attack_count,
       base_stat.devids,
       industry_count,
       region_count
FROM
  (SELECT md5,
          sum(attack_count) AS attack_count,
          collect_list(concat(devid)) AS devids
   FROM md5_stat
   GROUP BY md5) base_stat
JOIN
  (SELECT md5,
          collect_list(concat(industry, '@', attack_count)) AS industry_count
   FROM
     (SELECT md5,
             CASE
                 WHEN industry IS NULL
                      OR length(industry) = 0 THEN "其他"
                 ELSE industry
             END AS industry,
             sum(attack_count) AS attack_count
      FROM md5_stat
      GROUP BY md5,
               industry) industry_temp
   GROUP BY md5) industry_stat ON base_stat.md5 = industry_stat.md5
JOIN
  (SELECT md5,
          collect_list(concat(country, '@', province, '@', attack_count)) AS region_count
   FROM
     (SELECT md5,
             CASE
                 WHEN country IS NULL
                      OR length(country) = 0 THEN "其他"
                 ELSE country
             END AS country,
             CASE
                 WHEN province IS NULL
                      OR length(province) = 0 THEN "其他"
                 ELSE province
             END AS province,
             sum(attack_count) AS attack_count
      FROM md5_stat
      GROUP BY md5,
               country,
               province) region_temp
   GROUP BY md5) region_stat ON base_stat.md5 = region_stat.md5

-- --- [5] INFO_EXIST_CHECK_SQL | CSV 约 line 3420 ---
SELECT 1 FROM sodl.dwb_sodl_domain_info WHERE day=:mday LIMIT 1        SELECT 1 FROM sodl.dwb_sodl_ip_info WHERE day=:mday LIMIT 1            SELECT count(1) FROM (SELECT 1 FROM sodl.dwb_sodl_md5_info 
        WHERE src_log='endpoint_security_log' AND file_attr='0' AND DAY=:mday LIMIT 1) t LIMIT 1             SELECT count(1) FROM (SELECT 1 FROM default.dwb_md5_info 
        WHERE src_log='log_audit' AND SOURCE='file_hash' AND attr='0' AND DAY=:mday LIMIT 1) t LIMIT 1


-- ========== ctig-report-data-analysis-prc ==========
-- DWB 表：sodl.dwb_sodl_domain_info, sodl.dwb_sodl_ip_info

-- --- [1] STAT_SQL | CSV 约 line 2854 ---
WITH black_reputation_domain as(
	SELECT 
        domain, 
        concat_ws(
            '|',
            regexp_extract(labels, 'category=([^,}}]+)', 1),
            regexp_extract(labels, 'family=([^,}}]+)', 1)
        )as label,
        threat_level,
        add_time,
		update_time
    FROM csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync
    WHERE reputation = '0'
	  AND deleted_time = 0
),
black_reputation_ip as(
	SELECT 
        ip, 
        concat_ws(
            '|',
            regexp_extract(labels, 'category=([^,}}]+)', 1),
            regexp_extract(labels, 'family=([^,}}]+)', 1)
        )as label,
        threat_level,
        add_time,
		update_time
    FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
    WHERE reputation = '0'
		  AND direction='2'
          AND port=0 
		  AND deleted_time=0
),
tenant_info as(
    SELECT DISTINCT
        t.tenant_id,
        t.device_id,
        d.device_id_encryption            
    FROM csc.ods_csc_tb_tenant_subscribe_info t
    LATERAL VIEW OUTER explode(split(t.device_id_encryption, ',')) d AS device_id_encryption
    where tenant_id in ({tenant_ids})
),
domain_filtered_log as(
    select 
        tenant_info.tenant_id,
        tenant_info.device_id,
        log_info.day,
        log_info.srcip,
        log_info.domain as ioc,
        sum(log_info.log_num) as log_num,
		black_reputation_domain.add_time,
        black_reputation_domain.label,
        black_reputation_domain.threat_level
    from
	(
	SELECT
		day,
		srcip, 
		manage as device_id, 
		domain,
		log_num,
		row_key
	FROM sodl.dwb_sodl_domain_info
	WHERE day BETWEEN {start_time} and {end_time}
		and row_key != ''
		-- 云情报网关日志
		and producttype = 'AF' 
		and src_log = 'network_security_log'
		and reqruleid BETWEEN '140000000' AND '149999999'
	) log_info 
	JOIN tenant_info ON log_info.device_id = tenant_info.device_id_encryption
	JOIN black_reputation_domain ON black_reputation_domain.domain = log_info.row_key
	group by 
	    tenant_info.tenant_id,
        tenant_info.device_id,
        log_info.day,   
        log_info.srcip,
        log_info.domain,
		black_reputation_domain.add_time,
        black_reputation_domain.label,
        black_reputation_domain.threat_level
),
ip_filtered_log as(
    select 
        tenant_info.tenant_id,
        tenant_info.device_id,
        log_info.day,
        log_info.srcip,
        log_info.dstip as ioc,
        sum(log_info.log_num) as log_num,
		black_reputation_ip.add_time,
        black_reputation_ip.label,
        black_reputation_ip.threat_level
    from
	(
	SELECT
		day,
		srcip, 
		manage as device_id, 
		dstip,
		log_num
	FROM sodl.dwb_sodl_ip_info
	WHERE day BETWEEN {start_time} and {end_time}
		-- 云情报网关日志
		and producttype = 'AF' 
		and src_log = 'network_security_log'
		and reqruleid BETWEEN '140000000' AND '149999999'
		-- 排除非法IP
		and dstip !=''
		and dstip not in ('8.8.8.8', '8.8.4.4','114.114.114.114', '114.114.115.115', '119.29.29.29', '223.5.5.5', '223.6.6.6', '1.1.1.1', '1.0.0.1')
		and dstip RLIKE '^([0-9]{{1,3}}\\\.){{3}}[0-9]{{1,3}}$'
		and dstip NOT RLIKE '^(0\\\.|127\\\.|10\\\.|172\\\.(1[6-9]|2[0-9]|3[01])\\\.|192\\\.168\\\.)'
	) log_info 
	JOIN tenant_info ON log_info.device_id = tenant_info.device_id_encryption
	JOIN black_reputation_ip ON black_reputation_ip.ip = log_info.dstip
	group by 
	    tenant_info.tenant_id,
        tenant_info.device_id,
        log_info.day,   
        log_info.srcip,
        log_info.dstip,
		black_reputation_ip.add_time,
        black_reputation_ip.label,
        black_reputation_ip.threat_level
),
data_stat AS(
  SELECT *
  FROM  domain_filtered_log
  union all
  SELECT *
  FROM  ip_filtered_log
),
ip_rpt_update_stat as(
	SELECT 
		count(1) as rpt_update_num
	FROM black_reputation_ip
	WHERE update_time > CAST(unix_timestamp('{start_time}', 'yyyyMMdd') * 1000 AS BIGINT)
),
domain_rpt_update_stat as(
	SELECT 
		count(1) as rpt_update_num
	FROM black_reputation_domain
	WHERE update_time > CAST(unix_timestamp('{start_time}', 'yyyyMMdd') * 1000 AS BIGINT)
),
url_rpt_update_stat as(
	SELECT 
		count(1) as rpt_update_num
	FROM csc.ods_csc_db_url_intelligence_tb_url_reputation_sync
    WHERE update_time > CAST(unix_timestamp('{start_time}', 'yyyyMMdd') * 1000 AS BIGINT)
      and deleted_time=0  and scene='malice'
),
file_rpt_update_stat as(
	SELECT 
		count(1) as rpt_update_num
	FROM sri.ods_sri_hashinfo
    WHERE 
        CAST(regexp_extract(update_time, '\\\:\\\s*([0-9]+)', 1) AS BIGINT) > CAST(unix_timestamp('{start_time}', 'yyyyMMdd') * 1000 AS BIGINT)
),
day_stat as(
	select
	    tenant_id,
		day,
		sum(log_num) as log_num
	from data_stat
	group by tenant_id, day
),
log_stat as(
	select
	    tenant_id,
		srcip, 
		device_id, 
		ioc, 
		sum(log_num) as log_num, 
		add_time, 
		label, 
		threat_level
	from data_stat
	group by tenant_id, srcip, device_id, ioc, add_time, label, threat_level
)


select
	t1.tenant_id,
	t3.rpt_update_num,
	t2.log_stat_arr,
	t1.day_stat_arr
from
(
	select 
		tenant_id,
		collect_list(concat_ws(',', cast(day as string), cast(log_num as string))) AS day_stat_arr
	from day_stat
	group by tenant_id
) t1
join 
(
	select 
		tenant_id,
		collect_list(
			concat_ws(',',srcip,device_id, ioc,cast(log_num as string),cast(add_time as string),label,threat_level)
		)as log_stat_arr
	from log_stat
	group by tenant_id

)t2 on t1.tenant_id = t2.tenant_id
cross join
(
	select (ip_rpt_update_stat.rpt_update_num + domain_rpt_update_stat.rpt_update_num + url_rpt_update_stat.rpt_update_num + file_rpt_update_stat.rpt_update_num) as rpt_update_num
	from ip_rpt_update_stat, domain_rpt_update_stat, url_rpt_update_stat, file_rpt_update_stat
	limit 1
) t3


-- ========== domain-heat-stats-cron-job ==========
-- DWB 表：sodl.dwb_sodl_domain_info

-- --- [1] cloud_domain.sql | CSV 约 line 2267 ---
-- http://code.sangfor.org/SRI/SCIA/FRAME/assembly-workshop/blob/master/cipd/domain-heat-stats-cron-job/app-cfg/ShenZhen-product/cloud_domain.sql
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_sum
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =:day_str
   AND SUBSTRING_INDEX(DOMAIN,".",-2) in ("amazonaws.com","myqcloud.com","aliyuncs.com","myhuaweicloud.com","vercel.app","netlify.app","glitch.me","edgeone.app")
   GROUP BY DOMAIN,
            MANAGE)
SELECT domain,
        sum(log_sum) AS log_cnt,
        count(DISTINCT MANAGE) AS dev_cnt
FROM t
GROUP BY domain

-- --- [2] second_level_domain.sql | CSV 约 line 2281 ---
-- http://code.sangfor.org/SRI/SCIA/FRAME/assembly-workshop/blob/master/cipd/domain-heat-stats-cron-job/app-cfg/ShenZhen-product/second_level_domain.sql
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_num
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =:day_str
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

-- --- [3] third_level_domain.sql | CSV 约 line 2306 ---
-- http://code.sangfor.org/SRI/SCIA/FRAME/assembly-workshop/blob/master/cipd/domain-heat-stats-cron-job/app-cfg/ShenZhen-product/second_level_domain.sql
WITH t AS
  (SELECT DOMAIN,
           MANAGE,
           sum(log_num) AS log_num
   FROM sodl.dwb_sodl_domain_info
   WHERE DAY =:day_str
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


-- ========== domain-hit-devnum-cronjob ==========
-- DWB 表：default.dwb_domain_info

-- --- [1] hive_sql | CSV 约 line 2116 ---
-- http://code.sangfor.org/SRI/SCIA/ATI/IOC-PRODUCT/domain-hit-devnum-cronjob/blob/master/unittest/data/app_cfg.json
SELECT DOMAIN,devnum,total_times FROM (SELECT DOMAIN,COUNT(DISTINCT devid) AS devnum,COUNT(devid) as total_times FROM default.dwb_domain_info WHERE DAY>=20250728 and DAY<=20250827 AND devid NOT IN (SELECT str1 AS dev FROM ods_custom_upload_data WHERE part1='test_dev' AND part2='test_devid') GROUP BY DOMAIN) subquery WHERE devnum > 10 LIMIT 15000000


-- ========== thug-task-monitor-prc ==========
-- 备注：917：已下线
-- DWB 表：default.dwb_domain_info, sodl.dwb_sodl_domain_info

-- --- [1] (未命名) | CSV 约 line 1446 ---
-- http://code.sangfor.org/SRI/SCIA/TIBFE/thug-task-monitor-prc/blob/master/hive_source/hive_feed.py
SELECT DISTINCT domain
FROM
(SELECT DISTINCT domain
FROM default.dwb_domain_info
WHERE DAY='20240401'
AND src_log='log_audit'
UNION ALL SELECT DISTINCT domain
FROM sodl.dwb_sodl_domain_info
WHERE DAY='20240401' ) t
WHERE (
domain regexp '(95598|hdcvi|nevint|oneplus|oppomobile|1hai|fawjiefang|cmburl|cmbur1|roewe|shcmct|zpmc|snerdi|dgspda|ihr\.dfl|ccccyhj|shecltd|cccclc|cnnc|sinointl|yituogroup|ippr|sinochem|cwcec|ccccitg|picc|cict|norinco|china|comac|ccecc|cntcc|cscec|flight|cma\.cn|cnooc|cfbpc|ynyc|crmsc|cetc13|cee.{0,1}group|dzp\.tv|scyt|cqyta|cpplb|shenhua|jspdi|acae|cggcintl|cggc|aiapi|rai[l1]way|crsc|cnechc|ccfcc|caiga|myvessel|crsg|cr11gbim|cec\-cn|crreg|crmrc|gzdex|tobacco|jhscm|doduotrip|sundray|fsyz|huaqin|xsyxapp|mengniu|tiantanbio|bmncc|beiben|mixcweb|crland|ts\.gd\.cn|superknow|xyfybjy|lndtc|bojx|gynybx|sdic|spicsx|spic|ceic|e\-chn|600795|sdic|cydl|sgydifc|wmmotors|wm\-oa\.|cambricon|15331|pamarkets|acura|zygs|95522|energy|hbny|midea|tpri|epcc|cydl|ycpc|ynjt|wbmining|citic|idcpc|cfhi|caict|csgc|openaboc|chng|mail\.csg|cicc|caep|cnbm|ccss|pric|cneic|cmbc|iwhr|celap|ceiec|cssn|avic|cnaf|csoa|ccs\.org|csscgc|cosco|cmc\.com|psbcoa|yhzqjj|cgwic|locpg|cetc|catic|zhongyugas|csic|ebscn|idcpc|srrc|snpsc|cnipa|taiji|bank|sio\.org|qxslab).+'
OR domain regexp '(mail|mai1|rnail).*(airforce|auth|account|check|core|count|cout|document|edu|gov|login|logon|info|online|server|sevr|site|software|support|upgrad|update|valid|verif)'
OR domain regexp '(mai1|mail|rnail|count).*(126|163).*(com\.|serve|system|member|download|login|logon|website|solution|core|support|quest)'
OR domain regexp '^(www\.){0,1}[a-zA-Z]*(126|163|l63|l26|sina)\-*[a-zA-Z]*\.[a-z]{3,10}$'
OR domain regexp '(gov\.cn|edu\.cn|gov\-cn|edu\-cn|educn|govcn|checkmail|checkurl|coremail|cstnet|jspsession|mai1\.|maill\.|rnail|smail|e\-mail|mailbox|mail\-box).+'
OR domain regexp '(account|auth|check|info|login|logon|mail|upgrad|update|verif).*(airforce|auth|account|check|core|count|cout|document|edu|gov|login|logon|info|mail|online|server|sevr|site|software|support|upgrad|update|valid|verif)'
OR domain regexp '(mail|mai1|rnail|gov|edu|account|auth|check|login|logon|support|upgrad|update|verif|neteas|bit|buaa|buct|caac|cae|cags|cap|cass|caic|cati|ccpi|ccs|cdi|cdu|ceie|ciae|cidca|citi|cmc|cmec|cmu|cnbm|cnsa|cos|cohc|cpmiec|cqu|csoc|cssc|cstnet|csu|cxxc|czec|dlmu|ecut|fmmu|fudan|fzu|gdei|huawei|hit|hwacreate|hydro|jari|jlu|jspi|lswz|maii|maric|miit|mil|mfa|most|muc|ndrc|maric|mod|mof|mohurd|most|mot|msa|nanhai|ncu|nea|nepa|nepu|nju|nudt|nsfc|nuaa|nudt|nwpu|paec|pak|piesat|pku|pof|poly|power|rcu|ruc|sass|sasac|sco|scu|sdu|shu|szu|shisu|sino|sina|sjtu|slaf|smg|snepc|snerdi|sohu|south|spacestar|suparco|swip|tianjiao|tongji|tsinghua|wbminig|xhtc|xisu|xjtu|xmu|xpsrchvw|yicai|10086|gov\.cn|edu\.cn|gov\-cn|edu\-cn|govcn|educn).+netlify.app'
OR domain regexp '(mail|mai1|rnail|account|auth|check|info|login|logon|upgrad|update|verif).*(bit|buaa|buct|caac|cae|cags|cap|cass|caic|cati|ccpi|ccs|cdi|cdu|ceie|ciae|cidca|citi|cmc|cmec|cmu|cnbm|cnsa|cos|cohc|cpmiec|cqu|csoc|cssc|cstnet|csu|cxxc|czec|dlmu|ecut|fmmu|fudan|fzu|gdei|huawei|hit|hwacreate|hydro|jari|jlu|jspi|lswz|maii|maric|miit|mil|mfa|most|muc|ndrc|maric|mod|mof|mohurd|most|mot|msa|nanhai|ncu|nea|nepa|nepu|nju|nudt|nsfc|nuaa|nudt|nwpu|paec|pak|piesat|pku|pof|poly|power|rcu|ruc|sass|sasac|sco|scu|sdu|shu|szu|shisu|sino|sina|sjtu|slaf|smg|snepc|snerdi|sohu|south|spacestar|suparco|swip|tianjiao|tongji|tsinghua|wbminig|xhtc|xisu|xjtu|xmu|xpsrchvw|yicai|10086).+'
OR domain regexp '(bit|buaa|buct|caac|cae|cags|cap|cass|caic|cati|ccpi|ccs|cdi|cdu|ceie|ciae|cidca|citi|cmc|cmec|cmu|cnbm|cnsa|cos|cohc|cpmiec|cqu|csoc|cssc|cstnet|csu|cxxc|czec|dlmu|ecut|fmmu|fudan|fzu|gdei|huawei|hit|hwacreate|hydro|jari|jlu|jspi|lswz|maii|maric|miit|mil|mfa|most|muc|ndrc|maric|mod|mof|mohurd|most|mot|msa|nanhai|ncu|nea|nepa|nepu|nju|nudt|nsfc|nuaa|nudt|nwpu|paec|pak|piesat|pku|pof|poly|power|rcu|ruc|sass|sasac|sco|scu|sdu|shu|szu|shisu|sino|sina|sjtu|slaf|smg|snepc|snerdi|sohu|south|spacestar|suparco|swip|tianjiao|tongji|tsinghua|wbminig|xhtc|xisu|xjtu|xmu|xpsrchvw|yicai|10086).*(mail|mai1|rnail|account|auth|check|info|login|logon|upgrad|update|verif).+'
)
AND NOT (
domain regexp '.+(localdomain|addr-in|host|local|dhcp|internal|novalocal|lan|yumfastupdate\.com|v6lvs\.com|gov\.cn|edu\.cn|e5\.sk
et\.cn|cn\.cn|getcacheddhcpresultsforcurrentconfig|home|googlesyndication\.com|googlebot\.com|googlevideo\.com|googleapis\.com|steelyard\.ca|e5\.sk|edu.hk|baiduyuncdn\.net|baiduyuncdn\.com|baidu\.com\.hk|xn\-\-fiqs8s|chinayuanwang\.com|fudan\.edu\.cn.{3,7}|xtepchina\.com\.cn|chinabulker\.com|heisino\.com|china\-tg\.com|navchina\.com|btrchina\.com|.chinabed\.com|jcdecaux\.org|ewpower\.com|sinomab\.com|mercadopago\.com\.pe|glpoly\.net|ccpit\.org|powerleader\.yongda|chinatat\.org|cansinotech\.com|brightmail\.com|armchina\.com|dnssina\.com|china\-goldcard\.com|sinopharm\-xs\.com|huawei\-3com\.com|amazonaws\.com|citicicc\.com|chinatat\.net|china\-atep\.org|qq\.com|chinacamel\.net|chinaunionpay\.net|rendachina\.com|smnchina\.com|kingsoonchina\.com|shenmapower\.com|vxichina\.com|chinapayhongkong\.com|com\.workgroup|avicbj\.ad|hansong\-china\.com|citicdameng\.com|tendawifi\.com|brain\-power\.net|steamgamepowered\.com|sohu\.com|huawei\-cacahe\.me|chinatelecom\-h\.com|huawei\.com|youthscape\.info|sinobo\.com|chinamobile\.com|sinopec\.ad|com\.airdream|snptc\-snerdi\.com|icloud\.com|greatpower\.com|cdeledu\.net|cloudfront\.net|testingbigaccountcooldomainname\.info|cdeledu\.cc|myqcloud\.com|chinatelecomglobal\.com|itatedu\.org|shxd\-power\.com|powersite\-group\.com|mediatonic\.games|daguo\.art|chinahaoke\.cn|china\-ncdn\-nrds\.com|sinaapp\.com|citicso\.com|websitemachines\.com|tdnsv6\.com|vsassets\.io|cmbchina\.com|ippr\.net|dhcp01\.com|dnsv1\.com|huaweicloudwaf\.com|china\-putian\.com|9sys\.com|chinawayltd\.com|8y4\.nl|awesomeads\.tech|aig\-china\.com|idazoo\.com|xolift\.com|cn\.workgroup|sfdomain\.com|intranet\.sinotrans|com\.tgs\-wlan\-user|whecloud\.com|aigcardchina\.com|xn\-\-mkr821lya63v\.xn\-\-io0a7i|kayo\-poweroak\.com|nongxinyin\.xn\-\-ses554g|sohuplus\.cn|aigchinaonline\.com|ylaee\.net|techpower\.com|sau6\.com|xn\-\-vuqy5bh45fvycbsa125h\.net|dcloudstc\.com|sec\.com|tonic\-u\.com|aigchinaservices\.com|xn\-\-bnqzyq5bz03bqtz6bel30c\.xn\-\-io0a7i|co\.uk|china\-cdn\-net\.com|avicil\.com|aigchina\.com|enseval\.com|gov\.my|admin\.totolink|tbtx\-inc\.net|corpnet\.asus|airguilingroup\.net|myhuaweicloud\.com|estudychinese\.net|miiee\.net|onewocloud\.cn|empower6\.com|cndevmode\.action|xn\-\-vuqy5b6z6k\.net|10086\.cn|cdel\.net|thusem\.org|xinhuahos\.com|com\.dxhzx|watts\.corp|sina\.cn|com\.blinkap|estudychinese\.org|glbus\.net|com\.router|wjgslb\.com|chinaman\.cc|sagames\.com|fornitebattleroyale\.com|sinaimg\.cn|jxt\-china\.com|aigchinasupport\.com|tdd\.la|highpower\.com|com\.cflogin|com\.tw|baidu360qqo\.com|paddypower\.it|toufu321\.com|ght\.com|casinoservices\.io|www\.hngoldenspring|comfavicon\.ico|qiniudns\.com|homearch\.store|sinaedge\.com|1baidu\.com|cnedu\.net|chinaccs\.com|aljchina\.com|smgtech\.net|bbwdjw\.cn|pkucc\.cf|xn\-\-ruqr73cqme32ql0hovx\.net|datorama\.io|jjy\.com|rtyu66\.cn|battle\-cars\.com|yunduncdn\.com|decentraland\.org|uestc\.cn|transmedchina\.com|shuzidao\.net|czptzy\.top|empower3\.com|septwolves\.com|gdsn\.com|chinayasha\.com|avic\.com|gz\-spi\.com|china\.xtep|testingbigaccountcooldomainname5\.info|arrival\.co|chinabihai\.com|abchinalife\.com|napoleoncasino\.be|com\.wifi|braintree\.tools|ftabchina\.com|pricelessspecials\.nl|erty35\.cn|polygon\.technology|iat\-guest\.com|meralcopowergen\.com|aigcredit\-china\.com|south\.am|ikarem\.io|xxit\.asia|xn\-\-fiq1px5rlkpgnktzt\.xn\-\-55qx5d|youxunpan\.net|com\.ralinkap|qf2002\.net|qywt\.net|iyu\-china\.com|xn\-\-vuqy5b910av5l2r3c\.xn\-\-ses554g|aigcreditchina\.com|xn\-\-tnqy50b\.net|cscecpower\.com|jufel\.net|homearch\.vip|homearch\.shop|com\.tendaap|com\.gaokeap|coolshow\.net|liyupower\.com|teamviewer\.com)$'
OR domain regexp 'recommend_list\.baidu\.com|accounts\.google\.com\.|ada\.baidu\.com\.|adservice\.google\.com\.|afd\.baidu\.com\.|afdconf\.baidu\.com\.|ajax-googleapis\.|als\.baidu\.com\.|\.aspmx\.l\.google\.com\.|-safebrowsing\.google\.com\.|android\.clients\.google\.com\.|android-safebrowsing\.google\.com\.|\.map\.baidu\.com\.|\.tuisong\.baidu\.com|appc\.baidu\.com\.|appnavi\.baidu\.com\.|aspmx2\.googlemail\.com|aspmx3\.googlemail\.com|aspmx4\.googlemail\.com|aspmx5\.googlemail\.com|audiolc\.baidu\.com\.|bdbus-turbonet\.baidu\.com\.|browserkernel\.baidu\.com\.|bwww1\.baidu\.com\.|bwww2\.baidu\.com\.|bwww3\.baidu\.com\.|bwww4\.baidu\.com\.|bwww5\.baidu\.com\.|clients1\.google\.com\.|clients2\.google\.com\.|clients3\.google\.com\.|clients4\.google\.com\.|clients5\.google\.com\.|clients6\.google\.com\.|collector\.dcdn\.baidu\.com\.|lcs\.baidu\.com\.|dns\.google\.com\.|f7\.baidu\.com\.|gimg1\.baidu\.com\.|gimg2\.baidu\.com\.|gimg3\.baidu\.com\.|gimg4\.baidu\.com\.|gimg5\.baidu\.com\.|h2mbd\.baidu\.com\.|hm\.baidu\.com\.|hmma\.baidu\.com\.|hy\.baidu\.com\.|mb\.baidu\.com\.|mdb\.baidu\.com\.|mime\.baidu\.com\.|sg\.baidu\.com\.|ttl\.baidu\.com\.|zc\.baidu\.com\.|hector\.baidu\.com\.|hectorstatic\.baidu\.com\.|hijack\.baidu\.com\.|minipro\.baidu\.com\.|yuedu\.baidu\.com\.|mobads\.baidu\.com\.|mobsec-sec\.baidu\.com\.|mtalk\.google\.com\.|\.ubs\.baidu\.com\.|nsclick\.baidu\.com\.|\.googledomains\.com|openapi\.baidu\.com\.|openrcv\.baidu\.com\.|ossapi\.baidu\.com\.|p\.gdown\.baidu\.com\.|paimgcdn-feed\.baidu\.|pics0\.baidu\.com\.|pics1\.baidu\.com\.|pics2\.baidu\.com\.|pics3\.baidu\.com\.|pics4\.baidu\.com\.|pics5\.baidu\.com\.|pics6\.baidu\.com\.|pics7\.baidu\.com\.|pim\.baidu\.com\.|pimlog\.baidu\.com\.|pn\.baidu\.com\.|pos\.baidu\.com\.|publish-pic-cpu\.baidu\.com\.|pushbos\.baidu\.com\.|sofire\.baidu\.com\.|sptbjct\.baidu\.com\.|spthzct\.baidu\.com\.|sptnj\.baidu\.com\.|sptnjct\.baidu\.com\.|srfsug\.baidu\.com\.|stat\.client\.baidu\.com\.|suggestqueries\.google\.com\.|supl\.google\.com\.|tcbox\.baidu\.com\.|techain\.baidu\.com\.|tiebapic\.baidu\.com\.|tracker\.dcdn\.baidu\.com\.|udpolimenew\.baidu\.com\.|udpolimeok\.baidu\.com\.|update\.client\.baidu\.com\.|update\.pan\.baidu\.com\.|userident\.baidu\.com\.|vivosec\.baidu\.com\.|wangpan\.lcs\.baidu\.com\.|wenda5242\.baidu\.com\.|zhitong-castor-dev\.baidu\.com\.|www\.baidu\.com\.|www\.google\.com\.'
)


-- ========== yara-sample-query-job ==========
-- 备注：917：可下线候选
-- DWB 表：default.dwb_md5_record

-- --- [1] (未命名) | CSV 约 line 3587 ---
-- http://code.sangfor.org/SRI/SCIA/YaraHunting/yara-sample-query-job/blob/master/cron-job/yara_sample_query/config.py
SELECT file_md5
FROM default.dwb_md5_record
JOIN sri.ods_sri_hashinfo ON md5=file_md5
WHERE DAY='20251024'
AND hour='22'
AND fdfs_path IS NOT NULL
AND fdfs_path != ""
AND attr_info=0
GROUP BY file_md5

