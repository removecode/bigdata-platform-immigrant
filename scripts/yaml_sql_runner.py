# -*- coding: utf-8 -*-
"""从 YAML 读取 SQL，经后端连接执行（Hive 或 StarRocks）。Hue 能跑、YAML 不能跑，多半是 YAML 写法或 Python 又吃了一层反斜杠。

推荐 YAML 写法见 outputs/app-queries-example.yaml。要点（ACT-061、ACT-062）：
  - SQL 必须用 | 或 |- 字面块，不要用双引号包整段 SQL。
  - execute 只传 SQL 字符串，不要传空 dict 参数（否则 % 会被当格式符）。
  - 不要用 string.Template.substitute / str.format 处理含 $.ip 或 {1,3} 的 SQL。
  - Hive 占位符用 %(name)s + MySQLdb/pymysql 字典参数；不要用 :name。
  - StarRocks filter-layout 用 v2 预处理（outputs/filter-layout-ip-seg-stat-starrocks-v2.sql），不要用 all.sql/v1 转义。

用法：
  # 只检查 YAML 解析出的 SQL 文本（不连库）
  python yaml_sql_runner.py --yaml queries.yaml --key filter_layout_ip_seg --sql-only

  # 与 Hue 导出的 .sql 文件逐字节对比
  python yaml_sql_runner.py --yaml queries.yaml --key filter_layout_ip_seg --diff /path/from_hue.sql

  # 执行 StarRocks（连接读环境变量 SR_*）
  export SR_HOST=... SR_PORT=32013 SR_USER=... SR_PASSWORD=...
  python yaml_sql_runner.py --yaml queries.yaml --key filter_layout_ip_seg

  # 执行 Hive（需 scia SDK，连接超时等见环境变量 HIVE_QUERY_TIMEOUT）
  python yaml_sql_runner.py --yaml queries.yaml --key some_hive_query --engine hive

环境变量：
  StarRocks: SR_HOST, SR_PORT, SR_USER, SR_PASSWORD, SR_CATALOG（可选 paimon）, SR_READ_TIMEOUT（默认 7500）
  Hive: HIVE_QUERY_TIMEOUT（默认 3600）；tez 队列等写在 YAML 条目的 hive_configuration 里。
"""
from __future__ import print_function

import argparse
import hashlib
import io
import json
import os
import sys
import time

try:
    text_type = unicode  # noqa: F821  # Python 2
except NameError:
    text_type = str

import yaml

try:
    import pymysql
except ImportError:
    pymysql = None


