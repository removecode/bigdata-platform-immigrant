-- 在 ACT-079/081 已覆盖 sodl.network_security_log 后，用最少查询补完资源排序。
-- 每条带 SET_VAR(new_planner_optimize_timeout = 30000)，与 outputs/table-volume-stats-starrocks.sql 一致。
-- 优先跑下面 3 条；@stat 10/@stat 11 可选（维表，通常远小于日志表）。

-- @minimal A | filter-layout 相关审计量（语句 1）：7 天、ip-proxy-svc，看扫描行数与 str10 体量
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    count(1) AS row_cnt,
    avg(length(str10)) AS str10_avg_len,
    max(length(str10)) AS str10_max_len
FROM csc.ods_csc_log_audit
WHERE day BETWEEN 20261026 AND 20261101
  AND app_id = 'ip-proxy-svc'
  AND module_id = 'ip-proxy-svc';

-- @minimal B | topthreat / top-visit 审计（语句 5、6、7、9）：单日 0 点、按 app_id 汇总
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    app_id,
    count(1) AS row_cnt,
    avg(length(str10)) AS str10_avg_len,
    max(length(str10)) AS str10_max_len
FROM csc.ods_csc_log_audit
WHERE day = 20261101
  AND hour = 0
  AND app_id IN ('ip-proxy-svc', 'domain-proxy-svc', 'url-proxy-svc', 'cloudcheck', 'analysis-proxy-api')
GROUP BY app_id
ORDER BY app_id;

-- @minimal C | top-visit 大表（语句 8、10）：各扫 1 天行数即可（与 @stat 5、6 等价，不必 7 天）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'dns_log' AS tbl,
    count(1) AS row_cnt
FROM sodl.dns_log
WHERE insertdate = '2026-11-01'
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'url_log' AS tbl,
    count(1) AS row_cnt
FROM sodl.url_log
WHERE insertdate = '2026-11-01';

-- @minimal D（可选）| filter-layout 信誉表 + dashboard 设备表
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    count(1) AS all_cnt,
    sum(CASE WHEN direction = '2' AND reputation = '0' THEN 1 ELSE 0 END) AS rpt_cnt
FROM ti.ods_ti_db_intelligence_tb_ip_reputation_sync;

SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    count(1) AS row_cnt
FROM `default`.ods_devicemanager_deviceinfo;
