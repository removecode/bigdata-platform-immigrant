# 生产侧真实样例（脱敏引用）

本目录存放**用户提供的** StarRocks / 数据湖表样例行，供 `lab/build_bulk_data.py`、`lab/run_migratable.py` 等造数时对齐**列名、空值形态、时间字段格式、典型取值**，不表示仓库已接入生产库。

## 使用约定

1. **只追加、不删改历史样例**；新批次用子目录或文件名带日期，例如 `sodl.network_security_log/samples-2026-11-03.tsv`。
2. 样例中的 ID、IP、域名等视为**已脱敏或低敏**引用；勿再粘贴生产密码、密钥。
3. 造数脚本应优先读本目录 `schema-columns.txt` 与 `samples-*.tsv`，而不是凭空填 `shopN.brandXX.com` 一类占位域名（除非任务明确允许）。
4. **缺什么就标什么**：当前没有 `csc.ods_csc_log_audit` / `str10` + `format_json_list` 的真实行；热门威胁 audit 分支仍依赖后续补样。

## 已收录表

| 表 | 列清单 | 样例行 | 来源 |
| --- | --- | --- | --- |
| `sodl.dns_log` | [schema-columns.txt](./sodl.dns_log/schema-columns.txt) | [samples.tsv](./sodl.dns_log/samples.tsv) | 用户 2026-11-03 聊天粘贴 |
| `sodl.network_security_log` | [schema-columns.txt](./sodl.network_security_log/schema-columns.txt) | [samples-key-fields.tsv](./sodl.network_security_log/samples-key-fields.tsv) | 同上（宽表仅保留造数/ SQL 常用键列） |
| `sodl.sip_iocstat_log` | [schema-columns.txt](./sodl.sip_iocstat_log/schema-columns.txt) | [samples.tsv](./sodl.sip_iocstat_log/samples.tsv) | 同上 |

## 与迁移规则的对照

- `manage` / `deviceid` 同时出现在宽表头中；StarRocks 转换规则 **DEC-021** 写查询侧用 `deviceId AS manage` 或 `deviceId AS devid`（见 `docs/StarRocks语句转换规则.md`）。样例里两列均有值，造数时不要只造已废弃的 `manage` 单列。
- 分区/过滤常用 **`insertdate`**（样例为 `2026-10-05`、`2026-10-28`、`2026-11-02` 等 **DATE 字符串**）与 **`inserttimestamp`**（样例为 **10 位秒级**整数，如 `1791216303`）。与 **DEC-016** 一致；未用 `day`/`hour` 整数分区列。
- `sodl.*` 无 `log_num`（**DEC-020**）；`sip_iocstat_log` 用 **`record_count`**。

## `default.format_json_list` 与本目录的关系

- **不是**与 `parse_json(str10)` + `unnest` 同义。Hive/生产 UDF 负责把 **audit 的 `str10` 字符串**拆成 JSON 元素数组；`str10` 常含多层转义，与裸 JSON 数组不同。
- 决策 **DEC-023**：转换时 **保留** `` `default`.format_json_list(...) ``，不擅自改成内置函数（`docs/StarRocks语句转换规则.md` L97–103）。
- **ACT-038** 曾临时改为 `parse_json` 以便本机无 UDF 时跑通；**ACT-045 / ACT-046** 已改回 UDF，并在本机 StarRocks 注册孪生函数（`lab/udf-sr/`）。
- 本目录**尚未**收录 `str10` 真实样例；补样后请增加 `csc.ods_csc_log_audit/` 或 `audit-str10/` 子目录。

## 追踪

- 目录建立：**ACT-073**（`docs/迁移事项进度与决策追踪.md`）。
- 本机 StarRocks 导入与 smoke：**ACT-074**；脚本 `load_lab_starrocks.py`，结果 `smoke-results.tsv`。

## 本机用真实样例查询（ACT-074）

```bash
# 需 lab StarRocks（lab/install.sh && lab/start.sh）
python3 reference/real-data/load_lab_starrocks.py
```

- 数据写入库 **`real_ref`**（与 `sodl.*` 生产表分离，列 subset + VARCHAR）。
- **不是**把宽表全字段灌进 StarRocks；也**未**跑完整 topthreat / audit SQL（无 str10 样例）。
