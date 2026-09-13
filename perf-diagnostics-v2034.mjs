const PHASE = '1.1';
const ENABLED = new URLSearchParams(location.search).get('perf') === '1' || sessionStorage.getItem('phc.perf.enabled') === '1';
if (ENABLED) sessionStorage.setItem('phc.perf.enabled','1');

const state = {
  enabled: ENABLED,
  startedAt: performance.now(),
  nav: [],
  resources: [],
  requests: [],
  longTasks: [],
  paints: {},
  activeNav: null,
  maxItems: 240,
  performanceKeys: new Set(),
  fetchPatched: false,
  xhrPatched: false,
};
const round = n => Math.round(Number(n || 0));
const now = () => performance.now();
const safeText = v => String(v ?? '').replace(/[<>]/g,'');

function classifyUrl(input){
  try{
    const raw = typeof input === 'string' ? input : (input?.url || String(input || ''));
    const u = new URL(raw, location.href);
    const path = u.pathname;
    if(path.includes('/rest/v1/rpc/')) return {kind:'rpc', name:path.split('/rest/v1/rpc/')[1].split('/')[0] || 'rpc'};
    if(path.includes('/rest/v1/')) return {kind:'rest', name:path.split('/rest/v1/')[1].split('/')[0] || 'rest'};
    if(path.includes('/auth/v1/')) return {kind:'auth', name:path.split('/auth/v1/')[1].split('/')[0] || 'auth'};
    if(path.includes('/storage/v1/')) return {kind:'storage', name:path.split('/storage/v1/')[1].split('/')[0] || 'storage'};
    if(/leaflet/i.test(path) || /openstreetmap|arcgisonline|opentopomap|unpkg/i.test(u.hostname)) return {kind:'map', name:u.hostname};
    if(/\.(m?js)$/i.test(path)) return {kind:'script', name:path.split('/').pop() || 'script'};
    if(/\.(css)$/i.test(path)) return {kind:'style', name:path.split('/').pop() || 'style'};
    if(/\.(png|jpe?g|webp|svg)$/i.test(path)) return {kind:'image', name:path.split('/').pop() || 'image'};
    return {kind:'other', name:u.hostname || 'same-origin'};
  }catch{return {kind:'other',name:'unknown'};}
}
function trim(arr){if(arr.length>state.maxItems)arr.splice(0,arr.length-state.maxItems);}
function capturePerformanceEntry(e){
  const c=classifyUrl(e.name),key=`${c.kind}|${c.name}|${round(e.startTime)}|${round(e.duration)}`;
  if(state.performanceKeys.has(key))return;
  state.performanceKeys.add(key);
  state.resources.push({source:'performance',kind:c.kind,name:c.name,start:round(e.startTime),end:round(e.responseEnd||(e.startTime+e.duration)),duration:round(e.duration),transfer:round(e.transferSize||0),encoded:round(e.encodedBodySize||0),initiator:e.initiatorType||''});
  trim(state.resources);
}
function captureBufferedResources(){try{(performance.getEntriesByType?.('resource')||[]).forEach(capturePerformanceEntry);}catch{}}
try{const po=new PerformanceObserver(list=>{list.getEntries().forEach(capturePerformanceEntry);renderPanel();});po.observe({type:'resource',buffered:true});}catch{}
try{const po=new PerformanceObserver(list=>list.getEntries().forEach(e=>{state.longTasks.push({start:round(e.startTime),duration:round(e.duration)});if(state.longTasks.length>40)state.longTasks.shift();}));po.observe({type:'longtask',buffered:true});}catch{}
try{const po=new PerformanceObserver(list=>list.getEntries().forEach(e=>{state.paints[e.name]=round(e.startTime);}));po.observe({type:'paint',buffered:true});}catch{}

