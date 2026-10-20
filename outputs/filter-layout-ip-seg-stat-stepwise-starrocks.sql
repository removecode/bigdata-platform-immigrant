-- filter-layout-ip-seg-stat-prc 分步验证（StarRocks）。每一步只回答一个问题，前一步不通过，不要跑后一步。
-- 背景：新平台 7 天任务 99.7 分钟跑完但返回 0 行（ACT-065），需要分清是「预处理写法解析不出元素」「数据确实没命中」还是「过滤/排除把结果删光」。
-- 窗口沿用诊断版：day = 20261001 AND hour = 0，取样 LIMIT 1000。hour 列是否存在、类型未确认，没有该列时去掉 `AND hour = 0` 并改用 day。
-- 执行每步前，请用 `repr(sql)` 或抓包确认实际发出的反斜杠个数与本文件一致（ACT-061、ACT-062）。
-- DEC-009：day、hour 的比较没有加 CAST。本文件不含新表名，沿用 DEC-014 的表名。
-- 「v1」指 outputs/filter-layout-ip-seg-stat-starrocks.sql 的写法，「v2」指 outputs/filter-layout-ip-seg-stat-starrocks-v2.sql 的写法。

-- 步骤 0：列和类型。确认 day、hour、app_id、module_id、str5、str10 都存在，以及 hour 的类型（DEC-009 要求按实际编码比较）。
DESC csc.ods_csc_log_audit;

-- 步骤 1：看 str10 的真实形态。has_backslash 是含反斜杠的行数（\" 存储）；ends_tilde 是以 ~] 结尾的行数；
-- ends_bracket 是以 ] 结尾的行数；has_multi 是含 `},{` 的行数（多元素）；has_semicolon 是值里含分号的行数（会被 split 拆碎）。
-- 通过标准：该样本里 has_backslash、ends_tilde 的比例与你对现网的认识一致。若 has_backslash 为 0，v1 的 '\"' 替换才可能是对的。
SELECT count(*) AS n,
       sum(CASE WHEN instr(str10, '\\') > 0 THEN 1 ELSE 0 END) AS has_backslash,
       sum(CASE WHEN left(str10, 1) = '[' THEN 1 ELSE 0 END) AS starts_bracket,
       sum(CASE WHEN right(str10, 1) = ']' THEN 1 ELSE 0 END) AS ends_bracket,
       sum(CASE WHEN right(str10, 2) = '~]' THEN 1 ELSE 0 END) AS ends_tilde,
       sum(CASE WHEN instr(str10, '},{') > 0 THEN 1 ELSE 0 END) AS has_multi,
       sum(CASE WHEN instr(str10, ';') > 0 THEN 1 ELSE 0 END) AS has_semicolon
FROM (
  SELECT str10
  FROM csc.ods_csc_log_audit
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
  LIMIT 1000
) a;

-- 步骤 2：同一批样本，v1 与 v2 的预处理各能解析出多少元素。parsed 是 $.ip 能取出值的元素数，hit 是 reputation 和 direction 都为 '2' 的元素数。
-- 通过标准：v1 的 parsed 明显低于 v2，说明 v1 解析不出，0 行来自写法；两者 parsed 都低，回到步骤 1 看数据形态。
-- elements 减 parsed 的差是解析不出的片段：值里带分号（如 UA 里的 `; `）被 split 拆碎，或 JSON 本身不合法。本机合成数据里 v2 也有这类片段，
-- 差值占比见步骤 1 的 has_semicolon；这些片段不影响命中判断，但会白占展开开销（ACT-063）。
WITH src AS (
  SELECT str10
  FROM csc.ods_csc_log_audit
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
  LIMIT 1000
),
e1 AS (
  SELECT resp
  FROM src, unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~\\]', ''), '\\}\\,\\{', '\;\{'), '\"', '"'), ';')) AS t(resp)
),
e2 AS (
  SELECT resp
  FROM src, unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~?\\]$', ''), '\\}\\,\\{', '};{'), '\\"', '"'), ';')) AS t(resp)
)
SELECT 'v1' AS version, count(*) AS elements,
       sum(CASE WHEN get_json_object(resp, '$.ip') IS NOT NULL THEN 1 ELSE 0 END) AS parsed,
       sum(CASE WHEN get_json_object(resp, '$.threat.reputation') = '2' AND get_json_object(resp, '$.threat.direction') = '2' THEN 1 ELSE 0 END) AS hit