def load_yaml(path):
    with io.open(path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def normalize_sql(sql):
    if sql is None:
        return u""
    if not isinstance(sql, text_type):
        sql = text_type(sql, "utf-8") if isinstance(sql, bytes) else text_type(sql)
    sql = sql.strip()
    while sql.endswith(u";"):
        sql = sql[:-1].rstrip()
    return sql


def find_entry(doc, key=None, sql_id=None):
    items = doc.get("sqls")
    if items is None:
        items = doc.get("queries")
    if not items:
        raise SystemExit("yaml has no sqls: or queries: list")
    if key is not None:
        for item in items:
            if item.get("key") == key or item.get("name") == key:
                return item
        raise SystemExit("no entry with key/name %r" % (key,))
    if sql_id is not None:
        for item in items:
            if item.get("id") == sql_id:
                return item
        raise SystemExit("no entry with id %s" % sql_id)
    raise SystemExit("pass --key or --id")


def entry_engine(entry, override):
    if override:
        return override
    eng = entry.get("engine") or entry.get("dialect") or "starrocks"
    return eng.lower()


def sql_fingerprint(sql):
    return hashlib.sha256(sql.encode("utf-8")).hexdigest()[:16]


def print_sql_diagnostics(sql, label):
    print("[%s] chars=%d sha256_16=%s" % (label, len(sql), sql_fingerprint(sql)))
    print("[%s] first 120 repr: %s" % (label, repr(sql[:120])))
    if "\\d" in sql and "\\\\d" not in sql:
        print("[%s] WARN: found \\d without \\\\d — Python/YAML may have eaten backslashes" % label)


def run_starrocks(entry, sql, max_rows):
    if pymysql is None:
        raise SystemExit("pymysql not installed")
    for var in ("SR_HOST", "SR_USER"):
        if not os.environ.get(var):
            raise SystemExit("missing env %s" % var)

    session = entry.get("session") or {}
    read_timeout = int(
        session.get("read_timeout")
        or os.environ.get("SR_READ_TIMEOUT")
        or max(int(session.get("query_timeout", 3600)) + 300, 7500)
    )

    conn = pymysql.connect(
        host=os.environ["SR_HOST"],
        port=int(os.environ.get("SR_PORT", "9030")),
        user=os.environ["SR_USER"],
        passwd=os.environ.get("SR_PASSWORD", ""),
        charset="utf8mb4",
        connect_timeout=int(session.get("connect_timeout", 60)),
        read_timeout=read_timeout,
        write_timeout=read_timeout,
        autocommit=True,
    )
    try:
        with conn.cursor() as cur:
            catalog = session.get("catalog") or os.environ.get("SR_CATALOG")
            if catalog:
                cur.execute("SET CATALOG %s" % catalog)
            qtimeout = session.get("query_timeout")
            if qtimeout is not None:
                cur.execute("SET query_timeout = %s" % int(qtimeout))
            planner = session.get("new_planner_optimize_timeout")
            if planner is not None:
                cur.execute("SET new_planner_optimize_timeout = %s" % int(planner))

            t0 = time.time()
            cur.execute(sql)
            cols = [d[0] for d in cur.description] if cur.description else []
            count = 0
            if cols:
                print("\t".join(text_type(c) for c in cols))
            while True:
                row = cur.fetchone()
                if row is None:
                    break
                count += 1
                if count <= max_rows:
                    print("\t".join(to_cell(v) for v in row))
                elif count == max_rows + 1:
                    print("...")
            cost = time.time() - t0
            print("[sr] done, rows=%d, cost=%.2fs" % (count, cost))
    finally:
        conn.close()


def to_cell(v):
    if v is None:
        return u"NULL"
    if isinstance(v, bytes):
        return v.decode("utf-8", "replace")
    return text_type(v)


def run_hive(entry, sql, max_rows, timeout):
    from scia.dao.hive import HiveDao

    run_config = entry.get("hive_configuration") or entry.get("hive_run_config") or {"tez.queue.name": "etl"}
    cli = HiveDao(timeout=timeout)
    t0 = time.time()
    count = 0
    with cli.cursor() as cursor:
        cursor.execute(sql, configuration=run_config)
        columns = [item[0] for item in cursor.description] if cursor.description else []
        if columns:
            print("\t".join(text_type(c) for c in columns))
        while True:
            row = cursor.fetchone()
            if row is None:
                break
            count += 1
            if count <= max_rows:
                if columns:
                    data = dict(zip(columns, row))
                    print("\t".join(to_cell(data.get(c)) for c in columns))
                else:
                    print(row)
            elif count == max_rows + 1:
                print("...")
    print("[hive] done, rows=%d, cost=%.2fs" % (count, time.time() - t0))


def main():
    parser = argparse.ArgumentParser(description="Execute SQL from YAML (Hive or StarRocks)")
    parser.add_argument("--yaml", required=True, help="path to queries yaml")
    parser.add_argument("--key", help="entry key or name")
    parser.add_argument("--id", type=int, help="entry id (migratable-tasks format)")
    parser.add_argument("--engine", choices=("hive", "starrocks"), help="override yaml engine")
    parser.add_argument("--sql-only", action="store_true", help="print sql only, no execute")
    parser.add_argument("--diff", metavar="FILE", help="compare yaml sql to a .sql file byte-for-byte")
    parser.add_argument("--max-rows", type=int, default=20, help="max rows to print (default 20)")
    args = parser.parse_args()

    doc = load_yaml(args.yaml)
    entry = find_entry(doc, key=args.key, sql_id=args.id)
    sql = normalize_sql(entry.get("sql") or entry.get("hive_sql") or entry.get("statement"))
    if not sql:
        raise SystemExit("entry has empty sql")

    print("[yaml] file=%s key=%s id=%s engine=%s" % (
        args.yaml,
        entry.get("key") or entry.get("name") or args.key,
        entry.get("id"),
        entry_engine(entry, args.engine),
    ))
    print_sql_diagnostics(sql, "yaml")

    if args.diff:
        with io.open(args.diff, "r", encoding="utf-8") as fh:
            other = normalize_sql(fh.read())
        print_sql_diagnostics(other, "diff")
        if sql == other:
            print("[diff] OK: identical after strip/trailing-semicolon")
        else:
            print("[diff] MISMATCH: len yaml=%d diff=%d" % (len(sql), len(other)))
            for i, (a, b) in enumerate(zip(sql, other)):
                if a != b:
                    print("[diff] first diff at index %d: yaml %r vs file %r" % (i, a, b))
                    break
            else:
                print("[diff] one side is prefix of the other")
            sys.exit(1)

    if args.sql_only:
        print("[yaml] --- sql begin ---")
        if sys.version_info[0] == 2:
            sys.stdout.write(sql.encode("utf-8"))
            sys.stdout.write("\n")
        else:
            print(sql)
        print("[yaml] --- sql end ---")
        return

    eng = entry_engine(entry, args.engine)
    timeout = int(entry.get("timeout") or os.environ.get("HIVE_QUERY_TIMEOUT", "3600"))

    if eng == "hive":
        run_hive(entry, sql, args.max_rows, timeout)
    elif eng in ("starrocks", "sr"):
        run_starrocks(entry, sql, args.max_rows)
    else:
        raise SystemExit("unknown engine %r" % eng)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("[yaml_sql_runner] failed: %s" % exc, file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
