# 用户 audit 真实样例验证摘要（2026-11-10）

依据：`reference/real-data/audit-str10/` 下用户贴回数据；本机 StarRocks 3.5.21 + `regexp_replace(str10,'\\\\+"','"')`（与 `outputs/topthreat-hot-stat-starrocks.sql` 一致）。

## 已收录

| 文件 | 内容 |
|------|------|
| `samples-domain-2026-11-01.tsv` | @pull 1 共 4 行（原 row5 `dom` 截断未收） |
| `samples-cloudcheck-extra-2026-11-01.tsv` | cloudcheck 追加 2 行 |
| `samples-file-2026-11-01-meta.tsv` | @pull 2 元数据 4 行（row5 截断） |
| `samples-file-2026-11-01-str10.jsonl` | 仅 row4 完整 str10（371 字节）；row1–3 过大未整段入库 |

## 黑域名 SQL（domain 分支 1）

| 发现 | 说明 |
|------|------|
| **json_each vs UDF** | 在正确 `regexp_replace` 后，**json_each(`$[*]`) 与 format_json_list 元素数一致**（样例：14 元素 EDR 行均为 14）。 |
| **JSON 形态** | `domain-proxy-svc`：元素含 **`$.domain` + `$.threat.*`**，**无 `$.info.attr`**。 |
| **cloudcheck** | 元素为 **`$.url`**（及 `$.category`），**无 `$.domain`**。 |
| **topthreat 过滤** | Hive/SR 草稿条件 `get_json_object(...,'$.info.attr')='0'` → 上述 4 行 **命中 0**。去掉 attr 过滤后 **可解析 domain 15 条**（14+1）。 |
| **与用户版 SQL** | 拆法在数组样例上一致；差异在 **字段路径与过滤条件**，不在 json_each/UDF。 |

## 黑文件 SQL（file 分支）

| 发现 | 说明 |
|------|------|
| **JSON 形态** | 元素含 `filemd5`、`info.attr`（样例中为 **数字 1 或 2**，非字符串 `"0"`）。 |
| **row1 肉眼** | 粘贴可见元素均为 **`"attr":2`**（上传批次）。 |
| **row4 本机** | 2 元素，`get_json_object(...,'$.info.attr')` 返回 **`'1'`**（字符串）。 |
| **topthreat 过滤** | `$.info.attr = '0'` 与 `attr = '0'`（外层）→ **0 行**；**不设 attr 过滤** → 2 行 md5。 |
| **row1–3 规模** | str10_len **7959 / 18501 / 18477**，单审计行多 md5，展开 CPU/内存风险高。 |

## 与用户 SQL / 助手 SQL 是否「一致」

- **一致**：`regexp_replace` 四反斜杠、数组上 **json_each 与 UDF 元素数**（本机已测）。
- **不一致（语义）**：现网 str10 **不是** 旧 Hive 文档里的 `info.attr='0'` + `domain` 形态；**domain-proxy** 与 **cloudcheck** 结构不同，需业务确认过滤规则是否已变。
- **不一致（时间）**：用户 SQL 用 `year/month/day+log_time`；助手草稿用 `day+hour`（DEC-016 未覆盖 audit 的 `log_time`）。

## 下一步（需用户）

1. 补全 **row5** 截断行。  
2. 确认 Hive 现网 **黑域名 / 黑文件** 是否仍用 `info.attr='0'`，还是已改为 `threat.reputation` / `attr` 数值枚举。  
3. 可选：`@pull 3` url 分支、`@pull 5` 元素计数贴回，用于 url/file 全量对账。
