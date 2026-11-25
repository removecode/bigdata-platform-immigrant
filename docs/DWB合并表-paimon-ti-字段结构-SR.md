# 10.115.51.1 dwb 表结构（paimon.ti）

分区键：`src_log`, `day`（SHOW PARTITIONS 的 PartitionKey 显示为 `day,src_log`，但数值对应 src_log/day）。所有列 Null/Key/Default/Extra 见下表。

## dwb_ti_domain_info（23 列）

| # | 字段 | 类型 | Null | Key | Default | Extra |
|---|---|---|---|---|---|---|
| 1 | threatclass | INT | Yes | false | None |  |
| 2 | threattype | INT | Yes | false | None |  |
| 3 | threatsubtype | INT | Yes | false | None |  |
| 4 | producttype | VARCHAR(1073741824) | Yes | false | None |  |
| 5 | manage | VARCHAR(1073741824) | Yes | false | None |  |
| 6 | productver | VARCHAR(1073741824) | Yes | false | None |  |
| 7 | domain | VARCHAR(1073741824) | Yes | false | None |  |
| 8 | engine | VARCHAR(1073741824) | Yes | false | None |  |
| 9 | srcip | VARCHAR(1073741824) | Yes | false | None |  |
| 10 | dstip | VARCHAR(1073741824) | Yes | false | None |  |
| 11 | reqruleid | VARCHAR(1073741824) | Yes | false | None |  |
| 12 | row_key | VARCHAR(1073741824) | Yes | false | None |  |
| 13 | family | VARCHAR(1073741824) | Yes | false | None |  |
| 14 | category | VARCHAR(1073741824) | Yes | false | None |  |
| 15 | attr | VARCHAR(1073741824) | Yes | false | None |  |
| 16 | add_time | VARCHAR(1073741824) | Yes | false | None |  |
| 17 | action | INT | Yes | false | None |  |
| 18 | agentid | VARCHAR(1073741824) | Yes | false | None |  |
| 19 | tenant | VARCHAR(1073741824) | Yes | false | None |  |
| 20 | log_num | BIGINT | Yes | false | None |  |
| 21 | attack_count | BIGINT | Yes | false | None |  |
| 22 | src_log | VARCHAR(1073741824) | Yes | false | None | partition key |
| 23 | day | BIGINT | Yes | false | None | partition key |

## dwb_ti_ip_info（24 列）

| # | 字段 | 类型 | Null | Key | Default | Extra |
|---|---|---|---|---|---|---|
| 1 | threatclass | INT | Yes | false | None |  |
| 2 | threattype | INT | Yes | false | None |  |
| 3 | threatsubtype | INT | Yes | false | None |  |
| 4 | producttype | VARCHAR(1073741824) | Yes | false | None |  |
| 5 | manage | VARCHAR(1073741824) | Yes | false | None |  |
| 6 | productver | VARCHAR(1073741824) | Yes | false | None |  |
| 7 | srcip | VARCHAR(1073741824) | Yes | false | None |  |
| 8 | dstip | VARCHAR(1073741824) | Yes | false | None |  |
| 9 | engine | VARCHAR(1073741824) | Yes | false | None |  |
| 10 | object | VARCHAR(1073741824) | Yes | false | None |  |
| 11 | direction | VARCHAR(1073741824) | Yes | false | None |  |
| 12 | reqruleid | VARCHAR(1073741824) | Yes | false | None |  |
| 13 | action | INT | Yes | false | None |  |
| 14 | agentid | VARCHAR(1073741824) | Yes | false | None |  |
| 15 | tenant | VARCHAR(1073741824) | Yes | false | None |  |
| 16 | dstport | INT | Yes | false | None |  |
| 17 | family | VARCHAR(1073741824) | Yes | false | None |  |
| 18 | category | VARCHAR(1073741824) | Yes | false | None |  |
| 19 | attr | VARCHAR(1073741824) | Yes | false | None |  |
| 20 | add_time | VARCHAR(1073741824) | Yes | false | None |  |
| 21 | log_num | BIGINT | Yes | false | None |  |
| 22 | attack_count | BIGINT | Yes | false | None |  |
| 23 | src_log | VARCHAR(1073741824) | Yes | false | None | partition key |
| 24 | day | BIGINT | Yes | false | None | partition key |

