-- ============================================================================
-- App: filter-layout-ip-seg-stat-prc  (CIPD/IP)
-- Repo: repos/SRI/SCIA/CIPD/IP/filter-layout-ip-seg-stat-prc
-- SQL source: assembly-workshop/cipd/filter-layout-ip-seg-stat-prc/app-cfg/ShenZhen-product/app_conf.yaml (key app_conf.hive_sql)
-- Engine: Hive (read-only SELECT). Executed via HiveDao cursor.execute(sql, dict, parameters=params)
--
-- Placeholder resolution (code: app-sdk/soapa-sangfor-lib/python/application/app.py:71-85)
--   today            = 2026-10-02
--   day_delta        = -1            (app_conf.yaml)
--   day_range        = 7             (app_conf.yaml)
--   day_max          = today + day_delta           = 2026-10-01 -> 20261001
--   day_min          = day_max - (day_range - 1)   = 2026-09-25 -> 20260925
--   day_unique       = hive_sql_params.day_unique  = 5
-- NOTE: substituted as bare integers, matching code (int(day_max.strftime("%Y%m%d"))).
-- ============================================================================

WITH rpt AS (
  SELECT DISTINCT regexp_extract(ip, '^(\d+\.\d+\.\d+)\.', 1) AS ip_seg
  FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
  WHERE direction='2' AND reputation='0'
),
resp_data AS (
  SELECT DAY AS date_day,
         split(get_json_object(resp, '$.ip'), ':')[0] AS ip,
         regexp_extract(split(get_json_object(resp, '$.ip'), ':')[0], '^(\d+\.\d+\.\d+)\.', 1) AS ip_c_seg
  FROM default.log_audit_source LATERAL VIEW explode(split(replace(regexp_replace(regexp_replace(regexp_replace(str10,'^\[',''),'~\]',''),'\}\,\{','\;\{'),'\"','"'), ';')) exploded_table AS resp
  WHERE log_app_id='ip-proxy-svc' AND DAY BETWEEN 20260925 AND 20261001
    AND module_id='ip-proxy-svc' AND str5 RLIKE 'cf'
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
  AND NOT EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg)
;

-- ============================================================================
-- App: domain-heat-stats-cron-job  (CIPD/BDPD)
-- Repo: repos/SRI/SCIA/CIPD/BDPD/domain-heat-stats-cron-job
-- SQL source: assembly-workshop/cipd/domain-heat-stats-cron-job/app-cfg/ShenZhen-product/{second,third,cloud}_domain.sql
-- Engine: Hive (read-only SELECT). Executed via HiveHandler.execute(sql, parameters={"day_str": ...})
--
-- Placeholder resolution (code: app/update_domain_heat_stats/__main__.py:154-157, utils.py:58-75)
--   For each sql file the config sets parameters.day = 2 (app-cfg.yaml DOMAIN_STATS_SQL_FILES)
--   day_str = get_day_before_n_days(n=item["parameters"]["day"])   [n = 2]
--           = today - 2 days = 2026-10-02 - 2d = 2026-09-30 -> 20260930
--   (NOTE: the code always uses datetime.now(); the explicit `day` arg is None here.)
-- Engine queue: tez.queue.name = operation (ShenZhen-product app-cfg.yaml HIVE.default.configuration)
-- ============================================================================


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

-- test_domain.sql (select "a.cn" ...) is only deployed when env_type == "test"; omitted here.

-- ============================================================================
-- App: cert-app-samplesync-country-job  (datareport)
-- Repo: repos/SRI/SCIA/datareport/cert-app-samplesync-country-job
-- SQL source: code constant, cron-job/sync_cert_app_country_sample_data/hive_manager.py:44-60
-- Engine: Hive (read-only SELECT). Executed via HiveDao cursor.execute(sql, parameters={...})
--
-- Placeholder resolution (ShenZhen-product config: default/cert-app-samplesync-country-job/app-cfg/ShenZhen-product/config.json)
--   :regexp_str   = get_regexp_str()  -> '^k1|^k2|...' joined from behavior_map keys
--                   = ^Trojan|^Backdoor|^Worm|^Virus|^Rootkit|^Bootkit|^Exploit|^Hacktool|^PUP|^Riskware|^Adware|^Suspicious|^Spyware|^Ransom|^Rogue|^CoinMiner|^Infostealer
--   :ago_oid      = get_oid(age_month_num=6) -> str(ObjectId.from_datetime(now - 6 months))
--                   NOTE: this is a MongoDB ObjectId hex derived from (today - 6 months) = 2026-04-02.
--                   The timestamp embedded is 2026-04-02 00:00:00 local. This script CANNOT compute the
--                   exact ObjectId without a MongoDB/bson runtime -- see value placeholder below.
--   :black        = FILE_ATTR_BLACK = 0
--   :gray         = FILE_ATTR_GRAY  = 2
--   :android      = "Android"
--   :android_os   = "AndroidOS"
--   :file_size    = country_pkg_size / each_package_count = 52428800 / 50 = 1048576
--   :limit_num    = cncert_sample_num * 4 = 500 * 4 = 2000
--
-- !!! ACTION REQUIRED: replace {AGO_OID} below with the real 24-hex ObjectId for (today - 6 months).
--     Compute in python: from bson import ObjectId; from datetime import datetime
--     from dateutil.relativedelta import relativedelta
--     str(ObjectId.from_datetime(datetime.now() - relativedelta(months=6)))
--     (as of 2026-10-02 -> datetime(2026,4,2,<now time>))
-- ============================================================================

SELECT virus_name, file_md5 FROM sri.ods_sri_hashinfo
WHERE virus_name regexp '^Trojan|^Backdoor|^Worm|^Virus|^Rootkit|^Bootkit|^Exploit|^Hacktool|^PUP|^Riskware|^Adware|^Suspicious|^Spyware|^Ransom|^Rogue|^CoinMiner|^Infostealer'
AND oid > '{AGO_OID}'
AND file_attr in (0, 2)
AND platform IN ('Android', 'AndroidOS')
AND fdfs_path != ""
AND file_size != "0" AND CAST (file_size AS INT) < 1048576
AND file_md5 NOT IN (SELECT str1 FROM csc.ods_csc_business_data)
ORDER BY file_attr ASC, oid DESC
LIMIT 2000
;

-- ============================================================================
-- App: cert-app-samplesync-job  (datareport)
-- Repo: repos/SRI/SCIA/datareport/cert-app-samplesync-job
-- SQL source: code constant, cron-job/sync_cert_app_sample_data/hive_manager.py:45-59
-- Engine: Hive (read-only SELECT). Executed via HiveDao cursor.execute(sql, parameters={...})
--
-- Placeholder resolution (ShenZhen-product config: default/cert-app-samplesync-job/app-cfg/ShenZhen-product/config.json)
--   :regexp_str   = behavior_map keys joined -> ^Trojan|^Backdoor|^Worm|^Virus|^Rootkit|^Bootkit|^Exploit|^Hacktool|^PUP|^Riskware|^Adware|^Suspicious|^Spyware|^Ransom|^Rogue|^CoinMiner|^Infostealer
--   :ago_oid      = get_oid(age_month_num=6) -> str(ObjectId.from_datetime(now - 6 months)) = (~2026-04-02)
--                   !!! replace {AGO_OID} -- see python snippet below.
--   :black        = 0 ; :gray = 2
--   :android      = "Android" ; :android_os = "AndroidOS"
--   :file_size    = provinces_pkg_size / provinces_sample_num = 52428800 / 50 = 1048576
--   :limit_num    = (len(provinces_arr) + len(extra_pkg_arr)) * provinces_sample_num * 2
--                 = (31 + 10) * 50 * 2 = 4100
--
-- !!! ACTION REQUIRED: fill {AGO_OID}:
--     from bson import ObjectId; from datetime import datetime
--     from dateutil.relativedelta import relativedelta
--     str(ObjectId.from_datetime(datetime.now() - relativedelta(months=6)))
-- ============================================================================

