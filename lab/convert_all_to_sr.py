#!/usr/bin/env python3
"""Rewrite /workspace/all.sql into StarRocks and optionally run it on the lab.

No new-platform table names were supplied with this request (DEC-013), so every
physical name stays as written and is marked 缺少新平台表名. Placeholder values
come from the comments in all.sql and from the rows built by
lab/build_bulk_data.py. They are lab fill-ins, not production parameters.

DEC-009 still applies: production migrated columns are VARCHAR, and this file
does not invent an encoding. Numeric comparisons are listed, not wrapped in a
guessed CAST. The lab tables keep the INT/BIGINT/VARCHAR types from ACT-034.
"""

from __future__ import annotations

import argparse
import calendar
import re
import sys
from pathlib import Path

import pymysql

ROOT = Path("/workspace")
SOURCE = ROOT / "all.sql"
SQL_OUT = ROOT / "outputs" / "all-starrocks.sql"
RESULT_OUT = ROOT / "outputs" / "all-starrocks-results.tsv"

AGO_TS = calendar.timegm((2026, 4, 2, 0, 0, 0))
AGO_OID = f"{AGO_TS:08x}{'0' * 16}"
RUN_TIME_MS = 1790901600000
SKYEYE_UPDATE_MS = RUN_TIME_MS - 365 * 86400 * 1000
# Days actually present in the lab vertex table. all.sql says the production
# list is every Wednesday from 2021-12 through 2026-12; ACT-034 did not load that.
LAB_DAYS = (
    "20260819, 20260826, 20260902, 20260909, 20260916, 20260923, "
    "20260925, 20260926, 20260927, 20260928, 20260929, 20260930, 20261001"
)

PLACEHOLDERS = {
    "{AGO_OID}": AGO_OID,
    "{DAYS}": LAB_DAYS,
    "{LAST_HOUR}": "2026100200",
    "{NOW_HOUR}": "2026100201",
    "{TENANT_IDS}": "'tenantA', 'tenantB', 'tenantC'",
    "{START_TIME}": "20260915",
    "{END_TIME}": "20261001",
    "{LAST_TS}": "1790901000",
    "{END_TS}": "1790901600",
    "{RUN_TIME_MS}": str(RUN_TIME_MS),
    "{SKYEYE_UPDATE_MS}": str(SKYEYE_UPDATE_MS),
    "${day}": "20261001",
    "${hour}": "0",
}

STRING_MARK = "«S{0:04d}»"


def mask_strings(sql: str) -> tuple[str, list[str]]:
    parts: list[str] = []
    strings: list[str] = []
    index = 0
    while index < len(sql):
        if sql[index] != "'":
            parts.append(sql[index])
            index += 1
            continue
        cursor = index + 1
        while cursor < len(sql):
            if sql[cursor] == "\\":
                cursor += 2
                continue
            if sql[cursor] == "'":
                if cursor + 1 < len(sql) and sql[cursor + 1] == "'":
                    cursor += 2
                    continue
                cursor += 1
                break
            cursor += 1
        strings.append(sql[index:cursor])
        parts.append(STRING_MARK.format(len(strings) - 1))
        index = cursor
    return "".join(parts), strings


def unmask_strings(sql: str, strings: list[str]) -> str:
    for number, literal in enumerate(strings):
        sql = sql.replace(STRING_MARK.format(number), literal)
    return sql


def hive_double_quotes(sql: str) -> str:
    """Hive uses double quotes for string literals. StarRocks uses single quotes."""
    output: list[str] = []
    index = 0
    while index < len(sql):
        character = sql[index]
        if character == "'":
            output.append(character)
            index += 1
            while index < len(sql):
                if sql[index] == "\\":
                    output.append(sql[index : index + 2])
                    index += 2
                    continue
                output.append(sql[index])
                if sql[index] == "'":
                    if index + 1 < len(sql) and sql[index + 1] == "'":
                        output.append("'")
                        index += 2
                        continue
                    index += 1
                    break
                index += 1
            continue
        if character == '"':
            output.append("'")
            index += 1
            while index < len(sql):
                if sql[index] == "\\":
                    output.append(sql[index : index + 2])
                    index += 2
                    continue
                if sql[index] == "'":
                    output.append("''")
                    index += 1
                    continue
                if sql[index] == '"':
                    output.append("'")
                    index += 1
                    break
                output.append(sql[index])
                index += 1
            continue
        output.append(character)
        index += 1
    return "".join(output)