## dwb_ti_md5_info（25 列）

| # | 字段 | 类型 | Null | Key | Default | Extra |
|---|---|---|---|---|---|---|
| 1 | threatclass | INT | Yes | false | None |  |
| 2 | threattype | INT | Yes | false | None |  |
| 3 | threatsubtype | INT | Yes | false | None |  |
| 4 | producttype | VARCHAR(1073741824) | Yes | false | None |  |
| 5 | manage | VARCHAR(1073741824) | Yes | false | None |  |
| 6 | productver | VARCHAR(1073741824) | Yes | false | None |  |
| 7 | filehash | VARCHAR(1073741824) | Yes | false | None |  |
| 8 | srcip | VARCHAR(1073741824) | Yes | false | None |  |
| 9 | dstip | VARCHAR(1073741824) | Yes | false | None |  |
| 10 | reqruleid | VARCHAR(1073741824) | Yes | false | None |  |
| 11 | engine | VARCHAR(1073741824) | Yes | false | None |  |
| 12 | tenant | VARCHAR(1073741824) | Yes | false | None |  |
| 13 | agentid | VARCHAR(1073741824) | Yes | false | None |  |
| 14 | file_attr | VARCHAR(1073741824) | Yes | false | None |  |
| 15 | file_type | VARCHAR(1073741824) | Yes | false | None |  |
| 16 | source_type | VARCHAR(1073741824) | Yes | false | None |  |
| 17 | type | VARCHAR(1073741824) | Yes | false | None |  |
| 18 | family | VARCHAR(1073741824) | Yes | false | None |  |
| 19 | platform | VARCHAR(1073741824) | Yes | false | None |  |
| 20 | upload_source | VARCHAR(1073741824) | Yes | false | None |  |
| 21 | virus_name_hash | VARCHAR(1073741824) | Yes | false | None |  |
| 22 | log_num | BIGINT | Yes | false | None |  |
| 23 | attack_count | BIGINT | Yes | false | None |  |
| 24 | src_log | VARCHAR(1073741824) | Yes | false | None | partition key |
| 25 | day | BIGINT | Yes | false | None | partition key |

## dwb_ti_url_info（21 列）

| # | 字段 | 类型 | Null | Key | Default | Extra |
|---|---|---|---|---|---|---|
| 1 | threatclass | INT | Yes | false | None |  |
| 2 | threattype | INT | Yes | false | None |  |
| 3 | threatsubtype | INT | Yes | false | None |  |
| 4 | producttype | VARCHAR(1073741824) | Yes | false | None |  |
| 5 | manage | VARCHAR(1073741824) | Yes | false | None |  |
| 6 | productver | VARCHAR(1073741824) | Yes | false | None |  |
| 7 | url | VARCHAR(1073741824) | Yes | false | None |  |
| 8 | raw_url | VARCHAR(1073741824) | Yes | false | None |  |
| 9 | engine | VARCHAR(1073741824) | Yes | false | None |  |
| 10 | action | INT | Yes | false | None |  |
| 11 | tenant | VARCHAR(1073741824) | Yes | false | None |  |
| 12 | srcip | VARCHAR(1073741824) | Yes | false | None |  |
| 13 | dstip | VARCHAR(1073741824) | Yes | false | None |  |
| 14 | reqruleid | VARCHAR(1073741824) | Yes | false | None |  |
| 15 | category | VARCHAR(1073741824) | Yes | false | None |  |
| 16 | family | VARCHAR(1073741824) | Yes | false | None |  |
| 17 | add_time | VARCHAR(1073741824) | Yes | false | None |  |
| 18 | log_num | BIGINT | Yes | false | None |  |
| 19 | attack_count | BIGINT | Yes | false | None |  |
| 20 | src_log | VARCHAR(1073741824) | Yes | false | None | partition key |
| 21 | day | BIGINT | Yes | false | None | partition key |
