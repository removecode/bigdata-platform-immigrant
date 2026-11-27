#!/usr/bin/env python3
"""Run outputs/migratable-tasks-starrocks.sql on the lab StarRocks with synthetic data.

The deliverable SQL keeps the real names (sodl.*, csc.*, ti.*, `default`.*). This runner
creates a scratch database `mig_lab`, rewrites those names to scratch tables only for
execution, loads synthetic VARCHAR data (DEC-009; sodl.inserttimestamp is BIGINT seconds),
and writes outputs/migratable-tasks-starrocks-results.tsv. It never touches the
existing lab databases and never connects to the user's StarRocks.
"""

from __future__ import annotations

import random
import re
import time
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parent.parent
SQL_PATH = ROOT / "outputs" / "migratable-tasks-starrocks.sql"
OUT_PATH = ROOT / "outputs" / "migratable-tasks-starrocks-results.tsv"
DB = "mig_lab"

RENAMES = [
    ("sodl.network_security_log", f"{DB}.sodl_network_security_log"),
    ("sodl.endpoint_security_log", f"{DB}.sodl_endpoint_security_log"),
    ("sodl.sip_iocstat_log", f"{DB}.sodl_sip_iocstat_log"),
    ("sodl.dns_log", f"{DB}.sodl_dns_log"),
    ("sodl.url_log", f"{DB}.sodl_url_log"),
    ("csc.ods_csc_log_audit", f"{DB}.csc_ods_csc_log_audit"),
    ("ti.ods_ti_db_intelligence_tb_ip_reputation_sync", f"{DB}.ti_ip_reputation"),
    ("`default`.ods_devicemanager_deviceinfo", f"{DB}.default_ods_devicemanager_deviceinfo"),
]

DDL = {
    "sodl_network_security_log": (
        "dstip varchar(64), srcip varchar(64), url varchar(512), engine varchar(32), severity varchar(16),"
        " threatclass varchar(16), threattype varchar(16), threatsubtype varchar(16), action varchar(16),"
        " producttype varchar(32), requesthead varchar(1024), requestbody varchar(1024), reqruleid varchar(32),"
        " titype varchar(8), dstip2 varchar(64), deviceId varchar(64), insertdate varchar(16), inserttimestamp bigint"
    ),
    "sodl_endpoint_security_log": (
        "threatclass varchar(16), threattype varchar(16), threatsubtype varchar(16), producttype varchar(32),"
        " deviceId varchar(64), filemd5 varchar(64), insertdate varchar(16), inserttimestamp bigint"
    ),
    "sodl_sip_iocstat_log": (
        "ioc varchar(512), ioc_type varchar(16), deviceId varchar(64), record_count varchar(16),"
        " insertdate varchar(16), inserttimestamp bigint"
    ),
    "sodl_dns_log": "queries varchar(256), producttype varchar(32), qr varchar(8), deviceId varchar(64), insertdate varchar(16)",
    "sodl_url_log": "host varchar(256), producttype varchar(32), deviceId varchar(64), insertdate varchar(16)",
    "csc_ods_csc_log_audit": (
        "day varchar(16), hour varchar(8), app_id varchar(64), module_id varchar(64), str1 varchar(64),"
        " str2 varchar(64), str4 varchar(65533), str5 varchar(64), str10 varchar(65533), long1 varchar(16)"
    ),
    "ti_ip_reputation": "ip varchar(64), direction varchar(8), reputation varchar(8)",
    "default_ods_devicemanager_deviceinfo": "dev_id varchar(64), product varchar(64), customer_info varchar(512)",
}

PRIVATE = re.compile(r"^((0\.0\.0\.0)|(127\.0\.0\.1)|(localhost)|(10\.)|(172\.1[6-9]\.)|(172\.2[0-9]\.)|(172\.3[0-1]\.)|(192\.168\.))")


def parse_statements(text: str):
    stmts = []
    cur = None
    for line in text.split("\n"):
        m = re.match(r"-- @stmt (\d+) \| (.*?) \| (.*)$", line)
        if m:
            cur = {"id": int(m.group(1)), "app": m.group(2), "seg": m.group(3), "lines": []}
            stmts.append(cur)
            continue
        if cur is None or line.startswith("--"):
            continue
        cur["lines"].append(line)
    for s in stmts:
        s["sql"] = "\n".join(s["lines"]).strip()
    return stmts


def rewrite(sql: str) -> str:
    for old, new in RENAMES:
        sql = sql.replace(old, new)
    return sql


def public_ip(rng):
    while True:
        ip = ".".join(str(rng.randint(1, 254)) for _ in range(4))
        if not PRIVATE.match(ip) and not ip.startswith(("224.", "240.", "255.")):
            return ip


def insert_many(cur, table, cols, rows):
    if not rows:
        return
    ph = ",".join(["%s"] * len(cols))
    for i in range(0, len(rows), 2000):
        cur.executemany(f"INSERT INTO {DB}.{table} ({','.join(cols)}) VALUES ({ph})", rows[i : i + 2000])


