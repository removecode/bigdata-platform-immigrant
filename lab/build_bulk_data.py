#!/usr/bin/env python3
"""Build synthetic rows for the tables named in all.sql and load this lab.

The shapes follow the substituted Hive/Trino statements in /workspace/all.sql
and the DWB columns recorded in docs/迁移事项进度与决策追踪.md (ACT-027, ACT-028).
No new-platform table mapping was supplied with that SQL, so the physical
names stay as written there (DEC-013). This is local lab data only.

Reference day used by the SQL comments is 2026-10-02. Filters therefore
target windows such as 20260925-20261001, day 20260930 and day 20261001.
"""

from __future__ import annotations

import calendar
import json
import os
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path

import pymysql

ROOT = Path("/var/lib/lab/bulk")
ARTIFACT = Path("/opt/cursor/artifacts/bulk-load-results.txt")
AGO_TS = calendar.timegm((2026, 4, 2, 0, 0, 0))
AGO_OID = f"{AGO_TS:08x}{'0' * 16}"
DAYS7 = [20260925, 20260926, 20260927, 20260928, 20260929, 20260930, 20261001]
SLD = [f"brand{i}.com" for i in range(1, 81)]
CLOUD_SUFFIX = [
    "amazonaws.com",
    "myqcloud.com",
    "aliyuncs.com",
    "myhuaweicloud.com",
    "vercel.app",
    "netlify.app",
    "glitch.me",
    "edgeone.app",
]
VIRUS_PREFIX = [
    "Trojan",
    "Backdoor",
    "Worm",
    "Virus",
    "Rootkit",
    "Exploit",
    "Adware",
    "Ransom",
    "Spyware",
    "CoinMiner",
]
GOOD_THREAT = [(209, 1, 0), (208, 2, 0), (216, 1, 0), (214, 3, 0), (203, 1, 0), (40, 1, 0), (212, 10, 0)]
BAD_THREAT = [(30, 10, 0), (90, 5, 1), (94, 4, 1)]
INDUSTRY = ["金融", "教育", "制造", "医疗", "其他"]
PROVINCE = ["广东", "北京", "浙江", "四川"]
HIGH_RULES = ["HIGH1", "HIGH2", "HIGH3"]
LOW_RULES = ["LOW1", "LOW2", "LOW3"]


def hive_escape(value: object) -> str:
    text = "" if value is None else str(value)
    return (
        text.replace("\\", "\\\\")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
    )


class Sink:
    def __init__(self, qualified: str, columns: list[tuple[str, str, str]]) -> None:
        self.qualified = qualified
        self.db, self.table = qualified.split(".")
        self.columns = columns
        self.path = ROOT / self.db / self.table / "data.tsv"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._fh = self.path.open("w", encoding="utf-8")
        self.n = 0

    def add(self, values: dict[str, object]) -> None:
        row = []
        for name, hive_type, _sr in self.columns:
            if name in values:
                row.append(values[name])
            elif hive_type in {"INT", "BIGINT"}:
                row.append(0)
            else:
                row.append("")
        self._fh.write("\t".join(hive_escape(item) for item in row) + "\n")
        self.n += 1

    def close(self) -> None:
        self._fh.close()


