-- 17 条可迁移语句涉及的 8 张表的体量统计（只统计，不拉明细）。
-- 目的：资源评估。静态分析看不出扫描量（ACT-075），这里补行数、天分布、大字段长度。
-- 库表名按 docs/StarRocks语句转换规则.md；sodl.* 缺少新平台表名，保留原名。
-- 列名：csc.ods_csc_log_audit 的 day、module_id、str1、str2、str5、str10 缺少新平台字段名，保留旧名。
-- DEC-009：day 的比较、length() 的结果按实际编码确认，未加 CAST。
-- 语句里不含 % 格式串。窗口取最近 7 天，请把日期换成你要评估的窗口。
-- 都是聚合查询，不返回明细。先从小窗口开始，每条先加 EXPLAIN 估一下，再跑。
-- 大表统计在目标集群上规划易超时：各条 SELECT 加 SET_VAR(new_planner_optimize_timeout = 30000)（用户 2026-11-10 确认；DEC-022 对业务语句为 60000，体量统计单独用 30000）。
-- 本机只在合成小表上验证过语法，行数没有参考意义。

-- @stat 1 | sodl.network_security_log 每天行数（语句 2、3、4、12、13、14、16、17 共用）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    insertdate,
    count(1) AS row_cnt
FROM sodl.network_security_log
WHERE insertdate BETWEEN '2026-10-26' AND '2026-11-01'
GROUP BY insertdate
ORDER BY insertdate;

-- @stat 2 | sodl.network_security_log 一天内按小时行数（判断小时任务一次扫多少）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    hour(from_unixtime(inserttimestamp)) AS hr,
    count(1) AS row_cnt
FROM sodl.network_security_log
WHERE insertdate = '2026-11-01'
GROUP BY hour(from_unixtime(inserttimestamp))
ORDER BY hr;

-- @stat 3 | sodl.network_security_log 过滤后的命中量（语句 2、4 的过滤条件，看过滤能留下多少行）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    insertdate,
    count(1) AS all_cnt,
    sum(CASE WHEN severity > 50 THEN 1 ELSE 0 END) AS severity_gt_50_cnt,
    sum(CASE WHEN severity > 50 AND action = 2 THEN 1 ELSE 0 END) AS severity_gt_50_action2_cnt
FROM sodl.network_security_log
WHERE insertdate BETWEEN '2026-10-26' AND '2026-11-01'
GROUP BY insertdate
ORDER BY insertdate;

-- @stat 4 | sodl.sip_iocstat_log 每天按 ioc_type 行数（语句 5、7）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    insertdate,
    ioc_type,
    count(1) AS row_cnt
FROM sodl.sip_iocstat_log
WHERE insertdate BETWEEN '2026-10-26' AND '2026-11-01'
GROUP BY insertdate, ioc_type
ORDER BY insertdate, ioc_type;

-- @stat 5 | sodl.dns_log 每天行数（语句 8）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    insertdate,
    count(1) AS row_cnt
FROM sodl.dns_log
WHERE insertdate BETWEEN '2026-10-26' AND '2026-11-01'
GROUP BY insertdate
ORDER BY insertdate;

-- @stat 6 | sodl.url_log 每天行数（语句 10）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    insertdate,
    count(1) AS row_cnt
FROM sodl.url_log
WHERE insertdate BETWEEN '2026-10-26' AND '2026-11-01'
GROUP BY insertdate
ORDER BY insertdate;

-- @stat 7 | sodl.endpoint_security_log 每天行数（语句 15）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    insertdate,
    count(1) AS row_cnt
FROM sodl.endpoint_security_log
WHERE insertdate BETWEEN '2026-10-26' AND '2026-11-01'
GROUP BY insertdate
ORDER BY insertdate;

-- @stat 8 | csc.ods_csc_log_audit 每天、每个 app_id 的行数和 str10 平均、最大长度（语句 1、5、6、7、9）
-- str10 长度决定 split/unnest 的展开量；filter-layout 的 CPU 主要耗在这里。
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    day,
    app_id,
    module_id,
    count(1) AS row_cnt,
    avg(length(str10)) AS str10_avg_len,
    max(length(str10)) AS str10_max_len
FROM csc.ods_csc_log_audit
WHERE day BETWEEN 20261026 AND 20261101
  AND app_id IN ('ip-proxy-svc', 'domain-proxy-svc', 'url-proxy-svc', 'cloudcheck', 'analysis-proxy-api')
GROUP BY day, app_id, module_id
ORDER BY day, app_id, module_id;

-- @stat 9 | csc.ods_csc_log_audit 一天内按小时行数（top-visit、topthreat 按小时取数时的单次扫描量）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    hour,
    app_id,
    count(1) AS row_cnt
FROM csc.ods_csc_log_audit
WHERE day = 20261101
  AND app_id IN ('ip-proxy-svc', 'domain-proxy-svc', 'url-proxy-svc', 'cloudcheck', 'analysis-proxy-api')
GROUP BY hour, app_id
ORDER BY hour, app_id;

-- @stat 10 | ti.ods_ti_db_intelligence_tb_ip_reputation_sync 规模（语句 1 的 rpt 子查询）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    count(1) AS all_cnt,
    sum(CASE WHEN direction = '2' AND reputation = '0' THEN 1 ELSE 0 END) AS rpt_cnt
FROM ti.ods_ti_db_intelligence_tb_ip_reputation_sync;

-- @stat 11 | default.ods_devicemanager_deviceinfo 规模（dashboard-stats-job 关联用）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    count(1) AS row_cnt
FROM `default`.ods_devicemanager_deviceinfo;
