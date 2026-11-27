#!/usr/bin/env python3
"""Load reference/real-data TSV samples into lab StarRocks and run smoke SELECTs.

Creates database real_ref with VARCHAR-heavy tables aligned to user samples (DEC-009).
Does not touch production. Idempotent: DROP + CREATE + INSERT each run.

Usage:
  python3 reference/real-data/load_lab_starrocks.py
  python3 reference/real-data/load_lab_starrocks.py --host 127.0.0.1 --port 9030
"""
from __future__ import annotations

import argparse
import csv
import sys
from datetime import datetime, timezone
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / "smoke-results.tsv"


def read_tsv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    rows: list[dict[str, str]] = []
    header: list[str] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if not header:
                header = parts
                continue
            rows.append(dict(zip(header, parts)))
    return header, rows


def connect(host: str, port: int):
    return pymysql.connect(
        host=host,
        port=port,
        user="root",
        password="",
        autocommit=True,
        charset="utf8mb4",
    )


def ensure_schema(cur) -> None:
    cur.execute("CREATE DATABASE IF NOT EXISTS real_ref")
    cur.execute("DROP TABLE IF EXISTS real_ref.sodl_dns_log")
    cur.execute("DROP TABLE IF EXISTS real_ref.sodl_network_security_log")
    cur.execute("DROP TABLE IF EXISTS real_ref.sodl_sip_iocstat_log")
    cur.execute(
        """
        CREATE TABLE real_ref.sodl_dns_log (
            v VARCHAR(8),
            recordtimestamp VARCHAR(64),
            uploadtimestamp VARCHAR(64),
            inserttimestamp VARCHAR(32),
            producttype VARCHAR(32),
            manage VARCHAR(128),
            deviceid VARCHAR(128),
            srcip VARCHAR(64),
            dstip VARCHAR(64),
            queries VARCHAR(512),
            insertdate VARCHAR(16)
        ) PROPERTIES('replication_num' = '1')
        """
    )
    cur.execute(
        """
        CREATE TABLE real_ref.sodl_network_security_log (
            v VARCHAR(8),
            recordtimestamp VARCHAR(32),
            uploadtimestamp VARCHAR(32),
            inserttimestamp VARCHAR(32),
            recordtime VARCHAR(32),
            vendor VARCHAR(32),
            producttype VARCHAR(32),
            manage VARCHAR(128),
            deviceid VARCHAR(128),
            srcip VARCHAR(64),
            dstip VARCHAR(64),
            moduletype VARCHAR(32),
            severity VARCHAR(16),
            confidence VARCHAR(16),
            dnsqueries VARCHAR(512),
            url VARCHAR(1024),
            highlight VARCHAR(512),
            manageip VARCHAR(64),
            insertdate VARCHAR(16)
        ) PROPERTIES('replication_num' = '1')
        """
    )
    cur.execute(
        """
        CREATE TABLE real_ref.sodl_sip_iocstat_log (
            v VARCHAR(8),
            recordtimestamp VARCHAR(32),
            uploadtimestamp VARCHAR(32),
            inserttimestamp VARCHAR(32),
            vendor VARCHAR(32),
            producttype VARCHAR(32),
            productver VARCHAR(128),
            deviceid VARCHAR(128),
            uuid VARCHAR(128),
            ioc VARCHAR(512),
            ioc_type VARCHAR(32),
            record_count VARCHAR(32),
            insertdate VARCHAR(16)
        ) PROPERTIES('replication_num' = '1')
        """
    )


def insert_dns(cur, rows: list[dict[str, str]]) -> int:
    n = 0
    for r in rows:
        if r.get("row_label") == "row_label":
            continue
        cur.execute(
            """
            INSERT INTO real_ref.sodl_dns_log
            (v, recordtimestamp, uploadtimestamp, inserttimestamp, producttype,
             manage, deviceid, srcip, dstip, queries, insertdate)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                r.get("v", ""),
                r.get("recordtimestamp") or None,
                r.get("uploadtimestamp") or None,
                r.get("inserttimestamp") or None,
                r.get("producttype") or None,
                r.get("manage") or None,
                r.get("deviceid") or None,
                r.get("srcip") or None,
                r.get("dstip") or None,
                r.get("queries") or None,
                r.get("insertdate") or None,
            ),
        )
        n += 1
    return n


def insert_net(cur, rows: list[dict[str, str]]) -> int:
    n = 0
    cols = [
        "v", "recordtimestamp", "uploadtimestamp", "inserttimestamp", "recordtime",
        "vendor", "producttype", "manage", "deviceid", "srcip", "dstip",
        "moduletype", "severity", "confidence", "dnsqueries", "url", "highlight",
        "manageip", "insertdate",
    ]
    for r in rows:
        if r.get("row_label") == "row_label":
            continue
        cur.execute(
            """
            INSERT INTO real_ref.sodl_network_security_log
            (v, recordtimestamp, uploadtimestamp, inserttimestamp, recordtime,
             vendor, producttype, manage, deviceid, srcip, dstip, moduletype,
             severity, confidence, dnsqueries, url, highlight, manageip, insertdate)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            tuple((r.get(c) or None) for c in cols),
        )
        n += 1
    return n