def split_top_args(args: str) -> list[str]:
    parts: list[str] = []
    buffer: list[str] = []
    depth = 0
    in_string = False
    index = 0
    while index < len(args):
        character = args[index]
        if character == "\\":
            buffer.append(args[index : index + 2])
            index += 2
            continue
        if character == "'":
            buffer.append(character)
            if in_string and index + 1 < len(args) and args[index + 1] == "'":
                buffer.append("'")
                index += 2
                continue
            in_string = not in_string
            index += 1
            continue
        if not in_string:
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            elif character == "," and depth == 0:
                parts.append("".join(buffer).strip())
                buffer = []
                index += 1
                continue
        buffer.append(character)
        index += 1
    parts.append("".join(buffer).strip())
    return parts


def escape_regex_literal(literal: str) -> str:
    """Keep regex backslashes after StarRocks strips unknown string escapes."""
    literal = literal.strip()
    if len(literal) < 2 or literal[0] != "'" or literal[-1] != "'":
        return literal
    body = literal[1:-1]
    output: list[str] = []
    index = 0
    while index < len(body):
        if body[index] == "\\" and index + 1 < len(body) and body[index + 1] == "\\":
            output.append("\\\\")
            index += 2
            continue
        if body[index] == "\\":
            output.append("\\\\")
            index += 1
            continue
        output.append(body[index])
        index += 1
    return "'" + "".join(output) + "'"


def rewrite_regexp_functions(sql: str) -> tuple[str, list[str]]:
    notes: list[str] = []

    def rewrite_extract(argument: str) -> str:
        if "regexp_replace(" in argument.lower():
            argument = replace_call(argument, "regexp_replace(", rewrite_replace)
        if "regexp_extract(" in argument.lower():
            argument = replace_call(argument, "regexp_extract(", rewrite_extract)
        parts = split_top_args(argument)
        if len(parts) >= 2:
            parts[1] = escape_regex_literal(parts[1])
        if len(parts) == 2:
            parts.append("1")
            message = "regexp_extract 两参数补上组号 1，对应第一个捕获组"
            if message not in notes:
                notes.append(message)
        return "regexp_extract(" + ", ".join(parts) + ")"

    def rewrite_replace(argument: str) -> str:
        if "regexp_replace(" in argument.lower():
            argument = replace_call(argument, "regexp_replace(", rewrite_replace)
        if "regexp_extract(" in argument.lower():
            argument = replace_call(argument, "regexp_extract(", rewrite_extract)
        parts = split_top_args(argument)
        if len(parts) >= 2:
            parts[1] = escape_regex_literal(parts[1])
            if "正则字面量的反斜杠按 StarRocks 字符串转义加倍" not in notes:
                notes.append("正则字面量的反斜杠按 StarRocks 字符串转义加倍")
        return "regexp_replace(" + ", ".join(parts) + ")"

    if "regexp_extract(" in sql.lower():
        sql = replace_call(sql, "regexp_extract(", rewrite_extract)
    if "regexp_replace(" in sql.lower():
        sql = replace_call(sql, "regexp_replace(", rewrite_replace)
    return sql, notes


