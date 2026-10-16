# 项目协作规则

## 重要决策与进度留痕

- 本项目统一使用 `docs/迁移事项进度与决策追踪.md` 记录重要决策和相关执行进展。
- 用户确认重要决策，或在已授权范围内形成影响项目的重要实施决策时，必须在本次任务结束前追加记录，不仅在聊天中说明。
- 重要决策包括：迁移范围、表或任务的保留/退役、数据来源与替代方案、责任划分、依赖顺序、里程碑、质量验收、切流回滚及资源安排的确定或变更。
- 追踪文件只允许在末尾追加（append-only），不得覆盖、删除、重排历史条目，也不得回填修改旧状态。纠错、撤销和状态变化追加新条目，并引用原编号。
- 追加前读取已有记录，避免重复记录同一决策，并沿用编号规则。新决策使用未占用的递增 `DEC-xxx`；已有事项的进展引用原决策或 `ACT-xxx` 编号。
- 每条记录写明实际日期、决策人或决策依据、决策内容、受影响表/任务/服务、证据及证据边界、当前状态和下一步。负责人、日期或依赖尚未确认时明确标为待确认，不得编造。
- 区分用户已确认决策、执行者已授权实施决策和待确认建议。不得将建议、推测或未执行的操作记录为已批准或已完成。
- 对表/任务下线、换源等决定，核对现有材料中的受影响服务，区分SQL明确引用、仅手工来源标注和缺少证据。记录决策不等于获得额外生产操作授权。
- 完成后简要告知追加的编号和要点，并提供追踪文件链接。

## 旧平台 SQL 转换为 StarRocks

用户给出旧平台查询语句时，转换成新平台 StarRocks（SR）语句。旧平台用 Hive 或 Trino 查询，语句一般是 Spark SQL 或 Trino SQL。新平台用 StarRocks 查询。

新平台的库、表、路径和部分字段与旧平台不同。每次把旧平台 SQL 改成 StarRocks 之前，先读 `docs/StarRocks语句转换规则.md`，并替换该文件里每一条已确认规则。

该文件目前包含 DEC-014 的库表对照，以及 DEC-015 的字段规则：标识符 `log_app_id` 改为 `app_id`。已经写成 `app_id` 的列保持不动。文件里没有的库、表和字段保留原名，库表标明「缺少新平台表名」，字段标明「缺少新平台字段名」，不自行补名。

`sodl.*` 在该文件写明「截图未列出 sodl 表」之前，保留原名并带上这句标注。`ti.ads_ti_ip_heat_produce` 不填进旧 SQL。`module_id`、`str1`–`str10`、`long1`、`hour`、`day` 仍按旧名保留。DEC-009 继续有效。

用户后续确认新的库、表、路径或字段时，追加到 `docs/StarRocks语句转换规则.md`，并在 `docs/迁移事项进度与决策追踪.md` 末尾追加记录。不要只改本段。

输出包含三部分：

- 替换并改写后的 StarRocks SQL
- 当次实际使用的旧表到新表对照
- 尚未替换的表，以及不能确认 StarRocks 是否支持的函数

已确认的数据契约仍要遵守：`docs/迁移事项进度与决策追踪.md` 的 DEC-009 规定目标表字段按 `VARCHAR` 落地。数值比较、时间范围、排序、聚合和关联需要显式转换。当次没有给出字段实际编码时，标出这些位置，不把旧平台字段类型写成 StarRocks 物理类型。

转换结果只是语句草稿。它不表示已经在生产 StarRocks 执行，也不表示可以切流。

## Cursor Cloud specific instructions

本仓库的可运行部分有两类：离线分析脚本，以及本机实验用的 StarRocks、Hive、Trino。后者只存在于 Cloud Agent 虚拟机，不改变公司测试环境或生产环境的事实。

实验环境由 `lab/install.sh` 安装、`lab/start.sh` 启动。查询页是 `http://127.0.0.1:8787`。三个引擎都已限制内存，并使用 8GB swap 文件 `/var/lib/lab/swapfile`。

| 组件 | 版本 | 地址 |
| --- | --- | --- |
| StarRocks FE / BE | 3.5.21 | MySQL 协议 `127.0.0.1:9030`，用户 `root`，密码为空；BE `127.0.0.1:9050` |
| Hive Metastore / HiveServer2 | Hive 4.0.1，Hadoop 3.4.1 | `127.0.0.1:9083` / `127.0.0.1:10000` |
| Trino | 446 | `http://127.0.0.1:8080` |
| 查询页 | `lab/query_platform.py` | `http://127.0.0.1:8787` |

样例表是 `lab.ioc_hit`。Trino 用 `hive.lab.ioc_hit` 和 `starrocks.lab.ioc_hit` 读取同一张逻辑表。Trino 446 是当前 Java 21 能运行的版本；材料里生产查询入口记为 Trino 358，不能把本机函数行为当成生产结论。

用户级 Python 依赖：

`python3 -m pip install --user 'sqlglot==30.18.0' 'pandas==3.0.6' 'openpyxl==3.1.5' 'pymysql==1.1.1'`

离线核对：

`python3 outputs/sql-source-audit/analyze.py`

该脚本读取仓库根目录的 `大数据平台YARN上的任务梳理-云脑大数据平台.csv` 与 `大数据平台YARN上的任务梳理-项目数据来源及输出.csv`，标准输出第一行包含 `jobs`、`manual`、`sql_units`。运行会重写 `outputs/sql-source-audit/parsed.json`。

以下脚本依赖本仓库之外的路径或文件：

- `scripts/extract_app_call_graph_context.py` 读取 `/Users/jun/project/sxf/2026/app-call-graph/results`
- `scripts/hive_queryid_to_sql.sh` 默认扫描 `/matrix/data/logs/hive`
- `scripts/analyze_operational_requirements.py` 读取 `需求/大数据平台-运营需求-收集.xlsx`
- `scripts/build_join_workbook.py` 读取仓库根目录的 `大数据平台YARN上的任务梳理.xlsx`
