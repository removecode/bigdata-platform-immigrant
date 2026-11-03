# audit str10 / format_json_list

本目录预留：用户尚未提供 `csc.ods_csc_log_audit`（或旧 `default.log_audit_source`）中带 **`str10`** 的真实行。

补样时请包含：

- `app_id` / `log_app_id`、`module_id`、`str1`、`str2`、`long1`、`day`、`hour`（若仍有）
- **`str10` 原始字符串**（含转义层），以及期望 `format_json_list` 拆出的元素个数
- 可选：Hive 上 `explode(default.format_json_list(...))` 的单行结果

参见 `reference/real-data/README.md` 与 DEC-023。