def escape_regexp_operator(sql: str) -> str:
    lower = sql.lower()
    output: list[str] = []
    index = 0
    while True:
        found = lower.find("regexp", index)
        if found < 0:
            output.append(sql[index:])
            break
        before = sql[found - 1] if found else ""
        after = lower[found + 6 : found + 8]
        if before.isalnum() or before == "_" or after.startswith("_"):
            output.append(sql[index : found + 6])
            index = found + 6
            continue
        cursor = found + 6
        while cursor < len(sql) and sql[cursor].isspace():
            cursor += 1
        if cursor < len(sql) and sql[cursor] == "'":
            end = cursor + 1
            while end < len(sql):
                if sql[end] == "\\":
                    end += 2
                    continue
                if sql[end] == "'":
                    if end + 1 < len(sql) and sql[end + 1] == "'":
                        end += 2
                        continue
                    end += 1
                    break
                end += 1
            output.append(sql[index:cursor])
            output.append(escape_regex_literal(sql[cursor:end]))
            index = end
            continue
        output.append(sql[index : found + 6])
        index = found + 6
    return "".join(output)


def matching_paren(sql: str, open_index: int) -> int:
    depth = 0
    index = open_index
    in_string = False
    while index < len(sql):
        character = sql[index]
        if character == "\\":
            index += 2
            continue
        if character == "'":
            if in_string and index + 1 < len(sql) and sql[index + 1] == "'":
                index += 2
                continue
            in_string = not in_string
            index += 1
            continue
        if not in_string:
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    return index
        index += 1
    raise ValueError(f"unbalanced paren at {open_index}: {sql[open_index:open_index + 80]!r}")


def replace_call(sql: str, name: str, builder) -> str:
    needle = name.lower()
    lower = sql.lower()
    output: list[str] = []
    index = 0
    while True:
        found = lower.find(needle, index)
        if found < 0:
            output.append(sql[index:])
            break
        open_paren = found + len(needle) - 1
        if sql[open_paren] != "(":
            output.append(sql[index : found + 1])
            index = found + 1
            continue
        close = matching_paren(sql, open_paren)
        output.append(sql[index:found])
        output.append(builder(sql[open_paren + 1 : close]))
        index = close + 1
    return "".join(output)


def replace_format_json_list(sql: str) -> str:
    def builder(argument: str) -> str:
        return f"ifnull(cast(parse_json({argument}) AS ARRAY<JSON>), [])"

    return replace_call(sql, "default.format_json_list(", builder)


def replace_lateral_explode(sql: str) -> str:
    needle = "lateral view explode("
    lower = sql.lower()
    output: list[str] = []
    index = 0
    while True:
        found = lower.find(needle, index)
        if found < 0:
            output.append(sql[index:])
            break
        open_paren = found + len(needle) - 1
        close = matching_paren(sql, open_paren)
        expression = sql[open_paren + 1 : close]
        match = re.match(r"\s+(\w+)\s+AS\s+(\w+)", sql[close + 1 :], flags=re.I)
        if not match:
            raise ValueError(sql[close : close + 80])
        alias, column = match.group(1), match.group(2)
        output.append(sql[index:found])
        output.append(f", unnest({expression}) AS {alias}({column})")
        index = close + 1 + match.end()
    return "".join(output)


def bump_hive_split_index(sql: str) -> str:
    """Hive split()[0] is the first element. StarRocks arrays are 1-based.

    splitByChar is ClickHouse and already 1-based, so it is left alone.
    """
    lower = sql.lower()
    output: list[str] = []
    index = 0
    while True:
        found = lower.find("split(", index)
        if found < 0:
            output.append(sql[index:])
            break
        if lower[max(0, found - 2) : found].endswith("bychar") or sql[found - 1 : found].isalnum():
            output.append(sql[index : found + 1])
            index = found + 1
            continue
        open_paren = found + len("split(") - 1
        close = matching_paren(sql, open_paren)
        call = sql[found : close + 1]
        match = re.match(r"\[(\d+)\]", sql[close + 1 :])
        output.append(sql[index:found])
        if match:
            output.append(f"{call}[{int(match.group(1)) + 1}]")
            index = close + 1 + match.end()
        else:
            output.append(call)
            index = close + 1
    return "".join(output)


