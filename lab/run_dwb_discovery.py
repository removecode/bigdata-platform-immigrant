#!/usr/bin/env python3
"""Run outputs/dwb-ti-discovery-starrocks.sql on the lab StarRocks.

Creates scratch DB `dwb_lab` with tables that have the exact columns/types of the user's
paimon.ti.dwb_ti_* (docs/DWB合并表-paimon-ti-字段结构-SR.md; VARCHAR shortened to 512),
loads synthetic rows for several src_log values, rewrites `paimon.ti.` -> `dwb_lab.` and
catalog-level SHOW statements to lab equivalents only for execution. Never touches the
user's cluster. Result summary: outputs/dwb-ti-discovery-starrocks-results.tsv.
"""

from __future__ import annotations

import random
import re
import time
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parent.parent
SQL_PATH = ROOT / "outputs" / "dwb-ti-discovery-starrocks.sql"
OUT_PATH = ROOT / "outputs" / "dwb-ti-discovery-starrocks-results.tsv"
DB = "dwb_lab"
DAY = 20261101

V = "varchar(512)"
TABLES = {
    "dwb_ti_domain_info": [
        ("threatclass", "int"), ("threattype", "int"), ("threatsubtype", "int"),
        ("producttype", V), ("manage", V), ("productver", V), ("domain", V), ("engine", V),
        ("srcip", V), ("dstip", V), ("reqruleid", V), ("row_key", V), ("family", V),
        ("category", V), ("attr", V), ("add_time", V), ("action", "int"), ("agentid", V),
        ("tenant", V), ("log_num", "bigint"), ("attack_count", "bigint"), ("src_log", V),
        ("day", "bigint"),
    ],
    "dwb_ti_ip_info": [
        ("threatclass", "int"), ("threattype", "int"), ("threatsubtype", "int"),
        ("producttype", V), ("manage", V), ("productver", V), ("srcip", V), ("dstip", V),
        ("engine", V), ("object", V), ("direction", V), ("reqruleid", V), ("action", "int"),
        ("agentid", V), ("tenant", V), ("dstport", "int"), ("family", V), ("category", V),
        ("attr", V), ("add_time", V), ("log_num", "bigint"), ("attack_count", "bigint"),
        ("src_log", V), ("day", "bigint"),
    ],
    "dwb_ti_md5_info": [
        ("threatclass", "int"), ("threattype", "int"), ("threatsubtype", "int"),
        ("producttype", V), ("manage", V), ("productver", V), ("filehash", V), ("srcip", V),
        ("dstip", V), ("reqruleid", V), ("engine", V), ("tenant", V), ("agentid", V),
        ("file_attr", V), ("file_type", V), ("source_type", V), ("type", V), ("family", V),
        ("platform", V), ("upload_source", V), ("virus_name_hash", V), ("log_num", "bigint"),
        ("attack_count", "bigint"), ("src_log", V), ("day", "bigint"),
    ],
    "dwb_ti_url_info": [
        ("threatclass", "int"), ("threattype", "int"), ("threatsubtype", "int"),
        ("producttype", V), ("manage", V), ("productver", V), ("url", V), ("raw_url", V),
        ("engine", V), ("action", "int"), ("tenant", V), ("srcip", V), ("dstip", V),
        ("reqruleid", V), ("category", V), ("family", V), ("add_time", V),
        ("log_num", "bigint"), ("attack_count", "bigint"), ("src_log", V), ("day", "bigint"),
    ],
}

SRC_LOGS = {
    "dwb_ti_domain_info": ["domain-proxy-svc", "network_security_log", "dns_log", "log_audit"],
    "dwb_ti_ip_info": ["ip-proxy-svc", "network_security_log", "sip_iocstat_log", "log_audit"],
    "dwb_ti_md5_info": ["analysis-proxy-api", "endpoint_security_log", "log_audit"],
    "dwb_ti_url_info": ["url_log", "network_security_log"],
}


def connect():
    return pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", autocommit=True,
                           charset="utf8mb4")


