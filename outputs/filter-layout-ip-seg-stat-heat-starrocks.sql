-- filter-layout-ip-seg-stat-prc 的预聚合版草稿：改读用户给出的 ti.ads_ti_ip_heat_produce，不再展开原始审计日志的 str10。
-- 旧语句见 all.sql L17–44；直接读原始审计表的 StarRocks 版见 outputs/filter-layout-ip-seg-stat-starrocks.sql。
-- 表字段来自用户截图：ip、devid_cnt、log_num、top_devids。用户描述主键为 (ip, date)，截图的 SELECT * 没有显示 date 列，需确认。
-- 指标对应：log_num 对应旧语句 count(*)；ip 对应旧语句 resp 里 $.ip 按冒号拆出的 IP。
-- 以下几点材料和截图都没写明，口径一致与否未确认：
--   1) 聚合作业是否已带旧语句的过滤：app_id='ip-proxy-svc'、module_id='ip-proxy-svc'、str5 含 cf、threat.reputation=2、threat.direction=2；
--   2) 聚合表只存「IP 当天记录数 >= 5」。旧语句的 ip_unique 和 total 统计的是网段内所有 IP，阈值会让这两个值变小，day_unique 也可能变小；
--   3) log_num 统计的是审计行数还是 str10 展开后的 resp 条数，旧语句统计的是后者；
--   4) date 列的类型和格式。下面按 'yyyy-MM-dd' 字符串写，窗口沿用 all.sql 的 2026-09-25 至 2026-10-01。
-- DEC-009：log_num 的求和、day_unique >= 5 的比较需要按实际编码转换，这里没有加 CAST，写法需用户在新平台确认。
-- 规划时间见 DEC-022。该语句是整段窗口的批量扫描，不是 1~100 个 IP 的点查，不套用点查的 10s 基线。
WITH rpt AS (
  SELECT DISTINCT regexp_extract(ip, '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_seg
  FROM ti.ods_ti_db_intelligence_tb_ip_reputation_sync
  WHERE direction = '2' AND reputation = '0'
),
agg_data AS (
  SELECT regexp_extract(ip, '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_c_seg,
         count(DISTINCT `date`) AS day_unique,
         count(DISTINCT ip) AS ip_unique,
         sum(log_num) / (count(DISTINCT `date`) + 1) AS total
  FROM ti.ads_ti_ip_heat_produce
  WHERE `date` BETWEEN '2026-09-25' AND '2026-10-01'
  GROUP BY ip_c_seg
)
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 3600) */ ip_c_seg, day_unique, ip_unique, total
FROM agg_data
WHERE day_unique >= 5
  AND NOT EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg);
