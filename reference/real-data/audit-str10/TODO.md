# audit str10 / format_json_list

本目录收录用户 2026-11-10 贴回的 **domain / file** audit 样例（见 `samples-domain-2026-11-01.tsv`、`samples-file-2026-11-01-*`）。**url 分支 @pull 3、file 大 str10 全文、row5 截断行** 仍待补。

补样时请包含：

- `app_id` / `log_app_id`、`module_id`、`str1`、`str2`、`long1`、`day`、`hour`（若仍有）
- **`str10` 原始字符串**（含转义层），以及期望 `format_json_list` 拆出的元素个数
- 可选：Hive 上 `explode(default.format_json_list(...))` 的单行结果

参见 `reference/real-data/README.md` 与 DEC-023。
