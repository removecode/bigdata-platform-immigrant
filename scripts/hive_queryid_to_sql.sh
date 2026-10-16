#!/usr/bin/env bash
set -euo pipefail

DEFAULT_LOG_DIR="/matrix/data/logs/hive"
DEFAULT_PATTERN="hiveserver2.log*"
DEFAULT_STAGE_DIR="/tmp/hive_queryid_to_sql"

LOG_DIR=""
PATTERN="$DEFAULT_PATTERN"
STAGE_DIR="$DEFAULT_STAGE_DIR"
FORMAT="text"
FORMAT_SET=0
SQL_DIR=""
LIMIT=0
NO_COMPRESSED=0
LOGS=()
QUERY_IDS=()
LOG_COUNT=0
QUERY_COUNT=0

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [query_id ...] [options]

Description:
  Map HiveServer2 queryId, such as hive_20260512015916_xxx, to full multi-line SQL.
  query_id supports prefix matching, for example hive_20260512015916.

Options:
  --log FILE             HiveServer2 log file to scan. Can be repeated.
  --log-dir DIR          Directory to scan. Default when --log is omitted: $DEFAULT_LOG_DIR
  --pattern PATTERN      File pattern under --log-dir. Default: $DEFAULT_PATTERN
  --stage-dir DIR        Directory used for copied/decompressed compressed logs. Default: $DEFAULT_STAGE_DIR
  --no-compressed        Skip compressed logs.
  --format text|tsv      Output format. Default: text when query_id is given, tsv when query_id is omitted
  --sql-dir DIR          Write one .sql file per matched queryId.
  --limit N              Stop after N matched queryIds. Default: no limit
  -h, --help             Show this help.

Examples:
  $(basename "$0") hive_20260512015916
  $(basename "$0") hive_20260512015916 --log /matrix/data/logs/hive/hiveserver2.log
  $(basename "$0") hive_20260512015916 --sql-dir /tmp/hive_sql
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --log)
      [ "$#" -ge 2 ] || die "--log requires FILE"
      LOGS[$LOG_COUNT]="$2"
      LOG_COUNT=$((LOG_COUNT + 1))
      shift 2
      ;;
    --log-dir)
      [ "$#" -ge 2 ] || die "--log-dir requires DIR"
      LOG_DIR="$2"
      shift 2
      ;;
    --pattern)
      [ "$#" -ge 2 ] || die "--pattern requires PATTERN"
      PATTERN="$2"
      shift 2
      ;;
    --stage-dir)
      [ "$#" -ge 2 ] || die "--stage-dir requires DIR"
      STAGE_DIR="$2"
      shift 2
      ;;
    --no-compressed)
      NO_COMPRESSED=1
      shift
      ;;
    --format)
      [ "$#" -ge 2 ] || die "--format requires text or tsv"
      FORMAT="$2"
      [ "$FORMAT" = "text" ] || [ "$FORMAT" = "tsv" ] || die "--format must be text or tsv"
      FORMAT_SET=1
      shift 2
      ;;
    --sql-dir)
      [ "$#" -ge 2 ] || die "--sql-dir requires DIR"
      SQL_DIR="$2"
      shift 2
      ;;
    --limit)
      [ "$#" -ge 2 ] || die "--limit requires N"
      LIMIT="$2"
      case "$LIMIT" in
        ''|*[!0-9]*) die "--limit must be a non-negative integer" ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        QUERY_IDS[$QUERY_COUNT]="$1"
        QUERY_COUNT=$((QUERY_COUNT + 1))
        shift
      done
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      QUERY_IDS[$QUERY_COUNT]="$1"
      QUERY_COUNT=$((QUERY_COUNT + 1))
      shift
      ;;
  esac
done

is_compressed() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.gz|*.bz2|*.zip) return 0 ;;
    *) return 1 ;;
  esac
}

stage_name_for() {
  local path="$1"
  path="${path#/}"
  path="${path//\//__}"
  printf '%s/%s' "$STAGE_DIR" "$path"
}

copy_and_decompress() {
  local src="$1"
  local copied out extract_dir member base lower

  mkdir -p "$STAGE_DIR"
  copied="$(stage_name_for "$src")"
  cp -p "$src" "$copied"

  lower="$(printf '%s' "$copied" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *.gz)
      out="${copied%.gz}"
      gzip -cd "$copied" > "$out"
      printf '%s\n' "$out"
      ;;
    *.bz2)
      out="${copied%.bz2}"
      bzip2 -cd "$copied" > "$out"
      printf '%s\n' "$out"
      ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || die "unzip not found, cannot read $src"
      extract_dir="${copied}.extract"
      rm -rf "$extract_dir"
      mkdir -p "$extract_dir"
      while IFS= read -r member; do
        case "$member" in
          */) continue ;;
        esac
        base="$(basename "$member")"
        [ -n "$base" ] || continue
        unzip -p "$copied" "$member" > "$extract_dir/$base"
        printf '%s\n' "$extract_dir/$base"
      done < <(unzip -Z1 "$copied")
      ;;
    *)
      printf '%s\n' "$copied"
      ;;
  esac
}

