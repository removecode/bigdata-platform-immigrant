#!/usr/bin/env python3
"""Compare user topthreat domain SQL vs assistant version on mixed real + audit fixtures.

Data sources:
  - reference/real-data/sodl.* TSV (user 2026-11-03)
  - Synthetic audit rows mimicking ACT-064 str10 (escaped quotes, ], ~], single object)

Runs on local StarRocks only; does not query user production.
"""
from __future__ import annotations

import csv
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs" / "topthreat-user-vs-assistant-compare.tsv"
REAL_NET = ROOT / "reference/real-data/sodl.network_security_log/samples-key-fields.tsv"
REAL_IOC = ROOT / "reference/real-data/sodl.sip_iocstat_log/samples.tsv"

START = "2026-10-05 23:50:00"
END = "2026-10-06 00:10:00"
DAY_INT = 20261005
HOUR_INT = 23
INSERTDATE = "2026-10-05"
TS_LO = 1791216303  # real sample inserttimestamp


def read_tsv(path: Path) -> list[dict[str, str]]:
    rows = []
    header = None
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if header is None:
                header = parts
                continue
            rows.append(dict(zip(header, parts)))
    return rows


def ensure_udf() -> None:
    jar = Path("/opt/lab/udf/lab-udf-sr.jar")
    if not jar.is_file():
        subprocess.check_call(["bash", str(ROOT / "lab/udf-sr/build.sh")])
    subprocess.check_call([sys.executable, str(ROOT / "lab/udf-sr/register.py")])


def setup_schema(cur) -> None:
    cur.execute("CREATE DATABASE IF NOT EXISTS topthreat_cmp")
    cur.execute("DROP TABLE IF EXISTS topthreat_cmp.audit")
    cur.execute("DROP TABLE IF EXISTS topthreat_cmp.net")
    cur.execute("DROP TABLE IF EXISTS topthreat_cmp.ioc")
    cur.execute(
        """
        CREATE TABLE topthreat_cmp.audit (
            app_id VARCHAR(64),
            module_id VARCHAR(64),
            str1 VARCHAR(32),
            str2 VARCHAR(128),
            long1 VARCHAR(8),
            str10 VARCHAR(65533),
            day INT,
            hour INT,
            year INT,
            month BIGINT,
            log_time DATETIME
        ) PROPERTIES('replication_num'='1')
        """
    )
    cur.execute(
        """
        CREATE TABLE topthreat_cmp.net (
            url VARCHAR(1024),
            deviceId VARCHAR(128),
            insertdate VARCHAR(16),
            inserttimestamp BIGINT
        ) PROPERTIES('replication_num'='1')
        """
    )
    cur.execute(
        """
        CREATE TABLE topthreat_cmp.ioc (
            ioc VARCHAR(512),
            ioc_type VARCHAR(32),
            deviceId VARCHAR(128),
            record_count BIGINT,
            insertdate VARCHAR(16),
            inserttimestamp BIGINT
        ) PROPERTIES('replication_num'='1')
        """
    )


def esc_sql(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "''")


def insert_audit_fixtures(cur) -> None:
    # Stored form: backslash-escaped quotes inside JSON (ACT-064 user fact).
    cases = [
        (
            "array_2elem",
            '[{\\"domain\\":\\"www.glashuirglurhtgqoer.com\\",\\"info\\":{\\"attr\\":\\"0\\"}},'
            '{\\"domain\\":\\"airobotheworld.gicp.net\\",\\"info\\":{\\"attr\\":\\"0\\"}}]',
        ),
        (
            "single_object",
            '{\\"domain\\":\\"single-object.example\\",\\"info\\":{\\"attr\\":\\"0\\"}}',
        ),
        (
            "array_tilde_end",
            '[{\\"domain\\":\\"tilde-bracket.example\\",\\"info\\":{\\"attr\\":\\"0\\"}}~]',
        ),
        (
            "attr_filtered",
            '[{\\"domain\\":\\"drop-me.example\\",\\"info\\":{\\"attr\\":\\"1\\"}}]',
        ),
    ]
    base = dict(
        app_id="domain-proxy-svc",
        module_id="domain-proxy-svc",
        str1="NGAF",
        str2="DEV_AUDIT_001",
        long1="0",
        day=DAY_INT,
        hour=HOUR_INT,
        year=2026,
        month=202610,
        log_time="2026-10-05 23:55:00",
    )
    for label, str10 in cases:
        cur.execute(
            "INSERT INTO topthreat_cmp.audit VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
            (
                base["app_id"],
                base["module_id"],
                base["str1"],
                base["str2"],
                base["long1"],
                str10,
                base["day"],
                base["hour"],
                base["year"],
                base["month"],
                base["log_time"],
            ),
        )