def epoch(cur, stamp: str) -> int:
    cur.execute("SELECT unix_timestamp(%s)", (stamp,))
    return int(cur.fetchone()[0])


def seed(cur):
    rng = random.Random(20261019)
    cur.execute(f"DROP DATABASE IF EXISTS {DB}")
    cur.execute(f"CREATE DATABASE {DB}")
    for t, cols in DDL.items():
        cur.execute(
            f"CREATE TABLE {DB}.{t} ({cols}) DUPLICATE KEY({cols.split()[0]}) "
            f"DISTRIBUTED BY HASH({cols.split()[0]}) BUCKETS 1 PROPERTIES('replication_num'='1')"
        )

    base = {d: epoch(cur, f"{d} 00:00:00") for d in ("2026-10-01", "2026-09-30", "2025-08-25")}
    devs = [f"dev{i:03d}" for i in range(40)]
    rep_cities = ["Shenzhen", "Beijing", "Hangzhou"]

    nsl = []
    words = ["wget", "curl", "powershell", "certutil"]
    for i in range(9000):
        day = rng.choice(["2026-10-01", "2026-10-01", "2026-10-01", "2026-09-30"])
        hour = rng.randint(0, 23)
        ts = base[day] + hour * 3600 + rng.randint(0, 3599)
        srcip = public_ip(rng) if rng.random() < 0.85 else rng.choice(["10.1.1.1", "192.168.0.9", "127.0.0.1", "bad"])
        dstip = public_ip(rng) if rng.random() < 0.8 else rng.choice(["10.2.3.4", "172.16.1.1", "x.y", ""])
        threatclass = rng.choice([209, 208, 216, 214, 203, 40, 212, 94, 30])
        threattype = rng.choice([10, 4, 5, 9])
        threatsubtype = rng.choice([0, 1, 2])
        head = rng.choice(["", "GET /a?password=Pa55word&x=1", "POST /l pwd=abc123;", f"GET /x {rng.choice(words)} http://e"])
        body = rng.choice(["", "user=a&password=Qwe12345", "cmd=powershell -enc AAA ", "{}"])
        nsl.append(
            (
                dstip, srcip, rng.choice(["http://bad%d.example.com/p" % rng.randint(1, 80), "evil%d.org" % rng.randint(1, 60), "1.2.3.4:80"]),
                rng.choice(["af", "edr", "premise_ioc", "cloud_ioc", "sase_ioc"]),
                str(rng.choice([10, 50, 51, 80, 100])), str(threatclass), str(threattype), str(threatsubtype),
                str(rng.choice([1, 2, 2])), rng.choice(["AF", "NGAF", "VNGAF", "EDR"]), head, body,
                str(rng.randint(13900000, 15100000)), str(rng.choice([0, 1, 2])), dstip,
                rng.choice(devs), day, ts,
            )
        )
    # rows for the dashboard-stats-job statements: 2025-08-25 01:xx
    for i in range(400):
        ts = base["2025-08-25"] + 3600 + rng.randint(0, 3599)
        tc = rng.choice([209, 214])
        nsl.append(
            (
                public_ip(rng), public_ip(rng), "dash%d.example.com" % rng.randint(1, 50), "af", "80", str(tc),
                str(rng.choice([1, 2, 3, 9, 14, 15])), "0", "2", rng.choice(["AF", "NGAF", "NULL"]), "", "",
                str(rng.randint(14000000, 14999998)), str(rng.choice([0, 1, 2])), public_ip(rng),
                rng.choice(devs + ["NULL"]), "2025-08-25", ts,
            )
        )
    insert_many(
        cur, "sodl_network_security_log",
        ["dstip", "srcip", "url", "engine", "severity", "threatclass", "threattype", "threatsubtype", "action",
         "producttype", "requesthead", "requestbody", "reqruleid", "titype", "dstip2", "deviceId", "insertdate",
         "inserttimestamp"],
        nsl,
    )

    esl = []
    for i in range(300):
        ts = base["2025-08-25"] + 3600 + rng.randint(0, 3599)
        esl.append((str(rng.choice([209, 214])), str(rng.choice([1, 9, 14, 3])), "0", rng.choice(["EDR", "NULL"]),
                    rng.choice(devs), rng.choice(["%032x" % rng.getrandbits(128), "NULL", ""]), "2025-08-25", ts))
    insert_many(cur, "sodl_endpoint_security_log",
                ["threatclass", "threattype", "threatsubtype", "producttype", "deviceId", "filemd5", "insertdate", "inserttimestamp"], esl)

    dns = [("a%d.evil%d.com" % (rng.randint(1, 9), rng.randint(1, 50)), rng.choice(["AF", "NGAF", "VNGAF", "EDR"]),
            str(rng.choice([0, 0, 1])), rng.choice(devs), "2026-10-01") for _ in range(4000)]
    dns += [("ab", "AF", "0", "dev001", "2026-10-01"), ("nodot", "AF", "0", "dev001", "2026-10-01")]
    insert_many(cur, "sodl_dns_log", ["queries", "producttype", "qr", "deviceId", "insertdate"], dns)

    urls = [(rng.choice(["h%d.example.com" % rng.randint(1, 80), "nodot", None]), rng.choice(["AF", "NGAF", "EDR"]),
             rng.choice(devs), "2026-10-01") for _ in range(3000)]
    insert_many(cur, "sodl_url_log", ["host", "producttype", "deviceId", "insertdate"], urls)

    insert_many(cur, "sodl_sip_iocstat_log", ["ioc", "ioc_type", "deviceId", "record_count", "insertdate", "inserttimestamp"],
                [("evil%d.org" % rng.randint(1, 60), rng.choice(["domain", "url"]), rng.choice(devs),
                  str(rng.randint(1, 9)), "2026-10-01", base["2026-10-01"] + rng.randint(0, 1800)) for _ in range(800)])

    insert_many(cur, "default_ods_devicemanager_deviceinfo", ["dev_id", "product", "customer_info"],
                [(d, rng.choice(["AF", "EDR", "NGAF"]), "{city=%s,ip=%s}" % (rng.choice(rep_cities), public_ip(rng))) for d in devs]
                + [("devnull", "AF", "NULL")])

    rep = [(".".join(map(str, (rng.randint(1, 60), rng.randint(0, 40), rng.randint(0, 9), rng.randint(1, 254)))), "2", "0")
           for _ in range(80)]
    rep += [("61.30.%d.5" % i, "2", "0") for i in range(5)]
    insert_many(cur, "ti_ip_reputation", ["ip", "direction", "reputation"], rep)

    audit = []
    seg_pool = [(rng.randint(100, 200), rng.randint(0, 255), rng.randint(0, 255)) for _ in range(25)]
    for (a, b, c) in seg_pool:
        for d in ("20260925", "20260926", "20260927", "20260928", "20260929", "20260930", "20261001"):
            for k in range(3):
                ip = f"{a}.{b}.{c}.{rng.randint(1, 254)}"
                el = '{"ip":"%s:80","threat":{"reputation":"2","direction":"2"}}' % ip
                audit.append((d, "0", "ip-proxy-svc", "ip-proxy-svc", "NGAF", rng.choice(devs), "", "cf", "[" + el + "~]", "0"))
    for _ in range(600):
        ips = ",".join('{"ip":"%s"}' % public_ip(rng) for _ in range(2))
        audit.append(("20261001", "0", "ip-proxy-svc", "ip-proxy-svc", "NGAF", rng.choice(devs),
                      '[%s]' % ips, "[cf]", "", "0"))
    for _ in range(1500):
        kind = rng.choice(["domain", "file", "url"])
        if kind == "domain":
            payload = '[{\\"domain\\":\\"Evil%d.COM\\"},{\\"domain\\":\\"bad%d.net\\"}]' % (rng.randint(1, 40), rng.randint(1, 40))
            row = ("20261001", "0", rng.choice(["domain-proxy-svc", "cloudcheck"]), rng.choice(["domain-proxy-svc", "CloudCheck"]))
        elif kind == "url":
            payload = '[{\\"url\\":\\"http://Evil%d.com/x\\"}]' % rng.randint(1, 40)
            row = ("20261001", "0", rng.choice(["url-proxy-svc", "cloudcheck"]), rng.choice(["url-proxy-svc", "CloudCheck"]))
        else:
            payload = '[{\\"filemd5\\":\\"%032X\\",\\"info\\":{\\"attr\\":\\"0\\"}}]' % rng.getrandbits(128)
            row = ("20261001", "0", "analysis-proxy-api", rng.choice(["file_hash", "file_scan"]))
        audit.append(row + (rng.choice(["NGAF", "EDR", "SIP", "VNGAF"]), rng.choice(devs), "", "", payload, "0"))
    insert_many(cur, "csc_ods_csc_log_audit",
                ["day", "hour", "app_id", "module_id", "str1", "str2", "str4", "str5", "str10", "long1"], audit)


def main():
    stmts = parse_statements(SQL_PATH.read_text(encoding="utf-8"))
    conn = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", charset="utf8mb4", autocommit=True)
    cur = conn.cursor()
    seed(cur)
    lines = ["id\tstatus\trows\tseconds\tapp\tsegment\terror"]
    for s in stmts:
        sql = rewrite(s["sql"])
        t0 = time.time()
        try:
            cur.execute(sql)
            n = len(cur.fetchall())
            lines.append(f"{s['id']}\tok\t{n}\t{time.time() - t0:.2f}\t{s['app']}\t{s['seg']}\t")
        except Exception as e:  # noqa: BLE001
            msg = str(e).replace("\n", " ").replace("\t", " ")[:300]
            lines.append(f"{s['id']}\terror\t\t{time.time() - t0:.2f}\t{s['app']}\t{s['seg']}\t{msg}")
    OUT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    cur.execute(f"DROP DATABASE {DB}")


if __name__ == "__main__":
    main()