SELECT virus_name, file_md5 FROM sri.ods_sri_hashinfo
WHERE virus_name regexp '^Trojan|^Backdoor|^Worm|^Virus|^Rootkit|^Bootkit|^Exploit|^Hacktool|^PUP|^Riskware|^Adware|^Suspicious|^Spyware|^Ransom|^Rogue|^CoinMiner|^Infostealer'
AND oid > '{AGO_OID}'
AND file_attr in (0, 2)
AND platform IN ('Android', 'AndroidOS')
AND fdfs_path != ""
AND file_size != "0" AND CAST (file_size AS INT) < 1048576
AND file_md5 NOT IN (SELECT str1 FROM csc.ods_csc_business_data)
ORDER BY file_attr ASC, oid DESC
LIMIT 4100
;

-- ============================================================================
-- App: ati-pdns-cache-job  (ATI)
-- Repo: repos/SRI/SCIA/ATI/ati-pdns-cache-job
-- SQL source: assembly-workshop/default/ati-pdns-cache-job/app-cfg/<env>/config.json (per task_id, key "sql")
--             NOTE: only ShenZhen-default / ShenZhen-dev / ShenZhen-test exist (no ShenZhen-product).
--                   Using ShenZhen-default set (1 task); dev/test sets add ngaf_dns/sip_dns/graph_ip tasks.
-- Engine: Hive (read-only SELECT). Executed via HiveUtil cursor.execute(sql)
--
-- Placeholder resolution (code: core/run.py, loader/sql_func.py:6-11, loader/hive_loader.py:33-38, utils/time_util.py)
--   {days} = "(d1, d2, ...)" comma list of days for the CURRENT ISO week-of-year starting from start_year.
--            get_all_week_info(): rrule WEEKLY byweekday=<current isoweekday> from Dec 1 of start_year(2021) to Dec 31 of year(yesterday).
--   Report reference: "today" per code = now - 1 day = 2026-10-01 (yesterday). isoweekday(2026-10-01)=3 (Wed).
--   => all Wednesdays from 2021-12-01..2021-12-31 (empty -> actually from 2021-12-01 window) through 2026-12-31.
--
--   !! The {days} list is long (Wednesdays from 2021-12 to 2026-12). Compute it exactly with:
--      from dateutil.rrule import rrule, WEEKLY
--      from datetime import datetime, timedelta
--      sy, y = 2021, (datetime.now()-timedelta(days=1)).year
--      wd = (datetime.now()-timedelta(days=1)).isoweekday()
--      days = [d.strftime("%Y%m%d") for d in rrule(WEEKLY, byweekday=wd,
--              dtstart=datetime(sy,12,1), until=datetime(y,12,31))]
--      days_str = "(" + ", ".join(days) + ")"
--   A truncated sample list for 2026 Wednesdays is shown below as {DAYS} placeholder.
-- ============================================================================

-- Task: ati_pdns_from_graph_domain  (ShenZhen-default config.json)
SELECT key AS domain FROM csc.ods_csc_ioc_vertex WHERE graph_type='Domain' AND day in ({DAYS}) AND data_source NOT IN ('pdns','ngaf_dns','sip_dns') GROUP BY key
;

-- ============================================================================
-- Extra tasks present only in ShenZhen-dev / ShenZhen-test (uncomment if needed):
--
-- ati_pdns_from_ngaf_dns:
-- SELECT queries AS domain FROM ngaf.ods_ngaf_dns WHERE day in ({DAYS}) AND answers NOT IN ('','-') GROUP BY queries
--
-- ati_pdns_from_sip_dns:
-- SELECT queries AS domain FROM sip.ods_sip_dns WHERE day in ({DAYS}) AND answers NOT IN ('','-') GROUP BY queries
--
-- ati_pdns_from_graph_ip:
-- SELECT key AS ip FROM csc.ods_csc_ioc_vertex WHERE graph_type='IP' AND day in ({DAYS}) AND data_source NOT IN ('pdns','ngaf_dns','sip_dns') GROUP BY key
-- ============================================================================

-- ============================================================================
-- App: ti-hot-data-detection-fusing-prc  (FCC)
-- Repo: repos/SRI/SCIA/FCC/ti-hot-data-detection-fusing-prc
-- SQL source: assembly-workshop/fcc/ti-hot-data-detection-fusing-prc/app-cfg/default/config.json (key "sql")
-- Engine: ClickHouse over HTTP GET (read-only SELECT).
--         core/core.py: url = cfg.URL ; requests.get(url, params={"user":..,"password":..,"query": sql})
--         (There is no DB cursor; run this against the ClickHouse HTTP endpoint directly.)
--
-- Placeholder resolution (code: core/core.py:73-81, utils/utils.py)
--   sql = AppConfig.sql.format(format_timestamp(last_time), format_timestamp(now))   -- TWO positional {}
--   format_timestamp(t) = strftime("%Y%m%d%H")   (hourly, local time)
--   now       = int(time.time())                       -> current hour
--   last_time = get_last_time(TASK_ID) if present, else now - task_before_hours(1)
--
-- today = 2026-10-02. First slot = (now - 1 hour); second slot = now.
-- Fill in the two hour-stamps {LAST_HOUR} and {NOW_HOUR} (format YYYYMMDDHH), e.g.:
--   if run at 2026-10-02 10:00 -> {LAST_HOUR}=2026100209, {NOW_HOUR}=2026100210
-- (last_time may already exist in task status; the fresh-start default is now-1h.)
-- ============================================================================

SELECT fileMd5, deviceId, virusName FROM sodl.handle_info_log WHERE formatDateTime(toDateTime(insertTimestamp), '%Y%m%d%H') >= '{LAST_HOUR}' AND formatDateTime(toDateTime(insertTimestamp), '%Y%m%d%H') < '{NOW_HOUR}' AND engineInfo LIKE '%IsHotspot%' AND detectEngine = '4'
;

-- ============================================================================
-- App: domain-hit-devnum-cronjob  (ATI / IOC-PRODUCT)
-- Repo: repos/SRI/SCIA/ATI/IOC-PRODUCT/domain-hit-devnum-cronjob
-- SQL source: assembly-workshop/cipd/domain-hit-devnum-cronjob/app-cfg/default/app_cfg.json (key app_cfg.hive_sql)
--             (repo copy in unittest/data/app_cfg.json is the sample; production uses the app-cfg file)
-- Engine: Hive (read-only SELECT). Executed via driver/hive_handler.py:27 cursor.execute(hive_sql.format(start_time, end_time))
--
-- Placeholder resolution (code: app/domain_hit_devnum_cronjob/__main__.py:24, utils/utils.py:43-56)
--   query_interval_day = 30  (app_cfg.json)
--   start_time = today - 30 days = 2026-10-02 - 30d = 2026-09-02 -> 20260902
--   end_time   = today           = 2026-10-02            -> 20261002
--   (both format %Y%m%d, positional {} slots)
-- ============================================================================

SELECT DOMAIN,devnum,total_times FROM (SELECT DOMAIN,COUNT(DISTINCT devid) AS devnum,COUNT(devid) as total_times FROM default.dwb_domain_info WHERE DAY>=20260902 and DAY<=20261002 AND devid NOT IN (SELECT str1 AS dev FROM ods_custom_upload_data WHERE part1='test_dev' AND part2='test_devid') GROUP BY DOMAIN) subquery WHERE devnum > 10 LIMIT 15000000
;

-- ============================================================================
-- App: black-file-clean-cronjob  (FCC)
-- Repo: repos/SRI/SCIA/FCC/black-file-clean-cronjob
-- SQL source: code constant, cron-job/black_file_clean/statistic.py:6-23 (STATISTIC_BLACK_MD5)
-- Engine: Hive (read-only SELECT). Executed via utils.py:33 cursor.execute(sql, configuration={"tez.queue.name": "default"})
-- Config: no app-cfg env dir; schedule baked in deploy.yaml (time: "1 3 * * *"). No SQL placeholders come from config.
--
-- Placeholder resolution (code: __main__.py:21, utils.py:7-14)
--   {day} = get_yesterday() = (datetime.today() - 1 day).strftime("%Y%m%d")
--         = 2026-10-02 - 1d = 2026-10-01 -> 20261001
--   NOTE: code substitutes the bare integer (no quotes): STATISTIC_BLACK_MD5.format(day=20261001)
-- ============================================================================

