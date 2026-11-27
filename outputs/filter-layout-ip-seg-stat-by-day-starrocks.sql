-- filter-layout-ip-seg-stat-prc 的逐天拆分版草稿：每天只扫一天原始审计，结果存中间表，再合并 7 天。
-- 目的：原 7 天语句无法执行、单天可以执行时，保持 7 天语义不变。原语句见 outputs/migratable-tasks-starrocks.sql 第 1 条（旧语句 all.sql L17–44）。
-- 中间表：<缺少新平台表名>，字段 day、ip_c_seg、ip、cnt。用户当次没有给出新平台表名，这里不自拟。建表语句和分区方式需按新平台规范决定。
-- 为什么等价：原语句的三个指标都能由「天 + 网段 + IP」粒度的次数还原：
--   day_unique = count(DISTINCT day)，ip_unique = count(DISTINCT ip)，total = sum(cnt) / (count(DISTINCT day) + 1)。
--   本机合成数据（9166 行审计、7 天）：原 7 天语句 118 行，拆分版 118 行，逐行一致；同一数据上原语句只取 1 天返回 0 行。
-- 重跑：中间表同一天重复写入会造成 cnt 翻倍，重跑前先删除该天数据，或建成主键表覆盖写入。
-- DEC-009：day 的比较、sum(cnt) 需要按实际编码转换，这里没有加 CAST。
-- day、module_id、str5、str10 缺少新平台字段名，保留旧名；hour 不涉及。

-- 步骤 1：每天执行一次，把 20261001 换成目标日期。7 天窗口执行 7 次（20260925 至 20261001）。
INSERT INTO `<缺少新平台表名>`
WITH resp_data AS (
  SELECT day AS date_day,
         split(get_json_object(resp, '$.ip'), ':')[1] AS ip,
         regexp_extract(split(get_json_object(resp, '$.ip'), ':')[1], '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_c_seg
  FROM csc.ods_csc_log_audit,
       unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~\\]', ''), '\\}\\,\\{', '\;\{'), '\"', '"'), ';')) AS exploded_table(resp)
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
    AND get_json_object(resp, '$.threat.reputation') = '2'
    AND get_json_object(resp, '$.threat.direction') = '2'
)
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 3600) */
       date_day, ip_c_seg, ip, count(*) AS cnt
FROM resp_data
GROUP BY date_day, ip_c_seg, ip;

-- 步骤 2：合并 7 天，沿用原语句的信誉表排除和 day_unique >= 5。
WITH rpt AS (
  SELECT DISTINCT regexp_extract(ip, '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_seg
  FROM ti.ods_ti_db_intelligence_tb_ip_reputation_sync
  WHERE direction = '2' AND reputation = '0'
),
agg_data AS (
  SELECT ip_c_seg,
         count(DISTINCT date_day) AS day_unique,
         count(DISTINCT ip) AS ip_unique,
         sum(cnt) / (count(DISTINCT date_day) + 1) AS total
  FROM `<缺少新平台表名>`
  WHERE date_day BETWEEN 20260925 AND 20261001
  GROUP BY ip_c_seg
)
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 3600) */ ip_c_seg, day_unique, ip_unique, total
FROM agg_data
WHERE day_unique >= 5
  AND NOT EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg);
