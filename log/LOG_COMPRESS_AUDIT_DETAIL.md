# log_compress 审计日志中间表操作详解

> 生成日期: 2026-06-10

## 概述

log_compress 任务针对审计日志中间表 `csc.ods_csc_log_audit` 的操作分为三个阶段：先构建中间表本身，再从中提取三类威胁情报生成 audit 版 DWB 数据，最后合并到主 DWB 分区。

## 整体执行顺序

```
insert_audit (完成) → fork [dw_md5_info_audit, dw_url_info_audit, dw_domain_info_audit] (并行)
                  → dw-join → start-join → merge_action → End
insert_stats (并行) → 直接到 start-join
```

关键设计：audit 版 DWB 任务**必须等 insert_audit 完成**（因为它们读 `csc.ods_csc_log_audit`），所以 workflow 中 `insert_audit` 的 `ok to="fork-dw"` 形成了串行依赖，而 `insert_stats` 则与其他任务并行。

---

## 第一阶段 — 构建审计日志中间表

### insert_audit.sql

从原始数据表抽取到审计日志中间表，过滤掉 configserver 数据。

```sql
INSERT OVERWRITE TABLE csc.ods_csc_log_audit PARTITION (app_id, year, month, day)
SELECT log_time, log_app_id, module_id, log_type, host_name,
       long1, long2, long3, long4, long5,
       str1, str2, str3, str4, str5, str6, str7, str8, str9, str10,
       hour, repository_name, cluster_name,
       log_app_id AS app_id, year, month, day
FROM default.log_audit_source
WHERE day="${day}" AND log_app_id NOT IN ('configserver');
```

- **源表**: `default.log_audit_source`
- **目标表**: `csc.ods_csc_log_audit`
- **分区键**: `(app_id, year, month, day)`
- **过滤条件**: 排除 `log_app_id='configserver'`

---

## 第二阶段 — 从审计日志中间表提取三类威胁情报

三个子任务并行执行，数据源全部来自 `csc.ods_csc_log_audit`。

### 2.1 dw_md5_info_audit — 提取 MD5 文件情报

- **筛选条件**: `app_id='analysis-proxy-api'`，`module_id IN ('file_hash','file_scan')`，`long1=0`
- **字段提取**: 从 `str10` 字段（JSON数组）通过 LATERAL VIEW explode 提取 `filemd5`、`info.attr`
- **产品类型映射**:

| str1 值 | 映射为 prod |
|---------|-----------|
| VNGAF, NGAF | AF |
| AC, VAC | AC |
| SIP, SIP_SMTP, SIP_SMB | SIP |
| CWPP | CWPP |
| SASE | SASE |
| 含 EDR 子串 | ER |

- **关联维度表**:
  - `sri.ods_sri_hashinfo` — 文件MD5情报（oid/file_attr/file_type/source_type/type/family/platform/upload_source/virus_name），关联条件 `lower(r1.md5) = lower(r2.file_md5)`
  - `default.ods_devicemanager_deviceinfo` — 设备客户画像（city/province/country/industry/sub_industry），关联条件 `r1.devid = r3.dev_id`
- **过滤条件**: md5 长度必须为32
- **聚合**: 按 (md5, devid, dev_version, prod, source, attr) 分组，`sum(log_num)` 得到 log_num 和 attack_count，`collect_list` 收集 extends
- **输出**: HDFS `/hive/dwb/default/md5_info_audit/${mday}`，Parquet 格式

### 2.2 dw_url_info_audit — 提取 URL 情报

两个来源 UNION ALL：

**来源一：cloudcheck**

| 条件 | 值 |
|------|---|
| app_id | cloudcheck |
| module_id | CloudCheck |
| str5 | urls |
| long1 | 0 |

- URL 提取: `default.calc_url_mask(get_json_object(str10_tmp, "$.url"))` — 从 str10 JSON 提取并标准化
- raw_url: `'-'`（不保留原始 URL）
- attr: `get_json_object(str10_tmp, "$.info.attr")`

**来源二：cloud-check-handler**

| 条件 | 值 |
|------|---|
| app_id | cloud-check-handler |
| module_id | cloud-check-handler |
| str5 | url |

- URL 提取: `default.calc_url_mask(str4)` — 直接从 str4 提取并标准化
- raw_url: `str4`（保留原始 URL）
- attr: `cast(long1 AS STRING)`

**产品类型映射**（两个来源相同）:

| str1 值 | 映射为 prod |
|---------|-----------|
| VNGAF, NGAF | AF |
| AC, VAC | AC |
| EDR, EDR_BOTNET | EDR |
| SIP, SIP_SMTP, SIP_SMB | SIP |
| SDW-R | SDW |