def insert_net_fixtures(cur) -> None:
    real = read_tsv(REAL_NET)
    for r in real:
        dev = r.get("deviceid") or r.get("manage") or "unknown"
        ins = r.get("inserttimestamp") or str(TS_LO)
        idate = r.get("insertdate") or INSERTDATE
        if not idate.strip():
            idate = INSERTDATE
        cur.execute(
            "INSERT INTO topthreat_cmp.net(url,deviceId,insertdate,inserttimestamp) VALUES (%s,%s,%s,%s)",
            (r.get("url") or "", dev, idate, int(ins)),
        )
    extra = [
        ("http://www.glashuirglurhtgqoer.com/path", "DEV_NET_HTTP", INSERTDATE, TS_LO),
        ("http://www.glashuirglurhtgqoer.com/redir?u=http://nested.evil.com/x", "DEV_NET_NESTED", INSERTDATE, TS_LO),
        ("//orphan-host.example/x", "DEV_NET_ORPHAN", INSERTDATE, TS_LO),
        ("www.pure-domain.example/foo", "DEV_NET_PURE", INSERTDATE, TS_LO),
        ("a.com/x//y", "DEV_NET_SLASH", INSERTDATE, TS_LO),
    ]
    for url, dev, idate, ts in extra:
        cur.execute(
            "INSERT INTO topthreat_cmp.net(url,deviceId,insertdate,inserttimestamp) VALUES (%s,%s,%s,%s)",
            (url, dev, idate, ts),
        )


def insert_ioc_fixtures(cur) -> None:
    real = read_tsv(REAL_IOC)
    for r in real:
        cur.execute(
            "INSERT INTO topthreat_cmp.ioc VALUES (%s,%s,%s,%s,%s,%s)",
            (
                r["ioc"],
                r["ioc_type"],
                r["deviceid"],
                int(r["record_count"]),
                r["insertdate"],
                int(r["inserttimestamp"]),
            ),
        )
    cur.execute(
        "INSERT INTO topthreat_cmp.ioc VALUES (%s,%s,%s,%s,%s,%s)",
        ("evil-domain-from-ioc.example", "domain", "DEV_IOC_001", 5, INSERTDATE, TS_LO),
    )


def q(cur, sql: str):
    sql % ()
    cur.execute(sql)
    return cur.fetchall()


def branch1_user(cur):
    return q(
        cur,
        f"""
        SELECT lower(get_json_object(f.value, '$.domain')) AS domain, str2 AS devid
        FROM topthreat_cmp.audit
        CROSS JOIN json_each(get_json_string(regexp_replace(str10, '\\\\\\\\+"', '"'), '$[*]')) f
        WHERE app_id IN ('domain-proxy-svc','cloudcheck')
          AND module_id IN ('domain-proxy-svc','CloudCheck')
          AND str1 IN ('VNGAF','NGAF','EDR','EDR_BOTNET','SIP','SIP_SMTP','SIP_SMB',
                       'AC','VAC','CWPP','SASE','EDR_WEBSITE','EDR_NPE',
                       'EDR_CLOUD_IDENTIFY','EDR_PK')
          AND long1 = 0
          AND get_json_object(f.value, '$.info.attr') = '0'
          AND year = 2026
          AND month = 202610
          AND day = {DAY_INT}
          AND log_time >= '{START}'
          AND log_time < '{END}'
        """,
    )


def branch1_mine(cur):
    return q(
        cur,
        f"""
        SELECT lower(get_json_object(str10_tmp, '$.domain')) AS domain, str2 AS devid
        FROM topthreat_cmp.audit,
             unnest(`default`.format_json_list(regexp_replace(str10, '\\\\\\\\+"', '"'))) AS str10_tbl(str10_tmp)
        WHERE app_id IN ('domain-proxy-svc', 'cloudcheck')
          AND module_id IN ('domain-proxy-svc', 'CloudCheck')
          AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
                       'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
                       'EDR_CLOUD_IDENTIFY', 'EDR_PK')
          AND long1 = 0
          AND get_json_object(str10_tmp, '$.info.attr') = '0'
          AND day = {DAY_INT}
          AND hour = {HOUR_INT}
        """,
    )


def branch1_expand_user(cur):
    return q(
        cur,
        f"""
        SELECT audit.app_id, length(audit.str10) AS len,
               count(f.value) AS elem_cnt
        FROM topthreat_cmp.audit
        CROSS JOIN json_each(get_json_string(regexp_replace(str10, '\\\\\\\\+"', '"'), '$[*]')) f
        GROUP BY audit.app_id, audit.str10
        """,
    )


def branch1_expand_mine(cur):
    return q(
        cur,
        f"""
        SELECT app_id, length(str10) AS len, count(1) AS elem_cnt
        FROM topthreat_cmp.audit,
             unnest(`default`.format_json_list(regexp_replace(str10, '\\\\\\\\+"', '"'))) AS t(x)
        GROUP BY app_id, str10
        """,
    )