SELECT DISTINCT lower(md5)
FROM default.dwb_md5_info
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
  AND threattype!=13 -- 13->botnet
  AND file_attr='0'
  AND length(filehash)=32
;

-- ============================================================================
-- App: ip-security-log-etl-prc  (CIPD/IP/C2IP-TMP)
-- Repo: repos/SRI/SCIA/CIPD/IP/C2IP-TMP/ip-security-log-etl-prc
-- SQL source: code constant, app-sdk/soapa-sangfor-lib/python/config.py:15-29 (C2_IP_SECURITY_LOG_SQL)
-- Engine: Hive (read-only SELECT). Executed via driver/hive_db.py:35 cursor.execute(sql, configuration=HIVE_CONFIG)
-- Config: no app-cfg env dir (deploy.yaml datacenter ShenZhen only). All values are code constants.
--
-- Placeholder resolution (code: security_log_handler.py:63-66, utils/comm_util.py:12-24, __main__.py:40)
--   {day}                   = get_yesterday_date(query_timestamp)
--                             query_timestamp = last_handle_time + 24h; fresh run -> today
--                             = today - 1 day = 2026-10-01 -> 20261001   (bare int, %Y%m%d)
--   {ipv4_pattren}          = IPV4_ADDRESS      = ^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$
--   {private_network_pattren} = PRIVATE_ADDRESS = ^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))
--   {data_limit}            = C2_IP_SECURITY_LOG_LIMIT = 100000
-- ============================================================================

select
    distinct dstip
from sodl.network_security_log
where DAY=20261001
    AND regexp_extract(dstip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
    AND regexp_extract(dstip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
    AND engine not in ('premise_ioc', 'cloud_ioc', 'sase_ioc')
    AND severity > 50
    AND (threatclass in (209, 208, 216, 214,  203, 40)
        or concat_ws('-',cast(threatclass as String),
                        cast(threattype as String),
                        cast(threatsubtype as String)) = '212-10-0')
limit 100000
;

-- ============================================================================
-- App: active-domain-elt-job  (CIPD/DOMAIN/PRE)
-- Repo: repos/SRI/SCIA/CIPD/DOMAIN/PRE/active-domain-elt-job
-- SQL source: app-sdk/soapa-sangfor-lib/python/configs/sql.py
--   INFO_EXIST_CHECK_SQL (sql.py:18-23)  -- :mday
--   ACTIVE_DOMAIN_SQL    (sql.py:28-90)  -- :start_day
-- Engine: Hive (read-only SELECT). Executed via driver/hive.py cursor.execute(sql, parameters=...)
-- Config: no app-cfg env dir (values are code constants).
--
-- Placeholder resolution (code: app/black-active-domain-etl-job/__main__.py:21-22, utils/public_module.py:13-21)
--   date = get_yesterday_date() = (now - 1 day).strftime("%Y%m%d") = 2026-10-01 -> 20261001
--   :mday      = date = 20261001
--   :start_day = date = 20261001
-- ============================================================================


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

-- ============================================================================
-- App: domain-security-log-etl-prc  (CIPD/DOMAIN/PRE)
-- Repo: repos/SRI/SCIA/CIPD/DOMAIN/PRE/domain-security-log-etl-prc
-- SQL source: app-sdk/soapa-sangfor-lib/python/configs/config.py
--   INFO_EXIST_CHECK_SQL              (config.py:20-23)  -- :mday
--   DOMAIN_SECURITY_LOG_EXTRACT_SQL   (config.py:27-47)  -- positional {} via .format(date)
-- Engine: Hive (read-only SELECT). Executed via driver/hive.py cursor.execute(sql, parameters=...)
-- Config: no app-cfg env dir (deploy ShenZhen only; values are code constants).
--
-- Placeholder resolution (code: app/domain-security-log-etl/__main__.py:26, common/util.py:12-20, core/data_load.py:27,55)
--   date = get_yesterday_date() = (now - 1 day).strftime("%Y%m%d") = 2026-10-01 -> 20261001
--   :mday = 20261001 ;  {} in extract SQL = 20261001 (bare int)
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) INFO_EXIST_CHECK_SQL  (:mday -> 20261001)  -- gate, run first
-- ---------------------------------------------------------------------------
SELECT 1 FROM sodl.network_security_log WHERE day=20261001 LIMIT 1
;


-- ---------------------------------------------------------------------------
-- 2) DOMAIN_SECURITY_LOG_EXTRACT_SQL  ({} -> 20261001)
-- ---------------------------------------------------------------------------
SELECT DOMAIN,
       COLLECT_SET(producttype) AS producttype_list,
       COLLECT_SET(CONCAT(CAST(threatclass AS STRING), '-', CAST(threattype AS STRING),
       '-', CAST(threatsubtype AS STRING))) AS type_list,
       SORT_ARRAY(COLLECT_SET(engine)) AS engine_list,
       COUNT(DISTINCT engine) AS engine_num
FROM
  (SELECT REGEXP_EXTRACT(url, '^(?:https?://)?(?:www\.)?([^/]+)', 1) AS DOMAIN,
          *
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND engine NOT IN ('premise_ioc', 'cloud_ioc', 'sase_ioc')
     AND severity > 50
     AND (threatclass IN (209, 208, 216, 214, 203, 40)
          OR CONCAT(CAST(threatclass AS STRING), '-', CAST(threattype AS STRING), '-',
          CAST(threatsubtype AS STRING)) = '212-10-0')
     AND action = 2) s
WHERE NOT (DOMAIN RLIKE '\d+\.\d+\.\d+\.\d+$' OR DOMAIN RLIKE ':')
GROUP BY DOMAIN
;

-- ============================================================================
-- App: black-ti-context-produce-prc  (TIBAE)
-- Repo: repos/SRI/SCIA/TIBAE/black-ti-context-produce-prc
-- SQL source: app-sdk/soapa-sangfor-lib/python/active_info_update/config/active_stat_sql.py
--   C2_IP_ACTIVE_STAT_SQL, ATTACK_IP_ACTIVE_STAT_SQL, DOMAIN_ACTIVE_STAT_SQL, MD5_ACTIVE_STAT_SQL
--   + INFO_EXIST_CHECK_SQL (config.py:122-133)
-- Engine: Hive (read-only SELECT). Executed via core/active_data_load.py:50 cursor.execute(sql, parameters={"mday": stat_date})
-- Config: only default/ShenZhen-dev/ShenZhen-test config.yaml (pulsar only; no SQL params).
--
-- Placeholder resolution (code: app/black-{ip,md5,domain}-active-context-produce-job/__main__.py)
--   stat_date = (now + timedelta(days=-1)).strftime("%Y%m%d") = 2026-10-01 -> 20261001
--   :mday = 20261001  (all statements)
-- ============================================================================


-- ---------------------------------------------------------------------------
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
-- 3) ATTACK_IP_ACTIVE_STAT_SQL  (direction="1", :mday -> 20261001)
-- ---------------------------------------------------------------------------
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


-- ---------------------------------------------------------------------------
-- 5) MD5_ACTIVE_STAT_SQL  (:mday -> 20261001, appears twice)
-- ---------------------------------------------------------------------------
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
   FROM default.dwb_md5_info
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
;

