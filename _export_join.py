# -*- coding: utf-8 -*-
import json
import sys

sys.stdout.reconfigure(encoding="utf-8")
with open(r"d:\project\bigdata\_yarn_join.json", encoding="utf-8") as f:
    d = json.load(f)


def srcs(j):
    skip = {"深二大数据平台", "深二大数据平台（？没有ngaf库了"}
    return "；".join(s for s in j.get("sources", []) if s and s not in skip)


def outs(j):
    return "；".join(j.get("outputs", []) or ["-"])


order_layer = {"原始层": 1, "中间层": 2, "业务层": 3, "": 4}
rows = [j for j in d["joined"] if j["key"] not in ("汇总",)]
rows.sort(key=lambda j: (order_layer.get(j["src_layer"] or "", 4), j["yarn_status"] or "z", j["key"]))

out_path = r"d:\project\bigdata\_join_tables.md"
lines = []
for layer in ["原始层", "中间层", "业务层", ""]:
    title = layer or "无层级（仅云脑CSV）"
    lines.append(f"\n## {title}\n")
    lines.append(
        "| 服务 | 云脑状态 | 来源表状态 | 优先级 | 负责人 | 业务分类 | 计算 | 作用 | 主要来源 | 输出 | 依赖标记 |"
    )
    lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
    for j in rows:
        if (j["src_layer"] or "") != layer:
            continue
        flags = []
        if j.get("read_old_dwb") and j.get("read_new_dwb"):
            flags.append("新旧DWB")
        elif j.get("read_old_dwb"):
            flags.append("旧DWB")
        elif j.get("read_new_dwb"):
            flags.append("新DWB")
        if j.get("read_ngaf"):
            flags.append("ngaf已无库")
        if j.get("read_sodl_ods"):
            flags.append("sodl ODS")
        if j.get("read_old_dwb_ip"):
            flags.append("读旧IP宽表")
        if j.get("read_new_dwb_url") and j["key"] != "sodl_dwb_info":
            flags.append("读新URL宽表")
        def cell(x, n=80):
            return (x or "-").replace("|", "/").replace("\n", " ")[:n]
        lines.append(
            "|".join(
                [
                    "",
                    j["key"],
                    j["yarn_status"] or "-",
                    j["src_status"] or "-",
                    j["yarn_prio"] or "-",
                    j["yarn_owner"] or "-",
                    cell(j["yarn_cat"], 24),
                    j["yarn_ttype"] or "-",
                    cell(j["yarn_purpose"], 28),
                    cell(srcs(j), 90),
                    cell(outs(j), 60),
                    ",".join(flags) or "-",
                    "",
                ]
            )
        )

lines.append("\n## 仅云脑CSV、来源表无记录\n")
for j in d["joined"]:
    if j["in_yarn"] and not j["in_src"]:
        lines.append(
            f"- `{j['key']}` 云脑状态={j['yarn_status']} 作用={j['yarn_purpose']} 备注={j['yarn_remark'][:80]}"
        )

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("wrote", out_path, "lines", len(lines))
