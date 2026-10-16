-- topthreat_hot_stat 的 StarRocks 草稿
-- 库表按 docs/StarRocks语句转换规则.md（DEC-014）。
-- default.log_audit_source 改为 csc.ods_csc_log_audit。
-- sodl.network_security_log、sodl.sip_iocstat_log：截图未列出 sodl 表，保留原名。
-- 字段按 DEC-015：标识符 log_app_id 改为 app_id。
-- csc.ods_csc_log_audit 仍用 day=20261001、hour=0。这不是 sodl 表，这两个字段标明「缺少新平台字段名」。
-- sodl.* 按 DEC-016、DEC-017：day=20261001 改为 insertdate='2026-10-01'；hour=0 改为 hour(from_unixtime(inserttimestamp)) = 0。
-- from_unixtime 按 all.sql L274 的秒级 Unix 时间推断。network_security_log、sip_iocstat_log 的类型未给出。
-- module_id、str1、str10、long1 仍用旧名，标明「缺少新平台字段名」。
-- 这些列来自旧压缩 SQL（log/LOG_COMPRESS_AUDIT_DETAIL.md L28–35），截图没有字段清单。
-- long1、day、hour、log_num、record_count 的比较和求和按 DEC-009 需要按实际编码转换。

-- 黑域名
SELECT domain,
       sum(domain_num) AS domain_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT domain,
          devid,
          count(1) AS domain_num
   FROM
     (SELECT lower(get_json_object(str10_tmp, '$.domain')) AS domain,
             str2 AS devid
      FROM csc.ods_csc_log_audit,
           unnest(ifnull(cast(parse_json(regexp_replace(str10, '\\\\+"', '"')) AS ARRAY<JSON>), [])) AS str10_tbl(str10_tmp)
      WHERE app_id IN ('domain-proxy-svc', 'cloudcheck')
        AND module_id IN ('domain-proxy-svc', 'CloudCheck')
        AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
                     'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
                     'EDR_CLOUD_IDENTIFY', 'EDR_PK')
        AND long1 = 0
        AND get_json_object(str10_tmp, '$.info.attr') = '0'
        AND day = 20261001
        AND hour = 0) a
   WHERE domain IS NOT NULL
     AND domain NOT IN ('', '-')
   GROUP BY domain, devid

   UNION ALL

   SELECT domain,
          devid,
          sum(log_num) AS domain_num
   FROM
     (SELECT split(split(url, '//')[cardinality(split(url, '//'))], '/')[1] AS domain,
             MANAGE AS devid,
             log_num
      FROM sodl.network_security_log
      WHERE url IS NOT NULL
        AND url NOT IN ('', '-')
        AND insertdate = '2026-10-01'
        AND hour(from_unixtime(inserttimestamp)) = 0) t
   WHERE domain IS NOT NULL
     AND domain != ''
   GROUP BY domain, devid

   UNION ALL

   SELECT ioc AS domain,
          manage AS devid,
          sum(record_count) AS domain_num
   FROM sodl.sip_iocstat_log
   WHERE ioc_type = 'domain'
     AND ioc IS NOT NULL
     AND ioc NOT IN ('', '-')
     AND insertdate = '2026-10-01'
     AND hour(from_unixtime(inserttimestamp)) = 0
   GROUP BY ioc, manage) t
GROUP BY domain, devid
ORDER BY domain_num DESC
LIMIT 100000;

-- 黑文件
SELECT md5,
       count(1) AS md5_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT lower(get_json_object(str10_tmp, '$.filemd5')) AS md5,
          get_json_object(str10_tmp, '$.info.attr') AS attr,
          str2 AS devid
   FROM csc.ods_csc_log_audit,
        unnest(ifnull(cast(parse_json(regexp_replace(str10, '\\\\+"', '"')) AS ARRAY<JSON>), [])) AS str10_tbl(str10_tmp)
   WHERE app_id = 'analysis-proxy-api'
     AND module_id IN ('file_hash', 'file_scan')
     AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
                  'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
                  'EDR_CLOUD_IDENTIFY', 'EDR_PK')
     AND long1 = 0
     AND day = 20261001
     AND hour = 0) a
WHERE md5 IS NOT NULL
  AND md5 NOT IN ('', '-')
  AND attr = '0'
GROUP BY md5, devid
ORDER BY md5_num DESC
LIMIT 100000;

-- 黑 URL
SELECT url,
       sum(url_num) AS url_num,
       count(DISTINCT devid) AS device_num
FROM
  (SELECT url,
          devid,
          count(1) AS url_num
   FROM
     (SELECT lower(get_json_object(str10_tmp, '$.url')) AS url,
             str2 AS devid
      FROM csc.ods_csc_log_audit,
           unnest(ifnull(cast(parse_json(regexp_replace(str10, '\\\\+"', '"')) AS ARRAY<JSON>), [])) AS str10_tbl(str10_tmp)
      WHERE app_id IN ('url-proxy-svc', 'cloudcheck')
        AND module_id IN ('url-proxy-svc', 'CloudCheck')
        AND str1 IN ('VNGAF', 'NGAF', 'EDR', 'EDR_BOTNET', 'SIP', 'SIP_SMTP', 'SIP_SMB',
                     'AC', 'VAC', 'CWPP', 'SASE', 'EDR_WEBSITE', 'EDR_NPE',
                     'EDR_CLOUD_IDENTIFY', 'EDR_PK')
        AND long1 = 0
        AND get_json_object(str10_tmp, '$.info.attr') = '0'
        AND day = 20261001
        AND hour = 0) a
   WHERE url IS NOT NULL
     AND url NOT IN ('', '-')
   GROUP BY url, devid

   UNION ALL

   SELECT url,
          manage AS devid,
          sum(log_num) AS url_num
   FROM sodl.network_security_log
   WHERE url IS NOT NULL
     AND url NOT IN ('', '-')
     AND insertdate = '2026-10-01'
     AND hour(from_unixtime(inserttimestamp)) = 0
   GROUP BY url, manage

   UNION ALL

   SELECT ioc AS url,
          manage AS devid,
          sum(record_count) AS url_num
   FROM sodl.sip_iocstat_log
   WHERE ioc_type = 'url'
     AND ioc IS NOT NULL
     AND ioc NOT IN ('', '-')
     AND insertdate = '2026-10-01'
     AND hour(from_unixtime(inserttimestamp)) = 0
   GROUP BY ioc, manage) t
GROUP BY url, devid
ORDER BY url_num DESC
LIMIT 100000;
