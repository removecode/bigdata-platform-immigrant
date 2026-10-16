"""Patch milestone branches in the user's saved v3 without rebuilding the map."""

import copy
import hashlib
import json
import os
import shutil
import tempfile
import uuid
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile


BASE = Path(__file__).resolve().parent
TARGET = BASE / "大数据迁移-E2E规划-v3.xmind"


def new_topic(title):
    return {"id": uuid.uuid4().hex, "class": "topic", "title": title}


def replace_branch(node, title, titles):
    node["title"] = title
    old = node.get("children", {}).get("attached", [])
    children = []
    for i, text in enumerate(titles):
        child = copy.deepcopy(old[i]) if i < len(old) else new_topic(text)
        child["title"] = text
        # These are leaf-level milestone descriptions; keep their saved styling.
        children.append(child)
    node.setdefault("children", {})["attached"] = children


def walk(node):
    yield node
    for group in node.get("children", {}).values():
        if isinstance(group, list):
            for child in group:
                yield from walk(child)


def main():
    initial_hash = hashlib.sha256(TARGET.read_bytes()).hexdigest()
    with ZipFile(TARGET) as archive:
        infos = archive.infolist()
        entries = {info.filename: archive.read(info.filename) for info in infos}
        comment = archive.comment
    data = json.loads(entries["content.json"])
    before = copy.deepcopy(data)
    overview = next(s for s in data if s["title"] == "项目全景")
    summary = next(n for n in overview["rootTopic"]["children"]["attached"] if n["title"] == "项目里程碑总览")
    sheet = next(s for s in data if s["title"] == "业务目标与里程碑")
    nodes = sheet["rootTopic"]["children"]["attached"]
    assert len(nodes) == 8
    assert [n["title"].split()[0] for n in nodes[1:]] == [f"M{i}" for i in range(7)]

    milestone_titles = [
        "M0 范围与交付计划确认",
        "M1 audit/stat直接消费业务迁移完成",
        "M2 SODL原始日志消费业务迁移完成",
        "M3 业务基础表消费业务迁移完成",
        "M4 中间表依赖业务迁移完成",
        "M5 范围内旧平台依赖退出",
    ]
    replace_branch(summary, summary["title"], milestone_titles + [
        "M1-M4按依赖并行；每批按G0-G5验收，不按编号串行",
        "前置交付单列：数据、基础表、必要中间结果、E2E测试环境；日期和负责人待确认",
    ])
    replace_branch(nodes[0], "业务里程碑与排期原则", [
        "[状态] 里程碑按业务类型定义，均待执行/确认，不代表已完成",
        "M0锁范围与成功标准；代表链路试点及外部交付承诺形成后锁定日期",
        "M1-M4是并行业务工作包，每批仍依次满足G0-G5验收关口",
        "迁移完成=本批E2E与性能通过、生产切流、约定周期观察及业务签字",
        "单任务只有一个最终归属；子分支可先验证，不重复计整任务完成",
        "混合输入必须齐备；两个待分类Hive查询任务补SQL后归入对应工作包",
        "上级汇报字段：业务范围、保留数、完成数、目标日期、负责人、最大阻塞",
    ])
    details = [
        [
            "支撑B1-B5；范围基线对应G0，首批环境准备服务G1-G3",
            "覆盖：45项逐项核定去留、承接责任、实际SQL依赖及业务读取者",
            "交付：数据湖/业务/我方具名负责人、表级交付日期、验收口径与预算",
            "交付：首批可完成E2E验收的测试环境与冒烟证据，覆盖输入到实际业务读取",
            "保留：写入隔离、可比数据与初始状态、日志报告、重试补数及恢复演练能力",
            "完成标准：首批归属与负责人明确；全量待决项有截止日，不默认下线",
            "牵头：项目推动者；确认：业务、数据湖及环境责任方；目标日期待确认",
        ],
        [
            "覆盖：3项压缩日志消费者中确认保留者，及可独立切换的原始audit业务分支",
            "示例：filter-layout-ip-seg-stat-prc、cipd-product-resource-monitor-prc；phishing需确认保留",
            "前置：audit/stat数据契约、必要信誉等维表、外部输入及本批E2E环境就绪",
            "执行：压缩表改读原始表，保留必要映射/过滤；批量适配与自动化验证",
            "交付：查询差异/性能、目标读回、真实业务使用、恢复及切流观察报告",
            "完成标准：本批保留业务按G0-G5通过并签字，不以SQL成功代替业务迁移",
            "混合任务纯audit分支可先验，但整任务在全部输入覆盖后只计一次",
            "牵头：消费任务负责人；签字：业务验收人；数量与目标日期待确认",
        ],
        [
            "覆盖：7项原始日志消费者中归属本包的保留任务，包含audit/SODL混合来源",
            "示例：domain-security-log-etl-prc、ip-security-log-etl-prc、top-visit-host-produce-job",
            "前置：所需SODL日志、辅助维表/外部输入、目标与E2E环境全部就绪",
            "SODL六张日志由谁接入及交付范围待确认，不要求重建无用途接入",
            "交付：完整来源查询/加工、目标读回、实际业务使用及性能报告",
            "完成标准：本包全部保留业务通过G0-G5，混合任务不能删去未就绪分支",
            "牵头：相关业务任务负责人；数据湖提供输入；业务签字与日期待确认",
            "与M1/M3可并行，不以全部audit任务完成作为前置",
        ],
        [
            "覆盖：ioc_vertex、business_data、hashinfo等消费者，当前归类4项",
            "示例：ati-pdns-cache-job、gnn-domain-hive-query-cronjob及两项cert导出任务",
            "前置：所需基础表及更新机制验收；hashinfo全量/增量衔接、删除与恢复通过",
            "ioc_vertex、business_data实际生产者另核实，不默认来自Mongo或DataX",
            "交付：业务查询、Mongo/Redis读回或文件导出/接收，以及适用SCP验收",
            "完成标准：确认保留范围通过G0-G5，历史、增量、目标及实际使用均正确",
            "牵头：消费任务负责人；接入承接方配合；业务签字与日期待确认",
        ],
        [
            "覆盖：当前7项中间表消费者中确认保留的任务；按Domain/MD5等依赖再拆批",
            "示例：domain-hit-devnum-cronjob、active-domain-elt-job、ctig-report-data-analysis-prc",
            "硬依赖：所需原始日志与维表就绪 → 必要中间结果生成并验证 → 下游E2E验收 → 切流观察",
            "Domain/MD5等独立分支可并行；混合审计/SODL消费者须全部必要输入齐备",
            "交付：等价模型口径、完整发布/就绪信号、生产校验及下游验收报告",
            "完成标准：必要结果及本批所有保留消费者通过G0-G5，不默认原样重建物理表",
            "开发与影子环境可提前并行；正式下游验收不能绕过上游结果验证",
            "牵头：模型与消费负责人；业务确认模型去留；目标日期按分支待确认",
        ],
        [
            "覆盖：全部保留业务、批准退役项及14项单独核定事项，两个待分类任务已落实归属",
            "前置：相关M1-M4业务观察验收完成，残留旧供数和业务读取依赖清零或完成批准处置",
            "交付：无旧依赖证据、旁路/维护/退役处置、共享链路停调度观察及保留期记录",
            "三区环境迁移范围另核定；过渡访问单列，不虚报完全退出",
            "完成标准：我方范围保留业务不再依赖旧平台，相关责任方签字",
            "先迁完下游再停共享中间加工/接入；不立即删数据，不擅自宣布平台全局下线",
            "牵头：项目推动者与数据湖；业务/共享链路方确认；目标日期待确认",
        ],
    ]
    for node, title, children in zip(nodes[1:7], milestone_titles, details):
        replace_branch(node, title, children)
    replace_branch(nodes[7], "前置交付节点与自动化提效", [
        "D1 audit/stat数据契约及可用性验收 → 支撑M1及相关中间加工",
        "D2 所需SODL日志交付 → 支撑M2和部分M4",
        "D3 Mongo同步/其他基础表交付 → 支撑M3，也支撑M1/M2/M4中的相关JOIN",
        "D4 必要中间结果生成及验证 → 支撑M4；不等于下游业务已完成",
        "D5 本批E2E测试环境可用 → 支撑对应业务工作包，不统一等待全部环境",
        "每项交付登记：负责人、日期、影响业务、验收证据、阻塞与升级条件",
        "自动化能力待建设：依赖预检、模板适配、测试部署、对账读回、报告与发布包",
        "代表链路先验工具：缺依赖/错数据可拦截、重跑幂等；复杂改造人工评审",
        "生产分批切流须审批，失败暂停；各包复用工具，不越过G0-G5关口",
    ])

    # Only these two milestone subtrees may change in the user's document.
    protected_ids = {summary["id"], sheet["rootTopic"]["id"]}
    def without_changed(value):
        if isinstance(value, dict):
            return {k: without_changed(v) for k, v in value.items()
                    if not (value.get("id") in protected_ids and k == "children")}
        if isinstance(value, list):
            return [without_changed(v) for v in value]
        return value
    assert without_changed(before) == without_changed(data)
    all_nodes = [n for s in data for n in walk(s["rootTopic"])]
    assert len({n["id"] for n in all_nodes}) == len(all_nodes)
    updated = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    backup = BASE / f"大数据迁移-E2E规划-v3-里程碑更新前-{datetime.now():%Y%m%d-%H%M%S-%f}.xmind"
    fd, temporary = tempfile.mkstemp(prefix="v3-milestones-", suffix=".xmind", dir=BASE)
    os.close(fd)
    try:
        with ZipFile(temporary, "w") as archive:
            archive.comment = comment
            for info in infos:
                archive.writestr(info, updated if info.filename == "content.json" else entries[info.filename])
        with ZipFile(temporary) as archive:
            assert archive.testzip() is None
            assert json.loads(archive.read("content.json")) == data
            for name, value in entries.items():
                if name != "content.json":
                    assert archive.read(name) == value
        if hashlib.sha256(TARGET.read_bytes()).hexdigest() != initial_hash:
            raise RuntimeError("v3 changed during editing; refusing to overwrite")
        shutil.copy2(TARGET, backup)
        assert hashlib.sha256(backup.read_bytes()).hexdigest() == initial_hash
        os.replace(temporary, TARGET)
    finally:
        if Path(temporary).exists():
            Path(temporary).unlink()
    print(json.dumps({"updated": str(TARGET), "backup": str(backup),
                      "milestones": milestone_titles, "preservation_checks": "passed",
                      "native_visual_check": "not performed"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
