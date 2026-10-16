#!/usr/bin/env python3
"""Load one small table into StarRocks and Hive so both engines return real rows."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pymysql

CSV = Path("/var/lib/lab/hive/ioc_hit.csv")
ROWS = [
    ("ip", "203.0.113.10", 3),
    ("domain", "example.test", 5),
    ("md5", "0123456789abcdef0123456789abcdef", 2),
]


def seed_starrocks() -> None:
    conn = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", autocommit=True)
    cur = conn.cursor()
    cur.execute("CREATE DATABASE IF NOT EXISTS lab")
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS lab.ioc_hit (
          ioc_type VARCHAR(32),
          ioc_value VARCHAR(128),
          hit_count BIGINT
        )
        DUPLICATE KEY(ioc_type, ioc_value)
        DISTRIBUTED BY HASH(ioc_value) BUCKETS 1
        PROPERTIES("replication_num"="1")
        """
    )
    cur.execute("TRUNCATE TABLE lab.ioc_hit")
    cur.executemany("INSERT INTO lab.ioc_hit VALUES (%s, %s, %s)", ROWS)
    cur.execute("SELECT ioc_type, ioc_value, hit_count FROM lab.ioc_hit ORDER BY ioc_value")
    print("starrocks", cur.fetchall())
    conn.close()


def seed_hive() -> None:
    CSV.write_text("".join(f"{kind},{value},{count}\n" for kind, value, count in ROWS), encoding="utf-8")
    sql = """
CREATE DATABASE IF NOT EXISTS lab;
DROP TABLE IF EXISTS lab.ioc_hit;
CREATE TABLE lab.ioc_hit (ioc_type STRING, ioc_value STRING, hit_count BIGINT)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'file:///var/lib/lab/hive/warehouse/lab.db/ioc_hit';
LOAD DATA LOCAL INPATH '/var/lib/lab/hive/ioc_hit.csv' OVERWRITE INTO TABLE lab.ioc_hit;
SELECT ioc_type, ioc_value, hit_count FROM lab.ioc_hit ORDER BY ioc_value;
""".strip()
    cmd = [
        "/opt/lab/hive/bin/beeline",
        "-u",
        "jdbc:hive2://127.0.0.1:10000",
        "--silent=true",
        "--showHeader=false",
        "--outputformat=tsv2",
        "-e",
        sql,
    ]
    env = dict(**{k: v for k, v in __import__("os").environ.items()})
    completed = subprocess.run(cmd, check=False, text=True, capture_output=True, env=env)
    print(completed.stdout)
    if completed.returncode != 0:
        print(completed.stderr)
        raise SystemExit(completed.returncode)


if __name__ == "__main__":
    seed_starrocks()
    seed_hive()
