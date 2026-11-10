# topthreat domain：用户 SQL vs 助手 SQL（本机 StarRocks 对照）

**依据**：`scripts/compare_topthreat_user_vs_assistant.py`；数据 `reference/real-data/sodl.*`（用户 2026-11-03）+ 按 **ACT-064** 构造的 audit `str10`（含 `\"` 转义；**不是**现网 audit 全量样本，`audit-str10/TODO.md` 仍缺）。

**环境**：StarRocks 3.5.21；`SET time_zone = '+08:00'`；窗口 `log_time` / `inserttimestamp`：`2026-10-05 23:50:00` – `2026-10-06 00:10:00`（覆盖真实样例 `inserttimestamp=1791216303`）。

**结果 TSV**：`outputs/topthreat-user-vs-assistant-compare.tsv`

## 分支 1（audit / str10）

| 对比项 | 用户 `json_each(get_json_string(...,'$[*]'))` | 助手 `unnest(format_json_list(...))` |
|--------|-----------------------------------------------|--------------------------------------|
| 正规 **JSON 数组**（2 元素，`attr=0`） | 2 条 domain | 2 条（一致） |
| **单对象**（非 `[...]`） | **0 条** | **1 条** `single-object.example` |
| 数组末尾 **`~]`**（filter-layout 曾见形态） | **0 条** | **1 条** `tilde-bracket.example` |
| `attr=1` 应被过滤 | 0 | 0 |

**结论**：在「转义后数组」上两者一致；**单对象 / `~]`** 上用户写法会少行，助手 UDF（Hive 孪生）会多出元素。现网 audit 是否大量出现这两种形态，**材料未记载**（需补 `reference/real-data/audit-str10/`）。

## 分支 2（`network_security_log` / url → domain）

**时间条件**（与语义无关的差异）：

- 用户：`inserttimestamp` 范围 → 命中 7 行（含 2 行真实样例 **url 为空** → domain 为 NULL）。
- 助手 DEC-016：`insertdate` + `hour(from_unixtime(...))=23` → **0 行**（同一样例在 +8 时 `hour=0`，与 `hour=23` 不一致）。

**在相同 `inserttimestamp` 窗口下**（只比域名解析，共 7 行）：

| url 样例 | 用户 `CASE + split_part` | 助手 `split(...)[cardinality]` |
|----------|--------------------------|--------------------------------|
| `http://.../path` | `www.glashuirglurhtgqoer.com` | 同左 |
| `http://.../redir?u=http://nested.evil.com/x` | `www.glashuirglurhtgqoer.com` | **`nested.evil.com`** |
| `//orphan-host.example/x` | **空串**（外层 `domain != ''` 丢弃） | **`orphan-host.example`** |
| `a.com/x//y` | **`a.com`** | **`y`** |
| `www.pure-domain.example/foo` | `www.pure-domain.example` | 同左 |

## 分支 3（`sip_iocstat_log` / domain ioc）

相同时间窗口下 **1 行一致**（构造的 `evil-domain-from-ioc.example`）。真实 TSV 两条为 **ioc_type=ip**，未参与 domain 分支。

## 整条 `domain_stat`（三分支 UNION 后聚合）

**不相等**：差异来自分支 1 多 2 域名 + 分支 2 域名解析 3 处 + 分支 2 空 url 的 NULL 行计数方式。

## file / url 语句（未单独跑全文）

`file_stat` / `url_stat` 的 audit 子查询与 domain **同一套** `json_each` vs `format_json_list`；**推断** file/url 与 domain 分支 1 结论相同。url 的 sodl 分支与 domain 分支 2 相同。

## 复现

```bash
bash lab/udf-sr/build.sh   # 需 FE enable_udf
python3 scripts/compare_topthreat_user_vs_assistant.py
```
