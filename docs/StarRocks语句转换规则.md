# StarRocks 语句转换规则

转换旧平台 SQL 时先读本文件，并替换其中每一条已确认规则。本文件是库、表、路径和字段的对照。方言改写仍按 `AGENTS.md` 与当次语句处理。

未出现在本文件、当次消息也没有给出新名称的对象，保留原名。库表标明「缺少新平台表名」。字段标明「缺少新平台字段名」。不按命名习惯补名。

`docs/迁移事项进度与决策追踪.md` 的 DEC-009 继续有效：编码未给出时，标出数值比较、时间范围、排序、聚合和关联，不自行加 `CAST`。转换结果是语句草稿，不表示已在当前 StarRocks 执行，也不表示可以切流。

## 库与表

确认日期：2026-10-16。决策：DEC-014。来源：用户给出的当前 StarRocks 截图。截图中的库是 `csc`、`sodl`、`ti`。

| 旧平台名 | 当前 StarRocks 名 | 依据 |
| --- | --- | --- |
| `default.log_audit_source` | `csc.ods_csc_log_audit` | 截图中 `csc` 只有这张表。`log/DATA_FLOW.md` L101、`log/LOG_COMPRESS_AUDIT_DETAIL.md` L28–39 写明它由 `default.log_audit_source` 写入 |
| `csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync` | `ti.ods_ti_db_intelligence_tb_ip_reputation_sync` | 截图表名。Mongo 来源 `db_intelligence.tb_ip_reputation` 见 `docs/datax-server-SZ-MongoDB到Hive同步任务映射.md` L40 |
| `csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync` | `ti.ods_ti_db_domain_intelligence_tb_domain_reputation_sync` | 截图表名。Mongo 来源 `db_domain_intelligence.tb_domain_reputation` 见同一映射 L38 |
| `csc.ods_csc_db_url_intelligence_tb_url_reputation_sync` | `ti.ods_ti_db_url_intelligence_tb_url_reputation_sync` | 截图表名。旧名见 `log/DATA_FLOW.md` L109，映射见 L39 |
| `sri.ods_sri_ti_tags` | `ti.ods_ti_db_scia_analysis_tb_syn_ti_tags_sync` | 截图表名含 `scia_analysis` 与 `syn_ti_tags`。`syn_ti_tags_mongo2hive.py` 的来源是 `SCIA_ANALYSIS` / `SynTiTags`，Hive 路径 `/hive/ods/sri/ti_tags`，见映射 L69 |
| `sri.ods_sri_hashinfo` | `ti.ods_ti_db_fc_hashinfo_tb_fc_hashinfo_sync` | 截图中的 hashinfo 表。旧表材料来自 Mongo 文件云查。两边字符串不完全相同 |

`sodl` 库在截图中存在，表没有展开。`sodl.*` 保留原名，并标明「截图未列出 sodl 表」。

截图还有 `ti.ads_ti_ip_heat_produce`。材料没有写明它对应哪张旧表，不把它填进旧 SQL。

## 字段

确认日期：2026-10-16。决策：DEC-015。来源：用户说明「log_app_id 要转为 app_id」。

| 旧字段 | 当前 StarRocks 字段 | 替换范围 |
| --- | --- | --- |
| `log_app_id` | `app_id` | 标识符。已经写成 `app_id` 的列保持不动。字符串字面量里的文本不替换 |

旧压缩 SQL 同时选出列 `log_app_id`，并把 `log_app_id AS app_id` 用作分区，见 `log/LOG_COMPRESS_AUDIT_DETAIL.md` L28–33 与 `docs/Hive到StarRocks任务分类与迁移边界.md` L124。这条规则按用户确认执行。截图没有字段清单，本表以外的列仍不能写成已经核对过的物理列。

## 不在本文件中的对象

以下名称在材料里出现过，当前没有用户确认的新名称，转换时保留原名并标明「缺少新平台表名」：

- `default.dwb_*`
- `sodl.dwb_sodl_*`
- `default.log_stats_source`
- `csc.ods_csc_log_stats`
- `business.*`

`module_id`、`str1`–`str10`、`long1`、`hour`、`day` 只在旧压缩 SQL 的选择列表中出现。它们不在本文件的字段表里，语句中保留原名，并标明「缺少新平台字段名」。

## 本机实验草稿

`outputs/all-starrocks.sql` 是本机实验库草稿。实验表的列名仍是 `log_app_id`。该文件不按本规则改名。交给用户的 StarRocks 语句按本文件替换。
