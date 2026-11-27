-- 了解 paimon.ti.dwb_ti_* 合并宽表所需的全部查询（DEC-027 之后）。
-- 每条只读，带 SET_VAR(new_planner_optimize_timeout = 30000)，不含百分号格式串。
-- 时间窗口：@dwb 1/2 用 day 区间；其余用单日 day = 20261101（与 ACT-079/081/082 同一天），可整体替换。
-- day 是 BIGINT，比较直接用数字；src_log 是 VARCHAR。
-- 先跑 @dwb 0 的 SHOW，再按顺序往下；@dwb 8、@dwb 10 较重，放最后。

-- @dwb 0a | 有哪些 catalog / 库 / 表（确认旧表还在不在、audit 表叫什么）
SHOW CATALOGS;
-- @dwb 0b
SHOW DATABASES FROM paimon;
-- @dwb 0c
SHOW TABLES FROM paimon.ti;
-- @dwb 0d
SHOW TABLES FROM paimon.csc;
-- @dwb 0e（旧 DWB 在内部 catalog 里是否还在：sodl.dwb_sodl_*、default.dwb_*）
SHOW TABLES FROM sodl;
-- @dwb 0f
SHOW DATABASES;

-- @dwb 1 | 四张表：最近一周每个 src_log 每天行数（有哪些来源、每天多大）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'domain' AS tbl, src_log, day, count(1) AS row_cnt
FROM paimon.ti.dwb_ti_domain_info
WHERE day BETWEEN 20261026 AND 20261101
GROUP BY src_log, day
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'ip' AS tbl, src_log, day, count(1) AS row_cnt
FROM paimon.ti.dwb_ti_ip_info
WHERE day BETWEEN 20261026 AND 20261101
GROUP BY src_log, day
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'md5' AS tbl, src_log, day, count(1) AS row_cnt
FROM paimon.ti.dwb_ti_md5_info
WHERE day BETWEEN 20261026 AND 20261101
GROUP BY src_log, day
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'url' AS tbl, src_log, day, count(1) AS row_cnt
FROM paimon.ti.dwb_ti_url_info
WHERE day BETWEEN 20261026 AND 20261101
GROUP BY src_log, day
ORDER BY tbl, src_log, day;

-- @dwb 2 | 四张表：src_log 全集与有数据的日期范围（从 2026-10-01 起）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'domain' AS tbl, src_log, min(day) AS min_day, max(day) AS max_day, count(DISTINCT day) AS day_cnt
FROM paimon.ti.dwb_ti_domain_info
WHERE day >= 20261001
GROUP BY src_log
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'ip' AS tbl, src_log, min(day), max(day), count(DISTINCT day)
FROM paimon.ti.dwb_ti_ip_info
WHERE day >= 20261001
GROUP BY src_log
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'md5' AS tbl, src_log, min(day), max(day), count(DISTINCT day)
FROM paimon.ti.dwb_ti_md5_info
WHERE day >= 20261001
GROUP BY src_log
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'url' AS tbl, src_log, min(day), max(day), count(DISTINCT day)
FROM paimon.ti.dwb_ti_url_info
WHERE day >= 20261001
GROUP BY src_log
ORDER BY tbl, src_log;

-- @dwb 3a | domain：每个 src_log 各列非空数（row_key 是否有值、threatclass 等是否只有 sodl 来源才有）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    src_log,
    count(1) AS row_cnt,
    count(domain) AS domain_nn,
    count(row_key) AS row_key_nn,
    sum(if(row_key = '', 1, 0)) AS row_key_empty,
    count(manage) AS manage_nn,
    count(producttype) AS producttype_nn,
    count(threatclass) AS threatclass_nn,
    count(reqruleid) AS reqruleid_nn,
    count(srcip) AS srcip_nn,
    count(dstip) AS dstip_nn,
    count(family) AS family_nn,
    count(category) AS category_nn,
    count(attr) AS attr_nn,
    count(add_time) AS add_time_nn,
    count(engine) AS engine_nn,
    count(action) AS action_nn,
    count(tenant) AS tenant_nn,
    count(agentid) AS agentid_nn