def branch2_user(cur):
    return q(
        cur,
        f"""
        SELECT CASE WHEN url LIKE '%%://%%' THEN split_part(split_part(url, '//', 2), '/', 1)
                    ELSE split_part(url, '/', 1) END AS domain,
               deviceId AS devid
        FROM topthreat_cmp.net
        WHERE url IS NOT NULL AND url NOT IN ('','-')
          AND inserttimestamp >= unix_timestamp('{START}')
          AND inserttimestamp < unix_timestamp('{END}')
        """,
    )


def branch2_mine(cur):
    return q(
        cur,
        f"""
        SELECT split(split(url, '//')[cardinality(split(url, '//'))], '/')[1] AS domain,
               deviceId AS devid
        FROM topthreat_cmp.net
        WHERE url IS NOT NULL AND url NOT IN ('', '-')
          AND insertdate = '{INSERTDATE}'
          AND hour(from_unixtime(inserttimestamp)) = {HOUR_INT}
        """,
    )


def branch2_mine_same_ts(cur):
    """Same time window as user branch2 (isolates domain extraction, not DEC-016 hour)."""
    return q(
        cur,
        f"""
        SELECT split(split(url, '//')[cardinality(split(url, '//'))], '/')[1] AS domain,
               deviceId AS devid
        FROM topthreat_cmp.net
        WHERE url IS NOT NULL AND url NOT IN ('', '-')
          AND inserttimestamp >= unix_timestamp('{START}')
          AND inserttimestamp < unix_timestamp('{END}')
        """,
    )


def branch3_user(cur):
    return q(
        cur,
        f"""
        SELECT ioc AS domain, deviceId AS devid, sum(record_count) AS domain_num
        FROM topthreat_cmp.ioc
        WHERE ioc_type = 'domain'
          AND ioc IS NOT NULL AND ioc NOT IN ('','-')
          AND inserttimestamp >= unix_timestamp('{START}')
          AND inserttimestamp < unix_timestamp('{END}')
        GROUP BY ioc, deviceId
        """,
    )


def branch3_mine(cur):
    return q(
        cur,
        f"""
        SELECT ioc AS domain, deviceId AS devid, sum(record_count) AS domain_num
        FROM topthreat_cmp.ioc
        WHERE ioc_type = 'domain'
          AND ioc IS NOT NULL AND ioc NOT IN ('', '-')
          AND inserttimestamp >= unix_timestamp('{START}')
          AND inserttimestamp < unix_timestamp('{END}')
        GROUP BY ioc, deviceId
        """,
    )


def full_domain_user(cur):
    return q(
        cur,
        f"""
        SELECT domain, sum(domain_num) AS domain_num, count(DISTINCT devid) AS device_num
        FROM (
          SELECT domain, devid, count(1) AS domain_num
          FROM (
            SELECT lower(get_json_object(f.value, '$.domain')) AS domain, str2 AS devid
            FROM topthreat_cmp.audit
            CROSS JOIN json_each(get_json_string(regexp_replace(str10, '\\\\\\\\+"', '"'), '$[*]')) f
            WHERE app_id IN ('domain-proxy-svc','cloudcheck')
              AND module_id IN ('domain-proxy-svc','CloudCheck')
              AND str1 IN ('VNGAF','NGAF','EDR','EDR_BOTNET','SIP','SIP_SMTP','SIP_SMB',
                           'AC','VAC','CWPP','SASE','EDR_WEBSITE','EDR_NPE',
                           'EDR_CLOUD_IDENTIFY','EDR_PK')
              AND long1 = 0
              AND get_json_object(f.value, '$.info.attr') = '0'
              AND year = 2026 AND month = 202610 AND day = {DAY_INT}
              AND log_time >= '{START}' AND log_time < '{END}'
          ) a
          WHERE domain IS NOT NULL AND domain NOT IN ('','-')
          GROUP BY domain, devid
          UNION ALL
          SELECT domain, devid, count(1) AS domain_num
          FROM (
            SELECT CASE WHEN url LIKE '%%://%%' THEN split_part(split_part(url, '//', 2), '/', 1)
                        ELSE split_part(url, '/', 1) END AS domain,
                   deviceId AS devid
            FROM topthreat_cmp.net
            WHERE url IS NOT NULL AND url NOT IN ('','-')
              AND inserttimestamp >= unix_timestamp('{START}')
              AND inserttimestamp < unix_timestamp('{END}')
          ) t
          WHERE domain IS NOT NULL AND domain != ''
          GROUP BY domain, devid
          UNION ALL
          SELECT ioc AS domain, deviceId AS devid, sum(record_count) AS domain_num
          FROM topthreat_cmp.ioc
          WHERE ioc_type = 'domain' AND ioc IS NOT NULL AND ioc NOT IN ('','-')
            AND inserttimestamp >= unix_timestamp('{START}')
            AND inserttimestamp < unix_timestamp('{END}')
          GROUP BY ioc, deviceId
        ) t
        GROUP BY domain, devid
        ORDER BY domain_num DESC
        LIMIT 100000
        """,
    )


