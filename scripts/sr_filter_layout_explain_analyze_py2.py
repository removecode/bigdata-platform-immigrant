# -*- coding: utf-8 -*-
"""Python 2.7：在 StarRocks 执行 filter-layout 1 小时 EXPLAIN ANALYZE。

连接环境变量：SR_HOST、SR_PORT、SR_USER、SR_PASSWORD；可选 SR_CATALOG=paimon。
SQL 与 outputs/filter-layout-ip-seg-stat-explain-analyze-starrocks.sql 一致，
query_timeout 提示为 7200 秒（用户诊断用）；改 day/hour 请改下方 SQL。

必须用 r 前缀三引号，否则正则反斜杠会被 Python 吃掉（ACT-062）。
"""
from __future__ import print_function

import os
import sys
import time

import pymysql

# 与仓库诊断版一致；仅 query_timeout 改为 7200。day / hour 按需要修改。
SQL = r"""
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
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 7200) */ ip_c_seg, day_unique, ip_unique, total
FROM agg_data
WHERE day_unique >= 5
  AND NOT EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg)
"""


def main():
    for key in ('SR_HOST', 'SR_USER'):
        if not os.environ.get(key):
            print('missing env %s' % key, file=sys.stderr)
            sys.exit(2)

    read_timeout = int(os.environ.get('SR_READ_TIMEOUT', '7500'))
    conn = pymysql.connect(
        host=os.environ['SR_HOST'],
        port=int(os.environ.get('SR_PORT', '9030')),
        user=os.environ['SR_USER'],
        passwd=os.environ.get('SR_PASSWORD', ''),
        charset='utf8mb4',
        connect_timeout=10,
        read_timeout=read_timeout,
    )
    t0 = time.time()
    try:
        with conn.cursor() as cursor:
            catalog = os.environ.get('SR_CATALOG')
            if catalog:
                cursor.execute('SET CATALOG %s' % catalog)
            cursor.execute(SQL.strip())
            n = 0
            for row in cursor:
                n += 1
                # EXPLAIN ANALYZE 通常一列多行文本
                print(row[0] if len(row) == 1 else row)
            print('[sr] done, plan lines: %d, cost: %.2fs' % (n, time.time() - t0))
    finally:
        conn.close()


if __name__ == '__main__':
    main()
