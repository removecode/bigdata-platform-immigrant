"""Add a first-sheet schedule while retaining all original XMind sheets."""
import copy
import json
import uuid
from pathlib import Path
from zipfile import ZipFile

base = Path(__file__).resolve().parent
source = base / '大数据迁移-E2E规划-指定版本-执行计划已更新.xmind'
target = base / '大数据迁移-E2E规划-业务对齐与时间规划.xmind'
plan = (base / '大数据迁移-E2E时间规划-业务对齐优先.md').read_text(encoding='utf-8')

def topic(title, children=()):
    node = {'id': uuid.uuid4().hex, 'class': 'topic', 'title': title}
    if children:
        node['children'] = {'attached': [topic(c) if isinstance(c, str) else c for c in children]}
    return node

root = topic('业务对齐优先：迁移时间规划（建议）', [
    topic('排期口径与确认边界', [
        '用户已明确：先确认业务迁移/下线范围；以下时长为建议，未获各方承诺',
        'D1为待确认启动日；D序号为工作日，观察期单列自然日',
        '建议25个工作日完成最后切换＋至少7个自然日观察＋2个工作日退出确认',
        '估算假设：2名开发＋1名测试，数据湖/DBA/运维有交付接口人；投入待确认',
        'D5锁范围，D10以试点实测、交付承诺重新估工；节假日按团队日历落日期',
        '后续旧版页签保留参考；工期以本页建议为准，旧数量/资料状态不直接作为当前结论',
    ]),
    topic('P0｜D1—D5 业务对齐与范围确认', [
        'D1：45项逐项定位用途、运行情况、实际读取者和业务确认人',
        'D2：优先确认退役候选、用途不明项和两张已决策下线表的消费影响',
        'D3：确认保留业务、历史范围、口径、SLA和验收人；已确认需求交数据湖',
        'D4：核对真实SQL与手工来源，梳理共享依赖、混合分支及低频任务',
        'D5：形成迁移/退役/保留但不涉及本次改造/待决清单；锁定首批',
        '关口：首批无未决项；其他待决项有负责人及期限，不默认下线',
    ]),
    topic('P1｜D3—D10 数据湖与E2E环境准备', [
        '只对已确认范围推进承接与交付；技术资料收集可提前',
        '逐表负责人、交付日期、历史与增量、字段及更新删除规则',
        'SODL日志、Mongo/其他基础表和必要中间结果分别落实',
        '三区Mongo、网络账号、计算资源、影子目标与生产样本重放',
        '关口：首批输入到真实任务、隔离输出、目标读回、业务读取可全链路验收',
    ]),
    topic('P2｜D8—D10 代表试点与排期复核', [
        '依赖首批完整数据与E2E环境；未就绪只能先做离线预检',
        '选已确认保留且依赖齐备的代表链路，包含压缩改原始性能风险验证',
        '试验批量SQL适配、固定窗口对账和目标读回工具',
        'D10交付实际工时、查询性能、差异及重跑证据，重新估算剩余排期',
    ]),
    topic('P3｜D11—D20 分批改造与验收', [
        '原始日志/基础表消费：输入齐备即可独立推进，不设空audit/stat里程碑',
        '中间表消费：日志与维表 → 必要中间结果验收 → 下游E2E',
        '压缩表消费：原始字段/口径 → 改造 → 规模性能 → E2E',
        '按业务领域组织验收，按技术依赖安排执行；独立模型与批次并行',
        '符合条件可提前切换并观察，不统一等待最后一周',
    ]),
    topic('P4｜D21—D25 问题收敛与最后批次切换', [
        '关键数据差异闭环，正常/峰值/补数性能达标',
        'Mongo文档、Redis值与TTL、Kafka消息及真实消费效果均验收',
        '恢复演练、切换窗口、批次/位点及迟到归属确认',
        '同范围单写者；异常停新写、恢复/补偿数据、恢复旧任务与读取并补边界对账',
        '关口：保留迁移项完成切换，退役项保留消费者依赖已处理',
    ]),
    topic('P5｜每批切换后至少7个自然日观察', [
        '从各批实际切换日起算；最后一批不能借用前批观察时长',
        '覆盖完整业务周期、时效、失败重试与状态变化',
        '低频任务等实际周期或业务认可的等价演练；不以7天无告警代替验收',
    ]),
    topic('P6｜观察通过后2个工作日退出确认（D26—D27）', [
        '先迁完保留消费者，再停止共享旧加工与接入',
        '检查残留旧查询、中转供数与低频任务，交接数据保留期',
        '我方旧依赖退出签字，不代表全平台下线或三区迁移全部完成',
    ]),
    topic('DEC-001｜两表下线纳入首轮业务对齐', [
        '租户订阅表：ctig-report-data-analysis-prc明确引用，需处理报告关联逻辑',
        'skyeye IP表：attack-ip-analysis-cronjob明确引用，需处理攻击IP筛选逻辑',
        'black-ti-context-produce-prc：租户表仅手工来源标注，完整代码依赖待核实',
        'datax-server：对应两个同步子任务待核实现网启用状态及停止安排',
        '表可下线不等于相关服务整体下线；当前只有决策确认，尚未实施',
    ]),
    topic('提效与最长耗时项', [
        '业务确认清单一次覆盖45项；共享表级交付和验收复用',
        '固定输入版本、批量适配、对账读回与报告生成，减少反复人工比对',
        '每日同步阻塞、每周两次集中决策；关键阻塞超过1工作日建议升级',
        '最大变量：业务未决、数据湖交付、三区目标、回填、性能、中间模型差异、低频观察',
        '分别汇报等待时间、人工时间、运行时间及各批确认/输入/E2E/切换/观察进度',
    ]),
])
root['structureClass'] = 'org.xmind.ui.logic.right'
root['notes'] = {'plain': {'content': plan}}
with ZipFile(source) as z:
    infos = z.infolist()
    entries = {i.filename: z.read(i.filename) for i in infos}
    archive_comment = z.comment
original = json.loads(entries['content.json'])
sheet = {'id': uuid.uuid4().hex, 'class': 'sheet', 'title': '时间规划（业务对齐优先）', 'rootTopic': root}
if original and 'theme' in original[0]:
    sheet['theme'] = copy.deepcopy(original[0]['theme'])
updated = [sheet] + original
entries['content.json'] = json.dumps(updated, ensure_ascii=False).encode('utf-8')
with ZipFile(target, 'w') as z:
    z.comment = archive_comment
    for info in infos:
        z.writestr(info, entries[info.filename])
with ZipFile(target) as z:
    assert z.testzip() is None
    saved = json.loads(z.read('content.json'))
    assert saved[1:] == original
    assert saved[0]['rootTopic']['notes']['plain']['content'] == plan
    for info in infos:
        if info.filename != 'content.json':
            assert z.read(info.filename) == entries[info.filename]
def ids(node):
    yield node['id']
    for child in node.get('children', {}).get('attached', []):
        yield from ids(child)
new_ids = list(ids(saved[0]['rootTopic']))
assert len(new_ids) == len(set(new_ids))
print(f'Created {target.name}: {len(new_ids)} new topics, {len(original)} original sheets preserved; ZIP and content checks passed.')
