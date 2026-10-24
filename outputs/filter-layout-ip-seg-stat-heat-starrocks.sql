-- filter-layout-ip-seg-stat-prc 预聚合版：读 ti.ads_ti_ip_heat_produce，不再扫 csc.ods_csc_log_audit / 展开 str10。
-- 字段（用户 2026-10-22 样本）：ip, devid_cnt, log_num, top_devids, day（例：20261002）。
-- 旧语句（威胁过滤 + 展开）见 outputs/filter-layout-ip-seg-stat-starrocks-v2.sql。
--
-- 【语义是否与旧任务一致，材料未确认，使用前必须与 Hive 对账】
-- 1) 该表若是「全量审计按 IP 日聚合」，则不含旧语句的 app_id/module_id/str5/threat.reputation/direction 过滤，结果会与 Hive 不同。
-- 2) 表内只保留当天 log_num>=5 的 IP（用户基线约 970 万行/天），网段内 ip_unique、total、day_unique 可能偏小。
-- 3) log_num 若是审计行 COUNT(*)，旧语句 count(*) 是「满足威胁条件的展开 resp 条数」，二者不一定相等。
-- 4) devid_cnt、top_devids 本任务最终输出不用，仅 heat 表自带字段。
-- DEC-009：day 的 BETWEEN、day_unique>=5、log_num 求和按实际类型转换；样本 day 为整数 yyyyMMdd，下面按整数写。
-- 窗口沿用 all.sql 占位：20260925–20261001；信誉排除与 v2 相同。

WITH rpt AS (
  SELECT DISTINCT regexp_extract(ip, '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_seg
  FROM ti.ods_ti_db_intelligence_tb_ip_reputation_sync
  WHERE direction = '2' AND reputation = '0'
),
agg_data AS (
  SELECT regexp_extract(ip, '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_c_seg,
         count(DISTINCT day) AS day_unique,
         count(DISTINCT ip) AS ip_unique,
         sum(log_num) / (count(DISTINCT day) + 1) AS total
  FROM ti.ads_ti_ip_heat_produce
  WHERE day BETWEEN 20260925 AND 20261001
  GROUP BY ip_c_seg
)
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 3600) */
       ip_c_seg, day_unique, ip_unique, total
FROM agg_data
WHERE day_unique >= 5
  AND NOT EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg);
