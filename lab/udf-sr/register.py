#!/usr/bin/env python3
"""Register default.format_json_list in the local StarRocks.

StarRocks fetches the UDF jar by URL, and the BE downloads it again when a
query first calls the function, so this leaves a detached HTTP server on
127.0.0.1:8899 serving /opt/lab/udf. Needs enable_udf = true and
-Djava.security.manager=allow in fe.conf (Java 21).
"""
import socket
import subprocess
import sys
import time

import pymysql

JAR_DIR = "/opt/lab/udf"
JAR_NAME = "lab-udf-sr.jar"
PORT = 8899

def port_open() -> bool:
    with socket.socket() as s:
        s.settimeout(0.4)
        return s.connect_ex(("127.0.0.1", PORT)) == 0


if not port_open():
    subprocess.Popen(
        [sys.executable, "-m", "http.server", str(PORT), "--bind", "127.0.0.1", "--directory", JAR_DIR],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(1)
if True:
    conn = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", autocommit=True)
    cur = conn.cursor()
    cur.execute("CREATE DATABASE IF NOT EXISTS `default`")
    cur.execute("DROP FUNCTION IF EXISTS `default`.format_json_list(string)")
    cur.execute(
        "CREATE FUNCTION `default`.format_json_list(string) RETURNS array<string> "
        "PROPERTIES ("
        '"symbol" = "lab.udfsr.FormatJsonList", "type" = "StarrocksJar", '
        f'"file" = "http://127.0.0.1:{PORT}/{JAR_NAME}")'
    )
    cur.execute("SHOW FULL FUNCTIONS IN `default` LIKE 'format_json_list'")
    print(cur.fetchall())
