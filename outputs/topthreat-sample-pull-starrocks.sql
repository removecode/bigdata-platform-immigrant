-- 热门威胁 + audit-str10 补样用：只抽样、不拉全表。
-- 请在目标 StarRocks 执行，把结果（TSV/CSV 或控制台复制）发回，助手写入 reference/real-data/。
-- 表名：若 catalog 为 paimon，把 csc.ods_csc_log_audit 改成 paimon.csc.ods_csc_log_audit（下同 sodl）。
-- 时间：先跑 1 小时；通过后再改窗口。下列默认 2026-11-01 第 0 小时（与此前 topthreat 草稿 hour=0 对齐）。
-- 语句无 % 格式串，可走 sql %% () 检查。
-- 大表请加规划 hint；你环境 30000 ms 可用（ACT-080）。

-- ========== 改这里（仅此两处）==========
-- WINDOW_START = '2026-11-01 00:00:00'
-- WINDOW_END   = '2026-11-01 01:00:00'
-- sodl 侧若只用 insertdate：SODL_INSERTDATE = '2026-11-01'，TS_LO/TS_HI 与上面 log_time 对应 unix 秒
-- =======================================

-- @pull 1 | audit 黑域名分支：原始行（请原样保存 str10，勿在 Excel 里改引号）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    app_id,
    module_id,
    str1,
    str2 AS devid,
    long1,
    year,
    month,
    day,
    hour,
    log_time,
    length(str10) AS str10_len,
    left(str10, 120) AS str10_prefix,
    right(str10, 40) AS str10_suffix,
    str10
FROM csc.ods_csc_log_audit
WHERE app_id IN ('domain-proxy-svc', 'cloudcheck')
  AND module_id IN ('domain-proxy-svc', 'CloudCheck')
  AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
               'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
               'EDR_CLOUD_IDENTIFY', 'EDR_PK')
  AND long1 = 0
  AND log_time >= '2026-11-01 00:00:00'
  AND log_time < '2026-11-01 01:00:00'
ORDER BY log_time
LIMIT 5;

-- @pull 2 | audit 黑文件分支
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    app_id,
    module_id,
    str1,
    str2 AS devid,
    long1,
    day,
    hour,
    log_time,
    length(str10) AS str10_len,
    str10
FROM csc.ods_csc_log_audit
WHERE app_id = 'analysis-proxy-api'
  AND module_id IN ('file_hash', 'file_scan')
  AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
               'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
               'EDR_CLOUD_IDENTIFY', 'EDR_PK')
  AND long1 = 0
  AND log_time >= '2026-11-01 00:00:00'
  AND log_time < '2026-11-01 01:00:00'
ORDER BY log_time
LIMIT 5;

-- @pull 3 | audit 黑 URL 分支
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    app_id,
    module_id,
    str1,
    str2 AS devid,
    long1,
    day,
    hour,
    log_time,
    length(str10) AS str10_len,
    str10
FROM csc.ods_csc_log_audit
WHERE app_id IN ('url-proxy-svc', 'cloudcheck')
  AND module_id IN ('url-proxy-svc', 'CloudCheck')
  AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
               'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
               'EDR_CLOUD_IDENTIFY', 'EDR_PK')
  AND long1 = 0
  AND log_time >= '2026-11-01 00:00:00'
  AND log_time < '2026-11-01 01:00:00'
ORDER BY log_time
LIMIT 5;

-- @pull 4 | str10 形态分布（该小时有多少行、是否单对象/数组/~] 尾）— 帮助判断 json_each vs UDF
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    app_id,
    count(1) AS row_cnt,
    sum(CASE WHEN left(trim(str10), 1) = '[' THEN 1 ELSE 0 END) AS starts_array,
    sum(CASE WHEN left(trim(str10), 1) = '{' THEN 1 ELSE 0 END) AS starts_object,
    sum(CASE WHEN right(trim(str10), 2) = '~]' THEN 1 ELSE 0 END) AS ends_tilde_bracket,
    avg(length(str10)) AS avg_len,
    max(length(str10)) AS max_len
FROM csc.ods_csc_log_audit
WHERE app_id IN ('domain-proxy-svc', 'cloudcheck', 'url-proxy-svc', 'analysis-proxy-api')
  AND long1 = 0
  AND log_time >= '2026-11-01 00:00:00'
  AND log_time < '2026-11-01 01:00:00'
GROUP BY app_id;

-- @pull 5 | 同一批行：json_each 拆出的元素个数（你现网写法）— 请与 @pull 1 的 str10 对照
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    a.app_id,
    a.log_time,
    count(f.value) AS json_each_cnt,
    sum(CASE WHEN get_json_object(f.value, '$.info.attr') = '0' THEN 1 ELSE 0 END) AS attr0_cnt
FROM csc.ods_csc_log_audit a
CROSS JOIN json_each(get_json_string(regexp_replace(a.str10, '\\\\+"', '"'), '$[*]')) f
WHERE a.app_id IN ('domain-proxy-svc', 'cloudcheck')
  AND a.module_id IN ('domain-proxy-svc', 'CloudCheck')
  AND a.long1 = 0
  AND a.log_time >= '2026-11-01 00:00:00'
  AND a.log_time < '2026-11-01 01:00:00'
GROUP BY a.app_id, a.log_time, a.str10
ORDER BY a.log_time
LIMIT 20;

-- @pull 6 | sodl.network_security_log：带 url 的行（热门威胁分支 2；你此前样例多为 dns 空 url）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    insertdate,
    inserttimestamp,
    hour(from_unixtime(inserttimestamp)) AS hr,
    deviceId AS devid,
    url,
    length(url) AS url_len,
    moduletype,
    producttype
FROM sodl.network_security_log
WHERE insertdate = '2026-11-01'
  AND url IS NOT NULL
  AND url NOT IN ('', '-')
  AND hour(from_unixtime(inserttimestamp)) = 0
ORDER BY inserttimestamp
LIMIT 20;

-- @pull 7 | sodl.sip_iocstat_log：domain / url 类型
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    insertdate,
    inserttimestamp,
    hour(from_unixtime(inserttimestamp)) AS hr,
    deviceId AS devid,
    ioc,
    ioc_type,
    record_count
FROM sodl.sip_iocstat_log
WHERE insertdate = '2026-11-01'
  AND ioc_type IN ('domain', 'url')
  AND ioc IS NOT NULL
  AND ioc NOT IN ('', '-')
  AND hour(from_unixtime(inserttimestamp)) = 0
ORDER BY inserttimestamp
LIMIT 20;

-- @pull 8 |（可选）若 @pull 1 报列不存在：DESC 审计表，把结果贴回
-- DESC csc.ods_csc_log_audit;
