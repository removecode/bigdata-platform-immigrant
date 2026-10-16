#!/usr/bin/env python3
"""Browser console that runs SQL on the local StarRocks, Hive, and Trino processes."""

from __future__ import annotations

import json
import socket
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import pymysql

HOST = "0.0.0.0"
PORT = 8787
MAX_ROWS = 200

PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>本地查询平台</title>
<style>
  :root { color-scheme: light; --ink:#1c2834; --line:#d5dde6; --panel:#f6f8fa; --accent:#0f6f6a; }
  body { margin:0; font:15px/1.45 "Segoe UI", "Noto Sans SC", sans-serif; color:var(--ink); background:#eef2f5; }
  header { padding:18px 24px; background:#14343a; color:#fff; }
  header h1 { margin:0 0 4px; font-size:22px; }
  header p { margin:0; color:#c9ddd9; }
  main { display:grid; grid-template-columns: 280px 1fr; gap:16px; padding:16px; }
  .card { background:#fff; border:1px solid var(--line); border-radius:10px; padding:14px; }
  label { display:block; font-weight:600; margin-bottom:6px; }
  select, textarea, button { font:inherit; }
  select, textarea { width:100%; box-sizing:border-box; border:1px solid var(--line); border-radius:8px; padding:8px; background:#fff; }
  textarea { min-height:180px; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  button { margin-top:10px; background:var(--accent); color:#fff; border:0; border-radius:8px; padding:8px 14px; cursor:pointer; }
  button:disabled { opacity:.6; cursor:wait; }
  .status { display:flex; flex-direction:column; gap:8px; }
  .engine { display:flex; justify-content:space-between; gap:8px; padding:8px; background:var(--panel); border-radius:8px; }
  .ok { color:#0b7a32; font-weight:700; }
  .down { color:#a12622; font-weight:700; }
  table { width:100%; border-collapse:collapse; margin-top:12px; }
  th, td { border-bottom:1px solid var(--line); text-align:left; padding:6px 8px; vertical-align:top; }
  th { background:var(--panel); }
  pre { white-space:pre-wrap; background:#2a2118; color:#f3e6d4; padding:10px; border-radius:8px; }
  @media (max-width: 800px) { main { grid-template-columns: 1fr; } }
</style>
</head>
<body>
<header>
  <h1>本地查询平台</h1>
  <p>StarRocks 3.5.21、Hive 4.0.1、Trino 446。SQL 由本机进程执行。</p>
</header>
<main>
  <section class="card">
    <h2>引擎</h2>
    <div id="status" class="status">检查中</div>
    <h2>示例</h2>
    <button type="button" id="sample-starrocks">StarRocks 表</button>
    <button type="button" id="sample-hive">Hive 表</button>
    <button type="button" id="sample-join">Trino 关联两边</button>
  </section>
  <section class="card">
    <label for="engine">执行引擎</label>
    <select id="engine">
      <option value="starrocks">StarRocks（MySQL 协议 9030）</option>
      <option value="hive">HiveServer2（10000）</option>
      <option value="trino">Trino（8080）</option>
    </select>
    <label for="sql" style="margin-top:12px">SQL</label>
    <textarea id="sql">SELECT ioc_type, ioc_value, hit_count FROM lab.ioc_hit ORDER BY ioc_value;</textarea>
    <button type="button" id="run">执行</button>
    <div id="meta"></div>
    <div id="result"></div>
  </section>
</main>
<script>
const samples = {
  starrocks: ["starrocks", "SELECT ioc_type, ioc_value, hit_count FROM lab.ioc_hit ORDER BY ioc_value;"],
  hive: ["hive", "SELECT ioc_type, ioc_value, hit_count FROM lab.ioc_hit ORDER BY ioc_value;"],
  join: ["trino", "SELECT h.ioc_value, h.hit_count AS hive_hits, s.hit_count AS sr_hits FROM hive.lab.ioc_hit h JOIN starrocks.lab.ioc_hit s ON h.ioc_value = s.ioc_value ORDER BY h.ioc_value;"]
};
async function refresh() {
  const data = await fetch("/api/status").then(r => r.json());
  document.getElementById("status").innerHTML = data.engines.map(e =>
    `<div class="engine"><span>${e.name}<br><small>${e.detail}</small></span><span class="${e.up ? "ok" : "down"}">${e.up ? "可连接" : "未就绪"}</span></div>`
  ).join("");
}
function render(payload) {
  document.getElementById("meta").textContent = payload.elapsed_ms + " ms · " + (payload.rows || []).length + " 行";
  if (payload.error) {
    document.getElementById("result").innerHTML = "<pre>" + payload.error.replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])) + "</pre>";
    return;
  }
  const cols = payload.columns || [];
  const rows = payload.rows || [];
  if (!cols.length) { document.getElementById("result").textContent = "语句已执行，没有结果列。"; return; }
  const esc = (v) => String(v ?? "").replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
  const head = "<tr>" + cols.map(c => `<th>${esc(c)}</th>`).join("") + "</tr>";
  const body = rows.map(r => "<tr>" + r.map(v => `<td>${v === null ? "" : esc(v)}</td>`).join("") + "</tr>").join("");
  document.getElementById("result").innerHTML = "<table>" + head + body + "</table>";
}
document.getElementById("run").onclick = async () => {
  const button = document.getElementById("run");
  button.disabled = true;
  try {
    const payload = await fetch("/api/query", {method:"POST", headers:{"Content-Type":"application/json"},
      body: JSON.stringify({engine: document.getElementById("engine").value, sql: document.getElementById("sql").value})
    }).then(r => r.json());
    render(payload);
  } finally { button.disabled = false; }
};
refresh();
setInterval(refresh, 10000);
for (const [id, value] of Object.entries(samples)) {
  const button = document.getElementById("sample-" + id);
  if (!button) continue;
  button.onclick = () => {
    document.getElementById("engine").value = value[0];
    document.getElementById("sql").value = value[1];
  };
}
</script>
</body>
</html>
"""


def port_open(port: int) -> bool:
    sock = socket.socket()
    sock.settimeout(0.4)
    try:
        return sock.connect_ex(("127.0.0.1", port)) == 0
    finally:
        sock.close()


def query_starrocks(sql: str) -> tuple[list[str], list[list[object]]]:
    conn = pymysql.connect(host="127.0.0.1", port=9030, user="root", password="", autocommit=True, connect_timeout=10)
    try:
        cur = conn.cursor()
        cur.execute(sql)
        columns = [item[0] for item in cur.description] if cur.description else []
        rows = [list(row) for row in cur.fetchmany(MAX_ROWS)] if columns else []
        return columns, rows
    finally:
        conn.close()


def query_hive(sql: str) -> tuple[list[str], list[list[object]]]:
    cmd = [
        "/opt/lab/hive/bin/beeline",
        "-u",
        "jdbc:hive2://127.0.0.1:10000",
        "--silent=true",
        "--showHeader=true",
        "--outputformat=tsv2",
        "-e",
        sql,
    ]
    completed = subprocess.run(cmd, check=False, text=True, capture_output=True, timeout=180)
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "beeline failed").strip()
        raise RuntimeError(detail[-4000:])
    lines = [line for line in completed.stdout.splitlines() if line.strip() and not line.startswith("SLF4J")]
    if not lines:
        return [], []
    columns = lines[0].split("\t")
    rows = [line.split("\t") for line in lines[1: MAX_ROWS + 1]]
    return columns, rows


def query_trino(sql: str) -> tuple[list[str], list[list[object]]]:
    statement = sql.strip()
    if statement.endswith(";"):
        statement = statement[:-1].strip()
    request = Request(
        "http://127.0.0.1:8080/v1/statement",
        data=statement.encode(),
        headers={"X-Trino-User": "lab", "Content-Type": "text/plain"},
        method="POST",
    )
    columns: list[str] = []
    rows: list[list[object]] = []
    url = None
    payload = json.load(urlopen(request, timeout=30))
    while True:
        if "error" in payload:
            failure = payload["error"]
            message = failure.get("message") if isinstance(failure, dict) else str(failure)
            raise RuntimeError(message)
        if payload.get("columns") and not columns:
            columns = [col["name"] for col in payload["columns"]]
        for row in payload.get("data") or []:
            if len(rows) < MAX_ROWS:
                rows.append(row)
        url = payload.get("nextUri")
        if not url or len(rows) >= MAX_ROWS:
            break
        payload = json.load(urlopen(Request(url, headers={"X-Trino-User": "lab"}), timeout=30))
    return columns, rows


QUERIES = {"starrocks": query_starrocks, "hive": query_hive, "trino": query_trino}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        return

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path in ("/", "/index.html"):
            self._send(200, PAGE.encode(), "text/html; charset=utf-8")
            return
        if self.path == "/api/status":
            engines = [
                {"name": "StarRocks", "detail": "FE 9030 / BE 9050", "up": port_open(9030) and port_open(9050)},
                {"name": "Hive", "detail": "Metastore 9083 / HiveServer2 10000", "up": port_open(9083) and port_open(10000)},
                {"name": "Trino", "detail": "Coordinator 8080", "up": port_open(8080)},
            ]
            self._send(200, json.dumps({"engines": engines}).encode(), "application/json")
            return
        self._send(404, b"not found", "text/plain")

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/api/query":
            self._send(404, b"not found", "text/plain")
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
            engine = str(payload.get("engine", ""))
            sql = str(payload.get("sql", "")).strip()
            if engine not in QUERIES:
                raise RuntimeError("engine must be starrocks, hive, or trino")
            if not sql or len(sql) > 20000:
                raise RuntimeError("SQL is empty or too long")
            import time
            started = time.perf_counter()
            columns, rows = QUERIES[engine](sql)
            elapsed = int((time.perf_counter() - started) * 1000)
            body = {"columns": columns, "rows": rows, "elapsed_ms": elapsed}
        except (RuntimeError, pymysql.Error, OSError, HTTPError, URLError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
            body = {"columns": [], "rows": [], "elapsed_ms": 0, "error": str(exc)}
        self._send(200, json.dumps(body, default=str).encode(), "application/json")


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