FROM paimon.ti.dwb_ti_domain_info
WHERE day = 20261101
GROUP BY src_log
ORDER BY src_log;

-- @dwb 3b | ip
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    src_log,
    count(1) AS row_cnt,
    count(manage) AS manage_nn,
    count(producttype) AS producttype_nn,
    count(srcip) AS srcip_nn,
    count(dstip) AS dstip_nn,
    sum(if(dstip = '', 1, 0)) AS dstip_empty,
    count(dstport) AS dstport_nn,
    count(object) AS object_nn,
    count(direction) AS direction_nn,
    count(threatclass) AS threatclass_nn,
    count(reqruleid) AS reqruleid_nn,
    count(family) AS family_nn,
    count(category) AS category_nn,
    count(attr) AS attr_nn,
    count(engine) AS engine_nn,
    count(action) AS action_nn,
    count(add_time) AS add_time_nn,
    count(tenant) AS tenant_nn,
    count(agentid) AS agentid_nn
FROM paimon.ti.dwb_ti_ip_info
WHERE day = 20261101
GROUP BY src_log
ORDER BY src_log;

-- @dwb 3c | md5
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    src_log,
    count(1) AS row_cnt,
    count(filehash) AS filehash_nn,
    sum(if(length(filehash) = 32, 1, 0)) AS filehash_len32,
    count(manage) AS manage_nn,
    count(producttype) AS producttype_nn,
    count(file_attr) AS file_attr_nn,
    count(file_type) AS file_type_nn,
    count(source_type) AS source_type_nn,
    count(type) AS type_nn,
    count(family) AS family_nn,
    count(platform) AS platform_nn,
    count(upload_source) AS upload_source_nn,
    count(virus_name_hash) AS virus_name_hash_nn,
    count(threatclass) AS threatclass_nn,
    count(reqruleid) AS reqruleid_nn,
    count(srcip) AS srcip_nn,
    count(dstip) AS dstip_nn,
    count(engine) AS engine_nn,
    count(tenant) AS tenant_nn,
    count(agentid) AS agentid_nn
FROM paimon.ti.dwb_ti_md5_info
WHERE day = 20261101
GROUP BY src_log
ORDER BY src_log;

-- @dwb 3d | url
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    src_log,
    count(1) AS row_cnt,
    count(url) AS url_nn,
    count(raw_url) AS raw_url_nn,
    count(manage) AS manage_nn,
    count(producttype) AS producttype_nn,
    count(category) AS category_nn,
    count(family) AS family_nn,
    count(add_time) AS add_time_nn,
    count(action) AS action_nn,
    count(threatclass) AS threatclass_nn,
    count(reqruleid) AS reqruleid_nn,
    count(srcip) AS srcip_nn,
    count(dstip) AS dstip_nn,
    count(engine) AS engine_nn,
    count(tenant) AS tenant_nn
FROM paimon.ti.dwb_ti_url_info
WHERE day = 20261101
GROUP BY src_log
ORDER BY src_log;

-- @dwb 4 | 四张表：producttype 取值（旧消费者按 'AF'、'EDR' 等过滤）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'domain' AS tbl, src_log, producttype, count(1) AS row_cnt
FROM paimon.ti.dwb_ti_domain_info
WHERE day = 20261101
GROUP BY src_log, producttype
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'ip' AS tbl, src_log, producttype, count(1)
FROM paimon.ti.dwb_ti_ip_info
WHERE day = 20261101
GROUP BY src_log, producttype
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'md5' AS tbl, src_log, producttype, count(1)
FROM paimon.ti.dwb_ti_md5_info
WHERE day = 20261101
GROUP BY src_log, producttype
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'url' AS tbl, src_log, producttype, count(1)
FROM paimon.ti.dwb_ti_url_info
WHERE day = 20261101
GROUP BY src_log, producttype
ORDER BY tbl, src_log, producttype;

