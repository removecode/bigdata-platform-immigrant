import fs from 'node:fs/promises';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';
const dir = new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1');
const data = JSON.parse(await fs.readFile(`${dir}/audit.json`,'utf8'));
const wb = Workbook.create();
const sheets={};
const names=['核对说明','逐任务核对','逐表差异','SQL片段索引','SQL原文'];
for(const name of names)sheets[name]=wb.worksheets.add(name);
function col(n){let s='';for(n++;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s;}
function table(name,headers,rows,widths){
  const s=sheets[name],last=col(headers.length-1),end=rows.length+1;
  s.getRange(`A1:${last}${end}`).values=[headers,...rows];
  s.showGridLines=false;
  s.getRange(`A1:${last}${end}`).format.font={name:'Microsoft YaHei',size:10,color:'#243247'};
  s.getRange(`A1:${last}${end}`).format.wrapText=true;
  s.getRange(`A1:${last}${end}`).format.verticalAlignment='top';
  widths.forEach((w,i)=>s.getRange(`${col(i)}1:${col(i)}${end}`).format.columnWidth=w);
  s.getRange(`A1:${last}1`).format={fill:'#263C56',font:{name:'Microsoft YaHei',bold:true,color:'#FFFFFF',size:10},rowHeight:32};
  rows.forEach((row,i)=>{
    const lines=Math.max(...row.map((v,c)=>String(v??'').split('\n').reduce((n,line)=>n+Math.max(1,Math.ceil([...line].reduce((a,ch)=>a+(ch.charCodeAt(0)>255?2:1),0)/(widths[c]-2))),0)));
    s.getRange(`A${i+2}:${last}${i+2}`).format.rowHeight=Math.min(400,Math.max(30,lines*15+10));
  });
  s.tables.add(`A1:${last}${end}`,true,`AuditTable${names.indexOf(name)+1}`);
  s.freezePanes.freezeRows(1);
  return s;
}
const join=a=>a.join('\n')||'—';
table('逐任务核对',[
 '任务','核对结论','SQL片段数','清单状态','负责人','手工来源表','SQL可见输入表','SQL引用但手工未标','手工标注但快照未见','短表名对应','核对说明','原手工来源与输出','来源清单位置','SQL证据位置'
],data.tasks.map(r=>[r.task,r.conclusion,r.sql_count,r.status,r.owner,r.manual_tables.length?join(r.manual_tables):'未列具体表或缺记录',join(r.read_tables),join(r.sql_only),r.sql_count?join(r.manual_only):'缺SQL，不能判断',join(r.short_match),r.note||'仅核对提供的SQL输入表集合；非SQL外部输入需查代码。',r.manual_raw,r.manual_ref,r.sql_refs||'无SQL正文']),[45,28,12,13,12,58,58,58,58,52,68,65,38,46]);
table('逐表差异',['任务','表名','对照结果','SQL证据','手工来源位置','输入引擎范围','说明'],data.details,[45,72,30,60,42,22,54]);
table('SQL片段索引',['证据ID','任务','原子任务标签','引擎','证据范围','SQL可见输入','未限定库名','写入表/目录（不计输入）','来源文件','起始行','结束行','代码引用地址'],data.units.map(u=>[u.id,u.task,u.sub,u.db_kind,u.quality,join(u.read),join(u.unqualified),join([...u.write,...u.paths]),'大数据平台YARN上的任务梳理-云脑大数据平台.csv',u.line,u.end,u.url]),[15,45,39,15,43,70,35,70,45,12,12,80]);
const sqlLines=[];
for(const u of data.units){
  // Literal backslash-n is source text; preserve it rather than pretending it is a source line.
  u.sql.split('\n').forEach((line,i)=>sqlLines.push([u.id,u.task,i+1,line]));
}
table('SQL原文',['证据ID','任务','片段内行号','原始SQL正文（未改写）'],sqlLines,[15,45,16,150]);
const desc=sheets['核对说明'];
const notes=[
 ['项目','内容'],
 ['核对范围','45个归一化任务，40条手工来源记录，81条非空SQL片段。Oozie/执行记录合并到同一服务，SQL片段不等于独立业务任务。'],
 ['证据边界','核对当前材料中的SQL快照与手工来源声明，不代表现网全量代码、启用状态或迁移验收。无SQL不能判为无依赖。'],
 ['一致的含义','仅指已提供SQL中可识别的输入表集合与手工声明对应。Mongo、Redis、Pulsar、EDS等非SQL输入不因缺SQL引用而被否定。'],
 ['解析口径','区分FROM/JOIN真实表与CTE、子查询、UDF及写入目标。参数仅作解析占位；截断和动态片段仅确认可见引用，不补造缺失语句。'],
 ['库名与引擎','未限定库名不擅自补default。SODL接入SQL和两个ClickHouse消费任务单列引擎，避免同名Hive/ClickHouse表混淆。'],
 ['原始来源','云脑任务CSV：服务、子任务、SQL正文；项目数据来源及输出CSV：人工来源声明。每条证据保留文件名和起始行，SQL原文按片段ID可筛选。'],
 ['独立校验','原始XLSX中的81份SQL正文与CSV匹配。每份SQL的显式限定库名FROM/JOIN引用与解析结果交叉核验。原始材料未修改。'],
 ['sodl_dwb_info','SQL读取IP信誉表而手工漏标；4张DWB同时标在手工输入和输出，快照未读取这4张表。需要纠正输入/输出边界。'],
 ['ti-ip-detection-send-prc','SQL读取ClickHouse sodl.operation_rdp_event_log，人工标记sodl.handle_info_log。需核实现网版本，不能直接按旧清单提接入需求。'],
 ['black-ti-context-produce-prc','已提供4类统计及存在性检查SQL未读租户订阅表，来源清单标了；需核查其他模块，不能据此判整任务不使用。'],
 ['log_compress','手工标default.dwb_url_info为输入，已提供快照未见引用；Domain SQL被截断，不能据此删除依赖。'],
 ['yara / sp / thug','三项有SQL而手工无对应记录。yara读default.dwb_md5_record、sri.ods_sri_hashinfo；sp读ods_sp_old_dev_update（库名待确认）；thug读两套Domain DWB。'],
 ['动态与截断','attack-ip-analysis有动态表名/SQL拼接，APT有截断SQL。可见固定引用对上不代表完整依赖已核实。'],
 ['后续动作','优先补SQL有而手工漏标的表；手工有而快照未见的表查部署代码/配置/视图；无SQL任务按非SQL接入、维护或缺资料逐项落实。'],
 ['迁移决策','本表不自动改变任务去留或删除原依赖。提供了SQL的暂停/历史任务仍需确认是否运行。'],
];
table('核对说明',notes[0],notes.slice(1),[37,115]);
const start=notes.length+3;
desc.getRange(`A${start}:B${start}`).values=[['核对结论','任务数']];
desc.getRange(`A${start}:B${start}`).format={fill:'#263C56',font:{color:'#FFFFFF',bold:true},rowHeight:28};
let offset=1;
for(const category of Object.keys(data.counts)){
 const r=start+offset++;
 desc.getRange(`A${r}`).values=[[category]];
 desc.getRange(`B${r}`).formulas=[[`=COUNTIF('逐任务核对'!B2:B46,A${r})`]];
}
desc.getRange(`A${start+offset}`).values=[['合计']];
desc.getRange(`B${start+offset}`).formulas=[[`=SUM(B${start+1}:B${start+offset-1})`]];
desc.getRange(`A${start+1}:B${start+offset}`).format.rowHeight=28;
desc.getRange(`B${start+1}:B${start+offset}`).setNumberFormat('0');
sheets['逐任务核对'].getRange('B2:B46').conditionalFormats.add('containsText',{text:'差异',format:{fill:'#FCE4D6'}});
sheets['逐任务核对'].getRange('B2:B46').conditionalFormats.add('containsText',{text:'缺',format:{fill:'#FFF2CC'}});
const check=await wb.inspect({kind:'table',range:`核对说明!A${start}:B${start+offset}`,include:'values,formulas',tableMaxRows:10,tableMaxCols:2,maxChars:2000});
console.log(check.ndjson);
const errors=await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},summary:'formula errors'});
console.log(errors.ndjson);
const previews=[['核对说明',`A${start}:B${start+offset}`],['逐任务核对','A2:E10'],['逐表差异','A1:C6'],['SQL片段索引','A1:E5'],['SQL原文','A1:D9']];
const file=await SpreadsheetFile.exportXlsx(wb);
await file.save(`${dir}/逐任务SQL与手工来源核对.xlsx`);
console.log('Export saved');
for(let i=0;i<previews.length;i++){
 const [sheetName,range]=previews[i];
 console.log('Rendering',sheetName,range);
 const blob=await wb.render({sheetName,range,scale:1,format:'png'});
 await fs.writeFile(`${dir}/preview-${i+1}.png`,new Uint8Array(await blob.arrayBuffer()));
}
console.log(JSON.stringify({tasks:data.tasks.length,sqlFragments:data.units.length,tableRelations:data.details.length,sqlLines:sqlLines.length,output:`${dir}/逐任务SQL与手工来源核对.xlsx`}));
