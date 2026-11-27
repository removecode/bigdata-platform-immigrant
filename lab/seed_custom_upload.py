#!/usr/bin/env python3
"""Create the local stand-in for paimon.ti.ods_ti_db_custom_upload_tb_custom_upload_sync.

Rows are exactly the six samples the user pasted from the old platform
(docs/迁移事项进度与决策追踪.md ACT-084, two rows per part1). Columns are the old
table's str1-str5, part1, part2; the new table's real column names are unconfirmed.
The lab has no paimon catalog, so the table lives in the lab database `ti`.
Not the full table: only these samples are known.
"""

from __future__ import annotations

import pymysql

TABLE = "ti.ods_ti_db_custom_upload_tb_custom_upload_sync"
COLUMNS = ["str1", "str2", "str3", "str4", "str5", "part1", "part2"]

SAMPLES = [
    ("17830043", "af_rule_id", "webshell"),
    ("13080588", "af_rule_id", "webshell"),
    ("B7CF33F1", "af_test_device_id", "attack_ip_analysis"),
    ("E6A17B09", "af_test_device_id", "attack_ip_analysis"),
    ("71CCCF1E28FFA98CD6B8ABC0BD87DC0C", "test_dev", "test_devid"),
    ("6ACC9BED3F02573DA4FD71735AEB5440", "test_dev", "test_devid"),
]


def ddl(name: str) -> str:
    cols = ", ".join(f"`{c}` VARCHAR(512)" for c in COLUMNS)
    return (
        f"CREATE TABLE IF NOT EXISTS {name} ({cols}) DUPLICATE KEY(`str1`) "
        "DISTRIBUTED BY HASH(`str1`) BUCKETS 1 PROPERTIES('replication_num'='1')"
    )


def load(cur, name: str) -> None:
    cur.execute(f"TRUNCATE TABLE {name}")
    cur.executemany(
        f"INSERT INTO {name} (`str1`, `part1`, `part2`) VALUES (%s, %s, %s)", SAMPLES
    )


def main() -> None:
    cur = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", autocommit=True).cursor()
    cur.execute("CREATE DATABASE IF NOT EXISTS ti")
    cur.execute(ddl(TABLE))
    load(cur, TABLE)
    cur.execute(f"SELECT part1, part2, count(*) FROM {TABLE} GROUP BY part1, part2 ORDER BY part1")
    for row in cur.fetchall():
        print(row)


if __name__ == "__main__":
    main()