def full_domain_mine(cur):
    return q(
        cur,
        f"""
        SELECT domain, sum(domain_num) AS domain_num, count(DISTINCT devid) AS device_num
        FROM (
          SELECT domain, devid, count(1) AS domain_num
          FROM (
            SELECT lower(get_json_object(str10_tmp, '$.domain')) AS domain, str2 AS devid
            FROM topthreat_cmp.audit,
                 unnest(`default`.format_json_list(regexp_replace(str10, '\\\\\\\\+"', '"'))) AS str10_tbl(str10_tmp)
            WHERE app_id IN ('domain-proxy-svc', 'cloudcheck')
              AND module_id IN ('domain-proxy-svc', 'CloudCheck')
              AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
                           'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
                           'EDR_CLOUD_IDENTIFY', 'EDR_PK')
              AND long1 = 0
              AND get_json_object(str10_tmp, '$.info.attr') = '0'
              AND day = {DAY_INT}
              AND hour = {HOUR_INT}
          ) a
          WHERE domain IS NOT NULL AND domain NOT IN ('', '-')
          GROUP BY domain, devid
          UNION ALL
          SELECT domain, devid, count(1) AS domain_num
          FROM (
            SELECT split(split(url, '//')[cardinality(split(url, '//'))], '/')[1] AS domain,
                   deviceId AS devid
            FROM topthreat_cmp.net
            WHERE url IS NOT NULL AND url NOT IN ('', '-')
              AND insertdate = '{INSERTDATE}'
              AND hour(from_unixtime(inserttimestamp)) = {HOUR_INT}
          ) t
          WHERE domain IS NOT NULL AND domain != ''
          GROUP BY domain, devid
          UNION ALL
          SELECT ioc AS domain, deviceId AS devid, sum(record_count) AS domain_num
          FROM topthreat_cmp.ioc
          WHERE ioc_type = 'domain'
            AND ioc IS NOT NULL AND ioc NOT IN ('', '-')
            AND inserttimestamp >= unix_timestamp('{START}')
            AND inserttimestamp < unix_timestamp('{END}')
          GROUP BY ioc, deviceId
        ) t
        GROUP BY domain, devid
        ORDER BY domain_num DESC
        LIMIT 100000
        """,
    )


def sets(rows):
    return {tuple(r) for r in rows}


def main() -> int:
    ensure_udf()
    conn = pymysql.connect(host="127.0.0.1", port=9030, user="root", autocommit=True, charset="utf8mb4")
    cur = conn.cursor()
    cur.execute("SET time_zone = '+08:00'")
    setup_schema(cur)
    insert_audit_fixtures(cur)
    insert_net_fixtures(cur)
    insert_ioc_fixtures(cur)

    results = []
    comparisons = [
        ("branch1_audit_expand_count", branch1_expand_user(cur), branch1_expand_mine(cur)),
        ("branch1_audit_domain_rows", branch1_user(cur), branch1_mine(cur)),
        ("branch2_net_domain_rows_dec016_hour", branch2_user(cur), branch2_mine(cur)),
        ("branch2_net_domain_rows_same_ts_window", branch2_user(cur), branch2_mine_same_ts(cur)),
        ("branch3_ioc_domain_rows", branch3_user(cur), branch3_mine(cur)),
        ("full_domain_stat", full_domain_user(cur), full_domain_mine(cur)),
    ]
    for name, u, m in comparisons:
        su, sm = sets(u), sets(m)
        results.append(
            dict(
                compare=name,
                user_rows=len(u),
                mine_rows=len(m),
                only_user=json.dumps(sorted(su - sm), ensure_ascii=False),
                only_mine=json.dumps(sorted(sm - su), ensure_ascii=False),
                equal="yes" if su == sm else "no",
            )
        )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(results[0].keys()), delimiter="\t")
        w.writeheader()
        w.writerows(results)

    for r in results:
        print(r["compare"], "equal=", r["equal"], "user=", r["user_rows"], "mine=", r["mine_rows"])
        if r["equal"] == "no":
            if r["only_user"] != "[]":
                print("  only_user", r["only_user"][:500])
            if r["only_mine"] != "[]":
                print("  only_mine", r["only_mine"][:500])

    cur.execute("DROP DATABASE topthreat_cmp")
    conn.close()
    print("wrote", OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