- **关联维度表**:
  - `csc.ods_csc_db_url_intelligence_tb_url_reputation_sync` — URL信誉库，关联条件 `md5(r1.url) = r2.mask`，提取 category/family/add_time
  - `default.ods_devicemanager_deviceinfo` — 设备客户画像
- **输出**: HDFS `/hive/dwb/default/url_info_audit/${mday}`，Parquet 格式

### 2.3 dw_domain_info_audit — 提取域名情报

两个来源 UNION ALL：

**来源一：cloudcheck**

| 条件 | 值 |
|------|---|
| app_id | cloudcheck |
| module_id | CloudCheck |
| str5 | domains |
| long1 | 0 |

- 域名提取: `get_json_object(str10_tmp, "$.domain")` — 从 str10 JSON 提取
- attr: `get_json_object(str10_tmp, "$.info.attr")`

**来源二：cloud-check-handler**

| 条件 | 值 |
|------|---|
| app_id | cloud-check-handler |
| module_id | cloud-check-handler |
| str5 | domain |

- 域名提取: `str4` — 直接取 str4 字段
- attr: `cast(long1 AS STRING)`

**产品类型映射**（同 url_info_audit）

- **域名逐级子域名拆解**: 通过 `LATERAL VIEW explode(split(substr('123456789', 0, size(split(DOMAIN, '\\.'))-1), ''))` 生成不同长度的子域名
- **子域名计算**: `substring_index(DOMAIN, '.', cast(sp_len AS int) - size(split(DOMAIN, '\\.')) - 1)`
- **关联维度表**:
  - `csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync` — 黑DNS库（deleted_time=0, reputation='0'）
  - `sri.ods_sri_ti_tags` — 威胁情报标签（family英文名, category中文名），关联两次（一次取 family，一次取 category）
  - `default.ods_devicemanager_deviceinfo` — 设备客户画像
- **匹配逻辑**: 对每个 (DOMAIN, devid, dev_version, dip) 组合，按 `row_key_len DESC` 排名，只取 `rank=1` 的最长匹配（最精确的黑域名标签）
- **保留条件**: `r3.row_key IS NOT NULL OR r2.DOMAIN = r2.sub_domain`（匹配到黑域名 或 域名本身即顶级域名）
- **输出**: HDFS `/hive/dwb/default/domain_info_audit/${mday}`，Parquet 格式

---

## 第三阶段 — 合并 audit 数据到主 DWB 分区

merge_data.sh 在 HDFS 上将 audit 数据移动到主 DWB 表分区的 `log_audit/` 子目录下：

```bash
hdfs dfs -mkdir -p /hive/dwb/default/domain_info/${mday}/log_audit
hdfs dfs -mv /hive/dwb/default/domain_info_audit/${mday}/* /hive/dwb/default/domain_info/${mday}/log_audit

hdfs dfs -mkdir -p /hive/dwb/default/url_info/${mday}/log_audit
hdfs dfs -mv /hive/dwb/default/url_info_audit/${mday}/* /hive/dwb/default/url_info/${mday}/log_audit

hdfs dfs -mkdir -p /hive/dwb/default/md5_info/${mday}/log_audit
hdfs dfs -mv /hive/dwb/default/md5_info_audit/${mday}/* /hive/dwb/default/md5_info/${mday}/log_audit
```

这样审计日志产出的数据就和 DWB 主表数据在同一个分区目录下共存，下游查询可以统一读取。

---

## 分区注册

三个 audit SQL 在写入 HDFS 后，都执行了分区注册：

```sql
ALTER TABLE default.dwb_md5_info ADD IF NOT EXISTS partition (DAY=${mday}) LOCATION "/hive/dwb/default/md5_info/${mday}";
ALTER TABLE default.dwb_url_info ADD IF NOT EXISTS partition (DAY=${mday}) LOCATION "/hive/dwb/default/url_info/${mday}";
ALTER TABLE default.dwb_domain_info ADD IF NOT EXISTS partition (DAY=${mday}) LOCATION "/hive/dwb/default/domain_info/${mday}";
```

注意：分区 LOCATION 指向的是主 DWB 目录（而非 `_audit` 目录），因为 merge 后数据已合并到主目录下。

---

## 已注释的旧 DW 任务

workflow 中还有4个旧的 DW 任务已被注释掉（`dw_md5_info`, `dw_url_info`, `dw_domain_info`, `dw_ip_info`），它们从 ngaf/ac/sip/edr 等旧架构 ODS 表直接提取数据，当前只走 audit 路径。
