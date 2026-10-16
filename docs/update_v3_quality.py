"""Add quality strategy comparison to saved v3, preserving existing map content."""
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
from datetime import datetime
from uuid import uuid4
from zipfile import ZipFile

BASE = Path(__file__).resolve().parent
TARGET = BASE / '大数据迁移-E2E规划-v3.xmind'
COPY = BASE / '大数据迁移-E2E规划-v3-质量保障方案已更新.xmind'


def topic(title, children=()):
    node = {'id': uuid4().hex, 'class': 'topic', 'title': title}
    if children:
        node['children'] = {'attached': [topic(c) if isinstance(c, str) else c for c in children]}
    return node


def main():
    initial = TARGET.read_bytes()
    with ZipFile(TARGET) as z:
        infos = z.infolist()
        entries = {i.filename: z.read(i.filename) for i in infos}
        comment = z.comment
    data = json.loads(entries['content.json'])
    original = copy.deepcopy(data)
    assert not any(s['title'] == '质量保障方案对比' for s in data)
    root = topic('质量保障方案对比与回滚', [
        topic('决策建议与适用边界', [
            '[建议待确认] 主方案B：新旧双跑、隔离输出、分批切流',
            'A用于前期快速筛选；完整业务仍需适用的E2E验收',
            'C不作为默认方案：同时写同一生产文档/Key/Topic风险高',
            '分别写新旧实例属于隔离输出；仍需确认业务读取路由与增量追平',
            '双跑不等于质量通过：输入可比、差异闭环、实际读取和恢复均需证据',
            '环境、阈值、观察期、资源及审批人待落实；当前未执行双写或切流',
        ]),
        topic('方案A：离线对账后切换', [
            '做法：固定窗口和版本，新旧查询/加工结果对比后安排切换',
            '覆盖：查询、加工逻辑、受控样例；持续增量和状态演变需另验',
            '正确性：依赖样例和窗口覆盖，不能只凭行数或抽样宣称全量一致',
            '生产风险：验证期较低，风险集中于切换后的实际运行',
            '成本：临时资源相对少，但差异定位和E2E验证仍需投入',
            '回滚：旧版本与输入可用；切换后错误目标数据仍需恢复/补偿',
            '适用：简单只读、可确定性重算任务；作为自动化预筛选',
            '不适用作唯一证据：增量累加、删除、TTL及外部业务副作用',
        ]),
        topic('方案B：双跑＋隔离输出【推荐】', [
            '做法：旧任务继续生产；新任务写影子集合/前缀/实例/Topic',
            '覆盖：真实查询转换、目标状态、新鲜度；另验实际业务读取',
            '正确性：相同完整窗口及可解释初始状态，持续独立读回对账',
            '生产风险：较低；隔离写入仍须限制共享计算/存储/网络负载',
            '成本：需要影子环境、双跑计算和对账资源，按批次复用控制成本',
            '回滚：切流前无生产写污染；切流后仍需数据恢复与副作用补偿',
            '适用：多数生产加工及Mongo/Redis/Kafka消费同步链路',
            '执行：小样本试点 → 批量自动验证 → 审批后单写者切流 → 观察',
        ]),
        topic('方案C：双写同一生产目标【不默认采用】', [
            '做法：新旧任务同时写同一Mongo文档、Redis Key或生产Kafka Topic',
            '覆盖：真实写入，但互相覆盖可能掩盖新任务错误',
            '正确性：要求业务幂等、版本/冲突控制、去重及可追溯写入来源',
            '生产风险：重复累加、覆盖、重复消息和不可撤销业务副作用',
            '成本：节约影子存储不代表更便宜，冲突治理和补偿可能更贵',
            '回滚：新旧结果混在生产中，恢复范围和责任难划分',
            '仅考虑：确有必要，已证明幂等/冲突控制且业务批准的特定场景',
            '本项目结论：不作为默认质量保障方案，不以双写替代对账',
        ]),
        topic('按任务类型组合验证', [
            '原始/压缩日志消费者：A固定窗口映射对账 → B真实程序影子输出',
            '中间表链路：固定输入验模型 → 下游B双跑；不能跳过中间结果校验',
            'Mongo接入：快照/增量衔接、更新删除、重放恢复与持续对账',
            'Mongo/Redis输出：已知初始状态 → 新增/更新/删除/TTL → 重试补数',
            'Kafka输出：影子Topic、独立验证消费者；验内容/重复/分区顺序及下游效果',
            '文件/SCP/指标：内容、完整发布、接收使用及重复处理',
        ]),
        topic('统一质量放行与里程碑', [
            'M0：约定本批质量方案、环境、阈值、业务验收人与恢复目标',
            'M1-M4：各业务包按G0-G5验收，方案选择不改变依赖先后',
            '切流前：输入/模型/查询/目标/业务适用验证通过；关键差异闭环',
            '切流前：正常和峰值性能、补数、回滚演练达标',
            '切流时：明确批次/业务键/位点边界及迟到归属，同一范围单一有效写者',
            '切流后：监测时效/差异/业务指标，覆盖约定周期',
            'M5：所有保留消费者验收，无旧供数依赖后才退出共享旧链路',
        ]),
        topic('回滚准备与触发', [
            '预先约定：关键错漏/重复、延迟超限、业务失败等阈值及决策人',
            '预先约定：恢复时间、可接受数据损失、执行人和验收人',
            '保存：旧代码/配置/调度、成功批次/位点、必要备份和正确恢复点',
            '保留：旧接入及中间加工在回退期的可恢复性和所需输入数据',
            '若旧目标停止更新：明确回切前增量如何追平，不能直接回路由',
        ]),
        topic('回滚执行与目标补偿', [
            '顺序：停止新写入 → 定位影响范围 → 恢复/补偿状态 → 恢复旧任务和读取 → 补边界 → 对账',
            '中间结果：恢复正确完整批次；旧模型过期时先恢复上游并补齐',
            'Mongo：恢复受影响文档/删除，防止覆盖其他业务的合法更新',
            'Redis：重建受影响Key/TTL，或回到已追平旧实例并验证',
            'Kafka：已消费消息不能靠回切撤销；按消息ID去重、重放或业务补偿',
            '读取者：目标状态正确后再恢复相应路由，验证实际业务读取',
            '演练仅在隔离或批准范围内；补偿能力不足不得放行相关生产切流',
        ]),
        topic('管理决策与提效', [
            '请求确认：主方案B，A辅助，C仅特批场景',
            '资源诉求：影子环境、双跑/对账配额、恢复保留期及责任人',
            '提效：共用映射、对账/读回工具；依赖编排、限并发、断点续跑',
            '自动化不取消业务验收与生产审批；工具需通过已知失败样例验证',
            '成本和时间以试点实测为准，不承诺未经验证的收益比例',
        ]),
    ])
    root['structureClass'] = 'org.xmind.ui.logic.right'
    data.append({'id': uuid4().hex, 'class': 'sheet', 'title': '质量保障方案对比', 'rootTopic': root})
    assert data[:-1] == original
    updated = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    if COPY.exists():
        raise FileExistsError(COPY)
    backup = BASE / f'大数据迁移-E2E规划-v3-质量方案更新前-{datetime.now():%Y%m%d-%H%M%S-%f}.xmind'
    fd, temporary = tempfile.mkstemp(prefix='quality-map-', suffix='.xmind', dir=BASE)
    os.close(fd)
    try:
        with ZipFile(temporary, 'w') as z:
            z.comment = comment
            for info in infos:
                z.writestr(info, updated if info.filename == 'content.json' else entries[info.filename])
        with ZipFile(temporary) as z:
            assert z.testzip() is None
            assert json.loads(z.read('content.json')) == data
            for name in entries:
                if name != 'content.json':
                    assert z.read(name) == entries[name]
        assert hashlib.sha256(TARGET.read_bytes()).digest() == hashlib.sha256(initial).digest(), 'Source changed'
        shutil.copy2(TARGET, backup)
        os.replace(temporary, TARGET)
        shutil.copy2(TARGET, COPY)
        assert TARGET.read_bytes() == COPY.read_bytes()
    finally:
        if Path(temporary).exists():
            Path(temporary).unlink()
    print(json.dumps({'updated': str(TARGET), 'copy': str(COPY), 'backup': str(backup),
                      'sheets': [s['title'] for s in data], 'unchanged_existing_sheets': True,
                      'archive_checks': 'passed', 'native_visual_check': 'not performed'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
