#!/usr/bin/env python3
"""Run outputs/dwb-consumers-after-starrocks.sql on the lab StarRocks with synthetic data.

Scratch DB `dwb_cons` holds: dwb_ti_domain_info / dwb_ti_ip_info (real merged-table columns and types,
VARCHAR shortened), the two reputation tables, and ods_custom_upload_data. Names are rewritten
only for execution (paimon.ti. / ti.ods_ti_ / `default`.ods_custom_upload_data -> dwb_cons.).
Each statement is checked against a hand-computed expectation. Never touches the user's cluster.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pymysql

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_dwb_discovery as r  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SQL_PATH = ROOT / "outputs" / "dwb-consumers-after-starrocks.sql"
OUT_PATH = ROOT / "outputs" / "dwb-consumers-after-starrocks-results.tsv"
DB = "dwb_cons"

SODL_DOMAIN = ["network_security_log", "dns_log", "sip_iocstat_log", "endpoint_security_log", "url_log"]


def conn():
    return pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", autocommit=True, charset="utf8mb4")


def make_tables(cur):
    cur.execute(f"DROP DATABASE IF EXISTS {DB} FORCE")
    cur.execute(f"CREATE DATABASE {DB}")
    for tbl in ("dwb_ti_domain_info", "dwb_ti_ip_info"):
        ddl = ", ".join(f"`{c}` {t}" for c, t in r.TABLES[tbl])
        cur.execute(
            f"CREATE TABLE {DB}.{tbl} ({ddl}) DUPLICATE KEY(`threatclass`) "
            "DISTRIBUTED BY HASH(`threatclass`) BUCKETS 1 PROPERTIES('replication_num'='1')"
        )
    cur.execute(
        f"CREATE TABLE {DB}.ods_ti_db_intelligence_tb_ip_reputation_sync "
        "(ip varchar(64), port int, direction varchar(8), expire_time bigint, deleted_time bigint) "
        "DUPLICATE KEY(ip) DISTRIBUTED BY HASH(ip) BUCKETS 1 PROPERTIES('replication_num'='1')"
    )
    cur.execute(
        f"CREATE TABLE {DB}.ods_ti_db_domain_intelligence_tb_domain_reputation_sync "
        "(domain varchar(256), labels varchar(512), label_details varchar(512), add_time varchar(64), "
        "deleted_time bigint, reputation varchar(8)) "
        "DUPLICATE KEY(domain) DISTRIBUTED BY HASH(domain) BUCKETS 1 PROPERTIES('replication_num'='1')"
    )
    cur.execute(
        f"CREATE TABLE {DB}.ods_custom_upload_data (part1 varchar(64), part2 varchar(64), str1 varchar(256)) "
        "DUPLICATE KEY(part1) DISTRIBUTED BY HASH(part1) BUCKETS 1 PROPERTIES('replication_num'='1')"
    )


def insert(cur, tbl, rows):
    cols = [c for c, _ in r.TABLES[tbl]]
    ph = ", ".join(["%s"] * len(cols))
    data = [tuple(row.get(c) for c in cols) for row in rows]
    cur.executemany(f"INSERT INTO {DB}.{tbl} ({', '.join('`'+c+'`' for c in cols)}) VALUES ({ph})", data)


def seed(cur):
    dom = []

    def d(src, day, manage, domain, log_num=1, attack=1, row_key=None, tc=None):
        dom.append(dict(src_log=src, day=day, manage=manage, domain=domain, log_num=log_num,
                        attack_count=attack, row_key=row_key, threatclass=tc))

    # domain-heat (day 20260930): cloud / second level / third level, plus audit rows that must be excluded
    d("network_security_log", 20260930, "devA", "a.s3.amazonaws.com", 5)
    d("network_security_log", 20260930, "devB", "a.s3.amazonaws.com", 7)
    d("domain-proxy-svc", 20260930, "devC", "a.s3.amazonaws.com", 100)
    d("dns_log", 20260930, "devA", "foo.bar.com.cn", 6)
    d("dns_log", 20260930, "devB", "foo.bar.com.cn", 6)
    d("network_security_log", 20260930, "devA", "www.evil.net", 11)
    d("domain-proxy-svc", 20260930, "devC", "www.evil.net", 50)
    d("network_security_log", 20260930, "devA", "low.test.org", 3)
    d("network_security_log", 20260930, "devA", "10.1.1.1.x", 99)
    d("network_security_log", 20260930, "devA", "has_us.evil2.net", 99)
    d("network_security_log", 20260929, "devA", "old.evil.net", 99)
    # domain-hit-devnum: 12 audit devices incl. 1 test device, one row each in window; sodl rows excluded
    for i in range(1, 13):
        d("domain-proxy-svc", 20260910 + i % 5, f"dev{i:02d}", "hit.example.org", 1)
    for i in range(1, 6):
        d("domain-proxy-svc", 20260915, f"dev{i:02d}", "other.example.org", 1)
    for i in range(20, 30):
        d("network_security_log", 20260915, f"dev{i}", "hit.example.org", 1)
    d("domain-proxy-svc", 20260801, "dev40", "hit.example.org", 1)
    # active-domain / black-ti domain (day 20261001)
    d("network_security_log", 20261001, "devA", "bad.com", 3, 3, "bad.com", 209)
    d("dns_log", 20261001, "devB", "bad.com", 5, 5, "bad.com", None)
    d("network_security_log", 20261001, "devTest", "bad.com", 9, 9, "bad.com", 209)
    d("domain-proxy-svc", 20261001, "devC", "bad.com", 100, 100, None, None)
    d("network_security_log", 20261001, "devA", "bad.com", 9, 9, "", 209)
    # a day that only has audit rows: the sodl gate must not pass
    d("domain-proxy-svc", 20261002, "devC", "x.com", 1)
    insert(cur, "dwb_ti_domain_info", dom)

    ip = []

    def i(src, manage, dstip, attack, tc, day=20261001):
        ip.append(dict(src_log=src, day=day, manage=manage, dstip=dstip, attack_count=attack, log_num=attack, threatclass=tc))

    i("sip_iocstat_log", "devA", "9.9.9.9", 4, None)
    i("network_security_log", "devB", "9.9.9.9", 6, 209)
    i("ip-proxy-svc", "devC", "9.9.9.9", 100, None)
    i("dns_log", "devD", "9.9.9.9", 50, None)
    i("network_security_log", "devE", "10.0.0.1", 7, 209)
    i("network_security_log", "devF", "8.8.8.8", 7, 209)
    insert(cur, "dwb_ti_ip_info", ip)

    cur.executemany(
        f"INSERT INTO {DB}.ods_ti_db_intelligence_tb_ip_reputation_sync VALUES (%s,%s,%s,%s,%s)",
        [("9.9.9.9", 0, "2", 1, 0), ("10.0.0.1", 0, "2", 1, 0), ("8.8.8.8", 0, "2", 1, 0), ("9.9.9.9", 80, "2", 1, 0)],
    )
    cur.execute(
        f"INSERT INTO {DB}.ods_ti_db_domain_intelligence_tb_domain_reputation_sync VALUES "
        "('bad.com','category=c2,family=fam1','source=s1,rule=r1','t1',0,'0'),"
        "('gone.com','category=x,family=y','source=s,rule=r','t2',0,'1')"
    )
    cur.execute(
        f"INSERT INTO {DB}.ods_custom_upload_data VALUES ('test_dev','test_devid','dev12'),('test_dev','test_devid','devTest')"
    )


def split_statements(text):
    out, label, buf = [], None, []
    for line in text.splitlines():
        m = re.match(r"--\s*@stmt\s+(\d+)\s+(.*)", line)
        if m:
            if buf:
                out.append((label, "\n".join(buf)))
                buf = []
            label = f"{m.group(1)} {m.group(2)}"
            continue
        if line.startswith("--") and not buf:
            continue
        buf.append(line)
    if buf:
        out.append((label, "\n".join(buf)))
    cleaned = []
    for label, body in out:
        body = "\n".join(l for l in body.splitlines() if not l.strip().startswith("--")).strip().rstrip(";")
        if body:
            cleaned.append((label, body))
    return cleaned


def lab_rewrite(sql):
    sql = sql.replace("paimon.ti.", f"{DB}.")
    sql = sql.replace("ti.ods_ti_", f"{DB}.ods_ti_")
    sql = sql.replace("`default`.ods_custom_upload_data", f"{DB}.ods_custom_upload_data")
    return sql


def norm(rows):
    out = []
    for row in rows:
        out.append(tuple(sorted(x) if isinstance(x, (list, tuple)) else (sorted(x.strip("[]").replace('"', "").split(",")) if isinstance(x, str) and x.startswith("[") else x) for x in row))
    return sorted(out, key=str)


def main():
    cur = conn().cursor()
    make_tables(cur)
    seed(cur)
    stmts = split_statements(SQL_PATH.read_text())
    assert len(stmts) == 11, len(stmts)

    expected = {
        1: 1, 2: 1, 9: 1, 10: 1,
    }
    failures = []
    lines = ["stmt\tstatus\trows\tcheck"]
    for label, sql in stmts:
        n = int(label.split()[0])
        _ = sql % ()
        cur.execute(lab_rewrite(sql))
        rows = cur.fetchall()
        check = "ok"
        if n in expected and len(rows) != expected[n]:
            check = f"expected {expected[n]} rows got {len(rows)}"
        if n == 3:
            # 9.9.9.9: sip 4 + network 6 = 10 (ip-proxy-svc 100 and dns_log 50 excluded; private/public-DNS ips excluded; port 80 row excluded)
            row = rows[0] if len(rows) == 1 else None
            ok = row and row[0] == "9.9.9.9" and int(row[5]) == 10
            ok = ok and sorted(eval(row[6]) if isinstance(row[6], str) else row[6]) == ["devA", "devB"]
            ok = ok and sorted(eval(row[9]) if isinstance(row[9], str) else row[9]) == ["0@4", "209@6"]
            check = "ok" if ok else f"unexpected {rows}"
        if n == 4:
            # 17 = devA 3 + devB 5 + devTest 9 (this task has no test-device filter); audit row (row_key NULL) and row_key='' row excluded
            row = rows[0] if len(rows) == 1 else None
            ok = row and row[0] == "bad.com" and int(row[2]) == 17
            ok = ok and sorted(eval(row[3])) == ["devA", "devB", "devTest"]
            ok = ok and sorted(eval(row[6])) == ["0@5", "209@12"]
            check = "ok" if ok else f"unexpected {rows}"
        if n == 5:
            check = "ok" if rows == (("hit.example.org", 11, 11),) else f"unexpected {rows}"
        if n == 6:
            got = sorted((a, int(b), int(c)) for a, b, c in rows)
            check = "ok" if got == [("1.x", 99, 1), ("amazonaws.com", 12, 2), ("com.cn", 12, 2), ("evil.net", 11, 1)] else f"unexpected {got}"
        if n == 7:
            got = sorted((a, int(b), int(c)) for a, b, c in rows)
            check = "ok" if got == [("bar.com.cn", 12, 2)] else f"unexpected {got}"
        if n == 8:
            got = sorted((a, int(b), int(c)) for a, b, c in rows)
            check = "ok" if got == [("a.s3.amazonaws.com", 12, 2)] else f"unexpected {got}"
        if n == 11:
            row = rows[0] if len(rows) == 1 else None
            ok = row and row[:6] == ("bad.com", "t1", "c2", "fam1", "s1", "r1") and int(row[6]) == 2
            check = "ok" if ok else f"unexpected {rows}"
        if check != "ok":
            failures.append((label, check))
        lines.append(f"{label}\t{'ok' if check == 'ok' else 'FAIL'}\t{len(rows)}\t{check}")
        print(label, len(rows), check)

    # the sodl gate must not pass for a day that only has audit rows
    gate = lab_rewrite(stmts[0][1]).replace("20261001", "20261002")
    cur.execute(gate)
    gate_rows = cur.fetchall()
    print("gate on audit-only day rows:", len(gate_rows))
    lines.append(f"gate(audit-only day)\t{'ok' if not gate_rows else 'FAIL'}\t{len(gate_rows)}\tshould be 0")
    if gate_rows:
        failures.append(("gate", "audit-only day passed"))

    OUT_PATH.write_text("\n".join(lines) + "\n")
    cur.execute(f"DROP DATABASE IF EXISTS {DB} FORCE")
    print("failures:", failures)
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
