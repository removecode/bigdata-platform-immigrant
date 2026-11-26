-- 业务：domain-heat-stats-cron-job / cloud_domain.sql（云服务域名热度，深圳产品线）
-- 旧语句：sodl.dwb_sodl_domain_info，WHERE DAY =:day_str
-- 新语句：合并表 paimon.ti.dwb_ti_domain_info（DEC-026/027）
-- 注意：未加 src_log 过滤，见 outputs 说明；day 为 BIGINT，直接与数字比较。
SELECT /*+ SET_VAR(new_planner_optimize_timeout = 60000) */
    domain,
    sum(log_sum) AS log_cnt,
    count(DISTINCT manage) AS dev_cnt
FROM (
    SELECT
        domain,
        manage,
        sum(log_num) AS log_sum
    FROM paimon.ti.dwb_ti_domain_info
    WHERE `day` = 20261101
      AND substring_index(domain, '.', -2) IN (
          'amazonaws.com', 'myqcloud.com', 'aliyuncs.com', 'myhuaweicloud.com',
          'vercel.app', 'netlify.app', 'glitch.me', 'edgeone.app'
      )
    GROUP BY domain, manage
) t
GROUP BY domain;