collect_logs() {
  local path name

  if [ "$LOG_COUNT" -eq 0 ] && [ -z "$LOG_DIR" ]; then
    LOG_DIR="$DEFAULT_LOG_DIR"
  fi

  for path in "${LOGS[@]+"${LOGS[@]}"}"; do
    if [ -e "$path" ]; then
      printf '%s\n' "$path"
    else
      warn "log file not found: $path"
    fi
  done

  if [ -n "$LOG_DIR" ]; then
    if [ ! -d "$LOG_DIR" ]; then
      warn "log dir not found: $LOG_DIR"
    else
      while IFS= read -r path; do
        name="$(basename "$path")"
        case "$name" in
          $PATTERN) printf '%s\n' "$path" ;;
        esac
      done < <(find "$LOG_DIR" -maxdepth 1 -type f | sort)
    fi
  fi
}

build_query_filter() {
  local joined="" q
  for q in "${QUERY_IDS[@]+"${QUERY_IDS[@]}"}"; do
    if [ -z "$joined" ]; then
      joined="$q"
    else
      joined="${joined}|${q}"
    fi
  done
  printf '%s' "$joined"
}

run_awk_parser() {
  local query_filter="$1"
  local source="$2"
  local count_file="$3"

  awk \
    -v query_filter="$query_filter" \
    -v source="$source" \
    -v format="$FORMAT" \
    -v sql_dir="$SQL_DIR" \
    -v limit="$LIMIT" \
    -v count_file="$count_file" '
function trim(s) {
  sub(/^[ \t\r\n]+/, "", s)
  sub(/[ \t\r\n]+$/, "", s)
  return s
}

function shell_quote(s,    q) {
  q = sprintf("%c", 39)
  gsub(q, q "\\" q q, s)
  return q s q
}

function query_wanted(query_id,    n, ids, i) {
  if (query_filter == "") {
    return 1
  }
  n = split(query_filter, ids, /\|/)
  for (i = 1; i <= n; i++) {
    if (query_id == ids[i] || index(query_id, ids[i]) == 1) {
      return 1
    }
  }
  return 0
}

function write_sql_file(query_id, sql,    path, cmd) {
  path = sql_dir "/" query_id ".sql"
  cmd = "mkdir -p " shell_quote(sql_dir)
  system(cmd)
  print sql > path
  close(path)
  return path
}

function emit(record,    first_line, head, query_id, sql, lines, sql_file, one_line) {
  if (record !~ /Compiling command\(queryId=[^)]*\)/) {
    return
  }

  first_line = record
  sub(/\n.*/, "", first_line)

  head = record
  sub(/^.*Compiling command\(queryId=/, "", head)
  query_id = head
  sub(/\).*/, "", query_id)
  query_id = trim(query_id)

  sql = record
  sub(/^.*Compiling command\(queryId=[^)]*\)[ \t]*/, "", sql)
  sql = trim(sql)

  if (query_id == "" || sql == "" || !query_wanted(query_id)) {
    return
  }

  count++
  sql_file = ""
  if (sql_dir != "") {
    sql_file = write_sql_file(query_id, sql)
  }

  if (format == "tsv") {
    one_line = sql
    gsub(/[ \t\r\n]+/, " ", one_line)
    printf "%s\t%s\t%s\t%s\n", query_id, substr(first_line, 1, 23), one_line, source
  } else {
    if (count > 1) {
      print ""
      print "===================================================================================================="
      print ""
    }
    print "query_id: " query_id
    print "log_time: " substr(first_line, 1, 23)
    print "source: " source
    if (sql_dir != "") {
      print "sql_file: " sql_file
    }
    print ""
    print sql
  }

  if (limit > 0 && count >= limit) {
    stopped = 1
    exit 0
  }
}

BEGIN {
  count = 0
  stopped = 0
}

/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9],[0-9][0-9][0-9][ \t]/ {
  if (record != "") {
    emit(record)
  }
  record = $0
  next
}

{
  if (record != "") {
    record = record "\n" $0
  }
}

END {
  if (!stopped && record != "") {
    emit(record)
  }
  printf "%d\n", count >> count_file
}
' "$source"
}

main() {
  local query_filter tmp_counts total_count path prepared count_line
  query_filter="$(build_query_filter)"
  tmp_counts="$(mktemp "${TMPDIR:-/tmp}/hive-queryid-count.XXXXXX")"
  total_count=0

  if [ "$QUERY_COUNT" -eq 0 ] && [ "$FORMAT_SET" -eq 0 ]; then
    FORMAT="tsv"
  fi

  if [ "$FORMAT" = "tsv" ]; then
    printf 'query_id\tlog_time\tsql\tsource\n'
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if is_compressed "$path"; then
      if [ "$NO_COMPRESSED" -eq 1 ]; then
        continue
      fi
      while IFS= read -r prepared; do
        [ -n "$prepared" ] || continue
        run_awk_parser "$query_filter" "$prepared" "$tmp_counts"
      done < <(copy_and_decompress "$path")
    else
      run_awk_parser "$query_filter" "$path" "$tmp_counts"
    fi
  done < <(collect_logs | awk '!seen[$0]++')

  while IFS= read -r count_line; do
    total_count=$((total_count + count_line))
  done < "$tmp_counts"
  rm -f "$tmp_counts"

  if [ "$total_count" -eq 0 ]; then
    die "no matching queryId found"
  fi
}

main "$@"
