# 数据湖 ODS 到 DWB 加工逻辑详解

> 生成日期: 2026-06-10

## 概述

SODL 数据湖从 ODS 层到 DWB 层的加工由两个 Oozie 任务串联完成：

1. **sodl_ods_info_new**（每小时第7分）：从 ClickHouse 抽取原始日志到 ODS 层
2. **sodl_dwb_info**（每天02:30）：从 ODS 层多源聚合到 DWB 层

ODS→DWB 之间做了以下六类核心操作：多源合并、字段标准化、数据过滤、域名逐级拆解与智能匹配、威胁情报维度关联、聚合粒度调整。

---

## 一、多源 UNION ALL 合并

每张 DWB 表都是从多张 ODS 表合并而来，将不同日志类型中相同维度的数据汇聚到一张宽表。

| DWB表 | 合并的ODS来源 | 提取的威胁指标 |
|---|---|---|
| dwb_sodl_md5_info | network_security_log(filehash) + endpoint_security_log(filemd5) + sip_iocstat_log(ioc_type='file') | 文件MD5 |
| dwb_sodl_domain_info | network_security_log(从url提取域名) + dns_log(queries) + sip_iocstat_log(ioc_type='domain') + endpoint_security_log(domain) + url_log(host) | 域名 |
| dwb_sodl_ip_info | network_security_log + dns_log + url_log + http_log + sip_iocstat_log(ioc_type='ip') | IP地址 |
| dwb_sodl_url_info | network_security_log(url) + url_log(host\|\|uri) + sip_iocstat_log(ioc_type='url') + http_log(url) | URL |

---

## 二、字段标准化对齐

不同 ODS 表的字段名和含义不同，DWB 层统一了字段命名和缺失值填充。

### 2.1 字段重命名

| ODS表 | 原始字段 | DWB统一字段 |
|---|---|---|
| sip_iocstat_log | deviceId | manage |
| endpoint_security_log | manageIp | dstip / manageip |
| url_log | sip / dip | srcip / dstip |

### 2.2 缺失值填充

非网络安全日志缺少威胁分类字段，统一填0或'-'：

```sql
0 AS threatclass,  0 AS threattype,  0 AS threatsubtype
'-' AS engine,     0 AS titype,      '-' AS reqRuleId
NULL AS action,     '-' AS dstip
```

### 2.3 数据转换

| 转换类型 | 说明 | 适用DWB表 |
|---|---|---|
| `lower(filehash/filemd5/ioc)` | MD5值统一转小写 | md5_info |
| `default.calc_url_mask(url)` | URL标准化，去除协议、端口等噪音，保留核心URL | url_info |
| `split(split(url, '//')[size(...)-1], '/')[0]` | 从URL中提取域名（取 // 后第一个 / 前的部分） | domain_info |
| `host \|\| uri` 再做 `calc_url_mask` | 从host和uri拼接后标准化 | url_info |
| `regexp_extract(ioc, '(.+)(:.+)?', 1)` | 从ioc中提取IP，去掉端口部分 | ip_info |

### 2.4 attack_count 差异处理

| ODS来源 | attack_count 计算方式 |
|---|---|
| 大部分ODS表 | `attack_count = log_num`（日志条数即攻击次数） |
| sip_iocstat_log | `attack_count = sum(record_count)`（用聚合计数而非日志条数） |

---

## 三、数据过滤

ODS 层是粗抽取（按时间范围全量聚合），DWB 层做了针对性的指标过滤。

### 3.1 通用过滤

| DWB表 | 过滤条件 |
|---|---|
| md5_info | `filehash != '' AND filehash IS NOT NULL`，最终 `length(filehash)=32` |
| domain_info | `domain IS NOT NULL AND domain != ''`，且必须在黑DNS库匹配或为顶级域名 |
| url_info | `url IS NOT NULL AND url != ''` |
| ip_info | 直接按日分区聚合，无额外字段过滤 |

