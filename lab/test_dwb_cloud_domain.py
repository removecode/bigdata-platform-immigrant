import sys, pathlib
sys.path.insert(0, "/workspace/lab")
import run_dwb_discovery as r
conn = r.connect(); cur = conn.cursor(); r.build(cur)
cols = "src_log, `day`, manage, domain, log_num"
data = [("log_audit",r.DAY,"devA","a.s3.amazonaws.com",3),("log_audit",r.DAY,"devA","a.s3.amazonaws.com",4),
        ("network_security_log",r.DAY,"devB","a.s3.amazonaws.com",5),("network_security_log",r.DAY,"devB","x.vercel.app",2),
        ("network_security_log",r.DAY-1,"devC","a.s3.amazonaws.com",100),("network_security_log",r.DAY,"devC","baidu.com",9)]
cur.executemany(f"INSERT INTO {r.DB}.dwb_ti_domain_info ({cols}) VALUES (%s,%s,%s,%s,%s)", data)
sql = "\n".join(l for l in pathlib.Path("/workspace/outputs/dwb-consumer-domain-heat-cloud-starrocks.sql").read_text().splitlines() if not l.startswith("--")).rstrip().rstrip(";")
_ = sql % ()
cur.execute(sql.replace("paimon.ti.", r.DB+"."))
for row in cur.fetchall(): print(row)
cur.execute(f"DROP DATABASE {r.DB} FORCE")