function requestStart(input,transport){
  if(!ENABLED)return null;
  const c=classifyUrl(input),nav=state.activeNav;
  const ctx={kind:c.kind,name:c.name,transport,start:now(),nav};
  if(nav){nav.inFlight=(nav.inFlight||0)+1;nav.networkStarted=(nav.networkStarted||0)+1;nav.lastNetworkActivity=ctx.start;}
  return ctx;
}
function requestEnd(ctx,status=0,ok=true,error=''){
  if(!ctx)return;
  const end=now();
  state.requests.push({source:ctx.transport,kind:ctx.kind,name:ctx.name,start:round(ctx.start),end:round(end),duration:round(end-ctx.start),status:Number(status)||0,ok:Boolean(ok),error:error?String(error).slice(0,80):'',navId:ctx.nav?.id||null});trim(state.requests);
  const nav=ctx.nav;if(nav){nav.inFlight=Math.max(0,(nav.inFlight||0)-1);nav.lastNetworkEnd=end;nav.lastNetworkActivity=end;}
  renderPanel();
}
if(ENABLED&&typeof window.fetch==='function'&&!window.__PHC_PERF_FETCH_PATCHED__){
  const originalFetch=window.fetch;
  window.fetch=async function(...args){const ctx=requestStart(args[0],'fetch');try{const res=await originalFetch.apply(this,args);requestEnd(ctx,res?.status,res?.ok,'');return res;}catch(e){requestEnd(ctx,0,false,e?.name||'fetch-error');throw e;}};
  window.__PHC_PERF_FETCH_PATCHED__=true;state.fetchPatched=true;
}
if(ENABLED&&window.XMLHttpRequest&&!window.__PHC_PERF_XHR_PATCHED__){
  const X=window.XMLHttpRequest,open=X.prototype.open,send=X.prototype.send;
  X.prototype.open=function(method,url,...rest){this.__phcPerfUrl=url;return open.call(this,method,url,...rest);};
  X.prototype.send=function(...args){const ctx=requestStart(this.__phcPerfUrl||'xhr','xhr');let ended=false;const done=()=>{if(ended)return;ended=true;requestEnd(ctx,this.status,this.status>=200&&this.status<400,'');};this.addEventListener('loadend',done,{once:true});this.addEventListener('error',done,{once:true});this.addEventListener('abort',done,{once:true});try{return send.apply(this,args);}catch(e){done();throw e;}};
  window.__PHC_PERF_XHR_PATCHED__=true;state.xhrPatched=true;
}