def build(cur):
    cur.execute(f"DROP DATABASE IF EXISTS {DB} FORCE")
    cur.execute(f"CREATE DATABASE {DB}")
    rnd = random.Random(20261125)
    for tbl, cols in TABLES.items():
        ddl = ", ".join(f"`{c}` {t}" for c, t in cols)
        cur.execute(
            f"CREATE TABLE {DB}.{tbl} ({ddl}) DUPLICATE KEY(`threatclass`) "
            "DISTRIBUTED BY HASH(`threatclass`) BUCKETS 1 PROPERTIES('replication_num'='1')"
        )
        names = [c for c, _ in cols]
        rows = []
        for day in (DAY - 1, DAY):
            for src in SRC_LOGS[tbl]:
                for i in range(40):
                    r = {c: None for c in names}
                    r["src_log"] = src
                    r["day"] = day
                    r["manage"] = f"dev{rnd.randint(1, 8):02d}"
                    r["producttype"] = rnd.choice(["AF", "EDR", "NGAF", None])
                    r["productver"] = "v1"
                    r["log_num"] = rnd.randint(1, 9)
                    r["attack_count"] = rnd.randint(1, 9)
                    r["engine"] = rnd.choice(["e1", "e2", None])
                    r["family"] = rnd.choice(["fam", None])
                    r["category"] = rnd.choice(["c2", None])
                    if src in ("network_security_log", "endpoint_security_log", "sip_iocstat_log"):
                        r["threatclass"] = rnd.choice([209, 208, 40, 30])
                        r["threattype"] = rnd.choice([13, 10, 1])
                        r["threatsubtype"] = 0
                        r["reqruleid"] = str(rnd.choice([140000001, 149999990, 5, 17830043]))
                    if "domain" in names and tbl == "dwb_ti_domain_info":
                        r["domain"] = f"d{rnd.randint(1, 15)}.example.com"
                        r["row_key"] = r["domain"] if src != "domain-proxy-svc" else None
                        r["attr"] = rnd.choice(["0", "1"])
                        r["action"] = rnd.choice([1, 2, None])
                    if tbl == "dwb_ti_ip_info":
                        r["dstip"] = f"203.0.113.{rnd.randint(1, 20)}"
                        r["srcip"] = f"198.51.100.{rnd.randint(1, 20)}" if src != "ip-proxy-svc" else None
                        r["dstport"] = rnd.choice([80, 443, None])
                        r["object"] = rnd.choice(["ip", None])
                        r["direction"] = rnd.choice(["1", "2"])
                        r["attr"] = rnd.choice(["0", "2"])
                    if tbl == "dwb_ti_md5_info":
                        r["filehash"] = "".join(rnd.choice("0123456789abcdef") for _ in range(32))
                        r["file_attr"] = rnd.choice(["0", "1", "2"])
                        r["upload_source"] = rnd.choice(["file_hash", "file_scan", None])
                        r["type"] = "av"
                    if tbl == "dwb_ti_url_info":
                        r["url"] = f"http://u{rnd.randint(1, 15)}.example.com/p"
                        r["raw_url"] = r["url"] + "?x=1"
                    rows.append(tuple(r[c] for c in names))
        ph = ", ".join(["%s"] * len(names))
        cur.executemany(f"INSERT INTO {DB}.{tbl} ({', '.join('`'+c+'`' for c in names)}) VALUES ({ph})", rows)


def split_statements(text: str):
    out, buf = [], []
    label = None
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"--\s*(@dwb\s+\S+)", s)
        if m and not buf:
            label = m.group(1)
        if s.startswith("--") or not s:
            continue
        buf.append(line)
        if s.endswith(";"):
            out.append((label, "\n".join(buf).rstrip().rstrip(";")))
            buf = []
    return out


LAB_REWRITE = [
    ("SHOW DATABASES FROM paimon", "SHOW DATABASES"),
    ("SHOW TABLES FROM paimon.ti", f"SHOW TABLES FROM {DB}"),
    ("SHOW TABLES FROM paimon.csc", f"SHOW TABLES FROM {DB}"),
    ("paimon.ti.", f"{DB}."),
]


def main():
    text = SQL_PATH.read_text()
    stmts = split_statements(text)
    conn = connect()
    cur = conn.cursor()
    build(cur)
    lines = ["label\tstatus\trows\tms\tnote"]
    bad = 0
    for label, sql in stmts:
        _ = sql % ()
        run = sql
        for a, b in LAB_REWRITE:
            run = run.replace(a, b)
        t0 = time.time()
        try:
            cur.execute(run)
            rows = cur.fetchall()
            status, n, note = "ok", len(rows), ""
        except Exception as e:  # noqa: BLE001
            status, n, note = "ERR", 0, str(e)[:200].replace("\t", " ").replace("\n", " ")
            bad += 1
        ms = int((time.time() - t0) * 1000)
        lines.append(f"{label}\t{status}\t{n}\t{ms}\t{note}")
        print(label, status, n, note)
    OUT_PATH.write_text("\n".join(lines) + "\n")
    cur.execute(f"DROP DATABASE IF EXISTS {DB} FORCE")
    print("statements", len(stmts), "errors", bad)
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