def define() -> dict[str, list[tuple[str, str, str]]]:
    def cols(*items: str) -> list[tuple[str, str, str]]:
        parsed = []
        for item in items:
            name, hive_type = item.split(":")
            if hive_type == "INT":
                sr = "INT"
            elif hive_type == "BIGINT":
                sr = "BIGINT"
            elif hive_type == "TEXT":
                sr = "VARCHAR(65533)"
                hive_type = "STRING"
            else:
                sr = "VARCHAR(512)"
                hive_type = "STRING"
            parsed.append((name, hive_type, sr))
        return parsed

    domain_old = cols(
        "domain:STR", "devid:STR", "dev_version:STR", "dip:STR", "prod:STR", "src_log:STR",
        "log_num:BIGINT", "attack_count:BIGINT", "extends:STR", "row_key:STR", "family:STR",
        "category:STR", "add_time:STR", "city:STR", "province:STR", "country:STR", "industry:STR",
        "sub_industry:STR", "source:STR", "attr:STR", "day:INT",
    )
    domain_new = cols(
        "threatclass:INT", "threattype:INT", "threatsubtype:INT", "producttype:STR", "manage:STR",
        "productver:STR", "domain:STR", "engine:STR", "titype:INT", "srcip:STR", "dstip:STR",
        "reqruleid:STR", "row_key:STR", "family:STR", "category:STR", "add_time:STR",
        "log_num:BIGINT", "attack_count:BIGINT", "src_log:STR", "city:STR", "province:STR",
        "country:STR", "industry:STR", "sub_industry:STR", "action:INT", "day:INT",
    )
    ip_new = cols(
        "threatclass:INT", "threattype:INT", "threatsubtype:INT", "producttype:STR", "manage:STR",
        "productver:STR", "srcip:STR", "dstip:STR", "engine:STR", "titype:INT", "reqruleid:STR",
        "log_num:BIGINT", "attack_count:BIGINT", "src_log:STR", "city:STR", "province:STR",
        "country:STR", "industry:STR", "sub_industry:STR", "action:INT", "family:STR",
        "category:STR", "add_time:STR", "day:INT",
    )
    md5_old = cols(
        "md5:STR", "devid:STR", "dev_version:STR", "dip:STR", "prod:STR", "src_log:STR",
        "log_num:BIGINT", "attack_count:BIGINT", "extends:STR", "oid:STR", "file_attr:STR",
        "file_type:STR", "source_type:STR", "type:STR", "family:STR", "platform:STR",
        "upload_source:STR", "virus_name_hash:STR", "city:STR", "province:STR", "country:STR",
        "industry:STR", "sub_industry:STR", "source:STR", "attr:STR", "day:INT",
    )
    md5_new = cols(
        "threatclass:INT", "threattype:INT", "threatsubtype:INT", "producttype:STR", "manage:STR",
        "productver:STR", "filehash:STR", "dstip:STR", "reqruleid:STR", "engine:STR", "oid:STR",
        "file_attr:STR", "file_type:STR", "source_type:STR", "type:STR", "family:STR",
        "platform:STR", "upload_source:STR", "virus_name_hash:STR", "log_num:BIGINT",
        "attack_count:BIGINT", "src_log:STR", "city:STR", "province:STR", "country:STR",
        "industry:STR", "sub_industry:STR", "day:INT",
    )
    return {
        "csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync": cols(
            "ip:STR", "direction:STR", "reputation:STR", "port:INT", "expire_time:BIGINT", "deleted_time:BIGINT"
        ),
        "csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync": cols(
            "domain:STR", "labels:STR", "label_details:STR", "add_time:STR", "deleted_time:BIGINT", "reputation:STR"
        ),
        "csc.ods_csc_business_data": cols("str1:STR"),
        "csc.ods_csc_ioc_vertex": cols("key:STR", "graph_type:STR", "day:INT", "data_source:STR"),
        "csc.ods_csc_log_stats": cols(
            "day:INT", "app_id:STR", "str1:STR", "str2:STR", "str3:STR", "str4:STR", "str5:STR", "long1:BIGINT"
        ),
        "csc.ods_csc_tim_db_unknown_intelligence_tb_skyeye_ip_info_sync": cols("ip:STR", "update_time:BIGINT"),
        "default.log_audit_source": cols(
            "day:INT", "hour:INT", "log_app_id:STR", "module_id:STR", "str1:STR", "str2:STR",
            "str4:TEXT", "str5:STR", "str10:TEXT", "long1:BIGINT",
        ),
        "default.dwb_domain_info": domain_old,
        "default.dwb_md5_info": md5_old,
        "default.ods_custom_upload_data": cols("str1:STR", "part1:STR", "part2:STR"),
        "sodl.dwb_sodl_domain_info": domain_new,
        "sodl.dwb_sodl_ip_info": ip_new,
        "sodl.dwb_sodl_md5_info": md5_new,
        "sodl.network_security_log": cols(
            "day:INT", "hour:INT", "srcip:STR", "dstip:STR", "engine:STR", "severity:INT",
            "threatclass:INT", "threattype:INT", "threatsubtype:INT", "url:STR", "action:INT",
            "producttype:STR", "log_num:BIGINT", "manage:STR", "reqruleid:STR", "rulename:STR",
            "requesthead:TEXT", "requestbody:TEXT",
        ),
        "sodl.dns_log": cols("day:INT", "hour:INT", "queries:STR", "log_num:BIGINT", "producttype:STR", "qr:INT", "manage:STR"),
        "sodl.url_log": cols("day:INT", "hour:INT", "host:STR", "log_num:BIGINT", "producttype:STR", "manage:STR"),
        "sodl.sip_iocstat_log": cols(
            "day:INT", "hour:INT", "ioc:STR", "ioc_type:STR", "manage:STR", "record_count:BIGINT"
        ),
        "sodl.handle_info_log": cols(
            "filemd5:STR", "deviceid:STR", "virusname:STR", "inserttimestamp:BIGINT", "engineinfo:STR", "detectengine:STR"
        ),
        "sodl.operation_rdp_event_log": cols("businesstype:STR", "inserttimestamp:BIGINT", "businesscontent:TEXT"),
        "sri.ods_sri_hashinfo": cols(
            "virus_name:STR", "file_md5:STR", "oid:STR", "file_attr:INT", "platform:STR", "fdfs_path:STR", "file_size:STR"
        ),
        "business.ti_domain_reputation_info": cols(
            "domain:STR", "labels:STR", "threat_level:STR", "add_time:STR", "reputation:STR", "deleted_time:BIGINT"
        ),
        "business.ti_ip_reputation_info": cols(
            "ip:STR", "labels:STR", "threat_level:STR", "add_time:STR", "reputation:STR",
            "direction:STR", "port:INT", "deleted_time:BIGINT",
        ),
        "business.tb_tenant_subscribe_info": cols("tenant_id:STR", "device_id:STR"),
        "business.ti_network_security_log": cols(
            "manage:STR", "alarmdate:STR", "srcip:STR", "intelligence:STR", "alarmcount:BIGINT"
        ),
    }


def ip_of(segment: str, host: int) -> str:
    return f"{segment}.{host}"


