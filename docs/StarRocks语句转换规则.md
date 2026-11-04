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

## sodl 表的日期和小时

确认日期：2026-10-16。决策：DEC-016。来源：用户说明 `sodl` 后的表没有 `day` 和 `hour`，`day` 用 `insertdate = '2026-10-01'` 代替，`hour` 用 `inserttimestamp`。

只改 `sodl.*`。`csc.ods_csc_log_audit` 不在这条里，它的 `day`、`hour` 仍按旧名保留，并标明「缺少新平台字段名」。

| 旧写法 | 当前写法 | 说明 |
| --- | --- | --- |
| `day = 20261001` | `insertdate = '2026-10-01'` | 用户给出的具体替换。八位 `YYYYMMDD` 写成 `'YYYY-MM-DD'` |
| `hour = 0` | `hour(from_unixtime(inserttimestamp)) = 0` | 小时取 `inserttimestamp`。不用 `uploadtimestamp`，不用 `recordtimestamp` |

用户给出的三个时间戳：

| 字段 | 含义 | 是否用来代替 `hour` |
| --- | --- | --- |
| `uploadtimestamp` | 日志上传时间戳，设备发出的时间 | 不用。口径偏客户端上报 |
| `inserttimestamp` | 日志入库时间戳，数据湖收到的时间 | 用这个 |
| `recordtimestamp` | 日志记录时间戳，事件发生的时间 | 不用。口径偏事件实际发生 |

查询端使用 MySQLdb / SQLAlchemy 时，SQL 文本里的 `%` 会被当成 Python 格式化占位符。`date_format(..., '%H')` 会报 `not enough arguments for format string`。交给用户的语句不写这种格式串，小时用 `hour()`。见 DEC-017。

**推断：** `from_unixtime(inserttimestamp)` 按秒级 Unix 时间解释。依据是 `all.sql` L274 对 `sodl.handle_info_log` 使用 `toDateTime(insertTimestamp)`，以及本机实验列 `inserttimestamp:BIGINT`（`lab/build_bulk_data.py` 对 `handle_info_log`、`operation_rdp_event_log`）。用户没有给出 `sodl.network_security_log`、`sodl.sip_iocstat_log` 上 `inserttimestamp` 的类型。若实际是毫秒或字符串，这个小时表达式要改。`from_unixtime` 使用 StarRocks 会话时区，旧 `hour` 的时区材料没有写明。按 DEC-009，这里不另加 `CAST`。

## sodl 表的 log_num

确认日期：2026-10-16。决策：DEC-019、DEC-020。来源：用户说明「这个要改为count(1)，sodl现在没有这个字段log_num」。此前黑域名语句已报 `Column 'log_num' cannot be resolved`。

`sodl.*` 的语句不再写 `log_num`。原来的 `sum(log_num)` 改为 `count(1)`。

旧字段清单里 `sodl.network_security_log` 仍有 `log_num`，见 `outputs/01a0f033-77ef-7e82-ab87-1ada9098deb2/build_sodl_fields.mjs`。当前 StarRocks 以用户说明为准，不用那份旧清单。`sodl.sip_iocstat_log` 的 `record_count` 不是 `log_num`，继续保留。

## sodl 表的 manage

确认日期：2026-10-16。决策：DEC-021。来源：用户说明「deviceId as manage」。

`sodl.*` 不再写列 `manage`。当前列名是 `deviceId`。语句里写 `deviceId AS manage`。原语句已经把 `manage` 取成 `devid` 时，写成 `deviceId AS devid`，`GROUP BY` 改为 `deviceId`。

## 规划时间

确认日期：2026-10-16。决策：DEC-022。来源：用户执行黑域名语句，StarRocks 报 `planner use long time 3072 ms in logical phase`，并提示增大 `new_planner_optimize_timeout`。

本机该变量默认值是 `3000` 毫秒。超过这个时间，语句在执行前就失败。复杂语句，以及 Hive 外表取元数据较慢时，会踩到这个上限。

交给用户的这类语句在最外层 `SELECT` 后写：

```sql
/*+ SET_VAR(new_planner_optimize_timeout = 60000) */
```

这是一条语句里的优化器提示，不依赖会话里先执行 `SET`。不要把提示拆成第二条语句。

## 查询超时

确认日期：2026-10-17。决策：DEC-024。来源：用户说明 filter-layout-ip-seg-stat-prc 的语句执行超时，要加 `SELECT /*+ SET_VAR(query_timeout=3600) */` 这类写法。

只针对用户点名超时的语句。该语句的提示写成 `/*+ SET_VAR(new_planner_optimize_timeout = 60000, query_timeout = 3600) */`，两个变量放在同一个提示里。其他语句出现 `Query reached its timeout` 时，再按这个写法加，不预先给所有语句加。

## 旧 SQL 来源不一致时

`all.sql` 与 917 梳理 CSV 对同一条语句的转义层数不同时，以 `all.sql` 为准（DEC-024，来源：用户说明「以all.sql为准」）。

## 用户的 UDF

确认日期：2026-10-16。决策：DEC-023。来源：用户说明「我的udf你别改」。

材料里的项目 UDF 是 `default.format_json_list`、`default.calc_url_mask`、`default.sub_parent_domain`（见 `log/ODS_TO_DWB_DETAIL.md`、`all.sql`）。转换时语句里的 UDF 调用原样保留，包括函数名、`default.` 前缀和参数，不改写成 `parse_json`、`unnest`、`regexp_replace` 等内置函数。不修改 `lab/udf` 下的 UDF 源码。若某个 UDF 在当前 StarRocks 不可用或签名不同，在输出的第三部分标明，不自行替换。

`default` 在 StarRocks 是保留字，`default.format_json_list(...)` 会报语法错误，函数库名要写成 `` `default`.format_json_list(...) ``。`explode` 没有对应写法，`LATERAL VIEW explode(UDF(...)) t AS x` 只能写成 `, unnest(UDF(...)) AS t(x)`。这两处是语法需要，函数名与参数不变。本机用 `lab/udf-sr` 里的孪生实现跑语句，见 ACT-046。

## 不在本文件中的对象

以下名称在材料里出现过，当前没有用户确认的新名称，转换时保留原名并标明「缺少新平台表名」：

- `default.dwb_*`
- `sodl.dwb_sodl_*`
- `default.log_stats_source`
- `csc.ods_csc_log_stats`
- `business.*`

`module_id`、`str1`–`str10`、`long1` 只在旧压缩 SQL 的选择列表中出现。它们不在本文件的字段表里，语句中保留原名，并标明「缺少新平台字段名」。

`day`、`hour` 在非 `sodl` 表上同样保留原名，并标明「缺少新平台字段名」。`sodl.*` 按上一节改成 `insertdate` 和 `inserttimestamp`。

## 本机实验草稿

`outputs/all-starrocks.sql` 是本机实验库草稿。实验表的列名仍是 `log_app_id`、`day`、`hour`。该文件不按本规则改名。交给用户的 StarRocks 语句按本文件替换。
