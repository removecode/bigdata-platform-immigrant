# DWB 分区是什么

**问：** DWB 分区是什么？

## 答

**DWB 分区** = DWB 宽表按**天**（`DAY` / `${mday}`）切分的数据块，对应 HDFS 上的目录；Hive 通过分区元数据指向这些目录。

### 示例（旧链路）

```text
/hive/dwb/default/md5_info/20260624/           ← 当天 DWB 分区
/hive/dwb/default/md5_info/20260624/log_audit/  ← audit 数据子目录
```

`merge_data.sh` 将 `*_info_audit/${mday}` 的文件移入主分区下的 `log_audit/`，再执行：

```sql
ALTER TABLE default.dwb_md5_info ADD IF NOT EXISTS partition (DAY=${mday})
  LOCATION "/hive/dwb/default/md5_info/${mday}";
```

> 来源：`log/LOG_COMPRESS_AUDIT_DETAIL.md` L156–185

### 与 ODS 分区的区别

| 层级 | 分区粒度 | 示例 |
|------|---------|------|
| ODS | 常按小时 + 多维 | `year/month/day/hour`；`app_id, year, month, day` |
| DWB | 主要按天 | `DAY=${mday}` |

### 谁创建分区

- `create_hive_partition`：T+2 **预建**部分 ODS 分区
- `log_compress` / `sodl_dwb_info`：任务跑完后 **写入并注册** DWB 分区

> 来源：`log/DATA_FLOW.md` L186–194、L112–117