def public_ip(index: int, first: int) -> str:
    third = (index // 200) % 250 + 1
    fourth = index % 200 + 2
    return f"{first}.40.{third}.{fourth}"


def json_ips(ips: list[str]) -> str:
    return json.dumps([{"ip": ip} for ip in ips], ensure_ascii=False, separators=(",", ":"))


def threat_blob(ips: list[str]) -> str:
    # Nested objects cannot be split on "},{" : that pattern consumes the outer
    # closing brace. The SQL also splits on ";", so complete objects are joined
    # that way and the "},{" rewrite becomes a no-op.
    parts = [
        json.dumps(
            {"ip": f"{ip}:8080", "threat": {"reputation": "2", "direction": "2"}},
            ensure_ascii=False,
            separators=(",", ":"),
        )
        for ip in ips
    ]
    return "[" + ";".join(parts) + "~]"


def request_head(kind: int, domain: str) -> str:
    if kind == 0:
        return f"GET /login?password=labpass{kind} HTTP/1.1\r\nUser-Agent: sqlmap/1.7\r\nHost: {domain}\r\n"
    if kind == 1:
        return f"GET /scan HTTP/1.1\r\nUser-Agent: nessus\r\nHost: {domain}\r\n"
    if kind == 2:
        return f"POST /cmd HTTP/1.1\r\nUser-Agent: mozilla\r\nHost: {domain}\r\n"
    return f"GET /index HTTP/1.1\r\nUser-Agent: browser\r\nHost: {domain}\r\n"


def build(sinks: dict[str, Sink]) -> None:
    keep = [f"45.10.{i}" for i in range(1, 61)] + [f"47.20.{i}" for i in range(1, 21)]
    block = [f"61.30.{i}" for i in range(1, 21)]
    real_devs = [f"dev{i:04d}" for i in range(1, 241)]
    test_devs = [f"testdev{i:03d}" for i in range(1, 31)]
    c2_ips = [public_ip(i, 101) for i in range(400)]
    atk_ips = [public_ip(i, 103) for i in range(500)]
    hit_domains = [f"hit{i}.visited.test" for i in range(1, 121)]
    black_domains = [f"black{i}.evil.test" for i in range(1, 81)]
    second_domains = [f"shop{j}.{sld}" for sld in SLD for j in range(1, 6)]
    third_domains = [f"leaf{j}.org{i}.com.cn" for i in range(1, 41) for j in range(1, 4)]
    third_domains += [f"leaf{j}.org{i}.org.cn" for i in range(1, 21) for j in range(1, 3)]
    cloud_domains = [f"app{i}.{suffix}" for suffix in CLOUD_SUFFIX for i in range(1, 16)]
    md5s = [f"{i:032x}" for i in range(1, 4001)]

    audit = sinks["default.log_audit_source"]
    for segment in keep + block:
        for day in DAYS7:
            for slot in range(12):
                hosts = [ip_of(segment, 10 + slot * 3 + offset) for offset in range(3)]
                audit.add({
                    "day": day,
                    "hour": slot % 24,
                    "log_app_id": "ip-proxy-svc",
                    "module_id": "ip-proxy-svc",
                    "str1": "NGAF",
                    "str2": real_devs[(slot + day) % len(real_devs)],
                    "str4": json_ips(hosts),
                    "str5": "[cf]",
                    "str10": threat_blob(hosts),
                    "long1": 1,
                })
    for i in range(3000):
        audit.add({
            "day": DAYS7[i % 7],
            "hour": i % 24,
            "log_app_id": "analysis-proxy-api",
            "module_id": "file_hash" if i % 2 == 0 else "other",
            "str1": "EDR",
            "str2": real_devs[i % len(real_devs)],
            "str4": "{}",
            "str5": "plain",
            "str10": json.dumps([{"filemd5": md5s[i % len(md5s)], "info": {"attr": "0"}}]),
            "long1": 1,
        })

    rep = sinks["csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync"]
    for segment in block:
        rep.add({
            "ip": ip_of(segment, 9),
            "direction": "2",
            "reputation": "0",
            "port": 80,
            "expire_time": 1790000000000,
            "deleted_time": 0,
        })
    for ip in c2_ips:
        rep.add({"ip": ip, "direction": "2", "reputation": "0", "port": 0, "expire_time": 1790000000000, "deleted_time": 0})
    for ip in atk_ips:
        rep.add({"ip": ip, "direction": "1", "reputation": "0", "port": 0, "expire_time": 1790000000000, "deleted_time": 0})
    for i in range(200):
        rep.add({
            "ip": public_ip(i, 110),
            "direction": "3",
            "reputation": "1",
            "port": 0,
            "expire_time": 1790000000000,
            "deleted_time": 1,
        })

    upload = sinks["default.ods_custom_upload_data"]
    for dev in test_devs:
        upload.add({"str1": dev, "part1": "test_dev", "part2": "test_devid"})
        upload.add({"str1": dev, "part1": "af_test_device_id", "part2": "attack_ip_analysis"})
    for rule in LOW_RULES:
        upload.add({"str1": rule, "part1": "af_rule_id", "part2": "low_trusted_ips_id" if rule != "LOW3" else "low_trusted_waf_id"})
    for rule in HIGH_RULES:
        upload.add({"str1": rule, "part1": "af_rule_id", "part2": "high_trusted_ips_id" if rule != "HIGH3" else "high_trusted_waf_id"})
    for ip in atk_ips[:15]:
        upload.add({"str1": ip, "part1": "attack_ip_analysis", "part2": "attack_ip_filter"})
    for i in range(1500):
        upload.add({"str1": f"other{i}", "part1": "unrelated", "part2": "noise"})

    old_domain = sinks["default.dwb_domain_info"]
    hit_days = list(range(20260902, 20260932)) + [20261001, 20261002]
    for domain_i, domain in enumerate(hit_domains):
        devices = real_devs[domain_i : domain_i + 12] + test_devs[:3]
        for dev_i, dev in enumerate(devices):
            for copy in range(8):
                old_domain.add({
                    "domain": domain,
                    "devid": dev,
                    "dev_version": "8.0",
                    "dip": public_ip(domain_i, 120),
                    "prod": "AF",
                    "src_log": "log_audit",
                    "log_num": 4,
                    "attack_count": 2,
                    "row_key": black_domains[domain_i] if domain_i < len(black_domains) else domain,
                    "family": "emotet",
                    "category": "trojan",
                    "add_time": "2026-09-01 00:00:00",
                    "city": "深圳",
                    "province": PROVINCE[domain_i % 4],
                    "country": "中国",
                    "industry": INDUSTRY[domain_i % 5],
                    "sub_industry": "lab",
                    "source": "labfeed",
                    "attr": "0",
                    "day": hit_days[(dev_i + copy) % len(hit_days)],
                })
    for i in range(400):
        old_domain.add({
            "domain": f"cold{i}.quiet.test",
            "devid": real_devs[i % 3],
            "log_num": 1,
            "row_key": f"cold{i}.quiet.test",
            "day": 20261001,
            "src_log": "log_audit",
        })

    new_domain = sinks["sodl.dwb_sodl_domain_info"]
    heat_rows = (
        [(domain, "second") for domain in second_domains]
        + [(domain, "third") for domain in third_domains]
        + [(domain, "cloud") for domain in cloud_domains]
    )
    for i, (domain, _kind) in enumerate(heat_rows):
        for manage_i in range(4):
            new_domain.add({
                "threatclass": 209,
                "threattype": 1,
                "producttype": "AF",
                "manage": real_devs[(i + manage_i) % len(real_devs)],
                "domain": domain,
                "engine": "af",
                "row_key": domain,
                "log_num": 8,
                "attack_count": 3,
                "src_log": "dns_log",
                "action": 2,
                "day": 20260930,
                "country": "中国",
                "province": PROVINCE[i % 4],
                "industry": INDUSTRY[i % 5],
            })
    for i, domain in enumerate(black_domains):
        for manage_i, manage in enumerate(real_devs[i : i + 6] + test_devs[:1]):
            new_domain.add({
                "threatclass": 208,
                "threattype": 2,
                "producttype": "NGAF",
                "manage": manage,
                "domain": domain,
                "engine": "af",
                "row_key": domain,
                "family": "emotet",
                "category": "trojan",
                "log_num": 6,
                "attack_count": 5,
                "src_log": "network_security_log",
                "action": 2,
                "day": 20261001,
                "country": "中国",
                "province": "广东",
                "industry": "金融",
            })
    for i in range(2000):
        new_domain.add({
            "domain": f"filler{i}.example.net",
            "manage": real_devs[i % len(real_devs)],
            "row_key": f"filler{i}.example.net",
            "log_num": 1,
            "day": DAYS7[i % 7],
            "threatclass": 40,
            "action": 2,
        })

    domain_rep = sinks["csc.ods_csc_db_domain_intelligence_tb_domain_reputation_sync"]
    for i, domain in enumerate(black_domains):
        domain_rep.add({
            "domain": domain,
            "labels": "category=trojan,family=emotet",
            "label_details": f"source=labfeed,rule=rule{i}",
            "add_time": "2026-08-01 00:00:00",
            "deleted_time": 0,
            "reputation": "0",
        })
    for i in range(150):
        domain_rep.add({
            "domain": f"gray{i}.example.net",
            "labels": "category=benign,family=none",
            "label_details": "source=other,rule=none",
            "add_time": "2026-08-02 00:00:00",
            "deleted_time": 1,
            "reputation": "2",
        })

    ip_info = sinks["sodl.dwb_sodl_ip_info"]
    for i, ip in enumerate(c2_ips):
        for manage_i in range(4):
            ip_info.add({
                "threatclass": GOOD_THREAT[i % len(GOOD_THREAT)][0],
                "threattype": 1,
                "producttype": "AF",
                "manage": real_devs[(i + manage_i) % len(real_devs)],
                "srcip": atk_ips[i % len(atk_ips)],
                "dstip": ip,
                "src_log": "network_security_log" if i % 2 == 0 else "sip_iocstat_log",
                "attack_count": 4,
                "log_num": 4,
                "action": 2,
                "day": 20261001,
                "country": "中国",
                "province": PROVINCE[i % 4],
                "industry": INDUSTRY[i % 5],
                "city": "深圳",
            })
    for i, ip in enumerate(atk_ips):
        ip_info.add({
            "threatclass": 209,
            "producttype": "AF",
            "manage": real_devs[i % len(real_devs)],
            "srcip": ip,
            "dstip": c2_ips[i % len(c2_ips)],
            "src_log": "network_security_log",
            "attack_count": 3,
            "action": 2,
            "day": 20261001,
            "country": "中国" if i % 5 else "",
            "province": PROVINCE[i % 4] if i % 5 else "",
            "industry": INDUSTRY[i % 5] if i % 4 else "",
        })
    for i in range(1500):
        ip_info.add({
            "dstip": "8.8.8.8",
            "srcip": "10.1.1.8",
            "manage": real_devs[i % 10],
            "src_log": "other",
            "attack_count": 1,
            "day": 20261001,
            "threatclass": 1,
        })

    net = sinks["sodl.network_security_log"]
    products = ["AF", "NGAF", "EDR"]
    for i in range(32000):
        matching = i % 10 != 0
        threat = GOOD_THREAT[i % len(GOOD_THREAT)] if matching else BAD_THREAT[i % len(BAD_THREAT)]
        src = atk_ips[i % len(atk_ips)] if matching else "10.9.8.7"
        dst = public_ip(i, 111) if matching else "192.168.1.9"
        rule = HIGH_RULES[i % 3] if i % 5 == 0 else (LOW_RULES[i % 3] if i % 11 == 0 else f"RULE{100 + (i % 60)}")
        domain = second_domains[i % len(second_domains)]
        kind = i % 4
        net.add({
            "day": 20261001 if i < 28000 else DAYS7[i % 7],
            "hour": i % 24,
            "srcip": src,
            "dstip": dst,
            "engine": "af" if matching else "premise_ioc",
            "severity": 75 if matching else 20,
            "threatclass": threat[0],
            "threattype": threat[1],
            "threatsubtype": threat[2],
            "url": f"http://{domain}/path/{i % 50}",
            "action": 2 if matching else 0,
            "producttype": products[i % 3],
            "log_num": (i % 7) + 1,
            "manage": test_devs[i % len(test_devs)] if i % 17 == 0 else real_devs[i % len(real_devs)],
            "reqruleid": rule,
            "rulename": f"detect CVE-2024-{(i % 4000) + 1000} lab",
            "requesthead": request_head(kind, domain),
            "requestbody": "os.system(id)" if kind == 2 else "ping",
        })

    dns = sinks["sodl.dns_log"]
    for i in range(8000):
        domain = second_domains[i % len(second_domains)] if i % 8 else "x"
        dns.add({
            "day": 20261001 if i < 7000 else DAYS7[i % 7],
            "hour": i % 24,
            "queries": domain,
            "log_num": (i % 9) + 1,
            "producttype": ["AF", "NGAF", "VNGAF"][i % 3] if i % 6 else "EDR",
            "qr": 0 if i % 5 else 1,
            "manage": real_devs[i % len(real_devs)],
        })

    url = sinks["sodl.url_log"]
    for i in range(6000):
        url.add({
            "day": 20261001 if i < 5000 else DAYS7[i % 7],
            "hour": i % 24,
            "host": cloud_domains[i % len(cloud_domains)] if i % 7 else "",
            "log_num": (i % 5) + 1,
            "producttype": ["AF", "NGAF", "VNGAF"][i % 3],
            "manage": real_devs[i % len(real_devs)],
        })

    sip = sinks["sodl.sip_iocstat_log"]
    for i in range(4000):
        sip.add({
            "day": 20261001 if i < 3500 else DAYS7[i % 7],
            "hour": i % 24,
            "ioc": black_domains[i % len(black_domains)] if i % 2 == 0 else f"http://{cloud_domains[i % len(cloud_domains)]}/a",
            "ioc_type": "domain" if i % 2 == 0 else "url",
            "manage": real_devs[i % len(real_devs)],
            "record_count": (i % 6) + 1,
        })

    old_md5 = sinks["default.dwb_md5_info"]
    new_md5 = sinks["sodl.dwb_sodl_md5_info"]
    for i, digest in enumerate(md5s):
        old_md5.add({
            "md5": digest,
            "devid": real_devs[i % len(real_devs)],
            "src_log": "log_audit" if i < 2500 else "other",
            "log_num": 2,
            "attack_count": 1,
            "oid": f"{(AGO_TS + 86400 * 100 + i):08x}{i:016x}",
            "file_attr": "0",
            "attr": "0" if i < 2500 else "1",
            "platform": "Android",
            "day": 20261001 if i < 3000 else 20260930,
            "source": "lab",
        })
        new_md5.add({
            "threatclass": 209 if i < 2500 else 13,
            "threattype": 1 if i % 9 else 13,
            "producttype": "EDR" if i < 2500 else "AF",
            "manage": real_devs[i % len(real_devs)],
            "filehash": digest,
            "src_log": "endpoint_security_log" if i < 2500 else "other",
            "file_attr": "0" if i < 2500 else "1",
            "log_num": 2,
            "attack_count": 1,
            "day": 20261001 if i < 3000 else 20260930,
            "oid": f"{(AGO_TS + 86400 * 100 + i):08x}{i:016x}",
        })

    hashinfo = sinks["sri.ods_sri_hashinfo"]
    business_data = sinks["csc.ods_csc_business_data"]
    for i, digest in enumerate(md5s):
        excluded = i % 8 == 0
        hashinfo.add({
            "virus_name": f"{VIRUS_PREFIX[i % len(VIRUS_PREFIX)]}.Android.Lab{i}",
            "file_md5": digest,
            "oid": f"{(AGO_TS + 86400 * 120 + i):08x}{i:016x}",
            "file_attr": 0 if i % 2 == 0 else 2,
            "platform": "Android" if i % 3 else "AndroidOS",
            "fdfs_path": f"/lab/fdfs/{digest}",
            "file_size": str(2048 + (i % 1000)),
        })
        if excluded:
            business_data.add({"str1": digest})
    for i in range(300):
        hashinfo.add({
            "virus_name": f"Benign.Lab{i}",
            "file_md5": f"{(5000 + i):032x}",
            "oid": f"{(AGO_TS - 10):08x}{i:016x}",
            "file_attr": 1,
            "platform": "Windows",
            "fdfs_path": "",
            "file_size": "0",
        })

    vertex = sinks["csc.ods_csc_ioc_vertex"]
    vertex_days = DAYS7 + [20260902, 20260909, 20260916, 20260923, 20260826, 20260819]
    for i, domain in enumerate(black_domains + second_domains[:400]):
        vertex.add({
            "key": domain,
            "graph_type": "Domain",
            "day": vertex_days[i % len(vertex_days)],
            "data_source": "af_dns" if i % 5 else "pdns",
        })
    for i, ip in enumerate(c2_ips + atk_ips[:200]):
        vertex.add({
            "key": ip,
            "graph_type": "IP",
            "day": vertex_days[i % len(vertex_days)],
            "data_source": "network" if i % 4 else "sip_dns",
        })

    stats = sinks["csc.ods_csc_log_stats"]
    for i in range(4000):
        day = DAYS7[i % 7]
        kind = i % 3
        if kind == 0:
            stats.add({
                "day": day, "app_id": "dns-intelligence-dispatch-prc", "str1": "cig_subscribe",
                "str2": "dl_dns_log", "str4": real_devs[i % len(real_devs)], "long1": (i % 5) + 1,
            })
        elif kind == 1:
            stats.add({
                "day": day, "app_id": "ip-realtime-identify-etl-prc", "str1": "etl_size",
                "str2": "kafka_poll_size", "str3": "CLOUD_INTELLIGENCE_GATEWAY",
                "str5": real_devs[i % len(real_devs)], "long1": (i % 4) + 1,
            })
        else:
            stats.add({
                "day": day, "app_id": "ip-realtime-identify-etl-prc", "str1": "filter_size",
                "str2": "valid_devid", "str3": "CLOUDCHECK_C2IP_CF",
                "str5": real_devs[i % len(real_devs)], "long1": (i % 3) + 1,
            })

    skyeye = sinks["csc.ods_csc_tim_db_unknown_intelligence_tb_skyeye_ip_info_sync"]
    now_ms = 1790901600000
    for i, ip in enumerate(atk_ips[:800]):
        skyeye.add({"ip": ip, "update_time": now_ms - i * 1000})
    for i in range(200):
        skyeye.add({"ip": public_ip(i, 118), "update_time": now_ms - 400 * 86400 * 1000})

    handle = sinks["sodl.handle_info_log"]
    base_ts = 1790900000
    for i in range(2000):
        handle.add({
            "filemd5": md5s[i % len(md5s)],
            "deviceid": real_devs[i % len(real_devs)],
            "virusname": f"{VIRUS_PREFIX[i % len(VIRUS_PREFIX)]}.Lab",
            "inserttimestamp": base_ts + (i % 7200),
            "engineinfo": "scan IsHotspot sample",
            "detectengine": "4" if i % 4 else "1",
        })

    rdp = sinks["sodl.operation_rdp_event_log"]
    for i in range(2000):
        ip = atk_ips[i % len(atk_ips)]
        content = json.dumps([{"ip": f"{ip}:{3389 + (i % 3)}"}], separators=(",", ":"))
        rdp.add({
            "businesstype": "21" if i % 5 else "1",
            "inserttimestamp": 1790901000 + (i % 500),
            "businesscontent": content,
        })

    biz_domain = sinks["business.ti_domain_reputation_info"]
    biz_ip = sinks["business.ti_ip_reputation_info"]
    for i, domain in enumerate(black_domains):
        biz_domain.add({
            "domain": domain,
            "labels": '{"category": "trojan", "family": "emotet"}',
            "threat_level": "3",
            "add_time": "20260801120000",
            "reputation": "0",
            "deleted_time": 0,
        })
    for ip in c2_ips:
        biz_ip.add({
            "ip": ip,
            "labels": '{"category": "c2", "family": "cobalt"}',
            "threat_level": "3",
            "add_time": "20260801120000",
            "reputation": "0",
            "direction": "2",
            "port": 0,
            "deleted_time": 0,
        })
    tenants = ["tenantA", "tenantB", "tenantC"]
    subscribe = sinks["business.tb_tenant_subscribe_info"]
    devices_by_tenant = {tenant: [f"{tenant}-dev{i}" for i in range(1, 9)] for tenant in tenants}
    for tenant, devices in devices_by_tenant.items():
        for device in devices:
            subscribe.add({"tenant_id": tenant, "device_id": device})
    blog = sinks["business.ti_network_security_log"]
    alarm_days = ["20260915", "20260920", "20260930", "20261001"]
    intel = black_domains[:40] + c2_ips[:40]
    for i in range(6000):
        tenant = tenants[i % 3]
        blog.add({
            "manage": devices_by_tenant[tenant][i % 8],
            "alarmdate": alarm_days[i % 4],
            "srcip": atk_ips[i % len(atk_ips)],
            "intelligence": intel[i % len(intel)],
            "alarmcount": (i % 5) + 1,
        })


def hive_ddl(sinks: dict[str, Sink]) -> str:
    lines = ["SET hive.stats.autogather=false;"]
    databases = sorted({sink.db for sink in sinks.values() if sink.db != "default"})
    for database in databases:
        lines.append(f"CREATE DATABASE IF NOT EXISTS {database};")
    for sink in sinks.values():
        body = ",\n  ".join(f"`{name}` {hive_type}" for name, hive_type, _sr in sink.columns)
        location = sink.path.parent.as_posix()
        lines.append(f"DROP TABLE IF EXISTS {sink.qualified};")
        lines.append(
            f"CREATE EXTERNAL TABLE {sink.qualified} (\n  {body}\n)\n"
            "ROW FORMAT DELIMITED FIELDS TERMINATED BY '\\t' ESCAPED BY '\\\\'\n"
            f"STORED AS TEXTFILE\nLOCATION 'file://{location}';"
        )
    return "\n".join(lines) + "\n"


def sr_ddl(sinks: dict[str, Sink]) -> list[str]:
    statements = []
    for database in sorted({sink.db for sink in sinks.values()}):
        statements.append(f"CREATE DATABASE IF NOT EXISTS `{database}`")
    for sink in sinks.values():
        body = ",\n  ".join(f"`{name}` {sr_type}" for name, _hive, sr_type in sink.columns)
        key = sink.columns[0][0]
        statements.append(f"DROP TABLE IF EXISTS `{sink.db}`.`{sink.table}`")
        statements.append(
            f"CREATE TABLE `{sink.db}`.`{sink.table}` (\n  {body}\n)\n"
            f"DUPLICATE KEY(`{key}`)\n"
            f"DISTRIBUTED BY HASH(`{key}`) BUCKETS 1\n"
            "PROPERTIES(\"replication_num\"=\"1\")"
        )
    return statements


def run_beeline(sql_path: Path) -> str:
    command = (
        "source /opt/lab/hive/conf/hive-env.sh && "
        "cd /tmp && /opt/lab/hive/bin/beeline -u 'jdbc:hive2://127.0.0.1:10000' "
        "--silent=true --showHeader=true --outputformat=tsv2 "
        f"-f {sql_path}"
    )
    completed = subprocess.run(["bash", "-lc", command], text=True, capture_output=True, check=False)
    output = (completed.stdout or "") + ("\n" + completed.stderr if completed.returncode else "")
    if completed.returncode != 0:
        raise RuntimeError(output[-4000:])
    return completed.stdout


def stream_load(sink: Sink, use_escape: bool = True) -> str:
    label = f"{sink.table}_{int(time.time())}_{sink.n}_{int(use_escape)}"
    url = f"http://127.0.0.1:8030/api/{sink.db}/{sink.table}/_stream_load"
    command = [
        "curl", "-sS", "--location-trusted", "-u", "root:",
        "-H", "Expect:100-continue",
        "-H", f"label:{label}",
        "-H", "column_separator:\t",
        "-H", "max_filter_ratio:0",
    ]
    if use_escape:
        command.extend(["-H", "escape:\\"])
    command.extend(["-T", str(sink.path), url])
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr or completed.stdout)
    payload = json.loads(completed.stdout)
    if payload.get("Status") not in {"Success", "Publish Timeout"}:
        if use_escape:
            return stream_load(sink, use_escape=False)
        raise RuntimeError(json.dumps(payload, ensure_ascii=False)[:2000])
    return f"{sink.qualified} loaded={payload.get('NumberLoadedRows')} filtered={payload.get('NumberFilteredRows')}"