### 3.2 http_log 产品类型过滤

http_log 在 ODS 抽取时已过滤：`productType IN ('NGAF', 'AF', 'VNGAF')`，仅保留AF系列产品。

### 3.3 sip_iocstat_log 指标类型过滤

sip_iocstat_log 按 `ioc_type` 字段分流到不同 DWB 表：

| ioc_type 值 | 流入DWB表 | 说明 |
|---|---|---|
| 'file' | md5_info | 文件类型IOC（MD5） |
| 'domain' | domain_info | 域名类型IOC |
| 'url' | url_info | URL类型IOC |
| 'ip' | ip_info | IP类型IOC |

### 3.4 域名表特殊过滤

`WHERE r3.row_key IS NOT NULL OR r2.domain=r2.sub_domain`

只保留命中黑DNS库的域名或顶级域名本身，普通未命中域名直接丢弃。这意味着 domain_info 不是全量域名日志，而是**仅包含黑域名相关记录**的窄表。

---

## 四、域名逐级子域名拆解与黑DNS匹配（domain_info 独有）

这是最复杂的加工逻辑，仅 domain_info 表使用。

### 4.1 处理流程

1. 对每个域名调用 `default.sub_parent_domain(domain)` UDF 生成所有层级的子域名
   - 例如 `evil.example.com` → `evil.example.com`, `example.com`, `com`
2. 每个子域名 LEFT JOIN 黑DNS库，看是否命中
3. 用 `row_number() OVER (PARTITION BY domain, manage, productver, dstip, srcip ORDER BY row_key_len DESC)` 选取最长匹配
4. 只取 `rank=1` — 最精确的威胁标签

### 4.2 设计意图

一条日志访问了 `evil.example.com`，即使黑DNS库里只有 `example.com` 的标签，也能关联上。通过按 `row_key_len DESC` 排序取 rank=1，优先使用最长（最精确）的匹配。例如黑DNS库同时有 `example.com` 和 `evil.example.com` 的标签时，优先取 `evil.example.com`。

### 4.3 黑DNS CTE构建

```sql
WITH black_dns AS (
  SELECT t2.family, tags2.ch_name AS category, t2.row_key, length(t2.row_key) AS row_key_len, t2.add_time
  FROM (
    SELECT max(tags1.en_name) AS family, t1.category, t1.row_key, max(t1.add_time) AS add_time
    FROM (
      SELECT domain AS row_key,
             regexp_extract(labels, 'family=(.*?)[,}]', 1) AS family,
             regexp_extract(labels, 'category=(.*?)[,}]', 1) AS category,
             deleted_time, add_time
      FROM csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync
      WHERE deleted_time=0 AND reputation='0'  -- 仅保留黑域名
    ) t1
    JOIN sri.ods_sri_ti_tags tags1 ON t1.family=tags1.row_key
    WHERE tags1.is_deleted='0'
    GROUP BY t1.row_key, t1.family, t1.category
  ) t2
  JOIN sri.ods_sri_ti_tags tags2 ON t2.category=tags2.row_key
  WHERE tags2.is_deleted='0'
)
```

- 数据源：`csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync`
- 筛选条件：`deleted_time=0`（未删除）且 `reputation='0'`（黑域名）
- 两次 JOIN `sri.ods_sri_ti_tags`：第一次获取 family 英文名，第二次获取 category 中文名
- 同一域名可能有多个 family 标签，用 `max()` 聚合取一个

---

## 五、威胁情报维度关联（LEFT JOIN）

四张 DWB 表都做了 LEFT JOIN 维度表来丰富数据。

### 5.1 关联关系总表

