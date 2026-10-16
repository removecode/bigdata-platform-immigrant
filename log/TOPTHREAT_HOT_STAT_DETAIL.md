# topthreat_hot_stat 数据处理流程

## 1. 调度配置

- **调度频率**: 每小时第 7 分钟执行 (`07 * * * *`)
- **时区**: Asia/Shanghai
- **时间偏移**: 使用 **T-2 小时**的数据（`coord:dateOffset(coord:nominalTime(), -2, 'HOUR')`），即当前触发时间往前推 2 小时作为数据分区
- **传递参数**: `mday`（yyyyMMdd）、`mhour`（HH）、`year`、`month`、`month_simple`、`day_simple`

## 2. 工作流结构

workflow 采用 **fork-join 并行模式**，三个子任务同时执行：

```
fork-topthreat-stat
  ├── domain_stat  →  black_domain_stat.sh  (黑域名统计)
  ├── url_stat    →  black_url_stat.sh     (黑URL统计)
  └── file_stat   →  black_file_stat.sh    (文件MD5统计)
start-join → End
```

每个 action 的失败重试策略：最多 3 次，间隔 2 分钟。

## 3. 三个子任务详情

### 3.1 domain_stat — 黑域名统计

| 项目 | 值 |
|------|-----|
| 脚本 | `black_domain_stat.sh` |
| 配置 | `black_domain_stat.yaml` |
| 处理器 | `topthreat_domain_processor.Processor` |
| 目标库 | `mongo-int.db_statistic.tb_original_domain_stat` |

**Hive SQL 逻辑**：三个数据源 UNION ALL 后聚合，取 top 100000：

1. **log_audit_source（主日志表）**：从 `str10` 字段解析 JSON，提取 `domain`，过滤条件包括：
   - `log_app_id` ∈ `domain-proxy-svc`, `cloudcheck`
   - `module_id` ∈ `domain-proxy-svc`, `CloudCheck`
   - `str1` ∈ 产品线标识（VNGAF, NGAF, EDR, SIP, AC, VAC, CWPP, SASE 等）
   - `long1 = 0`（威胁命中标记）
   - JSON 中 `info.attr = '0'`（黑名单属性）
   - 按 `devid`(str2) 分组统计域名出现次数

2. **sodl.network_security_log（网络安全日志表）**：从 `url` 字段截取域名部分（`split(split(url,'//')[last],'/')[0]`），按 `manage`(设备ID) 和 `log_num` 汇总

3. **sodl.sip_iocstat_log（SIP IOC统计日志）**：取 `ioc_type = 'domain'` 的记录，按 `ioc`(域名) 和 `manage` 汇总 `record_count`

**最终聚合**：按 `domain` + `devid` 分组，求 `sum(domain_num)` 和 `count(DISTINCT devid)`，按 `domain_num` 降序取前 100000 条。

**MongoDB 写入格式**：
- 查询键：`{key: domain, hour: day+hour}`
- 更新字段：`update_time`, `check_cnts`(命中次数), `dev_cnts`(设备数)
- 插入时补设：`key`, `hour`, `insert_time`
- 采用 `upsert=True`，同一 key+hour 只保留最新

---

### 3.2 url_stat — 黑URL统计

| 项目 | 值 |
|------|-----|
| 脚本 | `black_url_stat.sh` |
| 配置 | `blcak_url_stat.yaml`（注意：文件名有拼写错误，blcak→black） |
| 处理器 | `topthreat_url_processor.Processor` |
| 目标库 | `mongo-int.db_statistic.tb_original_url_stat` |

**Hive SQL 逻辑**：与 domain_stat 结构一致，三个数据源 UNION ALL：

1. **log_audit_source**：提取 `url` 字段，`log_app_id` ∈ `url-proxy-svc`, `cloudcheck`，`module_id` ∈ `url-proxy-svc`, `CloudCheck`
2. **sodl.network_security_log**：直接取 `url` 字段
3. **sodl.sip_iocstat_log**：取 `ioc_type = 'url'` 的记录

