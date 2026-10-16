#!/usr/bin/env bash
# Idempotent local lab install: StarRocks 3.5.21, Hadoop 3.4.1, Hive 4.0.1, Trino 446.
set -euo pipefail

LAB_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAVA_HOME_DEFAULT="/usr/lib/jvm/java-21-openjdk-amd64"

sudo mkdir -p /opt/lab/dist /var/lib/lab /var/log/lab
sudo chown -R ubuntu:ubuntu /opt/lab /var/lib/lab /var/log/lab

if [[ ! -f /var/lib/lab/swapfile ]]; then
  sudo fallocate -l 8G /var/lib/lab/swapfile
  sudo chmod 600 /var/lib/lab/swapfile
  sudo mkswap /var/lib/lab/swapfile
fi

sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libaio1t64
sudo ln -sfn /usr/bin/python3 /usr/local/bin/python
if [[ ! -e /usr/lib/x86_64-linux-gnu/libaio.so.1 ]]; then
  aio="$(ls /usr/lib/x86_64-linux-gnu/libaio.so.* 2>/dev/null | head -1 || true)"
  if [[ -n "${aio}" ]]; then
    sudo ln -sfn "$(basename "${aio}")" /usr/lib/x86_64-linux-gnu/libaio.so.1
  fi
fi

python3 -m pip install --user 'pymysql==1.1.1' 'sqlglot==30.18.0' 'pandas==3.0.6' 'openpyxl==3.1.5'

download() {
  local url="$1" dest="$2"
  if [[ -s "${dest}" ]]; then
    return 0
  fi
  curl -fL --retry 3 --retry-delay 2 -A 'Mozilla/5.0' -o "${dest}.partial" "${url}"
  mv "${dest}.partial" "${dest}"
}

download "https://releases.starrocks.io/starrocks/StarRocks-3.5.21-ubuntu-amd64.tar.gz" /opt/lab/dist/starrocks.tgz
download "https://archive.apache.org/dist/hadoop/common/hadoop-3.4.1/hadoop-3.4.1.tar.gz" /opt/lab/dist/hadoop.tgz
download "https://archive.apache.org/dist/hive/hive-4.0.1/apache-hive-4.0.1-bin.tar.gz" /opt/lab/dist/hive.tgz
download "https://maven.aliyun.com/repository/central/io/trino/trino-server/446/trino-server-446.tar.gz" /opt/lab/dist/trino-server-446.tar.gz
download "https://repo1.maven.org/maven2/io/trino/trino-cli/446/trino-cli-446-executable.jar" /opt/lab/dist/trino-cli-446-executable.jar

if [[ ! -d /opt/lab/StarRocks-3.5.21-ubuntu-amd64 ]]; then
  tar -xzf /opt/lab/dist/starrocks.tgz -C /opt/lab
fi
if [[ ! -d /opt/lab/hadoop-3.4.1 ]]; then
  tar -xzf /opt/lab/dist/hadoop.tgz -C /opt/lab
fi
if [[ ! -d /opt/lab/apache-hive-4.0.1-bin ]]; then
  tar -xzf /opt/lab/dist/hive.tgz -C /opt/lab
fi
if [[ ! -x /opt/lab/trino-server-446/bin/launcher ]]; then
  tar -xzf /opt/lab/dist/trino-server-446.tar.gz -C /opt/lab
fi

ln -sfn /opt/lab/StarRocks-3.5.21-ubuntu-amd64 /opt/lab/starrocks
ln -sfn /opt/lab/hadoop-3.4.1 /opt/lab/hadoop
ln -sfn /opt/lab/apache-hive-4.0.1-bin /opt/lab/hive
ln -sfn /opt/lab/trino-server-446 /opt/lab/trino
chmod +x /opt/lab/dist/trino-cli-446-executable.jar
ln -sfn /opt/lab/dist/trino-cli-446-executable.jar /opt/lab/trino-cli

python3 - "${JAVA_HOME_DEFAULT}" <<'PY'
import pathlib, sys
java_home = sys.argv[1]
fe = pathlib.Path("/opt/lab/starrocks/fe/conf/fe.conf")
text = fe.read_text()
old = None
for line in text.splitlines():
    if line.startswith("JAVA_OPTS="):
        old = line
        break
