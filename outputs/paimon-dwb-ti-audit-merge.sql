-- 用户提供的统一 TI 中间表（Paimon）建表 + audit 侧写入 SQL 快照
-- 用途：新旧 DWB 合并目标表；本条只含 audit/proxy 分支 INSERT，不含 sodl ODS 分支 UNION
-- 占位：${hivevar:mday} 为分区日（bigint yyyyMMdd）
-- 来源：用户 2026-11-25 粘贴；归档 outputs/paimon-dwb-ti-audit-merge.sql

-- =============================================================================
-- IP
-- =============================================================================
CREATE DATABASE IF NOT EXISTS paimon.ti;

CREATE TABLE IF NOT EXISTS paimon.ti.dwb_ti_ip_info (
    threatclass       int,
    threattype        int,
    threatsubtype     int,
    producttype       string,
    manage            string,
    productver        string,
    srcip             string,
    dstip             string,
    engine            string,
    object            string,
    direction         string,
    reqruleid         string,
    action            int,
    agentid           string,
    tenant            string,
    dstport           int,
    family            string,
    category          string,
    attr              string,
    add_time          string,
    log_num           bigint,
    attack_count      bigint,
    `day`             bigint,
    src_log           string
)
USING paimon
PARTITIONED BY (`day`, src_log)
TBLPROPERTIES (
    'connector'                               = 'paimon',
    'file.format'                             = 'orc',
    'partition.timestamp-formatter'           = 'yyyyMMdd',
    'partition.timestamp-pattern'             = '$day',
    'bucket'                                  = '-1',
    'partition.expiration-time'               = '180 d',
    'partition.expiration-check-interval'     = '1 d',
    'snapshot.num-retained.min'               = '3',
    'snapshot.num-retained.max'               = '5',
    'snapshot.expire.clean-empty-directories' = 'true'
);

CALL paimon.sys.expire_partitions('paimon.ti.dwb_ti_ip_info');

INSERT OVERWRITE TABLE paimon.ti.dwb_ti_ip_info PARTITION (`day`, src_log='ip-proxy-svc')
SELECT NULL AS threatclass,
       NULL AS threattype,
       NULL AS threatsubtype,
       prod AS producttype,
       devid AS manage,
       dev_version AS productver,
       NULL AS srcip,
       ip AS dstip,
       `engine`,
       `object`,
       direction,
       NULL AS reqruleid,
       NULL AS action,
       NULL AS agentid,
       NULL AS tenant,
       port AS dstport,
       family,
       category,
       attr,
       NULL AS add_time,
       count(1) AS log_num,
       count(1) AS attack_count,
       cast(${hivevar:mday} AS bigint) AS `day`
