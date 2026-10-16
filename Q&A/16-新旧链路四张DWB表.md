# 新旧链路都会生成 MD5/域名/URL/IP 四张表吗

**问：** 现在新旧链路都会生成 MD5、域名、URL、IP 四张 DWB 表吗？

## 答

**不是。当前文档下，两条链路都未完整产出四类 DWB 宽表。**

| 指标 | 新链路 `sodl.dwb_sodl_*` | 旧链路 `default.dwb_*`（现行 audit） |
|------|--------------------------|-------------------------------------|
| **MD5** | ✅ `dwb_sodl_md5_info` | ✅ `dwb_md5_info` |
| **域名** | ✅ `dwb_sodl_domain_info` | ✅ `dwb_domain_info` |
| **URL** | ❌ `dwb_sodl_url_info` **已暂停** | ✅ `dwb_url_info` |
| **IP** | ✅ `dwb_sodl_ip_info` | ❌ 无 `ip_info_audit`；`dw_ip_info` 已注释 |

### 结论

- **新链路**：MD5 + 域名 + IP（3 张），**缺 URL**
- **旧链路**：MD5 + 域名 + URL（3 张），**缺 IP**
- 四类指标分布在两套表体系中，**不能假设任意一套都有完整四类**

```text
新链路：MD5 ✅  域名 ✅  URL ❌  IP ✅
旧链路：MD5 ✅  域名 ✅  URL ✅  IP ❌
```

### 原因

1. 新链路 URL：`dwb_sodl_url_info` 在 workflow 中已注释（`feature-pause-url-info`）
2. 旧链路 IP：audit 阶段只有 md5/url/domain 三个 audit 任务；旧 `dw_ip_info` 等多源 DW 已注释

## 来源

- `log/DATA_FLOW.md` L104–110、L144–151、L279–280
- `log/LOG_COMPRESS_AUDIT_DETAIL.md` L179–182、L189–191
- `outputs/...系统分析临时文档.md` L250–253
