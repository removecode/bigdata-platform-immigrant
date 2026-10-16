import csv, json, re, sys, hashlib
from pathlib import Path
from collections import defaultdict, Counter
sys.path.insert(0,str(Path(__file__).parent/'pydeps'))
import sqlglot
from sqlglot import exp
from sqlglot.optimizer.scope import traverse_scope

BASE=Path(__file__).resolve().parents[2]
OUT=Path(__file__).parent
YARN='大数据平台YARN上的任务梳理-云脑大数据平台.csv'
SRC='大数据平台YARN上的任务梳理-项目数据来源及输出.csv'
def key(s):
    return re.sub(r'\(oozie\)$','',s.strip().lstrip('*＊').splitlines()[0]).strip()
def records(name, skip=0):
    with (BASE/name).open(encoding='utf-8-sig',newline='') as f:
        r=csv.reader(f)
        for _ in range(skip): next(r)
        header=next(r)
        while True:
            start=r.line_num+1
            try: row=next(r)
            except StopIteration: break
            yield start,r.line_num,row
TABLE=re.compile(r'\b(?:default|csc|sri|sodl|ngaf|ac|edr|sip|cloudeye)\.[a-zA-Z_][\w]*',re.I)
manual={}
for start,end,row in records(SRC):
    if not row[0].strip():continue
    blob=row[1]
    source=re.split(r'数据输出[：:]',blob,maxsplit=1)[0]
    output=blob[len(source):]
    manual[key(row[0])]={'raw':blob,'source':source,'tables':sorted(set(t.lower() for t in TABLE.findall(source))), 'outputs':sorted(set(t.lower() for t in TABLE.findall(output))), 'line':start, 'end':end}

jobs={}; units=[]; current=None; sub=''; raw_rows=[]
for start,end,row in records(YARN,1):
    row+=['']*max(0,32-len(row))
    if row[0].strip()=='汇总':current=None;continue
    if row[0].strip():
        current=key(row[0]);sub=''
        jobs.setdefault(current,{'task':current,'status':row[1],'owner':row[2],'purpose':row[3],'sqls':[],'rows':[]})
    if not current or not row[1].strip():continue
    jobs[current]['rows'].append(start)
    if row[4].strip() not in ('','/','、'):sub=row[4]
    sql=row[21].strip()
    raw_rows.append([current,start,end,sub,row[7],row[20],sql])
    if not re.search(r'\b(SELECT|WITH|INSERT|CREATE|ALTER|SHOW|DELETE|UPDATE)\b',sql,re.I):continue
    unit={'task':current,'sub':sub or '(未命名)','line':start,'end':end,'engine':row[7], 'url':row[20], 'sql':sql,'read':[],'unqualified':[],'write':[],'paths':[], 'method':'AST','error':''}
    cleaned=sql.replace('\\n','\n').replace('\\t','\t')
    # Resolve only template syntax, not business logic; preserve original SQL in evidence.
    cleaned=re.sub(r'\{log_type\}', '__log_type__',cleaned)
    cleaned=re.sub(r'\$?\{\{?[\w.]+\}?\}', '1',cleaned)
    cleaned=re.sub(r':\b[a-zA-Z_]\w*', '1',cleaned)
    cleaned=re.sub(r'%[ds]', '1',cleaned)
    cleaned=re.sub(r'%\([\w]+\)s', '(1)',cleaned)
    if current=='active-domain-elt-job' and '\"\"\"' in cleaned:
        cleaned=';\n'.join(re.findall(r'\"\"\"(.*?)\"\"\"',cleaned,re.S))
    if current=='black-ti-context-produce-prc' and sub=='INFO_EXIST_CHECK_SQL':
        cleaned=re.sub(r'(LIMIT\s+1)\s+(SELECT)',r'\1;\n\2',cleaned,flags=re.I)
    unit['paths']=re.findall(r'''(?:directory)\s+['"]([^'"]+)['"]''',cleaned,re.I)
    try:
        trees=sqlglot.parse(cleaned,read='clickhouse' if row[7].lower()=='ck' or current=='sodl_ods_info' else 'hive')
        all_read=set(); unqualified=set(); writes=set()
        for tree in trees:
            if tree is None:continue
            for scope in traverse_scope(tree):
                for _,(_,source) in scope.selected_sources.items():
                    if isinstance(source,exp.Table):
                        name='.'.join(x for x in [source.catalog,source.db,source.name] if x).lower()
                        if source.db:all_read.add(name)
                        else:unqualified.add(name)
            if isinstance(tree,(exp.Insert,exp.Create,exp.Update,exp.Delete)):
                target=tree.this
                if isinstance(target,exp.Schema):target=target.this
                if isinstance(target,exp.Table):writes.add('.'.join(x for x in [target.catalog,target.db,target.name] if x).lower())
        unit['read']=sorted(all_read);unit['unqualified']=sorted(unqualified);unit['write']=sorted(writes)
    except Exception as e:
        unit['method']='需复核';unit['error']=str(e)[:450]
        unit['read']=sorted(set(x.lower() for x in re.findall(r'\b(?:FROM|JOIN)\s+((?:default|csc|sri|sodl|ngaf|ac|edr|sip)\.[a-zA-Z_]\w*)',sql,re.I)))
    units.append(unit);jobs[current]['sqls'].append(len(units)-1)

OUT.mkdir(exist_ok=True)
(OUT/'parsed.json').write_text(json.dumps({'jobs':jobs,'manual':manual,'units':units,'raw_rows':raw_rows},ensure_ascii=False,indent=2),encoding='utf-8')
print('jobs',len(jobs),'manual',len(manual),'sql_units',len(units))
for i,u in enumerate(units):
    print(i,u['task'],u['sub'],'L'+str(u['line']),u['method'],'R=',','.join(u['read']),'U=',','.join(u['unqualified']),'W=',','.join(u['write']))
    if u['error']:print('ERROR',u['error'][:220])
