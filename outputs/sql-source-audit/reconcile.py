import json,re,sys,hashlib,csv
from pathlib import Path
from collections import Counter
from zipfile import ZipFile
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parent
BASE=ROOT.parents[1]
d=json.loads((ROOT/'parsed.json').read_text(encoding='utf-8'))
jobs,manual,units=d['jobs'],d['manual'],d['units']

# Independent read of original xlsx values, without applying malformed legacy styles.
ns={'m':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
workbook_checks=[]
for p in BASE.glob('*.xlsx'):
    with ZipFile(p) as z:
        strings=[]
        if 'xl/sharedStrings.xml' in z.namelist():
            strings=[''.join(t.text or '' for t in e.findall('.//m:t',ns)) for e in ET.fromstring(z.read('xl/sharedStrings.xml')).findall('m:si',ns)]
        values=[]
        for name in z.namelist():
            if re.fullmatch(r'xl/worksheets/sheet\d+.xml',name):
                for c in ET.fromstring(z.read(name)).findall('.//m:c',ns):
                    v=c.find('m:v',ns)
                    if c.get('t')=='s' and v is not None:values.append(strings[int(v.text)])
                    elif c.get('t')=='inlineStr':values.append(''.join(t.text or '' for t in c.findall('.//m:t',ns)))
                    elif v is not None:values.append(v.text or '')
        normalized={v.strip().replace('\r\n','\n') for v in values}
        matches=sum(u['sql'].replace('\r\n','\n') in normalized for u in units)
        workbook_checks.append({'file':p.name,'sql_matches':matches,'csv_sqls':len(units)})

special={
 'sodl_dwb_info':'SQL漏标IP信誉；4张SODL DWB同时列在手工输入/输出中，已提供SQL只写结果目录、未读这4张表，疑似混入产出。URL SQL存在不证明分支现网启用。',
 'log_compress':'Domain SQL在字符串中截断；default.dwb_url_info手工标为输入，但现有快照未读。不能据不完整SQL判断该输入无用。',
 'black-ti-context-produce-prc':'4类统计SQL及存在性检查均未读租户订阅表，手工清单却列出。需核查其他模块，不能直接删除依赖。',
 'ti-ip-detection-send-prc':'SQL明确读sodl.operation_rdp_event_log，清单标sodl.handle_info_log。属于ClickHouse输入，不能按Hive缺表处理。',
 'domain-hit-devnum-cronjob':'SQL未限定ods_custom_upload_data库名，与手工default.ods_custom_upload_data短名一致；会话默认库需确认。',
 'sp-old-update-report-cron-job':'当前CSV已有SQL：读取未限定库名的ods_sp_old_dev_update；手工来源清单没有该任务。',
 'yara-sample-query-job':'当前CSV已有SQL：default.dwb_md5_record与sri.ods_sri_hashinfo；不能沿用此前无SQL的结论，也不能把md5_record当md5_info。',
 'thug-task-monitor-prc':'手工来源清单缺任务；SQL读取default/SODL Domain DWB。任务已下线记录需现网复核，不代表需恢复迁移。',
 'attack-ip-analysis-cronjob':'固定表名与手工列表吻合，但有动态表名/CTE片段及不完整模板；动态替换可能引入其他表，不能判完整对应。',
 'apt-hunting-monitor-process-job':'可见表名与手工列表对应，但IP/URL SQL被截断；两份清单去留状态冲突，需核实现网版本。',
 'active-domain-elt-job':'两条CSV子任务标签与正文疑似对调：INFO_EXIST_CHECK_SQL为主体查询，ACTIVE_DOMAIN_SQL为检查SQL配置。输入集合仍可核对。',
 'sodl_ods_info':'SQL读取的是ClickHouse SODL源表；与Hive目标同名不代表读取Hive，也不代表自依赖。',
}

for i,u in enumerate(units):
    u['id']=f'SQL-{i+1:03}'
    u['db_kind']='ClickHouse' if u['task'] in ('sodl_ods_info','ti-ip-detection-send-prc','ti-hot-data-detection-fusing-prc') else 'Hive'
    u['quality']='完整快照可解析（不代表现网全量）'
    if u['method']=='需复核':
        u['method']='可见FROM/JOIN人工复核'
        u['quality']='截断SQL，仅确认可见引用' if u['task'] in ('log_compress','apt-hunting-monitor-process-job') else '动态/不完整模板，仅确认可见引用'
    if u['task']=='active-domain-elt-job' and u['line']==3126:
        u['quality']='检查SQL配置已拆分解析；子任务标签疑似对调'
    if u['task']=='black-ti-context-produce-prc' and u['line']==3420:
        u['quality']='连续检查SQL已拆分解析'
    # Independent direct FROM/JOIN scan validates all qualified source relations.
    visible=set(x.lower() for x in re.findall(r'\b(?:FROM|JOIN)\s+((?:default|csc|sri|sodl|ngaf|ac|edr|sip)\.[a-zA-Z_]\w*)',u['sql'],re.I))
    assert visible==set(u['read']),(u['id'],visible,u['read'])

rows=[];details=[]
for task,job in jobs.items():
    us=[units[i] for i in job['sqls']]
    m=manual.get(task)
    expected=set(m['tables'] if m else [])
    reads=set(t for u in us for t in u['read'])
    unq=set(t for u in us for t in u['unqualified'])
    candidate={}
    for short in unq:
        hits=[t for t in expected if t.split('.')[-1]==short]
        if len(hits)==1:candidate[short]=hits[0]
    matched=reads&expected
    sql_only=reads-expected
    manual_only=expected-reads-set(candidate.values())
    incomplete=any(u['method']!='AST' for u in us)
    if not us:status='缺SQL，无法核对'
    elif not m:status='缺手工来源记录'
    elif sql_only or manual_only:status='发现表名差异'
    elif candidate or unq:status='短名对应，库名待确认'
    elif incomplete:status='可见引用一致，动态或截断待补'
    else:status='已提供SQL表集合一致'
    notes=special.get(task,'')
    if not us:notes='材料没有SQL正文；保留手工来源，不能将无SQL误判为无依赖。'
    src_lines=[]
    if m:
        src_lines=[x.strip() for x in m['source'].splitlines() if x.strip() and not re.fullmatch(r'数据来源[：:]?',x.strip())]
    row={**job,'conclusion':status,'sql_count':len(us),'manual_count':len(expected),'sql_table_count':len(reads)+len(unq),
         'manual_tables':sorted(expected),'read_tables':sorted(reads)+[t+'（未限定库名）' for t in sorted(unq)],
         'match':sorted(matched),'sql_only':sorted(sql_only),'manual_only':sorted(manual_only),
         'short_match':[f'{a} → {b}（库名待确认）' for a,b in candidate.items()],
         'manual_raw':m['raw'] if m else '手工清单无此任务',
         'manual_source':m['source'] if m else '',
         'manual_ref':f'{"大数据平台YARN上的任务梳理-项目数据来源及输出.csv"} 第{m["line"]}行' if m else '无记录',
         'sql_refs':'；'.join(f'{u["id"]} 第{u["line"]}行' for u in us),
         'external':'\n'.join(x for x in src_lines if not re.search(r'\b(?:default|csc|sri|sodl|ngaf|ac|edr|sip|cloudeye)\.',x)),
         'note':notes,'incomplete':incomplete}
    rows.append(row)
    for t in sorted(expected|reads):
        if not us:kind='仅手工标注，缺SQL'
        elif t in matched:kind='SQL与手工一致'
        elif t in candidate.values():kind='短名对应，库名待确认'
        elif t in sql_only:kind='SQL有引用，手工未标' if m else 'SQL有引用，手工缺任务'
        else:kind='手工标注，快照未见引用'
        evidence=[u for u in us if t in u['read'] or any(t==full and short in u['unqualified'] for short,full in candidate.items())]
        details.append([task,t,kind,'\n'.join(f'{u["id"]} / {u["sub"]} / 第{u["line"]}行' for u in evidence) or '无可见SQL引用',
                        row['manual_ref'], 'ClickHouse' if task in ('sodl_ods_info','ti-ip-detection-send-prc','ti-hot-data-detection-fusing-prc') else 'Hive/清单声明',
                        '同时出现在手工输出；不视为已证明输入' if m and t in m['outputs'] and t in manual_only else ('SQL证据范围不完整' if incomplete else '')])
    for t in sorted(unq-set(candidate)):
        details.append([task,t+'（未限定库名）','SQL短表名，库名待确认','\n'.join(u['id'] for u in us if t in u['unqualified']),row['manual_ref'],'Hive','不擅自补default库名'])

counts=Counter(r['conclusion'] for r in rows)
result={'tasks':rows,'details':details,'units':units,'counts':dict(counts),'workbook_checks':workbook_checks,
        'raw_rows':d['raw_rows'],'manual_records':manual,
        'source_hashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [BASE/'大数据平台YARN上的任务梳理-云脑大数据平台.csv',BASE/'大数据平台YARN上的任务梳理-项目数据来源及输出.csv']}}
assert len(rows)==45 and len(set(r['task'] for r in rows))==45
assert sum(r['sql_count'] for r in rows)==81
assert set(manual)<=set(jobs)
(ROOT/'audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print('counts',dict(counts),'workbook_checks',workbook_checks)
for r in rows:print(r['task'],r['sql_count'],r['conclusion'],'漏:',','.join(r['sql_only']),'未见:',','.join(r['manual_only']))