-- ============================================================================
-- App: ctig-report-data-analysis-prc  (CIPD/BDPD)
-- Repo: repos/SRI/SCIA/CIPD/BDPD/ctig-report-data-analysis-prc
-- SQL source: code constant STAT_SQL, app-sdk/soapa-sangfor-lib/python/config/internal_config.py:221-317
-- Engine: StarRocks (MySQL protocol via pymysql). Executed at data_analysis.py:203-205 cursor.execute(stat_sql) -- read-only SELECT.
--
-- Placeholder resolution (code: data_analysis.py:188-193, __main__.py:62-68)
--   {tenant_ids} = ','.join(["'{}'".format(tid) for tid in tenant_ids])
--                  tenant_ids comes from the runtime task payload (Redis priority queue), NOT from date/config.
--                  -> MUST be supplied by the calling task. Replace {TENANT_IDS} with the tenant list.
--   {start_time} = task['start_time']  (date string, format %Y%m%d, e.g. 20250715) -- from task payload
--   {end_time}   = task['end_time']    (date string, format %Y%m%d)               -- from task payload
--                  NOTHING in this app derives start/end from "today"; they are the report window requested.
--                  For a fresh manual run ending today (2026-10-02), a typical window would be e.g.
--                  start_time=20260901, end_time=20261002 -- confirm with the report request.
--
-- !! ACTION REQUIRED: fill {TENANT_IDS}, {START_TIME}, {END_TIME}.
--    tenant_ids substituted as:  'tid1','tid2','tid3'   (quoted, comma-separated)
-- ============================================================================

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
    WHERE tenant_id IN ({TENANT_IDS})
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
    WHERE log.alarmDate BETWEEN '{START_TIME}' AND '{END_TIME}'
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

-- ============================================================================
-- App: ti-ip-detection-send-prc  (CIPD/IP)   [Go app]
-- Repo: repos/SRI/SCIA/CIPD/IP/ti-ip-detection-send-prc
-- SQL source: src/soapa-app/cmd/ti-ip-detection-send-prc/config.yaml  (keys ip_sql / ip_sql_with_limit)
-- Engine: ClickHouse over HTTP GET (read-only SELECT).
--         core/ip_extractor.go:102-147 -> GET cfg.ClickHouseConf.Addr?user=..&password=..&query=<sql>
--
-- Placeholder resolution (code: core/ip_extractor.go:75-97, utils/utils.go)
--   %d slots are UNIX EPOCH SECONDS (int64 seconds, NOT %Y%m%d).
--   lastTime = MongoDB TaskSynStatus last time; on first run (0):
--                now - task_before_minutes(10)   -> GetTimestampBeforeMinute
--   endTime  = now (GetCurrentTimestamp) - default_exec_sec(0); task_range_sec=0 so unchanged.
--   ip_limit = 2000000 -> the WITH-LIMIT variant is used.
--
-- "today" = 2026-10-02. The schedule is "*/10 * * * *" (every 10 min).
-- Fill {LAST_TS} and {END_TS}, plus <LIMIT>=2000000. Example if run at 2026-10-02 10:00:00 local:
--   end   = epoch seconds of 2026-10-02 10:00:00  = 1790901600   (compute: date -d '2026-10-02 10:00:00' +%s)
--   last  = end - 600                              = 1790901000
-- (In production lastTime comes from the task-status DB, not now-10min; the fresh-run default is now-10min.)
-- ============================================================================

SELECT DISTINCT
    splitByChar(':', JSONExtractString(element, 'ip'))[1] AS ip_address,
    splitByChar(':', JSONExtractString(element, 'ip'))[2] AS port,
    insertTimestamp
FROM
    sodl.operation_rdp_event_log
ARRAY JOIN JSONExtractArrayRaw(businessContent) AS element
WHERE
    businessType = '21'
    AND insertTimestamp >= {LAST_TS} AND insertTimestamp < {END_TS} limit 2000000;

-- ============================================================================
-- App: top-visit-host-produce-job  (CIPD/BDPD)  -- 3 jobs: domain / ip / url
-- Repo: repos/SRI/SCIA/CIPD/BDPD/top-visit-host-produce-job
-- SQL source: app-sdk/soapa-sangfor-lib/python/data_etl/log_stat_sql.py (verbatim below)
-- Engine: Hive (read-only SELECT). Executed via data_etl/log_extract.py cursor.execute(sql, parameters=param)
-- Config: only default/ShenZhen-dev app-cfg (no SQL params there).
--
-- Placeholder resolution (code: log_extract.py:52-97, common/utils.py:36-46, data_etl/constant.py)
--   :date       = get_time_before_n_days(now, n=1, date_format=PARTITION_DATE_FORMAT="%Y%m%d")
--               = 2026-10-02 - 1 day = 2026-10-01 -> 20261001
--   %(devices)s = self.device_id (tuple of subscribed device ids + CUSTOM_DEVICE, list->tuple).
--                 RUNTIME data (device subscription), NOT derivable from date/config.
--                 Substitute as a tuple literal, e.g. ('dev1','dev2',0). Only *_BY_DEVICE uses it.
--   Runtime path: the domain/ip/url produce jobs call etl(need_device=False) -> non-device SQL runs.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) DNS_LOG_STAT_SQL   (:date -> 20261001)
-- ---------------------------------------------------------------------------
SELECT queries as domain,
       sum(log_num) AS num
FROM sodl.dns_log
WHERE day = 20261001
  AND producttype in ('AF', 'NGAF', 'VNGAF')
  AND qr=0
  AND length(queries) > 3
  AND locate('.', queries) != 0
GROUP BY queries
;


-- ---------------------------------------------------------------------------
-- 2) IP_LOG_STAT_SQL   (:date -> 20261001)
-- ---------------------------------------------------------------------------
with ip_stat as (
SELECT concat(split(ip, '\\.')[0], '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]) AS c_segment
FROM
    (SELECT get_json_object(replace(str4, '\\', ''), '$[*].ip') AS ip_list
      FROM default.log_audit_source
      WHERE day = 20261001
        AND log_app_id='ip-proxy-svc'
        AND module_id='ip-proxy-svc'
        AND str1='NGAF'
        AND str5='[cf]') s
   LATERAL VIEW explode(split(regexp_replace(ip_list, '\\[|\\]|\\"', ''), ',')) exploded_table AS ip
   WHERE locate('.', ip) != 0
)
SELECT c_segment as ip,
       count(1) as num
FROM ip_stat
GROUP BY c_segment
LIMIT 500000
;


-- ---------------------------------------------------------------------------
-- 3) URL_LOG_STAT_SQL   (:date -> 20261001)
-- ---------------------------------------------------------------------------
SELECT host,
       sum(log_num) AS num
FROM sodl.url_log
WHERE day = 20261001
  AND host is not null
  AND locate('.', host)  != 0
  AND producttype in ('AF', 'NGAF', 'VNGAF')
GROUP BY host
;