function panelReady(view){
  const panel=document.querySelector(`[data-portal-panel="${CSS.escape(view)}"]`);if(!panel||panel.hidden)return false;
  if(view==='overview')return document.querySelectorAll('#stats > *').length>0;
  if(view==='communities')return Boolean(panel.querySelector('.spatial-community-card,[data-hq55-user-house],#community-body tr'));
  if(view==='houses')return Boolean(panel.querySelector('#my-house-body tr,.myh-card,[data-my-house]'));
  if(view==='health'){const rows=[...panel.querySelectorAll('#health-person-body tr')];if(!rows.length)return false;return !rows.some(r=>/กำลังโหลด|loading/i.test(r.textContent||''));}
  if(view==='work')return Boolean(panel.querySelector('[data-field200-host] .field200-kpis,#health-stats .stat'));
  return true;
}
const apiKind=k=>['rpc','rest','auth','storage'].includes(k);
const requestRowsForNav=nav=>state.requests.filter(r=>r.navId===nav.id);
function mapRowsForNav(nav,end){captureBufferedResources();return state.resources.filter(r=>r.kind==='map'&&r.start>=nav.start&&r.start<=end);}
function summarizeRpc(rows){
  const m=new Map();rows.filter(r=>r.kind==='rpc').forEach(r=>{const x=m.get(r.name)||{name:r.name,count:0,totalMs:0,maxMs:0,statuses:{}};x.count++;x.totalMs+=r.duration;x.maxMs=Math.max(x.maxMs,r.duration);const sk=String(r.status||0);x.statuses[sk]=(x.statuses[sk]||0)+1;m.set(r.name,x);});
  return [...m.values()].sort((a,b)=>b.totalMs-a.totalMs).map(x=>({...x,totalMs:round(x.totalMs),maxMs:round(x.maxMs)}));
}
function finalizeNav(nav,reason='settled'){
  if(nav.finished)return;nav.finished=true;try{nav.observer?.disconnect();}catch{}
  const end=now(),req=requestRowsForNav(nav),maps=mapRowsForNav(nav,end);
  nav.end=round(end);nav.settledMs=round(end-nav.start);nav.reason=reason;nav.pendingRequests=nav.inFlight||0;nav.requests=req.length+maps.length;nav.apiRequests=req.filter(r=>apiKind(r.kind)).length;nav.rpcRequests=req.filter(r=>r.kind==='rpc').length;nav.mapRequests=maps.length;nav.rpcSummary=summarizeRpc(req);
  nav.slowest=[...req,...maps].map(r=>({kind:r.kind,name:r.name,duration:r.duration,status:r.status??null,source:r.source})).sort((a,b)=>b.duration-a.duration).slice(0,8);
  nav.dataReadyState=nav.dataReadyMs!=null?'post-tap-mutation':(nav.cachedAtTap&&!nav.contentMutated?'cached-at-tap':'not-observed');
  state.nav.push({id:nav.id,view:nav.view,start:round(nav.start),uiMs:nav.uiMs,dataReadyMs:nav.dataReadyMs,dataReadyState:nav.dataReadyState,cachedAtTap:nav.cachedAtTap,contentMutated:nav.contentMutated,networkStarted:nav.networkStarted||0,pendingRequests:nav.pendingRequests,end:nav.end,settledMs:nav.settledMs,reason:nav.reason,requests:nav.requests,apiRequests:nav.apiRequests,rpcRequests:nav.rpcRequests,mapRequests:nav.mapRequests,rpcSummary:nav.rpcSummary,slowest:nav.slowest});
  if(state.nav.length>30)state.nav.shift();if(state.activeNav?.id===nav.id)state.activeNav=null;renderPanel();
}
function monitorNav(nav){
  const tick=()=>{if(nav.finished)return;const t=now();if(nav.contentMutated&&nav.dataReadyMs==null&&panelReady(nav.view))nav.dataReadyMs=round(t-nav.start);const idleFrom=Math.max(nav.lastNetworkActivity||nav.start,nav.lastMutationAt||nav.start);if(t-nav.start>=650&&(nav.inFlight||0)===0&&t-idleFrom>=500){finalizeNav(nav,'idle-after-activity');return;}if(t-nav.start>=12000){finalizeNav(nav,'timeout-12s');return;}setTimeout(tick,100);};setTimeout(tick,100);
}
function startNav(view){
  if(state.activeNav)finalizeNav(state.activeNav,'superseded');
  const t=now(),panel=document.querySelector(`[data-portal-panel="${CSS.escape(view)}"]`);
  const nav={id:`${Date.now()}-${Math.random().toString(36).slice(2,7)}`,view,start:t,uiMs:null,dataReadyMs:null,cachedAtTap:panelReady(view),contentMutated:false,lastMutationAt:t,lastNetworkActivity:t,lastNetworkEnd:t,networkStarted:0,inFlight:0,finished:false,observer:null};state.activeNav=nav;
  if(panel){nav.observer=new MutationObserver(records=>{const meaningful=records.some(m=>!(m.type==='attributes'&&m.target===panel&&m.attributeName==='hidden'));if(meaningful){nav.contentMutated=true;nav.lastMutationAt=now();}});nav.observer.observe(panel,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['hidden','class','disabled']});}
  requestAnimationFrame(()=>{const p=document.querySelector(`[data-portal-panel="${CSS.escape(view)}"]`);nav.uiMs=p&&!p.hidden?round(now()-t):null;renderPanel();});monitorNav(nav);
}
document.addEventListener('click',e=>{if(!ENABLED)return;const b=e.target.closest?.('#portal-nav [data-portal-view]');if(b)startNav(b.dataset.portalView||'unknown');},true);

