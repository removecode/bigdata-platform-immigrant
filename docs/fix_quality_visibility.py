"""Make quality comparison visible on the user's overview sheet."""
import copy
import json
import os
import shutil
import tempfile
from datetime import datetime
from pathlib import Path
from zipfile import ZipFile
from update_v3_quality import topic

base = Path(__file__).resolve().parent
target = base / '大数据迁移-E2E规划-v3-质量保障方案已更新.xmind'
visible = base / '大数据迁移-E2E规划-质量方案首页可见.xmind'
original_bytes = target.read_bytes()
with ZipFile(target) as z:
    infos = z.infolist()
    entries = {i.filename: z.read(i.filename) for i in infos}
    comment = z.comment
data = json.loads(entries['content.json'])
before = copy.deepcopy(data)
overview = next(s for s in data if s['title'] == '项目全景')
assert not any(n['title'] == '质量保障方案对比与回滚【新增】' for n in overview['rootTopic']['children']['attached'])
branch = topic('质量保障方案对比与回滚【新增】', [
    topic('A 离线对账后切换', [
        '固定窗口比新旧结果；适合简单查询与快速预筛选',
        '资源较省；持续增量和状态变化覆盖不足，需补E2E验证',
    ]),
    topic('B 双跑＋隔离输出【推荐】', [
        '旧任务保障生产，新任务写影子Mongo/Redis/Kafka目标',
        '验证查询、真实写入、目标读回和实际业务读取',
        '需要临时计算与存储；批量自动化验证、分批复用控制成本',
    ]),
    topic('C 双写同一生产目标【不默认采用】', [
        '新旧同时写同一文档/Key/Topic，存在覆盖、累加及重复副作用',
        '仅限已证明幂等、冲突控制与补偿能力且获批的场景',
    ]),
    topic('质量放行与回滚', [
        '切流前：输入到业务五层验收、性能和恢复演练通过',
        '切流时：固定批次/位点及迟到归属，同范围单一写者',
        '异常：停新写 → 定位影响 → 恢复/补偿数据 → 恢复旧任务与读取 → 补边界对账',
        'Mongo/Redis恢复正确状态；Kafka已消费消息须业务补偿',
        '旧接入/中间加工及输入在恢复期保持可恢复，观察通过再退出',
    ]),
    '完整风险、成本、适用范围与责任要求见第5画布“质量保障方案对比”',
])
overview['rootTopic']['children']['attached'].insert(0, branch)
overview['rootTopic']['branch'] = 'unfolded'
meta = json.loads(entries['metadata.json'])
meta['activeSheetId'] = overview['id']
updated = {
    'content.json': json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode(),
    'metadata.json': json.dumps(meta, ensure_ascii=False, separators=(',', ':')).encode(),
}
check = copy.deepcopy(data)
checked_overview = next(s for s in check if s['title'] == '项目全景')
checked_overview['rootTopic']['children']['attached'].pop(0)
if 'branch' in next(s for s in before if s['title'] == '项目全景')['rootTopic']:
    checked_overview['rootTopic']['branch'] = next(s for s in before if s['title'] == '项目全景')['rootTopic']['branch']
else:
    checked_overview['rootTopic'].pop('branch', None)
assert check == before
if visible.exists():
    raise FileExistsError(visible)
fd, temp = tempfile.mkstemp(dir=base, suffix='.xmind', prefix='quality-visible-')
os.close(fd)
try:
    with ZipFile(temp, 'w') as z:
        z.comment = comment
        for info in infos:
            z.writestr(info, updated.get(info.filename, entries[info.filename]))
    with ZipFile(temp) as z:
        assert z.testzip() is None
        assert json.loads(z.read('metadata.json'))['activeSheetId'] == overview['id']
        assert json.loads(z.read('content.json')) == data
    assert target.read_bytes() == original_bytes, 'File changed during edit'
    backup = base / f'质量保障方案-首页修正前-{datetime.now():%Y%m%d-%H%M%S-%f}.xmind'
    shutil.copy2(target, backup)
    os.replace(temp, target)
    shutil.copy2(target, visible)
finally:
    if Path(temp).exists():
        Path(temp).unlink()
print(json.dumps({'updated': str(target), 'visible_copy': str(visible), 'default_sheet': '项目全景', 'first_branch': branch['title'], 'original_content_preserved': True, 'checks': 'passed'}, ensure_ascii=False))