-- ============================================================================
-- _BY_DEVICE variants (only used when need_device=True; fill {DEVICES})
--   %(devices)s -> tuple literal, e.g. ('dev1','dev2',0)
-- ---------------------------------------------------------------------------
-- DNS_LOG_STAT_SQL_BY_DEVICE:
-- SELECT queries as domain, sum(log_num) AS num
-- FROM sodl.dns_log
-- WHERE day = 20261001
--   AND producttype in ('AF', 'NGAF', 'VNGAF')
--   AND qr=0 AND length(queries) > 3 AND locate('.', queries) != 0
--   AND manage in {DEVICES}
-- GROUP BY queries
--
-- IP_LOG_STAT_SQL_BY_DEVICE:
-- SELECT c_segment as ip, count(1) as num
-- FROM (
--   SELECT concat(split(ip, '\\.')[0], '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]) AS c_segment
--   FROM (
--     SELECT get_json_object(replace(str4, '\\', ''), '$[*].ip') AS ip_list
--     FROM default.log_audit_source
--     WHERE day = 20261001 AND log_app_id='ip-proxy-svc' AND module_id='ip-proxy-svc'
--       AND str1='NGAF' AND str5 = '[cf]' AND str2 in {DEVICES}) s
--   LATERAL VIEW explode(split(regexp_replace(ip_list, '\\[|\\]|\\"', ''), ',')) explod

-- ============================================================================
-- App: cipd-product-resource-monitor-prc  (CIPD/COMMON)
-- Repo: repos/SRI/SCIA/CIPD/COMMON/cipd-product-resource-monitor-prc
-- SQL source: app-sdk/soapa-sangfor-lib/python/configs/sql.py (7 statements, verbatim below)
-- Engine: Hive (read-only SELECT). Executed via driver/hive.py:43 cursor.execute(sql, parameters=param)
-- Config: only default/ShenZhen-dev app-cfg (no SQL params); values are code constants.
--
-- Placeholder resolution (code: app/cloudgateway-device-count-monitor-job/__main__.py:22-23,
--   configs/config.py:25-26, util.py:17-26)
--   ONE_DAY = 1 ; ONE_WEEK = 7
--   yesterday_date = get_previous_date(ONE_DAY)  = today - 1 = 2026-10-01 -> 20261001
--   pre_date       = get_previous_date(ONE_WEEK) = today - 7 = 2026-09-25 -> 20260925
--   :mday -> 20261001 ;  :sday -> 20260925 ;  :eday -> 20261001
--   (NOTE: get_previous_date uses datetime.now(); today=2026-10-02.)
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) STAT_LOG_CHECK  (:mday -> 20261001)  -- table-exists gate
-- ---------------------------------------------------------------------------
select 1
from csc.ods_csc_log_stats
where day=20261001
and app_id = 'ip-realtime-identify-etl-prc'
limit 1
;


-- ---------------------------------------------------------------------------
-- 2) DOMAIN_DEVICE_COUNT_STAT  (:mday -> 20261001)
-- ---------------------------------------------------------------------------
select str4, sum(long1)
from csc.ods_csc_log_stats
where day=20261001
and app_id = 'dns-intelligence-dispatch-prc'
and str1 = 'cig_subscribe'
and str2 = 'dl_dns_log'
group by str4
;


-- ---------------------------------------------------------------------------
-- 3) CLOUDGATEWAY_IP_DEVICE_COUNT_STAT  (:mday -> 20261001)
-- ---------------------------------------------------------------------------
select str5, sum(long1)
from csc.ods_csc_log_stats
where day=20261001
and app_id = 'ip-realtime-identify-etl-prc'
and str1 = 'etl_size'
and str2 = 'kafka_poll_size'
and str3 = 'CLOUD_INTELLIGENCE_GATEWAY'
group by str5
;


-- ---------------------------------------------------------------------------
-- 4) CLOUDCHECK_IP_DEVICE_COUNT_STAT  (:mday -> 20261001)
-- ---------------------------------------------------------------------------
select str5, sum(long1)
from csc.ods_csc_log_stats
where day=20261001
and app_id = 'ip-realtime-identify-etl-prc'
and str1 = 'filter_size'
and str2 = 'valid_devid'
and str3 = 'CLOUDCHECK_C2IP_CF'
group by str5
;


-- ---------------------------------------------------------------------------
-- 5) DOMAIN_DEVICE_STAT  (:sday -> 20260925, :eday -> 20261001)
-- ---------------------------------------------------------------------------
select distinct str4
from csc.ods_csc_log_stats
where day>=20260925 and day<=20261001
and app_id = 'dns-intelligence-dispatch-prc'
and str1 = 'cig_subscribe'
and str2 = 'dl_dns_log'
;


-- ---------------------------------------------------------------------------
-- 6) CLOUDGATEWAY_IP_DEVICE_STAT  (:sday -> 20260925, :eday -> 20261001)
-- ---------------------------------------------------------------------------
select distinct str5
from csc.ods_csc_log_stats
where day>=20260925 and day<=20261001
and app_id = 'ip-realtime-identify-etl-prc'
and str1 = 'etl_size'
and str2 = 'kafka_poll_size'
and str3 = 'CLOUD_INTELLIGENCE_GATEWAY'
;


-- ---------------------------------------------------------------------------
-- 7) CLOUDCHECK_IP_DEVICE_STAT  (:sday -> 20260925, :eday -> 20261001)
-- ---------------------------------------------------------------------------
select distinct str5
from csc.ods_csc_log_stats
where day>=20260925 and day<=20261001
and app_id = 'ip-realtime-identify-etl-prc'
and str1 = 'filter_size'
and str2 = 'valid_devid'
and str3 = 'CLOUDCHECK_C2IP_CF'
;

-- ============================================================================
-- App: attack-ip-analysis-cronjob  (TIBAE)  -- 6 sub-jobs
-- Repo: repos/SRI/SCIA/TIBAE/attack-ip-analysis-cronjob
-- SQL source: code constants under
--   app-sdk/soapa-sangfor-lib/python/attack_ip_*_analysis/filter_log/constant.py
-- Engine: Hive (read-only SELECT). Executed via base_db/hive_db.py HiveSqlCli (cursor.execute).
-- Config: no SQL params in app-cfg (default/ShenZhen-dev only, pulsar config). Values are code constants.
--
-- Shared placeholder resolution (code: utils/run_time.py, each filter_log_data.py)
--   DAY/`day` = SRTime.get_yesterday_date() = (now - 1d).strftime("%Y%m%d") = 2026-10-01 -> 20261001
--   run_time  = SRTime.get_time_ms() = int(time.time()*1000)  -> MILLISECOND epoch at run time
--               !! not derivable from "today"; compute: python -c "import time;print(int(time.time()*1000))"
--               -> fill {RUN_TIME_MS} (e.g. run at 2026-10-02 10:00 -> 1790901600000)
--   skyeye_update_time = SRTime.get_nday_time(n=365) = (now_ms - 365*86400*1000) -> MILLISECOND epoch
--               -> fill {SKYEYE_UPDATE_MS} (now - 365d in ms)   (af_skyeye only)
--   exclude_type_list = the 35 EXCLUDE_THREAT_TYPE literals joined with commas (shared, given inline below)
--   private_network_pattren / ipv4_pattren = PRIVATE_ADDRESS / IPV4_ADDRESS (regex, given inline)
--   tag_stats = TAG_STATS.format(log_type=<X>)  (inlined per sub-query below)
-- ============================================================================


-- ###########################################################################
-- SUB-JOB 1/6: af_rule  (attack_ip_af_rule_analysis)  -- 4 statements
--   NETWORK_SECURITY_LOG_SQL, ATK_IP_VIBRANT_SQL, ATK_IP_EXPIRE_SQL, ATK_IP_REVIVE_SQL
--   log_type=attack_security_log ; NET_VIBRANT_NUM=5 ; NET_EXPIRE_NUM=10
-- ###########################################################################

-- ---- 1a) NETWORK_SECURITY_LOG_SQL (day=20261001) ----
WITH attack_security_log AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename,'((cve-\d+-\d+)|(CVE-\d+-\d+)|(cnnvd-\d+-\d+)|(CNNVD-\d+-\d+))') AS bug_id,
          producttype,
          severity
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) NOT IN ('30-10-0','30-999-0','90-5-1','90-5-2','90-7-1','90-7-2','90-7-3','90-7-4','90-7-5','90-7-6','90-7-8','90-7-999','90-9-0','94-2-1','94-2-2','94-2-3','94-2-999','94-4-1','94-4-7','94-4-999','94-5-1','212-1-0','212-5-0','212-9-1','212-9-2','212-9-3','216-6-0','216-7-1','216-10-1','216-10-2','216-11-1','216-12-0','216-999-0','204-2-12','204-2-999')
     AND manage NOT IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
     AND regexp_extract(srcip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
     AND regexp_extract(srcip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
     AND cast(reqruleid AS string) NOT IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='low_trusted_ips_id' OR part2='low_trusted_waf_id'))),
     trusted_sid_stat AS
  (SELECT srcip,
          count(distinct(reqruleid)) AS trusted_rule_count
   FROM attack_security_log
   WHERE reqruleid IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
   bug_id_stat AS
  (SELECT srcip,
          collect_list(bug_id || '@' || num) AS bug_sum
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
          collect_list(attack_type || '@' || num) AS attack_type_sum
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
              collect_set(reqruleid) AS rule_id_list,
              collect_set(producttype) AS source_list,
              avg(severity) as avg_severity
        FROM attack_security_log
        GROUP BY srcip) s
   LEFT JOIN trusted_sid_stat ON s.srcip = trusted_sid_stat.srcip
   LEFT JOIN attack_type_stat ON s.srcip = attack_type_stat.srcip
   LEFT JOIN bug_id_stat ON s.srcip = bug_id_stat.srcip
   LEFT JOIN
      (SELECT srcip,
              collect_list(reqruleid || '@' || attack_std) AS attack_std
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
FROM log_stat
;
-- ---- 1b) ATK_IP_VIBRANT_SQL  (run_time={RUN_TIME_MS}, segment_num=5) ----
SELECT *
FROM
  (SELECT concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]) AS ips,
          count(1) AS num
   FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
   WHERE deleted_time=0
     AND direction='1'
     AND expire_time>={RUN_TIME_MS}
   GROUP BY concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2])) black_ip