FROM e1
UNION ALL
SELECT 'v2', count(*),
       sum(CASE WHEN get_json_object(resp, '$.ip') IS NOT NULL THEN 1 ELSE 0 END),
       sum(CASE WHEN get_json_object(resp, '$.threat.reputation') = '2' AND get_json_object(resp, '$.threat.direction') = '2' THEN 1 ELSE 0 END)
FROM e2;

-- 步骤 3：v2 展开后 reputation、direction 的取值分布。rep 或 dr 为 NULL 说明字段没取出（路径或类型不对）；
-- 有取值但没有 '2'，说明解析正常，这批样本确实没有命中。direction 若是数字 2，get_json_object 返回的是字符串 '2'，可以直接比较。
SELECT get_json_object(resp, '$.threat.reputation') AS rep,
       get_json_object(resp, '$.threat.direction') AS dr,
       count(*) AS n
FROM (
  SELECT str10
  FROM csc.ods_csc_log_audit
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
  LIMIT 1000
) a,
unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~?\\]$', ''), '\\}\\,\\{', '};{'), '\\"', '"'), ';')) AS t(resp)
GROUP BY rep, dr
ORDER BY n DESC
LIMIT 20;

-- 步骤 4：命中元素的 ip 与 /24 网段取出来没有。ip_c_seg 为空或 NULL 说明 `split(...)[1]` 或网段正则有问题。
SELECT get_json_object(resp, '$.ip') AS raw_ip,
       split(get_json_object(resp, '$.ip'), ':')[1] AS ip,
       regexp_extract(split(get_json_object(resp, '$.ip'), ':')[1], '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_c_seg
FROM (
  SELECT str10
  FROM csc.ods_csc_log_audit
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
  LIMIT 1000
) a,
unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~?\\]$', ''), '\\}\\,\\{', '};{'), '\\"', '"'), ';')) AS t(resp)
WHERE get_json_object(resp, '$.threat.reputation') = '2'
  AND get_json_object(resp, '$.threat.direction') = '2'
LIMIT 10;

-- 步骤 5：信誉表一侧。rpt 太大会把所有网段排除掉，返回 0 行；rpt 为空则没有排除。
-- segs 是 direction='2' AND reputation='0' 的去重网段数；total_rows 是该表总行数。direction、reputation 的实际编码未确认（DEC-009）。
SELECT count(*) AS total_rows,
       sum(CASE WHEN direction = '2' AND reputation = '0' THEN 1 ELSE 0 END) AS matched_rows,
       count(DISTINCT CASE WHEN direction = '2' AND reputation = '0'
                           THEN regexp_extract(ip, '^(\\d+\\.\\d+\\.\\d+)\\.', 1) END) AS segs
FROM ti.ods_ti_db_intelligence_tb_ip_reputation_sync;

-- 步骤 6：一整小时的 v2 命中数与网段数（不取样，会真跑，约 40 秒量级，见 ACT-059）。
-- 通过标准：hit 大于 0 说明该小时有命中元素；再看 segs，才有后面按天累计 day_unique 的意义。
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 3600) */
       count(*) AS elements,
       sum(CASE WHEN get_json_object(resp, '$.ip') IS NOT NULL THEN 1 ELSE 0 END) AS parsed,
       sum(CASE WHEN get_json_object(resp, '$.threat.reputation') = '2' AND get_json_object(resp, '$.threat.direction') = '2' THEN 1 ELSE 0 END) AS hit,
       count(DISTINCT CASE WHEN get_json_object(resp, '$.threat.reputation') = '2' AND get_json_object(resp, '$.threat.direction') = '2'
                           THEN regexp_extract(split(get_json_object(resp, '$.ip'), ':')[1], '^(\\d+\\.\\d+\\.\\d+)\\.', 1) END) AS segs
FROM csc.ods_csc_log_audit,
     unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~?\\]$', ''), '\\}\\,\\{', '};{'), '\\"', '"'), ';')) AS t(resp)
WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
  AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf';

-- 步骤 7：把 day_unique >= 5 放宽到 >= 1 验证聚合与信誉排除（只用于验证，不是生产口径）。
-- 一天窗口里 day_unique 最大为 1，所以 >= 1 返回全部网段；再比较「带排除」与「不带排除」的行数差，就是信誉表实际排除的网段数。
-- 这一步要扫整天，量级约 15 分钟（ACT-060 外推），确认前面步骤都通过后再跑。
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
       unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~?\\]$', ''), '\\}\\,\\{', '};{'), '\\"', '"'), ';')) AS t(resp)
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001
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
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 7200) */
       count(*) AS segs_all,
       sum(CASE WHEN EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg) THEN 1 ELSE 0 END) AS segs_excluded_by_rpt
FROM agg_data;
