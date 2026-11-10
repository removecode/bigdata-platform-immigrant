-- filter-layout-ip-seg-stat-prc 的 StarRocks 语句（CIPD/IP，旧 Hive SQL 见 all.sql L17–44）
-- 库表按 docs/StarRocks语句转换规则.md（DEC-014）：
--   default.log_audit_source -> csc.ods_csc_log_audit
--   csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync -> ti.ods_ti_db_intelligence_tb_ip_reputation_sync
-- 字段按 DEC-015：log_app_id 改为 app_id。
-- csc.ods_csc_log_audit 的 day、module_id、str5、str10 和 ti 表的 ip、direction、reputation 缺少新平台字段名，保留旧名。
-- 方言：LATERAL VIEW explode 改为 unnest；Hive 数组下标从 0 起，StarRocks 从 1 起；正则里的反斜杠加倍；RLIKE 写成 REGEXP。
-- 转义以 all.sql 为准（DEC-024）：`},{` 换成 `;{`，`\"` 一行按 all.sql 原文改写。917 梳理 CSV 同一行多一层反斜杠，二者不一致，未采用 CSV。
-- 日期 20260925–20261001 沿用 all.sql 里 today=2026-10-02、day_range=7 解出的窗口，day_unique=5 同样沿用，不是生产调度参数。
-- DEC-009：day 的 BETWEEN、day_unique >= 5 的比较需要按实际编码转换，这里没有加 CAST。
-- 规划时间见 DEC-022，语句提示把 new_planner_optimize_timeout 放到 60000 毫秒。
-- 该语句执行超时，同一个提示再加 query_timeout = 3600 秒（DEC-024）。
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