WHERE num>=5
  AND ips NOT IN
    (SELECT str1
     FROM default.ods_custom_upload_data
     WHERE part1='attack_ip_analysis'
       AND part2='attack_ip_filter' )
;


-- ---- 1c) ATK_IP_EXPIRE_SQL  (run_time={RUN_TIME_MS}, segment_num=10) ----
SELECT *
FROM
  (SELECT concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]) AS ips,
          count(1) AS num
   FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
   WHERE deleted_time=0
     AND direction='1'
     AND expire_time<{RUN_TIME_MS}
   GROUP BY concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2])) black_ip
WHERE num>=10
  AND ips NOT IN
    (SELECT str1
     FROM default.ods_custom_upload_data
     WHERE part1='attack_ip_analysis'
       AND part2='attack_ip_filter' )
;


-- ---- 1d) ATK_IP_REVIVE_SQL  (run_time={RUN_TIME_MS}, segment_num=10) ----
WITH black_ips AS
  (SELECT concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]) AS ips,
          count(1) AS num
   FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
   WHERE deleted_time=0
     AND direction='1'
     AND expire_time>={RUN_TIME_MS}
   GROUP BY concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]))
SELECT ip
FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
WHERE deleted_time=0
  AND direction='1'
  AND expire_time<{RUN_TIME_MS}
  AND concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]) IN
    (SELECT ips
     FROM black_ips
     WHERE num>=10)
  AND concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]) NOT IN
    (SELECT str1
     FROM default.ods_custom_upload_data
     WHERE part1='attack_ip_analysis'
       AND part2='attack_ip_filter')
;