| DWB表 | 关联的维度表 | 关联条件 | 获取的字段 |
|---|---|---|---|
| md5_info | `sri.ods_sri_hashinfo` | `lower(filehash) = lower(file_md5)` | oid, file_attr, file_type, source_type, type, family, platform, upload_source, virus_name |
| md5_info | `default.ods_devicemanager_deviceinfo` | `manage = dev_id` | city, province, country, industry, sub_industry |
| domain_info | 黑DNS CTE | `sub_domain = row_key` | family, category, add_time |
| domain_info | `default.ods_devicemanager_deviceinfo` | `manage = dev_id` | city, province, country, industry, sub_industry |
| ip_info | 黑IP CTE | `dstip = row_key` | family, category, add_time |
| ip_info | `default.ods_devicemanager_deviceinfo` | `manage = dev_id` | city, province, country, industry, sub_industry |
| url_info | URL信誉 CTE | `md5(url) = mask` | category, family, add_time |
| url_info | `default.ods_devicemanager_deviceinfo` | `manage = dev_id` | city, province, country, industry, sub_industry |

### 5.2 黑IP CTE构建

```sql
WITH black_ip AS (
  SELECT fam_tags.en_name AS family, cat_tags.ch_name AS category, base.row_key, CAST(base.add_time AS STRING) AS add_time
  FROM (
    SELECT ip AS row_key, add_time,
           REGEXP_EXTRACT(REGEXP_EXTRACT(labels, '\\[(.+?)\\]', 1), 'family=(.*?)[,}]', 1) AS family_key,
           REGEXP_EXTRACT(REGEXP_EXTRACT(labels, '\\[(.+?)\\]', 1), 'category=(.*?)[,}]', 1) AS category_key
    FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
    WHERE deleted_time=0 AND reputation='0' AND direction='2' AND port=0
  ) base
  JOIN sri.ods_sri_ti_tags fam_tags ON base.family_key = fam_tags.row_key AND fam_tags.is_deleted='0'
  JOIN sri.ods_sri_ti_tags cat_tags ON base.category_key = cat_tags.row_key AND cat_tags.is_deleted='0'
)
```

- 数据源：`csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync`
- 筛选条件：`deleted_time=0`（未删除），`reputation='0'`（黑IP），`direction='2'`（目的IP），`port=0`（不限端口）
- labels 字段格式为 `[family=xxx,category=yyy]`，需正则提取后两次 JOIN ti_tags 获取中英文名

### 5.3 URL信誉 CTE构建

```sql
WITH report_cloud_lib_url AS (
  SELECT mask, cast(add_time as string) as add_time, category,
    CASE
      WHEN indexA=0 AND indexP=0 THEN NULL
      WHEN indexA=0 AND indexP>0 THEN regexp_extract(labels, "(B002_P....)", 1)  -- 仅钓鱼
      WHEN indexA>0 AND indexP=0 THEN regexp_extract(labels, "(B002_A.....)", 1)  -- 仅攻击
      WHEN indexA<indexP THEN regexp_extract(labels, "(B002_A.....)", 1)         -- 攻击为主
      ELSE regexp_extract(labels, "(B002_P....)", 1)                            -- 钓鱼为主
    END AS family
  FROM (
    SELECT mask, add_time, labels,
           regexp_extract(labels, "(B002_C....)", 1) AS category,
           instr(labels, 'A') AS indexA, instr(labels, 'P') AS indexP
    FROM csc.ods_csc_db_url_intelligence_tb_url_reputation_sync
    WHERE instr(labels, 'B002')>0 AND deleted_time=0
  ) t
)
```

- 数据源：`csc.ods_csc_db_url_intelligence_tb_url_reputation_sync`
- 筛选条件：labels 含 `B002`（URL威胁标签），`deleted_time=0`
- 关联条件：`md5(url) = mask`（URL经MD5哈希后匹配）
- family 分类逻辑：根据 labels 中 A（攻击）和 P（钓鱼）的位置判断威胁类型

### 5.4 设备客户画像提取

所有DWB表都从 `default.ods_devicemanager_deviceinfo` 的 `customer_info` JSON 字段中正则提取地理和行业信息：