def apply_dialect(sql: str) -> tuple[str, list[str]]:
    notes: list[str] = []
    original = sql
    for token, value in PLACEHOLDERS.items():
        if token in sql:
            sql = sql.replace(token, value)
            notes.append(f"占位符 {token} 用本机实验值填入")
    sql = hive_double_quotes(sql)
    if "(?<=user-agent:" in sql:
        sql = sql.replace(
            "regexp_extract(lower(requesthead), '(?<=user-agent: ).*?(?=\\r\\n)', 0)",
            "regexp_extract(lower(requesthead), 'user-agent: ([^\\r\\n]*)', 1)",
        )
        notes.append("RE2 不支持前瞻/后顾，User-Agent 提取改为捕获组")
    unescape = "regexp_replace(str10, '[\\\\]+\"', '\"')"
    if unescape in sql:
        sql = sql.replace(unescape, "regexp_replace(str10, '\\\\\\\\+\"', '\"')")
        notes.append("format_json_list 前面的反斜杠引号替换改为 RE2 能编译的 \\\\+\"")
    if "formatdatetime(" in sql.lower():
        sql = re.sub(
            r"formatDateTime\s*\(\s*toDateTime\s*\(\s*(\w+)\s*\)\s*,\s*'%Y%m%d%H'\s*\)",
            r"date_format(from_unixtime(\1), '%Y%m%d%H')",
            sql,
            flags=re.I,
        )
        notes.append("ClickHouse formatDateTime/toDateTime 改为 date_format(from_unixtime(...))")
    if "array join" in sql.lower():
        sql = re.sub(
            r"ARRAY\s+JOIN\s+JSONExtractArrayRaw\s*\(\s*(\w+)\s*\)\s+AS\s+(\w+)",
            r", unnest(ifnull(cast(parse_json(\1) AS ARRAY<JSON>), [])) AS \2_tbl(\2)",
            sql,
            flags=re.I,
        )
        notes.append("ClickHouse ARRAY JOIN 改为 unnest(parse_json(...))")
    if "format_json_list" in sql.lower():
        sql = replace_format_json_list(sql)
        notes.append("default.format_json_list 改为 parse_json 后 unnest；本机 StarRocks 没有同名函数")
    if "lateral view" in sql.lower():
        sql = replace_lateral_explode(sql)
        notes.append("LATERAL VIEW explode 改为 unnest")
    if re.search(r"collect_set\s*\(\s*distinct\s*\(", sql, flags=re.I):
        sql = re.sub(
            r"collect_set\s*\(\s*distinct\s*\(\s*([^()]+)\s*\)\s*\)",
            r"array_agg(DISTINCT \1)",
            sql,
            flags=re.I,
        )
        notes.append("collect_set(distinct(...)) 改为 array_agg(DISTINCT ...)")
    if re.search(r"\bcollect_set\s*\(", sql, flags=re.I):
        sql = re.sub(r"\bcollect_set\s*\(", "array_agg(DISTINCT ", sql, flags=re.I)
        notes.append("collect_set 改为 array_agg(DISTINCT ...)；StarRocks 3.5 没有 collect_set")
    if re.search(r"\bcollect_list\s*\(", sql, flags=re.I):
        sql = re.sub(r"\bcollect_list\s*\(", "array_agg(", sql, flags=re.I)
        notes.append("collect_list 改为 array_agg")
    if "||" in sql:
        sql = re.sub(
            r"(\w+)\s*\|\|\s*'@'\s*\|\|\s*(\w+)",
            r"concat(\1, '@', \2)",
            sql,
        )
        notes.append("Hive 字符串 || 改为 concat；StarRocks 的 || 不是拼接")
    if "split(" in sql.lower():
        sql = bump_hive_split_index(sql)
        notes.append("Hive 数组下标从 0 起，StarRocks 从 1 起")
    if "splitbychar" in sql.lower():
        sql = re.sub(
            r"splitByChar\s*\(\s*':'\s*,\s*JSONExtractString\s*\(\s*(\w+)\s*,\s*'ip'\s*\)\s*\)",
            r"split(get_json_string(\1, '$.ip'), ':')",
            sql,
            flags=re.I,
        )
        notes.append("ClickHouse splitByChar 下标本来从 1 起，改为 split/get_json_string 后保持原下标")
    if r"'\\.'" in sql:
        sql = sql.replace(r"'\\.'", "'.'")
        notes.append("split 分隔符在 StarRocks 是字面量，正则 '\\.' 改为 '.'")
    if re.search(r"\bsize\s*\(", sql, flags=re.I):
        sql = re.sub(r"\bsize\s*\(", "cardinality(", sql, flags=re.I)
        sql = sql.replace(
            "[cardinality(split(url, '//')) -1]",
            "[cardinality(split(url, '//'))]",
        )
        notes.append("size() 改为 cardinality()；最后一个元素的下标改为长度本身")
    if re.search(r"\bsort_array\s*\(", sql, flags=re.I):
        sql = re.sub(r"\bsort_array\s*\(", "array_sort(", sql, flags=re.I)
        notes.append("sort_array 改为 array_sort")
    sql, regexp_notes = rewrite_regexp_functions(sql)
    notes.extend(regexp_notes)
    masked, strings = mask_strings(sql)
    if "==" in masked:
        masked = masked.replace("==", "=")
        notes.append("== 改为 =")
    if re.search(r"\brlike\b", masked, flags=re.I):
        masked = re.sub(r"\brlike\b", "REGEXP", masked, flags=re.I)
        notes.append("rlike 改为 REGEXP")
    if re.search(r"(?<![`\w])key(?![\w`])", masked):
        masked = re.sub(r"(?<![`\w])key(?![\w`])", "`key`", masked)
        notes.append("key 是保留字，标识符加反引号")
    sql = unmask_strings(masked, strings)
    escaped = escape_regexp_operator(sql)
    if escaped != sql:
        notes.append("REGEXP 模式中的反斜杠按 StarRocks 字符串转义加倍")
        sql = escaped
    sql = re.sub(r"(?<![\w`.])ods_custom_upload_data\b", "`default`.ods_custom_upload_data", sql)
    sql = re.sub(r"(?<![`\w])default\.", "`default`.", sql)
    if "`default`." in sql:
        notes.append("`default` 在 StarRocks 是保留字，库名加反引号")
    if sql.lower().count("bug_id_stat as") >= 2 and "from skyeye_attack_security_log\n   where reqruleid in" in sql.lower():
        notes.append("原文在 log_stat 闭合前重复了 bug_id_stat，括号对不上；这是 all.sql 原文问题")
    if sql == original and not notes:
        notes.append("方言无需改写")
    return sql, notes