-- ###########################################################################
-- SUB-JOB 2/6: af_skyeye  (attack_ip_af_skyeye_analysis)  -- 1 statement
--   log_type=skyeye_attack_security_log ; skyeye_high_num=100 ; skyeye_num=30
--   skyeye_update_time={SKYEYE_UPDATE_MS} (= now_ms - 365d)
-- ###########################################################################
WITH skyeye_attack_security_log AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename,'((cve-\d+-\d+)|(CVE-\d+-\d+)|(cnnvd-\d+-\d+)|(CNNVD-\d+-\d+))') AS bug_id
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) NOT IN ('30-10-0','30-999-0','90-5-1','90-5-2','90-7-1','90-7-2','90-7-3','90-7-4','90-7-5','90-7-6','90-7-8','90-7-999','90-9-0','94-2-1','94-2-2','94-2-3','94-2-999','94-4-1','94-4-7','94-4-999','94-5-1','212-1-0','212-5-0','212-9-1','212-9-2','212-9-3','216-6-0','216-7-1','216-10-1','216-10-2','216-11-1','216-12-0','216-999-0','204-2-12','204-2-999')
     AND manage NOT IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_test_device_id'
          AND part2='attack_ip_analysis')
     AND regexp_extract(srcip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
     AND regexp_extract(srcip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
     AND cast(reqruleid AS string) NOT IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='low_trusted_ips_id' OR part2='low_trusted_waf_id'))),
     skyeye_ip AS
  (SELECT ips,
          count(1) AS num
   FROM
     (SELECT ip,
             concat(split(ip, '\\.')[0] , '.', split(ip, '\\.')[1], '.', split(ip, '\\.')[2]) AS ips
      FROM csc.ods_csc_tim_db_unknown_intelligence_tb_skyeye_ip_info_sync
      WHERE update_time>={SKYEYE_UPDATE_MS}
      GROUP BY ip) t
   WHERE ips NOT IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='attack_ip_analysis'
          AND part2='attack_ip_filter')
   GROUP BY ips),
     trusted_sid_stat AS
  (SELECT srcip,
          count(distinct(reqruleid)) AS trusted_rule_count
   FROM skyeye_attack_security_log
   WHERE reqruleid IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
    bug_id_stat AS
  (SELECT srcip,
          collect_list(bug_id || '@' || num) AS bug_sum
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
          collect_list(attack_type || '@' || num) AS attack_type_sum
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
             collect_set(distinct(reqruleid)) AS rule_id_list
   FROM skyeye_attack_security_log
   WHERE reqruleid IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
    bug_id_stat AS
  (SELECT srcip,
          collect_list(bug_id || '@' || num) AS bug_sum
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
          collect_list(attack_type || '@' || num) AS attack_type_sum
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
             collect_set(distinct(reqruleid)) AS rule_id_list
      FROM skyeye_attack_security_log
      GROUP BY srcip) s
   LEFT JOIN trusted_sid_stat ON s.srcip = trusted_sid_stat.srcip
   LEFT JOIN attack_type_stat ON s.srcip = attack_type_stat.srcip
   LEFT JOIN bug_id_stat ON s.srcip = bug_id_stat.srcip)
SELECT *
FROM log_stat
WHERE concat(split(srcip, '\\.')[0] , '.', split(srcip, '\\.')[1], '.', split(srcip, '\\.')[2]) IN
    (SELECT ips
     FROM skyeye_ip
     WHERE num>=100)
  OR (concat(split(srcip, '\\.')[0] , '.', split(srcip, '\\.')[1], '.', split(srcip, '\\.')[2]) IN
        (SELECT ips
         FROM skyeye_ip
         WHERE num>=30)
      AND trusted_rule_count > 0)
  OR (srcip IN
        (SELECT ip
         FROM csc.ods_csc_tim_db_unknown_intelligence_tb_skyeye_ip_info_sync
         WHERE update_time>={SKYEYE_UPDATE_MS})
      AND trusted_rule_count > 0)
;

-- ###########################################################################
-- SUB-JOB 3/6: seclog (RCE + UA)  (attack_ip_seclog_analysis)  -- 2 statements
--   log_type=attack_security_log_rce / attack_security_log_ua
-- ###########################################################################

-- ---- 3a) NETWORK_SECURITY_LOG_SQL (RCE) ----
WITH attack_security_log_rce AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename,
          '((cve-\d+-\d+)|(CVE-\d+-\d+)|(cnnvd-\d+-\d+)|(CNNVD-\d+-\d+))') AS bug_id,
          producttype
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND manage NOT IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
        ),
   bug_id_stat AS
  (SELECT srcip,
          collect_list(bug_id || '@' || num) AS bug_sum
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
          collect_list(reqruleid || '@' || num) AS reqruleid_sum
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
          collect_list(attack_type || '@' || num) AS attack_type_sum
   FROM
     (SELECT srcip,
             cast(attack_type AS string) AS attack_type,
             cast(count(attack_type) AS string) AS num
      FROM attack_security_log_rce
      GROUP BY srcip,
               attack_type) attack_s
   GROUP BY srcip),

   keyword_stat AS (
      SELECT srcip, collect_set(keyword) AS hit_keywords
    FROM (
      SELECT srcip, keyword
      FROM (
        SELECT srcip, regexp_extract(requesthead, 'eval\(|assert\(|preg_replace\(|call_user_func\(|call_user_func_array\(|create_function\(|array_map\(|system\(|passthru\(|exec\(|pcntl_exec\(|shell_exec\(|popen\(|proc_open\(|ob_start\(|ProcessBuilder\(|runtime\.exec\(|Runtime\.getRuntime\(\)\.exec\(|os\.system\(|os\.popen\(|subprocess\.Popen\(|cat \/etc\/passwd ', 0) AS keyword
        FROM sodl.network_security_log
        where day=20261001
        UNION
        SELECT srcip, regexp_extract(url, 'eval\(|assert\(|preg_replace\(|call_user_func\(|call_user_func_array\(|create_function\(|array_map\(|system\(|passthru\(|exec\(|pcntl_exec\(|shell_exec\(|popen\(|proc_open\(|ob_start\(|ProcessBuilder\(|runtime\.exec\(|Runtime\.getRuntime\(\)\.exec\(|os\.system\(|os\.popen\(|subprocess\.Popen\(|cat \/etc\/passwd ', 0) AS keyword
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
where regexp_extract(srcip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
     AND regexp_extract(srcip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
;

-- ---- 3b) NETWORK_SECURITY_LOG_SQL_UA (malicious UA) ----
WITH attack_security_log_ua AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename,
          '((cve-\d+-\d+)|(CVE-\d+-\d+)|(cnnvd-\d+-\d+)|(CNNVD-\d+-\d+))') AS bug_id,
          regexp_extract(lower(requesthead), '(?<=user-agent: ).*?(?=\r\n)', 0) as user_agent
   FROM sodl.network_security_log
   WHERE DAY=20261001
    and requesthead != ''
    and regexp_extract(srcip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
     AND regexp_extract(srcip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
     AND manage NOT IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
        ),
    bug_id_stat AS
  (SELECT srcip,
          collect_list(bug_id || '@' || num) AS bug_sum
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
          collect_list(reqruleid || '@' || num) AS reqruleid_sum
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
          collect_list(attack_type || '@' || num) AS attack_type_sum
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
    select srcip, collect_set(mal_ua) AS hit_mal_ua
    from (
     SELECT srcip, regexp_extract(user_agent, 'zgrab|datacha0s|masscan|morfeus fucking scanner|netsparker|nessus|nmap scripting engine|openvas|sqlmap|wordpress hash grabber|wpscan|struts\-pwn|detectify|dirbuster|\(hydra\)|\.nasl|absinthe|advanced email extractor|arachni\/|autogetcontent|bilbo|brutus|bsqlbf|cgichk|cisco\-torch|commix|core\-project\/1\.0|crimscanner\/|domino hunter|dotdotpwn|email extractor|fhscan core 1\.|floodgate|f\-secure radar|get\-minimal|gobuster|gootkit auto\-rooter scanner|grabber|grendel\-scan|havij|inspath|internet ninja|jaascois|zmeu|Jorgee|metis|mysqloit|n\-stealth|nikto|nmap nse|nmap\-nse|nsauditor|pangolin|paros|pmafind|prog\.customcrawler|qualys was|s\.t\.a\.l\.k\.e\.r\.|security scan|springenwerk|sql power injector|sqlninja|sysscan|teh forest lobster|this is an exploit|toata dragostea|toata dragostea mea pentru diavola|uil2pn|vega\/|voideye|w3af\.sf\.net|w3af\.sourceforge\.net|w3af\.org|webbandit|webinspect|webshag|webtrends security analyzer|webvulnscan|whatweb|whcc\/|xmlrpc exploit ', 0)
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
  FROM ua_stat
;


-- ###########################################################################
-- SUB-JOB 4/6: low_trusted  (attack_ip_low_trusted_analysis)  -- 1 statement
--   log_type=low_trusted_log ; low_trusted_filter='' (empty)
-- ###########################################################################
WITH low_trusted_log AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename,'((cve-\d+-\d+)|(CVE-\d+-\d+)|(cnnvd-\d+-\d+)|(CNNVD-\d+-\d+))') AS bug_id,
          producttype,
          severity
   FROM sodl.network_security_log
   WHERE DAY=20261001
     AND concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) NOT IN ('30-10-0','30-999-0','90-5-1','90-5-2','90-7-1','90-7-2','90-7-3','90-7-4','90-7-5','90-7-6','90-7-8','90-7-999','90-9-0','94-2-1','94-2-2','94-2-3','94-2-999','94-4-1','94-4-7','94-4-999','94-5-1','212-1-0','212-5-0','212-9-1','212-9-2','212-9-3','216-6-0','216-7-1','216-10-1','216-10-2','216-11-1','216-12-0','216-999-0','204-2-12','204-2-999')
     AND manage NOT IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
     AND regexp_extract(srcip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
     AND regexp_extract(srcip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
     ),
     trusted_sid_stat AS
  (SELECT srcip,
          count(distinct(reqruleid)) AS trusted_rule_count
   FROM low_trusted_log
   WHERE reqruleid IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
   bug_id_stat AS
  (SELECT srcip,
          collect_list(bug_id || '@' || num) AS bug_sum
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
          collect_list(attack_type || '@' || num) AS attack_type_sum
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
              collect_set(reqruleid) AS rule_id_list,
              collect_set(producttype) AS source_list,
              avg(severity) as avg_severity
        FROM low_trusted_log
        GROUP BY srcip) s
   LEFT JOIN trusted_sid_stat ON s.srcip = trusted_sid_stat.srcip
   LEFT JOIN attack_type_stat ON s.srcip = attack_type_stat.srcip
   LEFT JOIN bug_id_stat ON s.srcip = bug_id_stat.srcip
   LEFT JOIN
      (SELECT srcip,
              collect_list(reqruleid || '@' || attack_std) AS attack_std
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
FROM log_stat
;
-- ###########################################################################
-- SUB-JOB 5/6: low_attack_type (XSS/SQLi + weak password)
--   log_type=xss_sql_injection_log / weak_password_log
-- ###########################################################################

-- ---- 5a) XSS_SQl_INJECTION_LOG_SQL ----
WITH xss_sql_injection_log AS
  (SELECT srcip,
          log_num,
          concat_ws('-',cast(threatclass as String),
            cast(threattype as String),
            cast(threatsubtype as String)) AS attack_type,
          manage,
          reqruleid,
          regexp_extract(rulename,'((cve-\d+-\d+)|(CVE-\d+-\d+)|(cnnvd-\d+-\d+)|(CNNVD-\d+-\d+))') AS bug_id,
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
        FROM default.ods_custom_upload_data
        WHERE part1='af_test_device_id'
        AND part2='attack_ip_analysis')
     AND regexp_extract(srcip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
     AND regexp_extract(srcip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
     ),
     trusted_sid_stat AS
  (SELECT srcip,
          count(distinct(reqruleid)) AS trusted_rule_count
   FROM xss_sql_injection_log
   WHERE reqruleid IN
       (SELECT str1
        FROM default.ods_custom_upload_data
        WHERE part1='af_rule_id'
          AND (part2='high_trusted_ips_id' OR part2='high_trusted_waf_id'))
   GROUP BY srcip),
   bug_id_stat AS
  (SELECT srcip,
          collect_list(bug_id || '@' || num) AS bug_sum
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
          collect_list(attack_type || '@' || num) AS attack_type_sum
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
              collect_set(reqruleid) AS rule_id_list,
              collect_set(producttype) AS source_list,
              avg(severity) as avg_severity,
              collect_set(action) as action_list
        FROM xss_sql_injection_log
        GROUP BY srcip) s
   LEFT JOIN trusted_sid_stat ON s.srcip = trusted_sid_stat.srcip
   LEFT JOIN attack_type_stat ON s.srcip = attack_type_stat.srcip
   LEFT JOIN bug_id_stat ON s.srcip = bug_id_stat.srcip
   LEFT JOIN
      (SELECT srcip,
              collect_list(reqruleid || '@' || attack_std) AS attack_std
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
FROM log_stat
;
-- ---- 5b) WEAK_PASSWORD_SQL ----
select
  'weak_password_log' as log_type,
  srcip as ip,
  count(distinct pwd) as pwd_num,
  collect_set(pwd) as pwd_list
from
(
  SELECT
    srcip,
    regexp_extract(requesthead, '(pwd|password)=([^&; ]+)', 2) as pwd
  FROM sodl.network_security_log
  WHERE day=20261001
    AND regexp_extract(srcip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
    AND regexp_extract(srcip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
    AND concat_ws('-',cast(threatclass as String),
                        cast(threattype as String)) in ('94-4')
    and regexp_extract(requesthead, '(pwd|password)=([^&; ]+)', 2) != ''
  union
  SELECT
    srcip,
    regexp_extract(requestbody, '(pwd|password)=([^&; ]+)', 2)  as pwd
  FROM sodl.network_security_log
  WHERE day=20261001
    AND regexp_extract(srcip,'^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))') = ''
    AND regexp_extract(srcip,'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$') != ''
    AND concat_ws('-',cast(threatclass as String),
                        cast(threattype as String)) in ('94-4')
    and regexp_extract(requestbody, '(pwd|password)=([^&; ]+)', 2) != ''
)a
group by srcip
;

-- ###########################################################################
-- SUB-JOB 6/6: wiki_related  (attack_ip_wiki_related_analysis)  -- 1 statement
--   log_name=network_security_log ; result_min_len=10 ; filter_word=NECESSARY_WORD joined by '|'
--   (SIP_LOG_HIVE_SQL is commented out in code -> omitted)
-- ###########################################################################
SELECT
    "network_security_log" as table_name,
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
AND regexp_extract(srcip, "^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))", 1) = ""
AND (requesthead != "" OR requestbody != "")
AND (regexp_extract(requesthead, "[^a-zA-Z](wget|curl|downloadfile|downloadstring|powershell|certutil|bitsadmin|mshta|ncat|msiexec|msxsl|rundll32|regsvr32|tftp|ipc$|pubprn.vbs|wmiexec|psexec|ftp:|jndi:|ldap:|rmi:)[^a-zA-Z0-9)_;,|]") != ""
    OR
    regexp_extract(requestbody, "[^a-zA-Z](wget|curl|downloadfile|downloadstring|powershell|certutil|bitsadmin|mshta|ncat|msiexec|msxsl|rundll32|regsvr32|tftp|ipc$|pubprn.vbs|wmiexec|psexec|ftp:|jndi:|ldap:|rmi:)[^a-zA-Z0-9)_;,|]") != "")
;

# topthreat_hot_stat — 黑域名统计 SQL

> 源文件: `oozie-sz/oozie_projects/jobs/ShenZhen/topthreat_hot_stat/code/black_domain_stat.yaml`
> Shell: `black_domain_stat.sh`
> output: `mongo-int.db_statistic.tb_original_domain_stat`
> processor_module: `topthreat_domain_stat`
> 调度: 每小时第 7 分钟（`07 * * * *`），取数窗口 `coord:nominalTime() - 2HOUR`
> 说明: `${day}` / `${hour}` 为占位符，由 shell 传入实际值替换

```sql
SELECT domain,
       sum(domain_num) AS domain_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT domain,
          devid,
          count(1) AS domain_num
   FROM
     (SELECT lower(get_json_object(str10_tmp, "$.domain")) AS domain,
             str2 AS devid
      FROM default.log_audit_source LATERAL VIEW explode(default.format_json_list(regexp_replace(str10, '[\\]+"', '"'))) str10_tbl AS str10_tmp
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
        AND get_json_object(str10_tmp, "$.info.attr")='0'
        AND day = ${day}
        AND hour = ${hour} ) a
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
      (SELECT split(split(url, '//')[size(split(url, '//')) -1], '/')[0] AS domain,
              MANAGE AS devid,
              log_num
       FROM sodl.network_security_log
       WHERE url IS NOT NULL
         AND url NOT IN ('',
                         '-')
         AND day = ${day}
         AND hour = ${hour})t
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
     AND day = ${day}
     AND hour = ${hour}
   GROUP BY ioc,
            manage ) t
GROUP BY domain,
         devid
ORDER BY domain_num DESC
LIMIT 100000
```

## 依赖 sodl 且用 hour 过滤的分支

| # | 源表 | 位置 | 说明 |
|---|------|------|------|
| 1 | `sodl.network_security_log` | black_domain_stat.yaml:56-61 | split url 剥出 domain，按 domain+devid 聚合 |
| 2 | `sodl.sip_iocstat_log` | black_domain_stat.yaml:72-78 | `ioc_type='domain'`，按 ioc+manage 聚合 |

# topthreat_hot_stat — 黑文件统计 SQL

> 源文件: `oozie-sz/oozie_projects/jobs/ShenZhen/topthreat_hot_stat/code/black_file_stat.yaml`
> Shell: `black_file_stat.sh`
> output: `mongo-int.db_statistic.tb_original_file_stat`
> processor_module: `file_processor`
> 调度: 每小时第 7 分钟（`07 * * * *`），取数窗口 `coord:nominalTime() - 2HOUR`
> 说明: `${day}` / `${hour}` 为占位符，由 shell 传入实际值替换

```sql
SELECT md5,
       count(1) AS md5_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT lower(get_json_object(str10_tmp, "$.filemd5")) AS md5,
          get_json_object(str10_tmp, "$.info.attr") AS attr,
          str2 AS devid
   FROM default.log_audit_source LATERAL VIEW explode(default.format_json_list(regexp_replace(str10, '[\\]+"', '"'))) str10_tbl AS str10_tmp
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
     AND day = ${day}
     AND hour = ${hour}) a
WHERE md5 IS NOT NULL
  AND md5 NOT IN ('',
                  '-')
  AND attr='0'
GROUP BY md5,
         devid
ORDER BY md5_num DESC
LIMIT 100000
```

## 说明

- **不使用 sodl 库**，仅依赖 `default.log_audit_source`。
- 与 domain/url 维度的差异：`log_app_id = 'analysis-proxy-api'`、`module_id IN ('file_hash','file_scan')`、取 `$.filemd5` 字段、仅校验 `attr='0'`（不含 `long1=0`）。

# topthreat_hot_stat — 黑URL统计 SQL

> 源文件: `oozie-sz/oozie_projects/jobs/ShenZhen/topthreat_hot_stat/code/blcak_url_stat.yaml`（文件名拼写为历史遗留 `blcak`）
> Shell: `black_url_stat.sh`
> output: `mongo-int.db_statistic.tb_original_url_stat`
> processor_module: `topthreat_url_stat`
> 调度: 每小时第 7 分钟（`07 * * * *`），取数窗口 `coord:nominalTime() - 2HOUR`
> 说明: `${day}` / `${hour}` 为占位符，由 shell 传入实际值替换

```sql
SELECT url,
       sum(url_num) AS url_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT url,
          devid,
          count(1) AS url_num
   FROM
     (SELECT lower(get_json_object(str10_tmp, "$.url")) AS url,
             str2 AS devid
      FROM default.log_audit_source LATERAL VIEW explode(default.format_json_list(regexp_replace(str10, '[\\]+"', '"'))) str10_tbl AS str10_tmp
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
        AND get_json_object(str10_tmp, "$.info.attr")='0'
        AND day = ${day}
        AND hour = ${hour} ) a
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
     AND day = ${day}
     AND hour = ${hour}
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
     AND day = ${day}
     AND hour = ${hour}
   GROUP BY ioc,
            manage ) t
GROUP BY url,
         devid
ORDER BY url_num DESC
LIMIT 100000
```

## 依赖 sodl 且用 hour 过滤的分支

| # | 源表 | 位置 | 说明 |
|---|------|------|------|
| 1 | `sodl.network_security_log` | blcak_url_stat.yaml:52-57 | 直接取 url，按 url+manage 聚合 |
| 2 | `sodl.sip_iocstat_log` | blcak_url_stat.yaml:66-72 | `ioc_type='url'`，按 ioc+manage 聚合 |