```
city        = regexp_extract(customer_info, "city=(.*?)[,}]", 1)
province    = regexp_extract(customer_info, "province=(.*?)[,}]", 1)
country     = regexp_extract(customer_info, "country=(.*?)[,}]", 1)
industry    = regexp_extract(customer_info, "industry=(.*?)[,}]", 1)
sub_industry = regexp_extract(customer_info, "sub_industry=(.*?)[,}]", 1)
```

关联条件：`manage = dev_id`

---

## 六、src_log 数据来源标记

每条 DWB 记录都携带 `src_log` 字段标记来自哪个 ODS 表，便于溯源：

| src_log 值 | 来源ODS表 |
|---|---|
| network_security_log | sodl.network_security_log |
| endpoint_security_log | sodl.endpoint_security_log |
| sip_iocstat_log | sodl.sip_iocstat_log |
| dns_log | sodl.dns_log |
| url_log | sodl.url_log |
| http_log | sodl.http_log |

---

## 七、聚合粒度变化

ODS 层按原始日志字段聚合（保留完整维度），DWB 层按威胁指标聚合，丢弃了与威胁分析无关的细粒度字段。

### 7.1 ODS层聚合维度（保留的完整字段）

| ODS表 | ODS层聚合维度 |
|---|---|
| dns_log | productType, manage, productVer, srcIp, dstIp, qr, qTypes, queries, aTypes, answers |
| network_security_log | threatClass, threatType, threatSubType, productType, manage, productVer, srcIp, dstIp, reqRuleId, fileHash, action, tiType, riskLevel, severity, engine, url, result, ruleName, requestHead, requestBody |
| endpoint_security_log | threatClass, threatType, threatSubType, productType, manage, manageIp, productVer, engine, fileMd5, domain |
| sip_iocstat_log | productType, deviceId, productVer, ioc_type, ioc |
| url_log | productType, deviceId, productVer, sip, dip, host, uri, urls |
| http_log | productType, manage, productVer, srcIp, dstIp, url |

### 7.2 DWB层聚合维度

| DWB表 | 聚合维度 | 聚合指标 |
|---|---|---|
| md5_info | (threatclass, threattype, threatsubtype, producttype, manage, productver, filehash, dstip, reqRuleId, engine) + src_log | sum(log_num), sum(log_num/record_count) AS attack_count |
| domain_info | (threatclass, threattype, threatsubtype, producttype, manage, productver, domain, engine, titype, srcip, dstip, action, reqRuleId) | sum(log_num), sum(log_num/record_count) AS attack_count |
| ip_info | (threatclass, threattype, threatsubtype, producttype, manage, productver, srcip, dstip, engine, titype, reqRuleId, action) | sum(log_num), sum(log_num/record_count) AS attack_count |
| url_info | (threatclass, threattype, threatsubtype, producttype, manage, productver, url, raw_url, engine, titype, srcip, dstip, reqRuleId) | sum(log_num), sum(log_num/record_count) AS attack_count |

### 7.3 ODS→DWB 丢弃的字段

| ODS表 | 丢弃的字段 | 原因 |
|---|---|---|
| dns_log | qr, qTypes, aTypes, answers | DNS协议细节，与威胁指标无关 |
| network_security_log | result, ruleName, requestHead, requestBody | 攻击细节/载荷，DWB层只关注威胁指标维度 |
| url_log | urls, uri（单独） | host\|\|uri已拼接为url，urls为备用字段 |
| http_log | url直接转为 calc_url_mask(url) | 保留raw_url，但聚合维度只看标准化后的url |

---

## 八、ODS→DWB 加工总结

