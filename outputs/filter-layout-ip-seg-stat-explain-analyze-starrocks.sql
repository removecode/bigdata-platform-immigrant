-- filter-layout-ip-seg-stat-prc 的诊断版：窗口缩到 1 小时，语句最前面加 EXPLAIN ANALYZE。
-- 基于 outputs/migratable-tasks-starrocks.sql 第 1 条，只改两处：
--   1) day BETWEEN 20260925 AND 20261001 改为 day = 20261001 AND hour = 0。小时取 0 是示例，按你要诊断的那一小时换；
--   2) 最前面加 EXPLAIN ANALYZE。
-- EXPLAIN ANALYZE 会真正执行查询，不返回结果行，返回带实际耗时、行数、内存的执行计划。
-- hour 列沿用旧名：all.sql L2026 的 default.log_audit_source 语句写 hour = ${hour}；csc.ods_csc_log_audit 是否有该列、类型是什么，未确认。
-- DEC-009：day、hour 的比较需要按实际编码转换，这里没有加 CAST。
-- 窗口只有 1 小时，day_unique 最多为 1，最外层 day_unique >= 5 会过滤掉所有行，所以正常执行也是 0 行。
-- 这里不看结果，只看耗时分布；该过滤在聚合之后，不影响前面扫描和展开的开销。
EXPLAIN ANALYZE
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
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
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