function bootSummary(){captureBufferedResources();const rows=state.resources.filter(r=>['script','style'].includes(r.kind));return{scripts:rows.filter(r=>r.kind==='script').length,styles:rows.filter(r=>r.kind==='style').length,bytes:rows.reduce((s,r)=>s+(r.transfer||r.encoded||0),0),slowest:rows.slice().sort((a,b)=>b.duration-a.duration).slice(0,6).map(r=>({kind:r.kind,name:r.name,duration:r.duration})),fcp:state.paints['first-contentful-paint']??null,fp:state.paints['first-paint']??null,longTasks:state.longTasks.length};}
function latestNav(){return state.activeNav||state.nav[state.nav.length-1]||null;}
function publicActiveNav(n){if(!n)return null;return{id:n.id,view:n.view,start:round(n.start),uiMs:n.uiMs,dataReadyMs:n.dataReadyMs,cachedAtTap:n.cachedAtTap,contentMutated:n.contentMutated,networkStarted:n.networkStarted||0,inFlight:n.inFlight||0,elapsedMs:round(now()-n.start)};}
function report(){captureBufferedResources();const n=(performance.getEntriesByType?.('navigation')||[])[0];return{phase:PHASE,generatedAt:new Date().toISOString(),page:location.pathname,viewport:{w:innerWidth,h:innerHeight,dpr:devicePixelRatio||1},connection:navigator.connection?{effectiveType:navigator.connection.effectiveType||'',downlink:navigator.connection.downlink||null,saveData:Boolean(navigator.connection.saveData)}:null,navigation:n?{domContentLoaded:round(n.domContentLoadedEventEnd),load:round(n.loadEventEnd),response:round(n.responseEnd)}:null,instrumentation:{fetchPatched:state.fetchPatched,xhrPatched:state.xhrPatched,performanceResourceEntries:state.resources.length,trackedRequests:state.requests.length},boot:bootSummary(),nav:state.nav,activeNav:publicActiveNav(state.activeNav)};}