| 操作 | 说明 |
|---|---|
| **多源合一** | 将 6 种安全日志中同类威胁指标（MD5/URL/域名/IP）合并到一张宽表 |
| **字段标准化** | 统一命名、缺失值填充、格式转换（小写、URL标准化、域名提取） |
| **威胁情报关联** | LEFT JOIN 威胁库获取 family/category/virus_name 等标签 |
| **设备画像关联** | LEFT JOIN 设备表获取地理/行业信息 |
| **智能匹配** | 域名做逐级子域名拆解取最长匹配；IP只匹配目的IP且方向为2的黑IP |
| **数据过滤** | 丢弃空值、无效指标、未命中黑名单的普通域名 |
| **粒度调整** | 丢弃与威胁分析无关的细粒度字段，按威胁指标维度聚合 |
| **来源标记** | 每条记录携带 src_log 标记来源ODS表，便于溯源 |

---

## 附录：各DWB表完整字段对比

### dwb_sodl_md5_info

| 字段 | 来源 |
|---|---|
| threatclass, threattype, threatsubtype | ODS源表（非network_security_log来源填0） |
| producttype, manage, productver | ODS源表 |
| filehash | ODS源表，统一lower() |
| dstip | network_security_log.dstIp / endpoint_security_log.manageIp / '-' |
| reqRuleId | network_security_log.reqRuleId / '-' |
| engine | ODS源表 / '-' |
| oid, file_attr, file_type, source_type, type, family, platform, upload_source, virus_name_hash | LEFT JOIN sri.ods_sri_hashinfo |
| log_num, attack_count | sum聚合 |
| src_log | 来源标记 |
| city, province, country, industry, sub_industry | LEFT JOIN default.ods_devicemanager_deviceinfo |

### dwb_sodl_domain_info

| 字段 | 来源 |
|---|---|
| threatclass, threattype, threatsubtype | ODS源表（非network_security_log来源填0） |
| producttype, manage, productver | ODS源表 |
| domain | network_security_log从url提取 / dns_log.queries / sip_iocstat_log.ioc / endpoint_security_log.domain / url_log.host |
| engine, titype | ODS源表 / '-' / 0 |
| srcip, dstip | ODS源表 / '-' |
| action | network_security_log.action / NULL |
| reqRuleId | ODS源表 / '-' |
| row_key, family, category, add_time | 黑DNS CTE匹配 |
| log_num, attack_count | sum聚合 |
| src_log | 来源标记 |
| city, province, country, industry, sub_industry | LEFT JOIN default.ods_devicemanager_deviceinfo |

### dwb_sodl_ip_info

| 字段 | 来源 |
|---|---|
| threatclass, threattype, threatsubtype | ODS源表（非network_security_log来源填0） |
| producttype, manage, productver | ODS源表 |
| srcip, dstip | ODS源表 / sip_iocstat_log从ioc提取IP / '-' |
| engine, titype | ODS源表 / '-' / 0 |
| reqRuleId | ODS源表 / '-' |
| action | network_security_log.action / NULL |
| family, category, add_time | 黑IP CTE匹配 |
| log_num, attack_count | sum聚合 |
| src_log | 来源标记 |
| city, province, country, industry, sub_industry | LEFT JOIN default.ods_devicemanager_deviceinfo |

### dwb_sodl_url_info（已暂停）

| 字段 | 来源 |
|---|---|
| threatclass, threattype, threatsubtype | ODS源表（非network_security_log来源填0） |
| producttype, manage, productver | ODS源表 |
| url | ODS源表经calc_url_mask标准化 |
| raw_url | ODS源表原始URL（url_log/http_log保留；network_security_log保留；sip_iocstat_log保留ioc） |
| engine, titype | ODS源表 / '-' / 0 |
| srcip, dstip | ODS源表 / '-' |
| reqRuleId | ODS源表 / '-' |
| category, family, add_time | URL信誉CTE匹配 |
| log_num, attack_count | sum聚合 |
| src_log | 来源标记 |
| city, province, country, industry, sub_industry | LEFT JOIN default.ods_devicemanager_deviceinfo |
