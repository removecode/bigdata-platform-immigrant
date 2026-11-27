# -*- coding: utf-8 -*-
"""在 StarRocks 上执行一条 SQL 的脚本模板。

连接信息只从环境变量读取，不写进代码：
  SR_HOST、SR_PORT、SR_USER、SR_PASSWORD；可选 SR_CATALOG（例如 paimon）。

SQL 的两种来源：
  1) 直接写在脚本里：三引号字符串前必须加 r 前缀。不加 r 时 Python 会处理反斜杠，
     正则里的 \\d、\\. 会被改掉，语句可能静默返回 0 行（见追踪文件 ACT-061、ACT-062）。
  2) 写在 YAML 里：SQL 用 | 字面块，不要用双引号或单引号。
     用法：python sr_query_template.py --yaml tasks.yaml --id 2

execute 只传 sql，不传参数，这样 SQL 里的 % 不会被当格式符。需要传参时用 %(name)s 并把字面 % 写成 %%。
"""

from __future__ import annotations

import argparse
import os

import pymysql
import yaml

INLINE_SQL = r"""
SELECT regexp_extract('10.1.2.3', '^(\\d+\\.\\d+\\.\\d+)\\.', 1) AS ip_seg
"""


def connect():
    conn = pymysql.connect(
        host=os.environ["SR_HOST"],
        port=int(os.environ.get("SR_PORT", "9030")),
        user=os.environ["SR_USER"],
        password=os.environ.get("SR_PASSWORD", ""),
        charset="utf8mb4",
        autocommit=True,
        connect_timeout=10,
        read_timeout=int(os.environ.get("SR_READ_TIMEOUT", "3700")),
    )
    catalog = os.environ.get("SR_CATALOG")
    if catalog:
        with conn.cursor() as cur:
            cur.execute("SET CATALOG " + catalog)
    return conn


def load_sql(path: str, sql_id: int) -> str:
    with open(path, encoding="utf-8") as fh:
        items = yaml.safe_load(fh)["sqls"]
    for item in items:
        if item["id"] == sql_id:
            return item["sql"]
    raise SystemExit("no sql with id %s in %s" % (sql_id, path))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--yaml")
    parser.add_argument("--id", type=int)
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()
    sql = load_sql(args.yaml, args.id) if args.yaml else INLINE_SQL
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(sql)
            print([col[0] for col in cur.description] if cur.description else [])
            for i, row in enumerate(cur):
                if i >= args.limit:
                    print("...")
                    break
                print(row)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