let panel=null;
function ensurePanel(){
  if(!ENABLED||panel)return panel;
  const style=document.createElement('style');style.textContent=`.phc-perf-btn{position:fixed;z-index:99990;right:10px;bottom:calc(92px + env(safe-area-inset-bottom));min-width:78px;min-height:46px;border:0;border-radius:12px;background:#17312d;color:#fff;font:700 13px system-ui;box-shadow:0 5px 20px #0004}.phc-perf-panel{position:fixed;z-index:99991;left:8px;right:8px;bottom:calc(150px + env(safe-area-inset-bottom));max-height:58vh;overflow:auto;padding:12px;border:1px solid #a8c7bc;border-radius:14px;background:#fffffff7;color:#17312d;font:12px/1.45 system-ui;box-shadow:0 12px 40px #0005}.phc-perf-panel[hidden]{display:none!important}.phc-perf-panel h3{margin:0 0 6px;font-size:15px}.phc-perf-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:6px}.phc-perf-kpi{padding:7px;border-radius:9px;background:#edf5f2;text-align:center}.phc-perf-kpi b{display:block;font-size:15px}.phc-perf-list{margin:8px 0;padding-left:18px}.phc-perf-actions{display:grid;grid-template-columns:1fr 1fr;gap:6px}.phc-perf-actions button{min-height:42px;border:1px solid #b7cfc7;border-radius:9px;background:#fff;font:700 12px system-ui}.phc-perf-warn{color:#8b4f0b;font-weight:700}`;document.head.appendChild(style);
  const btn=document.createElement('button');btn.type='button';btn.className='phc-perf-btn';btn.textContent='PERF 1.1';panel=document.createElement('section');panel.className='phc-perf-panel';panel.hidden=true;panel.setAttribute('aria-label','Phase 1.1 performance diagnostics');btn.onclick=()=>{panel.hidden=!panel.hidden;renderPanel();};document.body.append(btn,panel);return panel;
}
async function copyReport(){const text=JSON.stringify(report(),null,2);try{await navigator.clipboard.writeText(text);return true;}catch{}try{const ta=document.createElement('textarea');ta.value=text;ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();const ok=document.execCommand('copy');ta.remove();return ok;}catch{return false;}}
function renderPanel(){
  if(!ENABLED)return;const p=ensurePanel();if(!p)return;const b=bootSummary(),n=latestNav();const ready=n?.dataReadyMs!=null?`${n.dataReadyMs} ms`:(n?.cachedAtTap?'cached':'—');const req=n?.requests??(n?.networkStarted??'—'),api=n?.apiRequests??'—',rpc=n?.rpcRequests??'—',map=n?.mapRequests??'—';const slow=(n?.slowest||[]).map(x=>`<li>${safeText(x.kind)} · ${safeText(x.name)} · <b>${round(x.duration)} ms</b>${x.status?` · ${x.status}`:''}</li>`).join('')||'<li>ยังไม่มี request ที่บันทึกในรอบนี้</li>';const rpcSummary=(n?.rpcSummary||[]).slice(0,5).map(x=>`<li>${safeText(x.name)} ×${x.count} · รวม <b>${x.totalMs} ms</b> · สูงสุด ${x.maxMs} ms</li>`).join('')||'<li>ยังไม่พบ RPC ในรอบนี้</li>';
  p.innerHTML=`<h3>Phase 1.1 · iOS Network Trace</h3><div class="phc-perf-grid"><div class="phc-perf-kpi">UI<b>${n?.uiMs??'—'} ms</b></div><div class="phc-perf-kpi">Data<b>${ready}</b></div><div class="phc-perf-kpi">Settle<b>${n?.settledMs??(n?round(now()-n.start):'—')} ms</b></div></div><p>เมนู: <b>${safeText(n?.view||'ยังไม่แตะ')}</b> · Net ${req} · API ${api} · RPC ${rpc} · Map ${map}</p><p>Hook: fetch ${state.fetchPatched?'✓':'×'} · XHR ${state.xhrPatched?'✓':'×'} · tracked ${state.requests.length}</p><p>Boot: script ${b.scripts} · style ${b.styles} · ${(b.bytes/1024).toFixed(1)} KB · FCP ${b.fcp??'—'} ms · Long task ${b.longTasks}</p><strong>RPC ในรอบนี้</strong><ol class="phc-perf-list">${rpcSummary}</ol><strong>คำขอที่ช้าที่สุด</strong><ol class="phc-perf-list">${slow}</ol><div class="phc-perf-actions"><button type="button" data-perf-copy>คัดลอกผล</button><button type="button" data-perf-clear>ล้างรอบนี้</button></div><p class="phc-perf-warn">เก็บเฉพาะชนิด endpoint/ชื่อ RPC เวลา และ HTTP status ไม่เก็บ query string ชื่อประชาชน PID HN หรือข้อมูลสุขภาพ</p>`;
  p.querySelector('[data-perf-copy]')?.addEventListener('click',async e=>{const ok=await copyReport();e.currentTarget.textContent=ok?'คัดลอกแล้ว':'คัดลอกไม่ได้';});p.querySelector('[data-perf-clear]')?.addEventListener('click',()=>{state.nav=[];state.resources=[];state.requests=[];state.longTasks=[];state.performanceKeys.clear();state.activeNav=null;performance.clearResourceTimings?.();renderPanel();});
}
if(ENABLED){window.PHCPerfDiagnostics={report,clear(){state.nav=[];state.resources=[];state.requests=[];state.longTasks=[];state.performanceKeys.clear();state.activeNav=null;performance.clearResourceTimings?.();renderPanel();},disable(){sessionStorage.removeItem('phc.perf.enabled');location.reload();}};if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{captureBufferedResources();ensurePanel();renderPanel();},{once:true});else{captureBufferedResources();ensurePanel();renderPanel();}window.addEventListener('load',()=>setTimeout(()=>{captureBufferedResources();renderPanel();},150),{once:true});setTimeout(()=>{captureBufferedResources();renderPanel();},1200);}