def sensitive_spots(sql: str) -> list[str]:
    masked, _strings = mask_strings(sql)
    found: list[str] = []
    patterns = [
        r"\b(?:sum|avg|stddev_pop|stddev)\s*\([^)]{0,80}\)",
        r"\b(?:day|hour|severity|log_num|attack_count|record_count|file_size|deleted_time|expire_time|update_time|inserttimestamp|long1|port|threatclass|threattype|threatsubtype|file_attr|qr|action)\b[^,\n]{0,40}(?:>=|<=|<>|!=|=|>|<)",
        r"(?:>=|<=|<>|!=|=|>|<)\s*-?\d+",
    ]
    for pattern in patterns:
        for match in re.finditer(pattern, masked, flags=re.I):
            text = " ".join(match.group(0).split())
            if text not in found:
                found.append(text)
            if len(found) >= 8:
                return found
    return found


def tables_in(sql: str) -> list[str]:
    masked, _strings = mask_strings(sql)
    names = re.findall(
        r"(?:from|join)\s+(`?[A-Za-z_][\w]*`?(?:\.`?[A-Za-z_][\w]*`?)?)",
        masked,
        flags=re.I,
    )
    ordered: list[str] = []
    for name in names:
        cleaned = name.replace("`", "")
        if cleaned.lower() in {"select", "unnest", "lateral"}:
            continue
        if "." not in cleaned and cleaned.lower() in {
            "rpt", "resp_data", "agg_data", "t", "t2", "s", "a", "b", "log",
            "black_dns", "test_dev", "black_domain", "black_ip", "black_list",
            "tenant_device", "log_base", "day_stat", "log_stat", "ip_stat",
        }:
            continue
        if "." not in cleaned:
            continue
        if cleaned not in ordered:
            ordered.append(cleaned)
    return ordered