-- @dwb 5 | md5：file_attr / upload_source / type 取值（旧 attr、source 的去向）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    src_log, file_attr, upload_source, source_type, type, count(1) AS row_cnt
FROM paimon.ti.dwb_ti_md5_info
WHERE day = 20261101
GROUP BY src_log, file_attr, upload_source, source_type, type
ORDER BY row_cnt DESC
LIMIT 200;

-- @dwb 6 | ip / domain：attr、direction、object、action 取值
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'ip' AS tbl, src_log, attr, direction, object, action, count(1) AS row_cnt
FROM paimon.ti.dwb_ti_ip_info
WHERE day = 20261101
GROUP BY src_log, attr, direction, object, action
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'domain' AS tbl, src_log, attr, NULL, NULL, action, count(1)
FROM paimon.ti.dwb_ti_domain_info
WHERE day = 20261101
GROUP BY src_log, attr, action
ORDER BY row_cnt DESC
LIMIT 200;

-- @dwb 7 | 旧消费者过滤条件在合并表上各命中多少行（0 说明 src_log 或字段口径变了）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'ctig_domain_af_net_rule14' AS rule_name, count(1) AS row_cnt
FROM paimon.ti.dwb_ti_domain_info
WHERE day = 20261101 AND row_key != '' AND producttype = 'AF'
  AND src_log = 'network_security_log'
  AND reqruleid BETWEEN '140000000' AND '149999999'
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'ctig_ip_af_net_rule14', count(1)
FROM paimon.ti.dwb_ti_ip_info
WHERE day = 20261101 AND producttype = 'AF'
  AND src_log = 'network_security_log'
  AND reqruleid BETWEEN '140000000' AND '149999999'
  AND dstip != ''
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'black_ti_ip_src_sip_or_net', count(1)
FROM paimon.ti.dwb_ti_ip_info
WHERE day = 20261101
  AND src_log IN ('sip_iocstat_log', 'network_security_log')
  AND dstip != ''
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'black_ti_domain_row_key_nonempty', count(1)
FROM paimon.ti.dwb_ti_domain_info
WHERE day = 20261101 AND row_key != ''
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'black_ti_md5_edr_file_attr0', count(1)
FROM paimon.ti.dwb_ti_md5_info
WHERE day = 20261101
  AND src_log = 'endpoint_security_log' AND file_attr = '0'
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'black_ti_md5_old_log_audit_file_hash_attr0', count(1)
FROM paimon.ti.dwb_ti_md5_info
WHERE day = 20261101
  AND src_log = 'log_audit' AND upload_source = 'file_hash' AND file_attr = '0'
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'black_file_clean_edr', count(1)
FROM paimon.ti.dwb_ti_md5_info
WHERE day = 20261101
  AND producttype = 'EDR' AND src_log = 'endpoint_security_log'
  AND threatclass = 209 AND threattype != 13
  AND file_attr = '0' AND length(filehash) = 32
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'black_file_clean_old_log_audit', count(1)
FROM paimon.ti.dwb_ti_md5_info
WHERE day = 20261101
  AND src_log = 'log_audit' AND file_attr = '0' AND length(filehash) = 32
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'domain_hit_devnum_old_log_audit', count(1)
FROM paimon.ti.dwb_ti_domain_info
WHERE day = 20261101 AND src_log = 'log_audit'
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'apt_old_ip_log_audit', count(1)
FROM paimon.ti.dwb_ti_ip_info
WHERE day = 20261101 AND src_log = 'log_audit';

-- @dwb 8 | 各 src_log 各取 2 行样例（较重：对一天的数据做窗口排序）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */ *
FROM (
  SELECT t.*, row_number() OVER (PARTITION BY src_log ORDER BY manage) AS rn
  FROM paimon.ti.dwb_ti_domain_info t
  WHERE day = 20261101
) a
WHERE rn <= 2
ORDER BY src_log, rn;