FROM
  (SELECT split(ip_raw, ':')[0] AS ip,
          str1 AS prod,
          str2 AS devid,
          str3 AS dev_version,
          str5 AS `engine`,
          `object`,
          direction,
          attr,
          split(ip_raw, ':')[1] AS port,
          category,
          (CASE
               WHEN str6 = '[contextThreat network location asn context]'
                   THEN if(family_raw IS NOT NULL, family_raw, behavior_raw)
               WHEN str6='[threat network]'
                   THEN if(direction = '2', family_raw, behavior_raw)
           END) AS family
   FROM
     (SELECT str1, str2, str3, str5, str6,
             rec.ip AS ip_raw,
             rec.threat.object AS `object`,
             rec.threat.direction AS direction,
             rec.threat.reputation AS attr,
             rec.threat.threatLabels[0].category AS category,
             rec.threat.threatLabels[0].family AS family_raw,
             rec.threat.threatLabels[0].behavior AS behavior_raw
      FROM paimon.csc.ods_csc_log_audit_tmp
      LATERAL VIEW EXPLODE(from_json(regexp_replace(str10, '[\\\\]+"', '"'), 'array<struct<ip:string,threat:struct<object:string,direction:string,reputation:string,threatLabels:array<struct<category:string,family:string,behavior:string,familyDescription:string,source:string>>>>>')) rec_tbl AS rec
      WHERE app_id='ip-proxy-svc'
        AND module_id='ip-proxy-svc'
        AND str6 = '[contextThreat network location asn context]'
        AND `day` = ${hivevar:mday}
     ) ctx
   UNION ALL
   SELECT split(ip_raw, ':')[0] AS ip,
          str1 AS prod,
          str2 AS devid,
          str3 AS dev_version,
          str5 AS `engine`,
          `object`,
          direction,
          attr,
          split(ip_raw, ':')[1] AS port,
          category,
          (CASE
               WHEN direction = '2' THEN family_raw
               ELSE behavior_raw
           END) AS family
   FROM
     (SELECT str1, str2, str3, str5, str6,
             rec.ip AS ip_raw,
             rec.threat.object AS `object`,
             rec.threat.direction AS direction,
             rec.threat.reputation AS attr,
             rec.threat.threatLabels.ip[0].category AS category,
             rec.threat.threatLabels.ip[0].family AS family_raw,
             rec.threat.threatLabels.ip[0].behavior AS behavior_raw
      FROM paimon.csc.ods_csc_log_audit_tmp
      LATERAL VIEW EXPLODE(from_json(regexp_replace(str10, '[\\\\]+"', '"'), 'array<struct<ip:string,threat:struct<object:string,direction:string,reputation:string,threatLabels:struct<ip:array<struct<category:string,family:string,behavior:string,familyDescription:string,source:string>>,port:array<struct<category:string,family:string,behavior:string,familyDescription:string,source:string>>>>>>')) rec_tbl AS rec
      WHERE app_id='ip-proxy-svc'
        AND module_id='ip-proxy-svc'
        AND str6 = '[threat network]'
        AND `day` = ${hivevar:mday}
     ) net
  ) t
WHERE ip IS NOT NULL
  AND ip NOT IN ('', '-')
GROUP BY ip, prod, devid, dev_version, `engine`, attr, category, family, `object`, direction, port;

-- =============================================================================
-- DOMAIN
-- =============================================================================
CREATE DATABASE IF NOT EXISTS paimon.ti;

CREATE TABLE IF NOT EXISTS paimon.ti.dwb_ti_domain_info (
    threatclass       int,
    threattype        int,
    threatsubtype     int,
    producttype       string,
    manage            string,
    productver        string,
    domain            string,
    engine            string,
    srcip             string,
    dstip             string,
    reqruleid         string,
    row_key           string,
    family            string,
    category          string,
    attr              string,
    add_time          string,
    action            int,
    agentid           string,
    tenant            string,
    log_num           bigint,
    attack_count      bigint,
    `day`             bigint,
    src_log           string
)
USING paimon
PARTITIONED BY (`day`, src_log)
TBLPROPERTIES (
    'connector'                               = 'paimon',
    'file.format'                             = 'orc',
    'partition.timestamp-formatter'           = 'yyyyMMdd',
    'partition.timestamp-pattern'             = '$day',
    'bucket'                                  = '-1',
    'partition.expiration-time'               = '180 d',
    'partition.expiration-check-interval'     = '1 d',
    'snapshot.num-retained.min'               = '3',
    'snapshot.num-retained.max'               = '5',
    'snapshot.expire.clean-empty-directories' = 'true'
);

CALL paimon.sys.expire_partitions('paimon.ti.dwb_ti_domain_info');

INSERT OVERWRITE TABLE paimon.ti.dwb_ti_domain_info PARTITION (`day`, src_log='domain-proxy-svc')
SELECT NULL AS threatclass,
       NULL AS threattype,
       NULL AS threatsubtype,
       prod AS producttype,
       devid AS manage,
       dev_version AS productver,
       `domain`,
       `engine`,
       NULL AS srcip,
       NULL AS dstip,
       NULL AS reqruleid,
       NULL AS row_key,
       family,
       category,
       attr,
       NULL AS add_time,
       NULL AS action,
       NULL AS agentid,
       NULL AS tenant,
       count(1) AS log_num,
       count(1) AS attack_count,
       cast(${hivevar:mday} AS bigint) AS `day`
