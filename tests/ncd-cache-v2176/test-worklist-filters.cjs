const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const {parseHTML}=require('linkedom');
const src=fs.readFileSync(require('path').join(__dirname,'../../field-work-reporting-v200.mjs'),'utf8');
const code=src.slice(src.indexOf('async function openWorkList('),src.indexOf('\nasync function openFollowups'));
const {document}=parseHTML('<html><body><div id="modal"></div></body></html>');
const body=document.querySelector('#modal'),calls=[],pending=[];
const fn=vm.runInNewContext(code+';openWorkList',{openModal:()=>body,PAGE_SIZE:50,prepareMobileTableCards:()=>{},effectiveScope:()=> 'all',ownerPid:null,num:v=>String(v),esc:v=>String(v??''),statusText:v=>v,priorityText:v=>v,fmtDate:v=>v||'',supabase:{rpc:(name,args)=>{calls.push({name,args});return new Promise(resolve=>pending.push(resolve));}}});
const row={display_name:'Synthetic',task_type:'ncd',status:'complete',progress_percent:100};
(async()=>{
 const first=fn({community:'community-fixture'});
 const status=body.querySelector('[data-filter-status]'),task=body.querySelector('[data-filter-task]');
 // Linkedom's select exposes a read-only value; use a test-only value accessor.
 Object.defineProperty(status,'value',{value:'due',writable:true});Object.defineProperty(task,'value',{value:'ncd',writable:true});
 const changed=status.onchange();assert.equal(calls[1].args.p_status,'due');assert.equal(calls[1].args.p_task_type,'ncd');assert.equal(calls[1].args.p_offset,0);assert.equal(calls[1].args.p_community,'community-fixture');
 pending[1]({data:[],error:null});await changed;
 pending[0]({data:Array(50).fill(row),error:null});await first;
 assert(body.querySelector('[data-field-count]').textContent.includes('แสดง 0 ราย'));assert(body.querySelector('[data-field-more]').hidden);assert(body.querySelector('[data-field-list-body]').textContent.includes('ไม่พบรายการ'));
 status.value='complete';const completed=status.onchange();pending[2]({data:Array(50).fill(row),error:null});await completed;
 assert.equal(calls[2].args.p_offset,0);assert.equal(calls[2].args.p_status,'complete');assert(!body.querySelector('[data-field-more]').hidden);
 const more=body.querySelector('[data-field-more]').onclick();assert.equal(calls[3].args.p_offset,50);assert.equal(calls[3].args.p_status,'complete');pending[3]({data:[row],error:null});await more;
 assert(body.querySelector('[data-field-count]').textContent.includes('แสดง 51 ราย'));assert(body.querySelector('[data-field-more]').hidden);
 console.log('Worklist filters: passed (server filters, offset reset, stale response, pagination, empty count)');
})().catch(e=>{console.error(e);process.exitCode=1});
