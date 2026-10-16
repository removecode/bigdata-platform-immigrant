"""Update only the execution branch in the explicitly selected user workbook."""
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
target = base / '大数据迁移-E2E规划-v3-质量方案更新前-20260910-194037-467369.xmind'
output = base / '大数据迁移-E2E规划-指定版本-执行计划已更新.xmind'
initial = target.read_bytes()
with ZipFile(target) as z:
    infos = z.infolist()
    entries = {i.filename: z.read(i.filename) for i in infos}
    comment = z.comment
data = json.loads(entries['content.json'])
before = copy.deepcopy(data)
sheet = next(s for s in data if s['title'] == '项目全景')
branch = next(n for n in sheet['rootTopic']['children']['attached'] if n['title'] == '执行与批次')
original_branch = copy.deepcopy(branch)
branch['title'] = '里程碑与执行批次（执行计划）'
branch.setdefault('children', {})['attached'] = [
    topic('执行总则：M1-M4按业务类型并行', [
        'M0阶段同步启动audit/stat、SODL、Mongo基础数据、必要模型及环境准备',
        '各包输入和验收条件齐备即可推进，编号不代表必须串行',
        '原始数据/维表就绪 → 中间结果生成并验证 → 下游E2E验收 → 切流观察',
        '开发、SQL适配与影子环境可提前并行；验收不得绕过上游依赖',
        '目标日期、负责人、保留数量与完成数量待确认，不视为已承诺排期',
    ]),
    topic('M0 范围与交付计划确认', [
        '执行：45项核定去留，拆SQL/子任务，明确输入、输出和实际业务读取者',
        '执行：数据湖承接及表级交付、业务验收口径、资源与负责人明确',
        '执行：首批测试环境可E2E验收，具备可比输入、隔离输出和读回能力',
        '执行：准备批量自动化迁移配置、依赖图及代表性试点',
        '前置：业务、数据湖与环境方共同确认责任和需求',
        '完成：首批范围、具体责任人、交付日期、验收标准及环境冒烟证据齐备',
        '其他待决项有期限；未确认不等于批准退役',
    ]),
    topic('M1 audit/stat直接消费业务迁移完成', [
        '范围：3项压缩日志消费者中保留项，及可独立切换的原始audit业务分支',
        '前置：audit/stat交付验收、必要维表/外部输入、目标与测试环境就绪',
        '执行：代表任务试点，压缩表改读原始表，复现字段和过滤口径',
        '执行：批量改源验证 → 影子输出 → 实际业务读取 → 审批后切流',
        '完成：本批数据、性能、E2E、恢复演练及切流观察通过，业务签字',
        '混合任务的audit分支完成不等于整任务完成；stat不必等待全部audit任务',
    ]),
    topic('M2 SODL原始日志消费业务迁移完成', [
        '范围：直接读取SODL日志的保留业务，含audit/SODL混合输入任务',
        '前置：所需SODL日志、辅助维表和外部输入、目标及E2E环境齐备',
        '执行：校验来源覆盖和更新时效，适配消费SQL并批量验证',
        '执行：查询转换、目标读回和业务用例通过后分批切流观察',
        '完成：本包保留业务全部必要来源覆盖并验收，不能删除缺失输入分支',
        '与M1/M3并行；不以全部audit业务完成为前置',
    ]),
    topic('M3 业务基础表消费业务迁移完成', [
        '范围：当前4项ioc_vertex、business_data、hashinfo等基础表消费者',
        '前置：实际生产者和目标表明确，必要数据及更新机制验收通过',
        '执行：涉及Mongo接入的，验证快照/增量衔接、更新删除及恢复',
        '执行：消费查询、Mongo/Redis同步或文件导出及接收验证；适用SCP另验',
        '完成：历史与增量满足业务，输出和实际使用正确，切流观察签字',
        '共享hashinfo等交付也支撑其他里程碑，不等同于M3下游完成',
    ]),
    topic('M4 中间表依赖业务迁移完成', [
        '范围：当前7项中间表消费者中保留任务，按Domain/MD5等真实依赖拆批',
        '前置：必要日志/维表、模型口径、承接方及目标环境明确并就绪',
        '执行1：生产必要等价结果，验证JOIN、去重、聚合和完整发布',
        '执行2：上游结果验收通过后，下游真实数据E2E验收',
        '执行3：业务批准后分批切流、观察和签字',
        '完成：模型正确、下游保留业务全部验收，不默认重建同名物理表',
        '独立模型可并行；混合audit/SODL消费者须等全部必要输入',
        '日常调度按完整批次就绪信号触发，不仅按固定钟点衔接',
    ]),
    topic('M5 范围内旧平台依赖退出', [
        '前置：相关M1-M4通过观察验收、退役获批、残留依赖核查完成',
        '执行：两项待分类任务补归属；旁路/维护/退役项全部核定处置',
        '执行：核查低频任务、实际读取及新区对旧平台中转供数的依赖',
        '执行：符合条件的共享旧调度停用并观察，按保留期交接归档',
        '完成：我方保留业务无遗漏旧依赖，共享链路责任方签字',
        '先迁完下游，再停共享中间加工与接入；不立即删旧数据',
        '过渡访问单列；我方退出不等于宣布整个平台下线',
    ]),
    topic('各业务包共用执行规则', [
        topic('最小改源与批量自动化', [
            '连接/表名/字段映射 → 方言适配 → 必要逻辑改造',
            '代表试点后扩展：预检、配置生成、测试部署、对账读回、报告与发布包',
            '禁止无差别全局替换；复杂SQL/UDF和模型改造人工评审',
            '限并发、失败暂停、幂等及断点续跑；自动化能力仍待建设和验证',
        ]),
        topic('子任务验证，整任务验收', [
            '子分支可先验，缺失输入不能省略；每个整任务只归属一个最终工作包',
            '原始明细替代压缩输入需实测性能，不能仅凭表类型判断',
            '输入 → 中间加工 → 查询转换 → 目标读回 → 真实业务使用逐层验证',
        ]),
        topic('质量与切流保护', [
            '建议新旧双跑、隔离输出；不默认同时写同一生产文档/Key/Topic',
            '批次均遵守G0-G5：关键差异、性能、业务验证及回滚演练通过才切流',
            '明确批次/位点边界和迟到归属，同范围一个有效生产写者',
            '目标实例变化时，验证实际业务读取路由与目标历史/增量状态',
            '异常停新写 → 恢复/补偿目标 → 恢复旧任务/读取 → 补边界并对账',
            'Kafka已消费副作用须预定补偿；回切代码不等于数据恢复',
        ]),
    ]),
]
# Verify every original object outside this branch is unchanged.
check = copy.deepcopy(data)
check_sheet = next(s for s in check if s['title'] == '项目全景')
check_nodes = check_sheet['rootTopic']['children']['attached']
index = next(i for i, n in enumerate(check_nodes) if n['id'] == original_branch['id'])
check_nodes[index] = original_branch
assert check == before
assert not output.exists(), 'Review copy already exists'
updated = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
fd, temporary = tempfile.mkstemp(prefix='execution-update-', suffix='.xmind', dir=base)
os.close(fd)
try:
    with ZipFile(temporary, 'w') as z:
        z.comment = comment
        for info in infos:
            z.writestr(info, updated if info.filename == 'content.json' else entries[info.filename])
    with ZipFile(temporary) as z:
        assert z.testzip() is None
        assert json.loads(z.read('content.json')) == data
        for name, content in entries.items():
            if name != 'content.json':
                assert z.read(name) == content
    assert target.read_bytes() == initial, 'User source changed during update'
    backup = base / f'指定版本-执行计划修改前-{datetime.now():%Y%m%d-%H%M%S-%f}.xmind'
    shutil.copy2(target, backup)
    os.replace(temporary, target)
    shutil.copy2(target, output)
finally:
    if Path(temporary).exists():
        Path(temporary).unlink()
print(json.dumps({'updated': str(target), 'review_copy': str(output), 'backup': str(backup), 'changed_branch': branch['title'], 'other_content_preserved': True, 'archive_checks': 'passed', 'native_visual_check': 'not performed'}, ensure_ascii=False))