def strip_inline_comments(sql: str) -> str:
    masked, strings = mask_strings(sql)
    masked = re.sub(r"--[^\n]*", "", masked)
    return unmask_strings(masked, strings)


def prepare_body(text: str) -> str:
    lines = []
    in_fence = False
    fence_sql = False
    for line in text.splitlines():
        if line.startswith("```"):
            if not in_fence:
                in_fence = True
                fence_sql = line.strip().startswith("```sql")
                if fence_sql:
                    lines.append("/*FENCE*/")
            else:
                if fence_sql:
                    lines.append("/*ENDFENCE*/")
                in_fence = False
                fence_sql = False
            continue
        if in_fence and not fence_sql:
            continue
        if not in_fence and (
            line.startswith("#")
            or line.startswith("|")
            or line.startswith(">")
            or line.lstrip().startswith("- ")
            or line.lstrip().startswith("* ")
        ):
            if line.startswith("# ") and not line.startswith("##"):
                title = line[2:].strip()
                lines.append(f"/*APP {title}*/")
                lines.append(f"/*SECTION {title}*/")
            continue
        if not in_fence and line.strip().startswith("-- App:"):
            lines.append(f"/*APP {line.split('App:', 1)[1].strip()}*/")
            continue
        if not in_fence and line.strip().startswith("--"):
            section = re.match(r"--\s+\d+\)\s+(\S+)", line.strip())
            sub = re.match(r"--\s+----\s+(\S+)", line.strip())
            subjob = re.match(r"--\s+(SUB-JOB\s+\d+/\d+)", line.strip())
            if subjob:
                lines.append(f"/*SECTION {subjob.group(1)}*/")
            elif section:
                lines.append(f"/*SECTION {section.group(1)}*/")
            elif sub:
                lines.append(f"/*SECTION {sub.group(1)}*/")
            continue
        lines.append(line)
    return "\n".join(lines)


def extract_statements(text: str) -> list[dict[str, str]]:
    body = prepare_body(text)
    statements: list[dict[str, str]] = []
    app = ""
    section = ""
    buffer: list[str] = []
    in_single = False
    in_double = False
    index = 0

    def flush() -> None:
        sql = strip_inline_comments("".join(buffer)).strip()
        buffer.clear()
        if sql:
            statements.append({"app": app, "section": section, "sql": sql})

    while index < len(body):
        if body.startswith("/*APP ", index):
            end = body.find("*/", index)
            app = body[index + 6 : end].strip()
            section = ""
            index = end + 2
            continue
        if body.startswith("/*SECTION ", index):
            end = body.find("*/", index)
            section = body[index + 10 : end].strip()
            index = end + 2
            continue
        if body.startswith("/*FENCE*/", index):
            index += len("/*FENCE*/")
            continue
        if body.startswith("/*ENDFENCE*/", index):
            flush()
            index += len("/*ENDFENCE*/")
            continue
        character = body[index]
        if character == "\\" and (in_single or in_double):
            buffer.append(body[index : index + 2])
            index += 2
            continue
        if character == "'" and not in_double:
            buffer.append(character)
            if in_single and index + 1 < len(body) and body[index + 1] == "'":
                buffer.append("'")
                index += 2
                continue
            in_single = not in_single
            index += 1
            continue
        if character == '"' and not in_single:
            buffer.append(character)
            in_double = not in_double
            index += 1
            continue
        if character == ";" and not in_single and not in_double:
            flush()
            index += 1
            continue
        buffer.append(character)
        index += 1
    flush()
    return statements


