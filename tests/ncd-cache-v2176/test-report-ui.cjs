const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const {parseHTML}=require('linkedom');
const src=fs.readFileSync(require('path').join(__dirname,'../../field-work-reporting-v200.mjs'),'utf8');
const start=src.indexOf('const esc='),end=src.indexOf('function dashboardIntegrity');
const render=vm.runInNewContext(src.slice(start,end)+';renderNcdActivityV2176');
const input={ncd_integrity:{passed:true,checked_at:'2026-10-20T00:30:00Z'},ncd_activity:{daily:[{service_day:'2026-10-01',people:10},{service_day:'2026-10-02',people:12}],weekly:[{week_start:'2026-09-28',people:18}]}};
const {document}=parseHTML(render(input));assert.equal(document.querySelectorAll('details').length,2);assert.equal(document.querySelectorAll('tbody tr').length,3);assert(document.toString().includes('+2'));
assert(!render({...input,ncd_integrity:{passed:false}}).includes('<table'));
assert.equal(render({}),'');console.log('Report UI: passed (daily/weekly, delta, unverified gate)');