**最终聚合**：按 `url` + `devid` 分组，求 `sum(url_num)` 和 `count(DISTINCT devid)`，降序取前 100000 条。

**MongoDB 写入格式**：与 domain_stat 相同，`{key: url, hour: day+hour}` upsert。

---

### 3.3 file_stat — 文件MD5统计

| 项目 | 值 |
|------|-----|
| 脚本 | `black_file_stat.sh` |
| 配置 | `black_file_stat.yaml` |
| 处理器 | `file_processor.Processor` |
| 目标库 | `mongo-int.db_statistic.tb_original_file_stat` |

**Hive SQL 逻辑**：仅从 **log_audit_source** 单表查询：

- `log_app_id = 'analysis-proxy-api'`
- `module_id` ∈ `file_hash`, `file_scan`
- 从 `str10` JSON 提取 `filemd5` 和 `info.attr`
- 过滤 `attr='0'`（黑名单）+ `long1=0`
- 按 `md5` + `devid` 分组，取 `count(1)` 和 `count(DISTINCT devid)`，降序取前 100000 条

**MongoDB 写入格式**：与 domain/url 不同，查询键为 `{key: md5, day: day}`（按天而非按小时），直接 `$set` 覆盖写入。

## 4. 公共处理框架（storage 模块）

三个子任务共享同一套 Python 处理框架 `storage`，流程如下：

```
shell脚本 → python -m storage day=X hour=Y conf_path=./xxx.yaml
    │
    ├── 1. 解析启动参数 → args_dict {day, hour, conf_path}
    ├── 2. StorageConf 解析 YAML 配置 → 提取 hive_sql / output / processor_module
    ├── 3. 按 YAML 中任务数创建线程池，每个任务一个线程
    ├── 4. Base Processor.run() 流程：
    │     ├── before(): 检查 Hive 游标和 MongoDB 客户端是否就绪
    │     ├── handler():
    │     │     ├── build_sql(): 用 Template 替换 ${day}/${hour}
    │     │     ├── query(): 通过 HiveUtil 执行 SQL（提交到 tez 队列 etl）
    │     │     ├── 分批 fetchmany(size=5000) 遍历结果
    │     │     │     ├── filter(): 过滤空 key 和 "NULL"
    │     │     │     ├── formatdata(): 转换为 pymongo UpdateOne 对象
    │     │     │     └── write_to_db(): bulk_write 批量写入 MongoDB（失败重试 5 次）
    │     │     └── 循环直到无更多数据
    │     └── after(): 打印统计日志（成功/过滤/失败条数）
```

**关键配置参数**：
- `WRITE_BUNCH_SIZE = 5000`（每批从 Hive 读取 5000 行）
- `DB_FAIL_RETRY = 5`（MongoDB 写入失败重试 5 次）
- `FILTER_KEY_LIST = ["NULL"]`（过滤 key 为空的脏数据）
- `YARN_QUEUE_NAME = "etl"`（Hive SQL 提交到 etl 队列）

## 5. 数据流总览

```
               ┌─────────────────────────────────────┐
               │  Hive 数据源 (day=X, hour=Y)         │
               │  ├ default.log_audit_source          │
               │  ├ sodl.network_security_log         │
               │  └ sodl.sip_iocstat_log              │
               └───────────┬─────────────────────────┘
                           │ Hive SQL 查询
                   ┌───────┼───────────┐
                   ▼       ▼           ▼
             domain统计  url统计    file统计
                   │       │           │
                   ▼       ▼           ▼
          topthreat_   topthreat_    file_
          domain_      url_         processor
          processor    processor        │
               │       │               │
               ▼       ▼               ▼
        ┌──────────────────────────────────────┐
        │  mongo-int.db_statistic               │
        │  ├ tb_original_domain_stat (按小时)    │
        │  ├ tb_original_url_stat    (按小时)    │
        │  └ tb_original_file_stat   (按天)     │
        └──────────────────────────────────────┘
```
