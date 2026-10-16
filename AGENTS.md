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

## Cursor Cloud specific instructions

本仓库是迁移文档和离线分析材料，没有需要常驻的 Web 服务。

用户级 Python 依赖（与当前核对脚本使用的 sqlglot 版本一致）：

`python3 -m pip install --user 'sqlglot==30.18.0' 'pandas==3.0.6' 'openpyxl==3.1.5'`

代表性检查：

`python3 outputs/sql-source-audit/analyze.py`

该脚本读取仓库根目录的 `大数据平台YARN上的任务梳理-云脑大数据平台.csv` 与 `大数据平台YARN上的任务梳理-项目数据来源及输出.csv`，标准输出第一行包含 `jobs`、`manual`、`sql_units`。运行会重写 `outputs/sql-source-audit/parsed.json`。

以下脚本依赖本仓库之外的路径或文件，云端虚拟机默认不具备：

- `scripts/extract_app_call_graph_context.py` 读取 `/Users/jun/project/sxf/2026/app-call-graph/results`
- `scripts/hive_queryid_to_sql.sh` 默认扫描 `/matrix/data/logs/hive`
- `scripts/analyze_operational_requirements.py` 读取 `需求/大数据平台-运营需求-收集.xlsx`
- `scripts/build_join_workbook.py` 读取仓库根目录的 `大数据平台YARN上的任务梳理.xlsx`