FROM
  (SELECT rec.`domain` AS `domain`,
          str1 AS prod,
          str2 AS devid,
          str3 AS dev_version,
          str5 AS `engine`,
          rec.threat.reputation AS attr,
          rec.threat.threatLabels[0].category AS category,
          rec.threat.threatLabels[0].family AS family
   FROM paimon.csc.ods_csc_log_audit_longterm
   LATERAL VIEW EXPLODE(from_json(regexp_replace(str10, '[\\\\]+"', '"'), 'array<struct<domain:string,threat:struct<reputation:string,threatLabels:array<struct<category:string,family:string,behavior:string,familyDescription:string,source:string>>>>>')) rec_tbl AS rec
   WHERE app_id='domain-proxy-svc'
     AND module_id='domain-proxy-svc'
     AND `day` = ${hivevar:mday} ) t
WHERE `domain` IS NOT NULL
  AND `domain` NOT IN ('', '-')
GROUP BY `domain`, prod, devid, dev_version, `engine`, attr, category, family;

-- =============================================================================
-- MD5
-- =============================================================================
CREATE DATABASE IF NOT EXISTS paimon.ti;

CREATE TABLE IF NOT EXISTS paimon.ti.dwb_ti_md5_info (
    threatclass       int,
    threattype        int,
    threatsubtype     int,
    producttype       string,
    manage            string,
    productver        string,
    filehash          string,
    srcip             string,
    dstip             string,
    reqruleid         string,
    engine            string,
    tenant            string,
    agentid           string,
    file_attr         string,
    file_type         string,
    source_type       string,
    type              string,
    family            string,
    platform          string,
    upload_source     string,
    virus_name_hash   string,
    log_num           bigint,
    attack_count      bigint,
    `day`             bigint,
    src_log           string
)
USING paimon
PARTITIONED BY (`day`, src_log)
TBLPROPERTIES (
    'connector'                               = 'paimon',
    'file.format'                             = 'orc',
    'partition.timestamp-formatter'           = 'yyyyMMdd',
    'partition.timestamp-pattern'             = '$day',
    'bucket'                                  = '-1',
    'partition.expiration-time'               = '180 d',
    'partition.expiration-check-interval'     = '1 d',
    'snapshot.num-retained.min'               = '3',
    'snapshot.num-retained.max'               = '5',
    'snapshot.expire.clean-empty-directories' = 'true'
);

CALL paimon.sys.expire_partitions('paimon.ti.dwb_ti_md5_info');

INSERT OVERWRITE TABLE paimon.ti.dwb_ti_md5_info PARTITION (`day`, src_log='analysis-proxy-api')
SELECT NULL AS threatclass,
       NULL AS threattype,
       NULL AS threatsubtype,
       prod AS producttype,
       devid AS manage,
       dev_version AS productver,
       filemd5 AS filehash,
       NULL AS srcip,
       NULL AS dstip,
       NULL AS reqruleid,
       NULL AS engine,
       NULL AS tenant,
       NULL AS agentid,
       attr AS file_attr,
       NULL AS file_type,
       NULL AS source_type,
       `type`,
       `family`,
       NULL AS platform,
       `source` AS upload_source,
       NULL AS virus_name_hash,
       count(1) AS log_num,
       count(1) AS attack_count,
       cast(${hivevar:mday} AS bigint) AS `day`
FROM
  (SELECT lower(rec.filemd5) AS filemd5,
          str1 AS prod,
          str2 AS devid,
          str3 AS dev_version,
          module_id AS `source`,
          rec.info.attr AS attr,
          rec.info.tags[0].type AS `type`,
          rec.info.tags[0].value AS family
   FROM paimon.csc.ods_csc_log_audit_longterm
   LATERAL VIEW EXPLODE(from_json(regexp_replace(str10, '[\\\\]+"', '"'), 'array<struct<filemd5:string,info:struct<attr:string,tags:array<struct<type:string,value:string,id:string>>>>>')) rec_tbl AS rec
   WHERE app_id = 'analysis-proxy-api'
     AND module_id IN ('file_hash', 'file_scan')
     AND `day` = ${hivevar:mday} )a
WHERE filemd5 IS NOT NULL
  AND filemd5 NOT IN ('', '-')
GROUP BY filemd5, prod, devid, dev_version, `source`, attr, `type`, family;