def render(statements: list[dict[str, object]]) -> str:
    table_names: list[str] = []
    for item in statements:
        for name in item["tables"]:
            if name not in table_names:
                table_names.append(name)
    header = [
        "-- 旧平台 SQL 转 StarRocks 草稿",
        "-- 来源：/workspace/all.sql",
        "-- 当次没有给出新平台库表名。下面每张表都保留原名，并标明「缺少新平台表名」。",
        "-- 这不是生产语句，也没有在生产 StarRocks 执行。",
        "-- DEC-009：目标字段按 VARCHAR 落地。本次没有字段实际编码，数值比较、聚合和时间范围只标出位置，不猜 CAST。",
        "-- 本机实验表仍是 ACT-034 的 INT/BIGINT/VARCHAR，所以下面语句按实验库物理类型执行。",
        "--",
        "-- 本机占位符（来自 all.sql 注释和 lab/build_bulk_data.py，不是生产参数）：",
        f"--   {{AGO_OID}} = {AGO_OID}",
        f"--   {{DAYS}} = 实验库已有分区，不是 2021-12 至 2026-12 的全部周三：{LAB_DAYS}",
        "--   {LAST_HOUR}/{NOW_HOUR} = 2026100200 / 2026100201（handle_info_log 的 inserttimestamp 都落在这一小时）",
        "--   {TENANT_IDS} = 'tenantA','tenantB','tenantC'",
        "--   {START_TIME}/{END_TIME} = 20260915 / 20261001",
        "--   {LAST_TS}/{END_TS} = 1790901000 / 1790901600",
        f"--   {{RUN_TIME_MS}} = {RUN_TIME_MS}",
        f"--   {{SKYEYE_UPDATE_MS}} = {SKYEYE_UPDATE_MS}",
        "--   ${day}/${hour} = 20261001 / 0",
        "--",
        "-- 旧表到新表对照",
    ]
    for name in table_names:
        header.append(f"--   {name}    缺少新平台表名")
    header.append("")
    blocks = ["\n".join(header)]
    for number, item in enumerate(statements, start=1):
        comment = [
            f"-- 语句 {number}",
            f"-- 应用：{item['app'] or '未标注'}",
        ]
        if item["section"]:
            comment.append(f"-- 分段：{item['section']}")
        comment.append("-- 方言：" + "；".join(item["notes"]))
        if item["tables"]:
            comment.append("-- 表：" + "，".join(f"{name}（缺少新平台表名）" for name in item["tables"]))
        if item["sensitive"]:
            comment.append("-- 字段编码未给出，DEC-009 需显式转换：" + "；".join(item["sensitive"]))
        else:
            comment.append("-- 字段编码未给出：本句没有扫到数字比较或数值聚合")
        blocks.append("\n".join(comment) + "\n" + str(item["sql"]).rstrip() + ";\n")
    return "\n".join(blocks)


def convert(text: str) -> list[dict[str, object]]:
    converted = []
    for item in extract_statements(text):
        sql, notes = apply_dialect(item["sql"])
        converted.append({
            "app": item["app"],
            "section": item["section"],
            "sql": sql.strip(),
            "notes": notes,
            "tables": tables_in(sql),
            "sensitive": sensitive_spots(sql),
        })
    return converted


