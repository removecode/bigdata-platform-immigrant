#!/usr/bin/env python3
"""Run the migratable StarRocks statements the way a background job does: SQL lives in a YAML file,
the program parses the YAML and sends each string to StarRocks through MySQLdb.

Steps
  1. Write outputs/migratable-tasks-starrocks.yaml from outputs/migratable-tasks-starrocks.sql (literal `|` blocks).
  2. yaml.safe_load it, check each parsed string equals the source text byte for byte.
  3. Execute every parsed string with MySQLdb on the lab StarRocks (scratch DB mig_lab, synthetic data) and compare
     row counts with outputs/migratable-tasks-starrocks-results.tsv.
  4. Run small experiments for the places where a YAML + driver layer can change SQL text.
It only talks to the local lab StarRocks. Nothing here touches the user's StarRocks.
"""

from __future__ import annotations

import csv
import string
import sys
import time
from pathlib import Path

import MySQLdb
import pymysql
import yaml

LAB = Path(__file__).resolve().parent
ROOT = LAB.parent
sys.path.insert(0, str(LAB))
import run_migratable as rm  # noqa: E402

YAML_PATH = ROOT / "outputs" / "migratable-tasks-starrocks.yaml"
OUT_PATH = ROOT / "outputs" / "migratable-tasks-starrocks-yaml-results.tsv"
BASE_TSV = ROOT / "outputs" / "migratable-tasks-starrocks-results.tsv"


class Literal(str):
    pass


yaml.add_representer(Literal, lambda d, v: d.represent_scalar("tag:yaml.org,2002:str", v, style="|"))


def write_yaml(stmts) -> str:
    items = [{"id": s["id"], "app": s["app"], "segment": s["seg"], "sql": Literal(s["sql"])} for s in stmts]
    text = yaml.dump({"sqls": items}, allow_unicode=True, sort_keys=False, width=10**6)
    YAML_PATH.write_text("# 由 lab/run_yaml_sql.py 从 outputs/migratable-tasks-starrocks.sql 生成；SQL 用 | 字面块，不经过 YAML 转义。\n" + text, encoding="utf-8")
    return text


def connect():
    return MySQLdb.connect(host="127.0.0.1", port=9030, user="root", passwd="", charset="utf8mb4", autocommit=True)


def try_exec(cur, sql, args=None):
    try:
        cur.execute(sql, args) if args is not None else cur.execute(sql)
        return "ok", cur.fetchall()
    except Exception as exc:  # noqa: BLE001
        return "error", f"{type(exc).__name__}: {str(exc)[:150]}"


def main() -> None:
    stmts = rm.parse_statements(rm.SQL_PATH.read_text(encoding="utf-8"))
    raw = write_yaml(stmts)
    literal_blocks = raw.count("sql: |")
    print(f"yaml: {len(stmts)} statements, {literal_blocks} written as literal blocks")

    parsed = yaml.safe_load(YAML_PATH.read_text(encoding="utf-8"))["sqls"]
    same = [p["sql"] == s["sql"] for p, s in zip(parsed, stmts)]
    print(f"round trip: {sum(same)}/{len(same)} parsed strings identical to the source text")

    base = {r["id"]: r for r in csv.DictReader(open(BASE_TSV, encoding="utf-8"), delimiter="\t")}

    seeder = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", charset="utf8mb4", autocommit=True)
    rm.seed(seeder.cursor())
    conn = connect()
    cur = conn.cursor()

    lines = ["id\tapp\tsegment\tstatus\trows\tbaseline_rows\tmatch\tseconds\terror"]
    for item in parsed:
        sql = rm.rewrite(item["sql"])
        t0 = time.time()
        status, res = try_exec(cur, sql)
        secs = time.time() - t0
        rows = len(res) if status == "ok" else ""
        b = base[str(item["id"])]["rows"]
        match = "yes" if status == "ok" and str(rows) == b else "no"
        err = "" if status == "ok" else res.replace("\t", " ")
        lines.append(f"{item['id']}\t{item['app']}\t{item['segment']}\t{status}\t{rows}\t{b}\t{match}\t{secs:.2f}\t{err}")
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))

    print("\n--- experiments ---")
    s1 = parsed[0]["sql"]
    s2 = parsed[1]["sql"]

    print("[paramstyle] named style :day_min / pyformat %(day_min)s through MySQLdb")
    print("  :day_min      ->", try_exec(cur, "SELECT :day_min AS d", {"day_min": 20260925}))
    print("  %(day_min)s   ->", try_exec(cur, "SELECT %(day_min)s AS d", {"day_min": 20260925}))
    print("  %(day_min)s as str ->", try_exec(cur, "SELECT %(day_min)s AS d", {"day_min": "20260925"}))

    print("[percent] a literal % in SQL when the program passes arguments")
    print("  args=None     ->", try_exec(cur, "SELECT 'a%b' AS p"))
    print("  args={}       ->", try_exec(cur, "SELECT 'a%b' AS p", {}))
    print("  args={}, %%   ->", try_exec(cur, "SELECT 'a%%b' AS p", {}))

    print("[template] string.Template and str.format on the real statements")
    for name, text in (("stmt1 filter-layout", s1), ("stmt2 C2_IP_SECURITY_LOG_SQL", s2)):
        try:
            string.Template(text).substitute(day=1)
            r1 = "ok"
        except Exception as exc:  # noqa: BLE001
            r1 = f"{type(exc).__name__}: {exc}"
        r2 = "unchanged" if string.Template(text).safe_substitute(day=1) == text else "changed"
        try:
            text.format(1, 2)
            r3 = "ok"
        except Exception as exc:  # noqa: BLE001
            r3 = f"{type(exc).__name__}: {str(exc)[:60]}"
        print(f"  {name}: Template.substitute={r1} | safe_substitute={r2} | str.format={r3}")

    print("[yaml style] the same statement written by hand in each YAML style")
    body = s2
    variants = {
        "literal |": "sql: |\n" + "\n".join("  " + l for l in body.split("\n")) + "\n",
        'double-quoted "..."': 'sql: "' + body.replace("\n", " ") + '"\n',
        "single-quoted '...'": "sql: '" + body.replace("\n", " ") + "'\n",
        "plain (no quotes)": "sql: " + body.replace("\n", " ") + "\n",
    }
    for k, v in variants.items():
        try:
            got = yaml.safe_load(v)["sql"]
            ok = " ".join(got.split()) == " ".join(body.split())
            print(f"  {k}: parsed, text identical={ok}")
        except Exception as exc:  # noqa: BLE001
            print(f"  {k}: {type(exc).__name__}: {str(exc).splitlines()[0][:90]}")

    print("[named param end to end] statement 1 with %(day_min)s / %(day_max)s from YAML, args passed to MySQLdb")
    p = s1.replace("day BETWEEN 20260925 AND 20261001", "day BETWEEN %(day_min)s AND %(day_max)s")
    assert p != s1
    p = p.replace("%", "%%").replace("%%(day_min)s", "%(day_min)s").replace("%%(day_max)s", "%(day_max)s")
    for label, args in (("int", {"day_min": 20260925, "day_max": 20261001}), ("str", {"day_min": "20260925", "day_max": "20261001"})):
        st, res = try_exec(cur, rm.rewrite(p), args)
        print(f"  args as {label}: {st}, rows={len(res) if st == 'ok' else res}, baseline={base['1']['rows']}")

    cur.execute(f"DROP DATABASE {rm.DB}")
    print("scratch database dropped")


if __name__ == "__main__":
    main()
