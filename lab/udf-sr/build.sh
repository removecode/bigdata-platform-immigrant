#!/usr/bin/env bash
# Compile the StarRocks twin of default.format_json_list. Does not touch lab/udf.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="/tmp/lab-udf-sr-classes"
JAR="/opt/lab/udf/lab-udf-sr.jar"

rm -rf "${OUT}"
mkdir -p "${OUT}" "$(dirname "${JAR}")"
find "${ROOT}/src" -name '*.java' > "${OUT}/sources.txt"
javac --release 21 -encoding UTF-8 -d "${OUT}" @"${OUT}/sources.txt"
jar cf "${JAR}" -C "${OUT}" .
echo "built ${JAR}"
