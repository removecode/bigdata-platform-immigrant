#!/usr/bin/env bash
# Start the local StarRocks, Hive, Trino, and query console. Safe to rerun.
set -euo pipefail

export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH="${JAVA_HOME}/bin:/opt/lab:${PATH}"
export HADOOP_HOME=/opt/lab/hadoop
export HADOOP_CONF_DIR=/opt/lab/hadoop/etc/hadoop
export HIVE_HOME=/opt/lab/hive
export HIVE_CONF_DIR=/opt/lab/hive/conf
# shellcheck disable=SC1091
source /opt/lab/hive/conf/hive-env.sh

mkdir -p /var/log/lab /var/lib/lab/hive/warehouse /var/lib/lab/hadoop/tmp
if [[ -f /var/lib/lab/swapfile ]] && ! swapon --show | grep -q /var/lib/lab/swapfile; then
  sudo swapon /var/lib/lab/swapfile || true
fi
sudo sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1 || true
sudo sysctl -w vm.max_map_count=2000000 >/dev/null 2>&1 || true
ulimit -n 65535 || true

port_open() {
  python3 - "$1" <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(0.4)
try:
    raise SystemExit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)
finally:
    s.close()
PY
}

wait_port() {
  local port="$1" name="$2" tries="${3:-60}"
  local i
  for i in $(seq 1 "${tries}"); do
    if port_open "${port}"; then
      echo "${name} is listening on ${port}"
      return 0
    fi
    sleep 2
  done
  echo "${name} did not open port ${port}" >&2
  return 1
}

if ! port_open 9030; then
  /opt/lab/starrocks/fe/bin/start_fe.sh --daemon
fi
wait_port 9030 "StarRocks FE" 40 || { tail -n 80 /opt/lab/starrocks/fe/log/fe.log || true; exit 1; }

if ! port_open 9050; then
  /opt/lab/starrocks/be/bin/start_be.sh --daemon
fi
wait_port 9050 "StarRocks BE" 40 || { tail -n 80 /opt/lab/starrocks/be/log/be.INFO || true; exit 1; }

python3 - <<'PY'
import time
import pymysql
last = None
for _ in range(30):
    try:
        conn = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", autocommit=True, connect_timeout=5)
        cur = conn.cursor()
        cur.execute("SHOW BACKENDS")
        rows = cur.fetchall()
        alive = any(str(row[8]).lower() == "true" or row[8] is True for row in rows) if rows else False
        # SHOW BACKENDS columns vary; also accept a row whose host is 127.0.0.1.
        hosts = [str(row[1]) for row in rows]
        if not any(h.startswith("127.0.0.1") for h in hosts):
            cur.execute('ALTER SYSTEM ADD BACKEND "127.0.0.1:9050"')
        conn.close()
        print("starrocks backends", hosts or "(added)")
        break
    except Exception as exc:
        last = exc
        time.sleep(2)
else:
    raise SystemExit(f"StarRocks SQL is not ready: {last}")
PY

if ! port_open 9083; then
  nohup /opt/lab/hive/bin/hive --service metastore >>/var/log/lab/hive-metastore.log 2>&1 &
  echo $! >/var/log/lab/hive-metastore.pid
fi
wait_port 9083 "Hive Metastore" 60 || { tail -n 100 /var/log/lab/hive-metastore.log || true; exit 1; }

if ! port_open 10000; then
  nohup /opt/lab/hive/bin/hive --service hiveserver2 >>/var/log/lab/hiveserver2.log 2>&1 &
  echo $! >/var/log/lab/hiveserver2.pid
fi
wait_port 10000 "HiveServer2" 90 || { tail -n 120 /var/log/lab/hiveserver2.log || true; exit 1; }

if ! port_open 8080; then
  /opt/lab/trino/bin/launcher start
fi
wait_port 8080 "Trino" 45 || { tail -n 80 /var/lib/lab/trino/var/log/server.log || true; exit 1; }

if ! port_open 8787; then
  nohup python3 /opt/lab/query_platform.py >>/var/log/lab/query-platform.log 2>&1 &
  echo $! >/var/log/lab/query-platform.pid
fi
wait_port 8787 "Query platform" 20 || { tail -n 80 /var/log/lab/query-platform.log || true; exit 1; }

if [[ ! -f /var/lib/lab/seeded ]]; then
  python3 /opt/lab/seed.py
  touch /var/lib/lab/seeded
fi

echo "lab is up"
