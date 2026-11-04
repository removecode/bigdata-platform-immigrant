-- filter-layout-ip-seg-stat-prc 的 StarRocks 语句 v2：按用户给出的真实日志格式修正预处理。
-- v1 见 outputs/filter-layout-ip-seg-stat-starrocks.sql 和 outputs/migratable-tasks-starrocks.sql 第 1 条；v1 在真实格式的数据上返回 0 行。
-- 本文件没有替换 v1，是否取代 v1 等用户确认（DEC-024 当时选了 all.sql 的写法，本次证据与它冲突，见 ACT-064）。
--
-- 用户提供的真实日志（ip-proxy-svc，一行）：
--   str10 = [{\"ip\":\"61.147.175.38:443\",\"network\":{...},\"threat\":{\"reputation\":\"2\",...,\"direction\":2}}]
--   即：引号前带反斜杠（\"）；末尾是 ]，没有 ~；reputation 是字符串，direction 是数字 2。
--   这里按显示内容当作原文处理；控制台显示的反斜杠是否就是存储内容，用户日志里 stored 值需确认。
-- 与 v1 的区别（共三处，全部来自上面的真实格式）：
--   1) `\"` 的替换写成 '\\"'（StarRocks 里是两个字符 \"），v1 的 '\"' 在 StarRocks 里只是一个双引号，替换等于空操作；
--   2) `},{` 换成 `};{`（保留右花括号），v1 换成 `;{` 会丢掉 }，非末尾元素变成不合法 JSON；
--   3) 末尾的 ] 用 '~?\\]$' 去掉。StarRocks 的 get_json_object 遇到对象后面多出的 ] 返回 NULL，Hive 则容忍，
--      所以旧平台没有这一步也能解析最后一个元素，StarRocks 必须去掉。
-- 本机验证：Hive 4.0.1 上用 917 梳理 CSV 的原文，对 242 条真实格式的日志展开，命中 156 行；
--   本语句的 resp_data 在 StarRocks 3.5.21 上同一批日志命中 156 行，逐行一致；v1 在同一批日志上是 0 行。
-- 未覆盖：字段值里带分号时 `;` 拆分会把元素截断，Hive 和本语句行为一致（都丢失该元素），本语句没有修复，也没有改变。
-- DEC-009：day 的 BETWEEN、day_unique >= 5 的比较需要按实际编码转换，这里没有加 CAST。
-- csc.ods_csc_log_audit 依赖连接的当前 catalog 是 paimon，或改写成 paimon.csc.ods_csc_log_audit（见 ACT-062）。
-- 日期窗口、day_unique 沿用 all.sql；规划超时和 query_timeout 见 DEC-022、DEC-024。
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
       unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~?\\]$', ''), '\\}\\,\\{', '};{'), '\\"', '"'), ';')) AS exploded_table(resp)
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
