#!/usr/bin/env bash
# Register the lab Hive UDFs. Safe to rerun after HiveServer2 is up.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAR="/opt/lab/udf/lab-udf.jar"
if [[ ! -f "${JAR}" ]]; then
  bash "${ROOT}/build.sh"
fi

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export HADOOP_HOME="${HADOOP_HOME:-/opt/lab/hadoop}"
export HADOOP_CONF_DIR="${HADOOP_CONF_DIR:-/opt/lab/hadoop/etc/hadoop}"
export HIVE_HOME="${HIVE_HOME:-/opt/lab/hive}"
export HIVE_CONF_DIR="${HIVE_CONF_DIR:-/opt/lab/hive/conf}"
# shellcheck disable=SC1091
source "${HIVE_CONF_DIR}/hive-env.sh"

SQL="$(mktemp)"
cat > "${SQL}" <<SQL
DROP FUNCTION IF EXISTS default.format_json_list;
DROP FUNCTION IF EXISTS default.calc_url_mask;
DROP FUNCTION IF EXISTS default.sub_parent_domain;
CREATE FUNCTION default.format_json_list AS 'lab.udf.FormatJsonList' USING JAR 'file://${JAR}';
CREATE FUNCTION default.calc_url_mask AS 'lab.udf.CalcUrlMask' USING JAR 'file://${JAR}';
CREATE FUNCTION default.sub_parent_domain AS 'lab.udf.SubParentDomain' USING JAR 'file://${JAR}';
SHOW FUNCTIONS LIKE '*format_json_list*';
SHOW FUNCTIONS LIKE '*calc_url_mask*';
SHOW FUNCTIONS LIKE '*sub_parent_domain*';
SQL

cd /tmp
"${HIVE_HOME}/bin/beeline" -u 'jdbc:hive2://127.0.0.1:10000' --silent=true --showHeader=false --outputformat=tsv2 -f "${SQL}"
rm -f "${SQL}"