def trino_count(sql: str) -> list[list[object]]:
    request = urllib.request.Request(
        "http://127.0.0.1:8080/v1/statement",
        data=sql.encode(),
        headers={"X-Trino-User": "lab", "Content-Type": "text/plain"},
        method="POST",
    )
    payload = json.load(urllib.request.urlopen(request, timeout=30))
    rows: list[list[object]] = []
    while True:
        if "error" in payload:
            raise RuntimeError(str(payload["error"])[:1500])
        rows.extend(payload.get("data") or [])
        url = payload.get("nextUri")
        if not url:
            return rows
        payload = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"X-Trino-User": "lab"}), timeout=60))


def main() -> None:
    if ROOT.exists():
        shutil.rmtree(ROOT)
    ROOT.mkdir(parents=True)
    sinks = {name: Sink(name, columns) for name, columns in define().items()}
    build(sinks)
    for sink in sinks.values():
        sink.close()
        print(f"wrote {sink.qualified} {sink.n} -> {sink.path}", flush=True)

    ddl_path = Path("/tmp/bulk_hive.sql")
    ddl_path.write_text(hive_ddl(sinks), encoding="utf-8")
    print("creating hive tables", flush=True)
    run_beeline(ddl_path)

    print("creating starrocks tables", flush=True)
    connection = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", autocommit=True)
    cursor = connection.cursor()
    for statement in sr_ddl(sinks):
        cursor.execute(statement)
    print("stream loading starrocks", flush=True)
    load_lines = []
    for sink in sinks.values():
        load_lines.append(stream_load(sink))
        print(load_lines[-1], flush=True)

    proofs = {
        "hive_filter_layout_kept_segments": """
SELECT count(*) AS kept,
       sum(CASE WHEN ip_c_seg LIKE '61.30.%' THEN 1 ELSE 0 END) AS blocked_remaining
FROM (
  WITH rpt AS (
    SELECT DISTINCT regexp_extract(ip, '^(\\\\d+\\\\.\\\\d+\\\\.\\\\d+)\\\\.', 1) AS ip_seg
    FROM csc.ods_csc_tim_db_intelligence_tb_ip_reputation_sync
    WHERE direction='2' AND reputation='0'
  ),
  resp_data AS (
    SELECT day AS date_day,
           split(get_json_object(resp, '$.ip'), ':')[0] AS ip,
           regexp_extract(split(get_json_object(resp, '$.ip'), ':')[0], '^(\\\\d+\\\\.\\\\d+\\\\.\\\\d+)\\\\.', 1) AS ip_c_seg
    FROM default.log_audit_source
    LATERAL VIEW explode(split(replace(regexp_replace(regexp_replace(regexp_replace(str10,'^\\\\[',''),'~\\\\]',''),'\\\\},\\\\{','\\\\;\\\\{'), '\\"', '"'), ';')) exploded_table AS resp
    WHERE log_app_id='ip-proxy-svc' AND day BETWEEN 20260925 AND 20261001
      AND module_id='ip-proxy-svc' AND str5 RLIKE 'cf'
      AND get_json_object(resp, '$.threat.reputation')='2'
      AND get_json_object(resp, '$.threat.direction')='2'
  ),
  agg_data AS (
    SELECT ip_c_seg, count(DISTINCT date_day) AS day_unique
    FROM resp_data
    GROUP BY ip_c_seg
  )
  SELECT ip_c_seg FROM agg_data
  WHERE day_unique >= 5
    AND NOT EXISTS (SELECT 1 FROM rpt WHERE rpt.ip_seg = agg_data.ip_c_seg)
) s
""",
        "hive_domain_heat_sld": """
SELECT count(*) AS sld_cnt
FROM (
  WITH t AS (
    SELECT domain, manage, sum(log_num) AS log_num
    FROM sodl.dwb_sodl_domain_info
    WHERE day=20260930 AND domain != '' AND locate(':', domain)=0 AND locate('_', domain)=0
      AND locate('*', domain)=0 AND domain NOT rlike '[0-9]$' AND domain NOT rlike '.arpa$'
    GROUP BY domain, manage
  ),
  t2 AS (
    SELECT substring_index(domain, '.', -2) AS sld, sum(log_num) AS log_sum
    FROM t GROUP BY substring_index(domain, '.', -2)
  )
  SELECT sld FROM t2 WHERE log_sum > 10
) s
""",
        "hive_domain_hit": """
SELECT count(*) AS hot_domains
FROM (
  SELECT domain, count(DISTINCT devid) AS devnum
  FROM default.dwb_domain_info
  WHERE day>=20260902 AND day<=20261002
    AND devid NOT IN (
      SELECT str1 FROM default.ods_custom_upload_data WHERE part1='test_dev' AND part2='test_devid'
    )
  GROUP BY domain
) s
WHERE devnum > 10
""",
        "hive_public_dstip": """
SELECT count(DISTINCT dstip) AS dst
FROM sodl.network_security_log
WHERE day=20261001
  AND regexp_extract(dstip,'^((0\\\\.0\\\\.0\\\\.0)|(127\\\\.0\\\\.0\\\\.1)|(localhost)|(10\\\\.)|(172\\\\.1[6-9]\\\\.)|(172\\\\.2[0-9]\\\\.)|(172\\\\.3[0-1]\\\\.)|(192\\\\.168\\\\.))') = ''
  AND regexp_extract(dstip,'^(\\\\d{1,3}\\\\.\\\\d{1,3}\\\\.\\\\d{1,3}\\\\.\\\\d{1,3})$') != ''
  AND engine NOT IN ('premise_ioc', 'cloud_ioc', 'sase_ioc')
  AND severity > 50
  AND (threatclass IN (209, 208, 216, 214, 203, 40)
       OR concat_ws('-', cast(threatclass AS string), cast(threattype AS string), cast(threatsubtype AS string)) = '212-10-0')
""",
        "hive_hash_sample": f"""
SELECT count(*) AS samples
FROM sri.ods_sri_hashinfo
WHERE virus_name regexp '^Trojan|^Backdoor|^Worm|^Virus|^Rootkit|^Bootkit|^Exploit|^Hacktool|^PUP|^Riskware|^Adware|^Suspicious|^Spyware|^Ransom|^Rogue|^CoinMiner|^Infostealer'
  AND oid > '{AGO_OID}'
  AND file_attr IN (0, 2)
  AND platform IN ('Android', 'AndroidOS')
  AND fdfs_path != ''
  AND file_size != '0' AND CAST(file_size AS INT) < 1048576
  AND file_md5 NOT IN (SELECT str1 FROM csc.ods_csc_business_data)
""",
    }
    report = [f"ago_oid {AGO_OID}", "row_counts"]
    report.extend(f"{sink.qualified}\t{sink.n}" for sink in sinks.values())
    report.extend(load_lines)
    for name, sql in proofs.items():
        print(f"proof {name}", flush=True)
        path = Path(f"/tmp/{name}.sql")
        path.write_text(sql.strip() + "\n", encoding="utf-8")
        output = run_beeline(path)
        interesting = [line for line in output.splitlines() if line and not line.startswith("SLF4J") and "null" not in line[:20]]
        report.append(f"## {name}")
        report.extend(interesting[-8:])

    cursor.execute("SELECT count(*) FROM sodl.network_security_log WHERE day=20261001")
    report.append(f"starrocks network_security_log day=20261001 {cursor.fetchone()[0]}")
    cursor.execute(
        "SELECT count(*) FROM business.ti_network_security_log WHERE alarmdate BETWEEN '20260901' AND '20261002'"
    )
    report.append(f"starrocks business alarms in window {cursor.fetchone()[0]}")
    connection.close()
    trino_rows = trino_count("SELECT count(*) FROM hive.sodl.dns_log WHERE day=20261001")
    report.append(f"trino hive.sodl.dns_log day=20261001 {trino_rows}")
    ARTIFACT.write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report), flush=True)


if __name__ == "__main__":
    main()