def run_lab(statements: list[dict[str, object]]) -> list[dict[str, object]]:
    connection = pymysql.connect(
        host="127.0.0.1",
        port=9030,
        user="root",
        password="",
        autocommit=True,
        read_timeout=180,
        write_timeout=180,
    )
    cursor = connection.cursor()
    cursor.execute("SET query_timeout = 120")
    results = []
    for number, item in enumerate(statements, start=1):
        sql = str(item["sql"])
        wrapped = f"SELECT COUNT(*) FROM (\n{sql}\n) lab_wrapped"
        try:
            cursor.execute(wrapped)
            count = cursor.fetchone()[0]
            status = "ok"
            error = ""
        except Exception as exc:
            count = ""
            error = " ".join(str(exc).split())[:500]
            source_break = "原文在 log_stat 闭合前重复了 bug_id_stat" in "；".join(item["notes"])
            status = "source_syntax" if source_break else "error"
        results.append({
            "n": number,
            "app": item["app"],
            "section": item["section"],
            "status": status,
            "rows": count,
            "error": error,
        })
        print(f"{number:02d} {status:5} rows={count!s:>8} {item['app'][:48]} {item['section'][:40]} {error[:160]}", flush=True)
    return results


def write_results(results: list[dict[str, object]], path: Path) -> None:
    lines = ["n\tstatus\trows\tapp\tsection\terror"]
    for item in results:
        lines.append(
            "\t".join([
                str(item["n"]),
                str(item["status"]),
                str(item["rows"]),
                str(item["app"]).replace("\t", " "),
                str(item["section"]).replace("\t", " "),
                str(item["error"]).replace("\t", " "),
            ])
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def self_check(text: str) -> None:
    statements = convert(text)
    joined = "\n".join(str(item["sql"]) for item in statements)
    assert "(?<=user-agent:" not in joined
    assert "formatDateTime" not in joined
    assert "JSONExtract" not in joined
    assert "LATERAL VIEW" not in joined.upper()
    assert "collect_set" not in joined.lower()
    assert "collect_list" not in joined.lower()
    assert "format_json_list" not in joined.lower()
    assert "splitByChar" not in joined
    assert "==" not in mask_strings(joined)[0]
    assert re.search(r"\brlike\b", mask_strings(joined)[0], flags=re.I) is None
    assert "split(ip, '.')[1]" in joined
    assert "split(ip, '.')[2]" in joined
    assert "split(ip, '.')[3]" in joined
    assert "[cardinality(split(url, '//'))]" in joined
    assert "`default`.log_audit_source" in joined
    assert AGO_OID in joined
    assert "||" not in mask_strings(joined)[0]
    assert "`key`" in joined
    assert "array_sort(" in joined
    assert "regexp_extract(dstip,'^((0\\\\.0\\\\.0\\\\.0)" in joined or "regexp_extract(dstip, '^((0\\\\.0\\\\.0\\\\.0)" in joined
    assert "split(get_json_string(element, '$.ip'), ':')[1] AS ip_address" in joined
    assert "split(get_json_string(element, '$.ip'), ':')[2] AS port" in joined
    assert "split(get_json_string(element, '$.ip'), ':')[3]" not in joined
    assert "'^\\\\['" in joined
    assert any("原文在 log_stat 闭合前重复了 bug_id_stat" in "；".join(item["notes"]) for item in statements)
    assert all(not item["sql"].lstrip().startswith(",") for item in statements)
    assert not any(item["sql"].lstrip().startswith("- ") for item in statements)
    print(f"self-check ok, {len(statements)} statements")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    text = SOURCE.read_text(encoding="utf-8")
    self_check(text)
    statements = convert(text)
    SQL_OUT.parent.mkdir(parents=True, exist_ok=True)
    SQL_OUT.write_text(render(statements), encoding="utf-8")
    print(f"wrote {SQL_OUT}")
    if args.run:
        results = run_lab(statements)
        write_results(results, RESULT_OUT)
        failed = [item for item in results if item["status"] == "error"]
        source = [item for item in results if item["status"] == "source_syntax"]
        print(f"ran {len(results)} failed {len(failed)} source_syntax {len(source)} -> {RESULT_OUT}")
        if failed:
            sys.exit(1)


if __name__ == "__main__":
    main()
