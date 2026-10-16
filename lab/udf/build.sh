#!/usr/bin/env bash
# Compile the three Hive UDFs named in the migration notes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${ROOT}/src"
OUT="/tmp/lab-udf-classes"
JAR="/opt/lab/udf/lab-udf.jar"
HIVE_EXEC="/opt/lab/hive/lib/hive-exec-4.0.1.jar"

if [[ ! -f "${HIVE_EXEC}" ]]; then
  echo "hive-exec is not installed at ${HIVE_EXEC}" >&2
  exit 1
fi

rm -rf "${OUT}"
mkdir -p "${OUT}" "$(dirname "${JAR}")"
find "${SRC}" -name '*.java' > "${OUT}/sources.txt"
javac --release 21 -encoding UTF-8 -cp "${HIVE_EXEC}" -d "${OUT}" @"${OUT}/sources.txt"
jar cf "${JAR}" -C "${OUT}" .
java -cp "${JAR}:${HIVE_EXEC}" lab.udf.UdfSelfCheck
echo "built ${JAR}"