-- @dwb 8b
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */ *
FROM (
  SELECT t.*, row_number() OVER (PARTITION BY src_log ORDER BY manage) AS rn
  FROM paimon.ti.dwb_ti_ip_info t
  WHERE day = 20261101
) a
WHERE rn <= 2
ORDER BY src_log, rn;

-- @dwb 8c
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */ *
FROM (
  SELECT t.*, row_number() OVER (PARTITION BY src_log ORDER BY manage) AS rn
  FROM paimon.ti.dwb_ti_md5_info t
  WHERE day = 20261101
) a
WHERE rn <= 2
ORDER BY src_log, rn;

-- @dwb 8d
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */ *
FROM (
  SELECT t.*, row_number() OVER (PARTITION BY src_log ORDER BY manage) AS rn
  FROM paimon.ti.dwb_ti_url_info t
  WHERE day = 20261101
) a
WHERE rn <= 2
ORDER BY src_log, rn;

-- @dwb 9 | 单日规模：行数、设备数、业务键去重数（domain-heat、black-ti 的聚合量级）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'domain' AS tbl, count(1) AS row_cnt, count(DISTINCT manage) AS dev_cnt,
    count(DISTINCT domain) AS key_cnt, sum(log_num) AS sum_log_num, sum(attack_count) AS sum_attack_count
FROM paimon.ti.dwb_ti_domain_info
WHERE day = 20261101
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'ip', count(1), count(DISTINCT manage), count(DISTINCT dstip), sum(log_num), sum(attack_count)
FROM paimon.ti.dwb_ti_ip_info
WHERE day = 20261101
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'md5', count(1), count(DISTINCT manage), count(DISTINCT filehash), sum(log_num), sum(attack_count)
FROM paimon.ti.dwb_ti_md5_info
WHERE day = 20261101
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'url', count(1), count(DISTINCT manage), count(DISTINCT url), sum(log_num), sum(attack_count)
FROM paimon.ti.dwb_ti_url_info
WHERE day = 20261101;

-- @dwb 10 | 粒度是否重复：同一组合下出现多行的组数（>0 说明表里还有未合并的重复行；较重）
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'domain' AS tbl, count(1) AS dup_group_cnt
FROM (
  SELECT 1
  FROM paimon.ti.dwb_ti_domain_info
  WHERE day = 20261101
  GROUP BY src_log, producttype, manage, productver, domain, engine, srcip, dstip,
           reqruleid, row_key, family, category, attr, threatclass, threattype, threatsubtype, action
  HAVING count(1) > 1
) x
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'ip' AS tbl, count(1)
FROM (
  SELECT 1
  FROM paimon.ti.dwb_ti_ip_info
  WHERE day = 20261101
  GROUP BY src_log, producttype, manage, productver, srcip, dstip, dstport, engine,
           object, direction, reqruleid, family, category, attr, threatclass, threattype, threatsubtype, action
  HAVING count(1) > 1
) x
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'md5' AS tbl, count(1)
FROM (
  SELECT 1
  FROM paimon.ti.dwb_ti_md5_info
  WHERE day = 20261101
  GROUP BY src_log, producttype, manage, productver, filehash, srcip, dstip, reqruleid, engine,
           file_attr, file_type, source_type, type, family, platform, upload_source,
           threatclass, threattype, threatsubtype
  HAVING count(1) > 1
) x
UNION ALL
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 30000) */
    'url' AS tbl, count(1)
FROM (
  SELECT 1
  FROM paimon.ti.dwb_ti_url_info
  WHERE day = 20261101
  GROUP BY src_log, producttype, manage, productver, url, raw_url, engine, srcip, dstip,
           reqruleid, category, family, threatclass, threattype, threatsubtype, action
  HAVING count(1) > 1
) x;
