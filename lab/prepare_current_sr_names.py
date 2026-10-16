#!/usr/bin/env python3
"""Expose the confirmed StarRocks names on this lab so converted SQL can run.

Physical lab tables keep the old columns. This script adds views only:
csc.ods_csc_log_audit projects log_app_id as app_id, and the two sodl log
tables gain insertdate plus inserttimestamp derived from day and hour.
It does not change the user's StarRocks.
"""

from __future__ import annotations

import pymysql

DATE_EXPR = (
    "concat(substr(cast(day AS STRING),1,4),'-',"
    "substr(cast(day AS STRING),5,2),'-',substr(cast(day AS STRING),7,2))"
)
TS_EXPR = (
    "unix_timestamp(concat(" + DATE_EXPR + ", ' ', "
    "lpad(cast(hour AS STRING), 2, '0'), ':00:00'))"
)


def is_view(cur, db: str, table: str) -> bool:
    cur.execute(f"SHOW TABLES FROM `{db}` LIKE %s", (table,))
    if not cur.fetchall():
        return False
    cur.execute(f"SHOW CREATE TABLE `{db}`.`{table}`")
    return cur.fetchone()[1].lstrip().upper().startswith("CREATE VIEW")


def ensure_sodl(cur, table: str, columns: list[str]) -> None:
    if is_view(cur, "sodl", table):
        print(f"sodl.{table} already a view")
        return
    cur.execute(f"ALTER TABLE sodl.{table} RENAME {table}_lab_base")
    cols = ", ".join(columns)
    cur.execute(
        f"CREATE VIEW sodl.{table} AS "
        f"SELECT {cols}, {DATE_EXPR} AS insertdate, {TS_EXPR} AS inserttimestamp "
        f"FROM sodl.{table}_lab_base"
    )
    print(f"created view sodl.{table}")


def main() -> None:
    conn = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="")
    cur = conn.cursor()
    cur.execute("CREATE DATABASE IF NOT EXISTS csc")
    if not is_view(cur, "csc", "ods_csc_log_audit"):
        cur.execute("DROP TABLE IF EXISTS csc.ods_csc_log_audit")
        cur.execute(
            "CREATE VIEW csc.ods_csc_log_audit AS "
            "SELECT day, hour, log_app_id AS app_id, module_id, str1, str2, str4, str5, str10, long1 "
            "FROM `default`.log_audit_source"
        )
        print("created view csc.ods_csc_log_audit")
    else:
        print("csc.ods_csc_log_audit already a view")
    ensure_sodl(
        cur,
        "network_security_log",
        [
            "day", "hour", "srcip", "dstip", "engine", "severity", "threatclass",
            "threattype", "threatsubtype", "url", "action", "producttype", "log_num",
            "manage", "reqruleid", "rulename", "requesthead", "requestbody",
        ],
    )
    ensure_sodl(
        cur,
        "sip_iocstat_log",
        ["day", "hour", "ioc", "ioc_type", "manage", "record_count"],
    )
    conn.close()


if __name__ == "__main__":
    main()