def insert_sip(cur, rows: list[dict[str, str]]) -> int:
    n = 0
    for r in rows:
        if not r.get("ioc"):
            continue
        cur.execute(
            """
            INSERT INTO real_ref.sodl_sip_iocstat_log
            (v, recordtimestamp, uploadtimestamp, inserttimestamp, vendor,
             producttype, productver, deviceid, uuid, ioc, ioc_type,
             record_count, insertdate)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """,
            (
                r.get("v", ""),
                r.get("recordtimestamp", ""),
                r.get("uploadtimestamp", ""),
                r.get("inserttimestamp", ""),
                r.get("vendor", ""),
                r.get("producttype", ""),
                r.get("productver", ""),
                r.get("deviceid", ""),
                r.get("uuid", ""),
                r.get("ioc", ""),
                r.get("ioc_type", ""),
                r.get("record_count", ""),
                r.get("insertdate", ""),
            ),
        )
        n += 1
    return n


def run_smokes(cur) -> list[tuple[str, str, str]]:
    out: list[tuple[str, str, str]] = []

    def one(name: str, sql: str) -> None:
        cur.execute(sql)
        rows = cur.fetchall()
        out.append((name, sql.replace("\n", " ").strip()[:200], repr(rows)))

    one("dns_row_count", "SELECT COUNT(*) FROM real_ref.sodl_dns_log")
    one(
        "dns_nlogtj",
        "SELECT queries, insertdate FROM real_ref.sodl_dns_log "
        "WHERE insertdate = '2026-11-02' AND queries = 'nlogtj.yukeweb.com'",
    )
    one("net_row_count", "SELECT COUNT(*) FROM real_ref.sodl_network_security_log")
    one(
        "net_insertdate_hour",
        "SELECT dnsqueries, insertdate, hour(from_unixtime(cast(inserttimestamp AS BIGINT))) AS hr "
        "FROM real_ref.sodl_network_security_log "
        "WHERE insertdate = '2026-10-05' ORDER BY dnsqueries",
    )
    one("sip_row_count", "SELECT COUNT(*) FROM real_ref.sodl_sip_iocstat_log")
    one(
        "sip_ip_sum_record_count",
        "SELECT ioc, ioc_type, sum(cast(record_count AS BIGINT)) AS cnt "
        "FROM real_ref.sodl_sip_iocstat_log "
        "WHERE insertdate = '2026-10-28' AND ioc_type = 'ip' "
        "GROUP BY ioc, ioc_type ORDER BY ioc",
    )
    one(
        "sip_topthreat_domain_branch_shape",
        "SELECT ioc AS domain, deviceid AS devid, sum(cast(record_count AS BIGINT)) AS domain_num "
        "FROM real_ref.sodl_sip_iocstat_log "
        "WHERE ioc_type = 'domain' AND insertdate = '2026-10-28' "
        "GROUP BY ioc, deviceid",
    )
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9030)
    args = parser.parse_args()

    _, dns_rows = read_tsv(ROOT / "sodl.dns_log" / "samples.tsv")
    _, net_rows = read_tsv(ROOT / "sodl.network_security_log" / "samples-key-fields.tsv")
    _, sip_rows = read_tsv(ROOT / "sodl.sip_iocstat_log" / "samples.tsv")

    try:
        conn = connect(args.host, args.port)
    except pymysql.err.OperationalError as e:
        print("StarRocks not reachable at %s:%s: %s" % (args.host, args.port, e), file=sys.stderr)
        print("Run lab/install.sh && lab/start.sh first (ACT-033).", file=sys.stderr)
        return 2

    cur = conn.cursor()
    ensure_schema(cur)
    nd = insert_dns(cur, dns_rows)
    nn = insert_net(cur, net_rows)
    ns = insert_sip(cur, sip_rows)
    smokes = run_smokes(cur)
    conn.close()

    ts = datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M %z")
    with RESULTS.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["loaded_at", ts])
        w.writerow(["inserted_dns", nd])
        w.writerow(["inserted_net", nn])
        w.writerow(["inserted_sip", ns])
        w.writerow([])
        w.writerow(["name", "sql_prefix", "result"])
        for row in smokes:
            w.writerow(row)

    print("Loaded dns=%s net=%s sip=%s" % (nd, nn, ns))
    for name, _, res in smokes:
        print("%s: %s" % (name, res))
    print("Wrote %s" % RESULTS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
