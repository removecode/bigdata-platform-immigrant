#!/usr/bin/env python3
"""Static cost signals for outputs/migratable-tasks-starrocks.sql (no execution).

Counts structural features that usually drive StarRocks CPU / scan cost. The score is a
heuristic for ranking review order, not a measurement. Compare with Hive history
(917 CSV ARA-MB-seconds) and with real EXPLAIN ANALYZE / slow_query on the target cluster.
"""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SQL_PATH = ROOT / "outputs" / "migratable-tasks-starrocks.sql"
OUT_PATH = ROOT / "outputs" / "migratable-17-static-cost-signals.tsv"

STMT_RE = re.compile(r"^-- @stmt (\d+) \| ([^|]+) \| (.+)$", re.M)

# 16 (WEAK_PASSWORD_SQL): no matching subtask row in 917 CSV; 17 (WIKI) = attack_ip_wiki_related_analysis.
ARA_MB_S = {
    1: 4174666032, 2: 114652903, 3: None, 4: 81530103, 5: 92080199, 6: 24667215,
    7: 60947554, 8: 206765545, 9: 509969502, 10: 59697052, 11: 4204875, 12: 7890698,
    13: 13078388, 14: 14022017, 15: 1660490, 16: None, 17: 165305676,
}


def split_statements(text: str) -> list[tuple[int, str, str, str]]:
    marks = list(STMT_RE.finditer(text))
    out = []
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        body = text[m.end():end]
        sql = "\n".join(l for l in body.splitlines() if not l.strip().startswith("--"))
        out.append((int(m.group(1)), m.group(2).strip(), m.group(3).strip(), sql))
    return out


def day_span(sql: str) -> int:
    m = re.search(r"day\s+BETWEEN\s+(\d{8})\s+AND\s+(\d{8})", sql, re.I)
    if m:
        return int(m.group(2)) - int(m.group(1)) + 1
    m = re.search(r"insertdate\s+BETWEEN\s+'(\d{4})-(\d\d)-(\d\d)'\s+AND\s+'(\d{4})-(\d\d)-(\d\d)'", sql, re.I)
    if m:
        from datetime import date
        a = date(*map(int, m.group(1, 2, 3)))
        b = date(*map(int, m.group(4, 5, 6)))
        return (b - a).days + 1
    return 1


def signals(sql: str) -> dict:
    low = sql.lower()
    tables = set(re.findall(r"\b(?:from|join)\s+((?:`?\w+`?\.)?`?\w+`?(?:\.\w+)?)", low))
    tables = {t for t in tables if "." in t and not t.startswith("unnest")}
    return {
        "tables": len(tables),
        "table_names": ",".join(sorted(tables)),
        "day_span": day_span(sql),
        "unnest": low.count("unnest("),
        "get_json_object": low.count("get_json_object("),
        "udf_format_json_list": low.count("format_json_list("),
        "regex": len(re.findall(r"regexp_extract\(|regexp_replace\(|\bregexp\b|\brlike\b", low)),
        "union_all": low.count("union all"),
        "count_distinct": len(re.findall(r"count\(\s*distinct", low)),
        "array_agg": low.count("array_agg("),
        "select_star": 1 if re.search(r"select\s+(?:[\w.]+\s*,\s*)?\*", low) or ", *" in low else 0,
        "not_exists": low.count("not exists"),
        "order_by": low.count("order by"),
        "limit": 1 if re.search(r"\blimit\s+\d+", low) else 0,
    }


def score(s: dict) -> int:
    return (
        s["day_span"] * 10
        + s["unnest"] * 15
        + s["get_json_object"] * 8
        + s["udf_format_json_list"] * 8
        + s["regex"] * 3
        + s["union_all"] * 5
        + s["count_distinct"] * 4
        + s["array_agg"] * 2
        + s["select_star"] * 6
        + s["not_exists"] * 4
        + max(s["tables"] - 1, 0) * 3
    )


def main() -> int:
    text = SQL_PATH.read_text(encoding="utf-8")
    rows = []
    for sid, task, seg, sql in split_statements(text):
        s = signals(sql)
        s.update(id=sid, task=task, segment=seg, score=score(s), ara_mb_s=ARA_MB_S.get(sid))
        rows.append(s)
    rows.sort(key=lambda r: -r["score"])
    cols = ["id", "task", "segment", "score", "ara_mb_s", "day_span", "unnest", "get_json_object",
            "udf_format_json_list", "regex", "union_all", "count_distinct", "array_agg",
            "select_star", "not_exists", "tables", "table_names"]
    with OUT_PATH.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(cols)
        for r in rows:
            w.writerow([r[c] if r[c] is not None else "" for c in cols])
    for r in rows:
        print("%2d %-30s %-34s score=%3d ara=%s span=%d unnest=%d json=%d regex=%d union=%d"
              % (r["id"], r["task"], r["segment"], r["score"], r["ara_mb_s"], r["day_span"],
                 r["unnest"], r["get_json_object"], r["regex"], r["union_all"]))
    print("wrote", OUT_PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
