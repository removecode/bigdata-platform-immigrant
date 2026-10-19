-- 诊断 filter-layout-ip-seg-stat-prc 在 1 小时窗口里展开后没有 resp 满足过滤条件（见 ACT-059）的原因。
-- 只取前 1000 行审计，不扫整个小时。day、hour 沿用 ACT-057 的写法，hour 列是否存在、类型未确认。
-- DEC-009：day、hour 的比较没有加 CAST。

-- 查询 1：原始 str10 样本，看 JSON 里引号是否带反斜杠、元素之间的分隔形式。
SELECT str10
FROM csc.ods_csc_log_audit
WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
  AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
LIMIT 3;

-- 查询 2：与原语句相同的预处理和展开后，reputation、direction 的取值分布。
-- rep 和 dr 为 NULL 表示 get_json_object 没解析出来，常见原因是转义没处理对；
-- 有取值但不是 '2'，说明解析正常、只是这批数据没有命中。
SELECT get_json_object(resp, '$.threat.reputation') AS rep,
       get_json_object(resp, '$.threat.direction') AS dr,
       get_json_object(resp, '$.ip') IS NOT NULL AS has_ip,
       count(*) AS n
FROM (
  SELECT str10
  FROM csc.ods_csc_log_audit
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
  LIMIT 1000
) a,
unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~\\]', ''), '\\}\\,\\{', '\;\{'), '\"', '"'), ';')) AS exploded_table(resp)
GROUP BY rep, dr, has_ip
ORDER BY n DESC
LIMIT 20;

-- 查询 3：同一批 1000 行审计，对比两种预处理写法能解析出多少元素。
--   all_sql：当前语句用的写法，`},{` 换成 `;{`（丢掉 `}`），`\"` 的替换在 StarRocks 里等于空操作；
--   csv_917：917 梳理 CSV 的语义，`},{` 换成 `};{`，把 `\"` 换成 `"`（ACT-047 记录的差异，DEC-024 选了 all.sql）。
-- parsed 是 $.threat.reputation 能解析出值的元素数，hit 是同时满足 reputation = '2' 与 direction = '2' 的元素数。
-- 两行 parsed 差距大，说明预处理写法决定了能解析多少元素，需要确认现网 Hive 实际执行的是哪一版。
WITH src AS (
  SELECT str10
  FROM csc.ods_csc_log_audit
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
  LIMIT 1000
),
v1 AS (
  SELECT resp
  FROM src, unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~\\]', ''), '\\}\\,\\{', '\;\{'), '\"', '"'), ';')) AS t(resp)
),
v2 AS (
  SELECT resp
  FROM src, unnest(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~\\]', ''), '\\}\\,\\{', '};{'), '\\"', '"'), ';')) AS t(resp)
)
SELECT 'all_sql' AS version, count(*) AS elements,
       sum(CASE WHEN get_json_object(resp, '$.threat.reputation') IS NOT NULL THEN 1 ELSE 0 END) AS parsed,
       sum(CASE WHEN get_json_object(resp, '$.threat.reputation') = '2' AND get_json_object(resp, '$.threat.direction') = '2' THEN 1 ELSE 0 END) AS hit
FROM v1
UNION ALL
SELECT 'csv_917', count(*),
       sum(CASE WHEN get_json_object(resp, '$.threat.reputation') IS NOT NULL THEN 1 ELSE 0 END),
       sum(CASE WHEN get_json_object(resp, '$.threat.reputation') = '2' AND get_json_object(resp, '$.threat.direction') = '2' THEN 1 ELSE 0 END)
FROM v2;

-- 查询 4：展开后的行数里，有多少是真元素，有多少是被值里的分号多拆出来的碎片（见 ACT-063）。
-- 现在的预处理把元素之间的 `},{` 换成 `;{`，再按 `;` 拆。JSON 字段值里如果本身带分号（比如 User-Agent），也会被拆开。
--   rows：取样的审计行数；
--   avg_by_separator：按 `},{` 个数算出的平均元素数，每行 = `},{` 个数 + 1；
--   avg_by_split：按现在的写法拆出来的平均行数；
--   avg_raw_semicolons：str10 原文里本来就有的分号个数。
-- avg_by_split 明显大于 avg_by_separator，说明有一部分展开是碎片，这部分碎片解析不出字段，却占用展开和解析的开销。
SELECT count(*) AS rows_n,
       avg((length(str10) - length(replace(str10, '},{', ''))) / 3 + 1) AS avg_by_separator,
       avg(array_length(split(replace(regexp_replace(regexp_replace(regexp_replace(str10, '^\\[', ''), '~\\]', ''), '\\}\\,\\{', '\;\{'), '\"', '"'), ';'))) AS avg_by_split,
       avg(length(str10) - length(replace(str10, ';', ''))) AS avg_raw_semicolons
FROM (
  SELECT str10
  FROM csc.ods_csc_log_audit
  WHERE app_id = 'ip-proxy-svc' AND day = 20261001 AND hour = 0
    AND module_id = 'ip-proxy-svc' AND str5 REGEXP 'cf'
  LIMIT 1000
) a;
