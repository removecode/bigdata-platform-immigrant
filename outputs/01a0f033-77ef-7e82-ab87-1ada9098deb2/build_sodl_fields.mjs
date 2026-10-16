import fs from 'node:fs/promises';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

const outputDir = 'D:/project/bigdata/outputs/01a0f033-77ef-7e82-ab87-1ada9098deb2';
const definitions = [
  ['sodl.dns_log', 'producttype:varchar manage:varchar productver:varchar srcip:varchar dstip:varchar qr:integer qtypes:varchar queries:varchar atypes:varchar answers:varchar log_num:bigint year:integer month:integer day:integer hour:integer'],
  ['sodl.endpoint_security_log', 'threatclass:integer threattype:integer threatsubtype:integer producttype:varchar manage:varchar manageip:varchar productver:varchar engine:varchar filemd5:varchar domain:varchar log_num:bigint year:integer month:integer day:integer hour:integer'],
  ['sodl.network_security_log', 'threatclass:integer threattype:integer threatsubtype:integer producttype:varchar manage:varchar productver:varchar srcip:varchar dstip:varchar reqruleid:varchar filehash:varchar action:integer titype:integer risklevel:integer severity:integer engine:varchar url:varchar result:varchar log_num:bigint rulename:varchar requesthead:varchar requestbody:varchar year:integer month:integer day:integer hour:integer'],
  ['sodl.sip_iocstat_log', 'producttype:varchar manage:varchar productver:varchar ioc_type:varchar ioc:varchar record_count:bigint log_num:bigint year:integer month:integer day:integer hour:integer'],
  ['sodl.url_log', 'producttype:varchar manage:varchar productver:varchar sip:varchar dip:varchar host:varchar uri:varchar urls:varchar log_num:bigint year:integer month:integer day:integer hour:integer'],
  ['sodl.http_log', 'producttype:varchar manage:varchar productver:varchar srcip:varchar dstip:varchar url:varchar log_num:bigint year:integer month:integer day:integer hour:integer'],
];
const rows = definitions.flatMap(([table, fields]) => fields.split(' ').map(entry => {
  const [field, type] = entry.split(':');
  return [table, field, type, null, null];
}));
if (rows.length !== 90) throw new Error(`Expected 90 fields, got ${rows.length}`);

const workbook = Workbook.create();
const sheet = workbook.worksheets.add('SODL日志字段');
sheet.showGridLines = false;
sheet.getRange('A1').values = [['SODL 日志表字段清单']];
sheet.getRange('A2').values = [['来源：用户提供的 6 张表字段清单；说明和示例待补充']];
sheet.getRange('A4:E94').values = [['表名', '字段', '类型', '说明', '示例'], ...rows];
sheet.getRange('A1:E94').format.font = { name: 'Arial', size: 11, color: '#1F2937' };
sheet.getRange('A1').format.font = { name: 'Arial', size: 15, bold: true, color: '#111827' };
sheet.getRange('A2').format.font = { name: 'Arial', size: 10, italic: true, color: '#6B7280' };
sheet.getRange('A4:E4').format = { fill: '#1F2937', font: { name: 'Arial', size: 11, bold: true, color: '#FFFFFF' } };
sheet.getRange('A:A').format.columnWidth = 32;
sheet.getRange('B:B').format.columnWidth = 24;
sheet.getRange('C:C').format.columnWidth = 14;
sheet.getRange('D:D').format.columnWidth = 28;
sheet.getRange('E:E').format.columnWidth = 28;
sheet.getRange('A4:E94').format.rowHeight = 21;
sheet.freezePanes.freezeRows(4);
const table = sheet.tables.add('A4:E94', true, 'SodlLogFields');
table.showFilterButton = true;

const check = await workbook.inspect({ kind: 'table', range: 'SODL日志字段!A4:E10', include: 'values', tableMaxRows: 7, tableMaxCols: 5, maxChars: 2200 });
console.log(check.ndjson);
await fs.mkdir(outputDir, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(`${outputDir}/SODL日志表字段清单.xlsx`);
console.log(`rows=${rows.length}; tables=${definitions.length}`);
const preview = await workbook.render({ sheetName: 'SODL日志字段', range: 'A1:E19', scale: 1.4, format: 'png' });
await fs.writeFile(`${outputDir}/sodl-fields-preview.png`, new Uint8Array(await preview.arrayBuffer()));