if old is None:
    raise SystemExit("fe.conf has no JAVA_OPTS")
new = (
    'JAVA_OPTS="-Dlog4j2.formatMsgNoLookups=true -Xms512m -Xmx768m -XX:+UseG1GC '
    '-Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time -XX:ErrorFile=${LOG_DIR}/hs_err_pid%p.log '
    '-Djava.security.policy=${STARROCKS_HOME}/conf/udf_security.policy"'
)
text = text.replace(old, new, 1)
extra = """
JAVA_HOME = %s
meta_dir = /var/lib/lab/starrocks/fe/meta
priority_networks = 127.0.0.1/32
""" % java_home
marker = "# lab-local-memory"
if marker not in text:
    text += "\n" + marker + extra
fe.write_text(text)

be = pathlib.Path("/opt/lab/starrocks/be/conf/be.conf")
btext = be.read_text()
bmarker = "# lab-local-memory"
if bmarker not in btext:
    btext += f"""
{bmarker}
JAVA_HOME = {java_home}
mem_limit = 2147483648
storage_root_path = /var/lib/lab/starrocks/be
priority_networks = 127.0.0.1/32
storage_page_cache_limit = 134217728
disable_storage_page_cache = true
"""
    be.write_text(btext)
PY

mkdir -p /var/lib/lab/starrocks/fe/meta /var/lib/lab/starrocks/be \
  /var/lib/lab/hive/warehouse /var/lib/lab/hadoop/tmp /var/lib/lab/trino \
  /opt/lab/trino/etc/catalog

cp "${LAB_SRC}/conf/core-site.xml" /opt/lab/hadoop/etc/hadoop/core-site.xml
cp "${LAB_SRC}/conf/mapred-site.xml" /opt/lab/hadoop/etc/hadoop/mapred-site.xml
cp "${LAB_SRC}/conf/hive-site.xml" /opt/lab/hive/conf/hive-site.xml
cp "${LAB_SRC}/conf/hive-env.sh" /opt/lab/hive/conf/hive-env.sh
cp "${LAB_SRC}/conf/trino/jvm.config" /opt/lab/trino/etc/jvm.config
cp "${LAB_SRC}/conf/trino/config.properties" /opt/lab/trino/etc/config.properties
cp "${LAB_SRC}/conf/trino/node.properties" /opt/lab/trino/etc/node.properties
cp "${LAB_SRC}/conf/trino/log.properties" /opt/lab/trino/etc/log.properties
cp "${LAB_SRC}/conf/trino/catalog/hive.properties" /opt/lab/trino/etc/catalog/hive.properties
cp "${LAB_SRC}/conf/trino/catalog/starrocks.properties" /opt/lab/trino/etc/catalog/starrocks.properties

# Hive schematool reads hive-site and opens Derby itself. Point it at the
# embedded database only for initialization; the running metastore uses the
# same URL while HiveServer2 and Trino use the Thrift URI.
if [[ ! -d /var/lib/lab/hive/metastore_db ]]; then
  export JAVA_HOME="${JAVA_HOME_DEFAULT}"
  export HADOOP_HOME=/opt/lab/hadoop
  export HADOOP_CONF_DIR=/opt/lab/hadoop/etc/hadoop
  export HIVE_HOME=/opt/lab/hive
  export HIVE_CONF_DIR=/opt/lab/hive/conf
  # shellcheck disable=SC1091
  source /opt/lab/hive/conf/hive-env.sh
  /opt/lab/hive/bin/schematool -dbType derby -initSchema
fi

mkdir -p /opt/lab/udf
rm -rf /opt/lab/udf/src
cp -a "${LAB_SRC}/udf/src" /opt/lab/udf/src
install -m 0755 "${LAB_SRC}/udf/build.sh" /opt/lab/udf/build.sh
install -m 0755 "${LAB_SRC}/udf/register.sh" /opt/lab/udf/register.sh
bash /opt/lab/udf/build.sh

install -m 0755 "${LAB_SRC}/start.sh" /opt/lab/start.sh
install -m 0755 "${LAB_SRC}/seed.py" /opt/lab/seed.py
install -m 0755 "${LAB_SRC}/query_platform.py" /opt/lab/query_platform.py
echo "lab install complete"
