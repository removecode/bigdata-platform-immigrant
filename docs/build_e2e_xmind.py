"""Build an XMind workbook from the maintained Markdown outline."""

import json
import re
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


BASE = Path(__file__).resolve().parent
SOURCE = BASE / "大数据迁移-E2E规划-导图大纲.md"
OUTPUT = BASE / "大数据迁移-E2E规划-v3.xmind"
NS = "urn:xmind:xmap:xmlns:content:2.0"
ET.register_namespace("", NS)


def uid():
    return uuid.uuid4().hex


def topic(title):
    return {"id": uid(), "class": "topic", "title": title}


def parse_outline():
    sheets, stack = [], []
    for number, line in enumerate(SOURCE.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        if line.startswith("# "):
            sheets.append({"id": uid(), "class": "sheet", "title": line[2:]})
            stack = []
            continue
        match = re.fullmatch(r"( *)- (.+)", line)
        if not match or not sheets or len(match[1]) % 2:
            raise ValueError(f"Invalid outline line {number}")
        level = len(match[1]) // 2
        node = topic(match[2])
        if level == 0:
            if "rootTopic" in sheets[-1]:
                raise ValueError("Multiple roots in one sheet")
            node["structureClass"] = "org.xmind.ui.logic.right"
            sheets[-1]["rootTopic"] = node
        else:
            if level > len(stack):
                raise ValueError(f"Skipped level at line {number}")
            stack[level - 1].setdefault("children", {}).setdefault("attached", []).append(node)
        stack[level:] = [node]
    assert len(sheets) == 4
    return sheets


def walk(node):
    yield node
    for child in node.get("children", {}).get("attached", []):
        yield from walk(child)


def xml_topic(parent, node):
    attributes = {"id": node["id"]}
    if "structureClass" in node:
        attributes["structure-class"] = node["structureClass"]
    element = ET.SubElement(parent, f"{{{NS}}}topic", attributes)
    ET.SubElement(element, f"{{{NS}}}title").text = node["title"]
    children = node.get("children", {}).get("attached", [])
    if children:
        container = ET.SubElement(element, f"{{{NS}}}children")
        attached = ET.SubElement(container, f"{{{NS}}}topics", {"type": "attached"})
        for child in children:
            xml_topic(attached, child)


def build():
    sheets = parse_outline()
    root = ET.Element(f"{{{NS}}}xmap-content", {"version": "2.0"})
    for sheet in sheets:
        element = ET.SubElement(root, f"{{{NS}}}sheet", {"id": sheet["id"]})
        ET.SubElement(element, f"{{{NS}}}title").text = sheet["title"]
        xml_topic(element, sheet["rootTopic"])

    entries = {
        "content.json": json.dumps(sheets, ensure_ascii=False, indent=2).encode("utf-8"),
        "content.xml": ET.tostring(root, encoding="utf-8", xml_declaration=True),
        "metadata.json": json.dumps({"creator": {"name": "Migration Planning"}, "activeSheetId": sheets[0]["id"]}).encode("utf-8"),
    }
    entries["manifest.json"] = json.dumps({"file-entries": {name: {} for name in entries}}).encode("utf-8")
    manifest_ns = "urn:xmind:xmap:xmlns:manifest:1.0"
    manifest = ET.Element(f"{{{manifest_ns}}}manifest")
    for name in entries:
        ET.SubElement(manifest, f"{{{manifest_ns}}}file-entry", {"full-path": name, "media-type": "text/xml" if name.endswith(".xml") else "application/json"})
    entries["META-INF/manifest.xml"] = ET.tostring(manifest, encoding="utf-8", xml_declaration=True)

    if OUTPUT.exists():
        raise FileExistsError(f"Refusing to overwrite: {OUTPUT}")
    with ZipFile(OUTPUT, "x", ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)

    # Reopen the actual artifact and cross-check both modern and legacy trees.
    with ZipFile(OUTPUT) as archive:
        assert archive.testzip() is None
        loaded = json.loads(archive.read("content.json"))
        xml = ET.fromstring(archive.read("content.xml"))
        nodes = [node for sheet in loaded for node in walk(sheet["rootTopic"])]
        assert len({node["id"] for node in nodes}) == len(nodes)
        xml_titles = [item.text for item in xml.findall(f".//{{{NS}}}topic/{{{NS}}}title")]
        assert xml_titles == [node["title"] for node in nodes]
        for name in json.loads(archive.read("manifest.json"))["file-entries"]:
            assert name in archive.namelist()
        overview = loaded[0]["rootTopic"]["children"]["attached"]
        assert len(overview) == 8
        assert overview[0]["title"] == "业务目标与成功标准"
        titles = {node["title"] for node in nodes}
        assert "测试环境具备E2E验收能力" in titles
        assert "批量自动化迁移能力建设" in titles
        milestone_titles = [node["title"] for node in loaded[3]["rootTopic"]["children"]["attached"]]
        assert all(any(title.startswith(f"M{i} ") for title in milestone_titles) for i in range(7))
    print(json.dumps({"output": str(OUTPUT), "sheets": [sheet["title"] for sheet in sheets], "topics": len(nodes), "archive_and_tree_checks": "passed", "native_xmind_visual_check": "not performed"}, ensure_ascii=False))


if __name__ == "__main__":
    build()
