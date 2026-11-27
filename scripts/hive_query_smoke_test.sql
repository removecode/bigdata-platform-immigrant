-- hive_query.py 功能冒烟（Hive / HiveServer2，非 StarRocks）
--
-- 用途：确认脚本能连上 Hive、execute 返回、fetchone 打印行、最后打出 done。
-- 不扫业务表，不跑 Tez 大作业；一般几秒内结束。
--
-- 用法（在 SOAPA / 有 scia SDK 的机器上）：
--   python2 hive_query.py /path/to/hive_query_smoke_test.sql
-- 或你当前的 python：
--   python hive_query.py hive_query_smoke_test.sql
--
-- 预期：
--   [hive] row 0: {u'n': 1, u'label': u'hive_query smoke'}  （Py2 键可能是 str）
--   ... 共 3 行 ...
--   [hive] done, total rows: 3, cost: x.xxs
--
-- 仅自检 SQL 文本、不连库：
--   python2 hive_query.py --sql-only hive_query_smoke_test.sql

SELECT 1 AS n, 'hive_query smoke' AS label
UNION ALL
SELECT 2 AS n, 'row_two' AS label
UNION ALL
SELECT 3 AS n, 'row_three' AS label
