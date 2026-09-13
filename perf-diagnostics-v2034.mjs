const ENABLED = new URLSearchParams(location.search).get('perf') === '1' || sessionStorage.getItem('phc.perf.enabled') === '1';
if (ENABLED) sessionStorage.setItem('phc.perf.enabled','1');

const state = {
  enabled: ENABLED,
  startedAt: performance.now(),
  nav: [],
  resources: [],
  longTasks: [],
  paints: {},
  activeNav: null,
  maxItems: 160,
};

const round = n => Math.round(Number(n || 0));
const now = () => performance.now();
const safeText = v => String(v ?? '').replace(/[<>]/g,'');

function classifyResource(name){
  try{
    const u = new URL(name, location.href);
    const path = u.pathname;
    if(path.includes('/rest/v1/rpc/')) return {kind:'rpc', name:path.split('/rest/v1/rpc/')[1].split('/')[0] || 'rpc'};
    if(path.includes('/rest/v1/')) return {kind:'rest', name:path.split('/rest/v1/')[1].split('/')[0] || 'rest'};
    if(path.includes('/auth/v1/')) return {kind:'auth', name:path.split('/auth/v1/')[1].split('/')[0] || 'auth'};
    if(path.includes('/storage/v1/')) return {kind:'storage', name:path.split('/storage/v1/')[1].split('/')[0] || 'storage'};
    if(/leaflet/i.test(path) || /openstreetmap|arcgisonline|opentopomap|unpkg/i.test(u.hostname)) return {kind:'map', name:u.hostname};
    if(/\.(m?js)$/i.test(path)) return {kind:'script', name:path.split('/').pop() || 'script'};
    if(/\.(css)$/i.test(path)) return {kind:'style', name:path.split('/').pop() || 'style'};
    if(/\.(png|jpe?g|webp|svg)$/i.test(path)) return {kind:'image', name:path.split('/').pop() || 'image'};
    return {kind:'other', name:u.hostname};
  }catch{return {kind:'other',name:'unknown'};}
}

function recordResource(e){
  const c = classifyResource(e.name);
  const item = {
    kind:c.kind,
    name:c.name,
    start:round(e.startTime),
    duration:round(e.duration),
    transfer:round(e.transferSize || 0),
    encoded:round(e.encodedBodySize || 0),
    initiator:e.initiatorType || '',
  };
  state.resources.push(item);
  if(state.resources.length > state.maxItems) state.resources.splice(0, state.resources.length - state.maxItems);
  if(state.activeNav && e.startTime >= state.activeNav.start){
    state.activeNav.lastNetworkEnd = Math.max(state.activeNav.lastNetworkEnd || 0, e.responseEnd || (e.startTime + e.duration));
  }
  renderPanel();
}

try{
  const po = new PerformanceObserver(list => list.getEntries().forEach(recordResource));
  po.observe({type:'resource', buffered:true});
}catch{}
try{
  const po = new PerformanceObserver(list => list.getEntries().forEach(e => {
    state.longTasks.push({start:round(e.startTime), duration:round(e.duration)});
    if(state.longTasks.length > 40) state.longTasks.shift();
  }));
  po.observe({type:'longtask', buffered:true});
}catch{}
try{
  const po = new PerformanceObserver(list => list.getEntries().forEach(e => { state.paints[e.name] = round(e.startTime); }));
  po.observe({type:'paint', buffered:true});
}catch{}

function panelReady(view){
  const panel = document.querySelector(`[data-portal-panel="${CSS.escape(view)}"]`);
  if(!panel || panel.hidden) return false;
  if(view === 'overview') return document.querySelectorAll('#stats > *').length > 0;
  if(view === 'communities') return Boolean(document.querySelector('.spatial-community-card,[data-hq55-user-house],#community-body tr'));
  if(view === 'houses') return Boolean(document.querySelector('#my-house-body tr,.myh-card,[data-my-house]'));
  if(view === 'health'){
    const rows=[...document.querySelectorAll('#health-person-body tr')];
    if(!rows.length) return false;
    return !rows.some(r => /กำลังโหลด|loading/i.test(r.textContent || ''));
  }
  if(view === 'work') return Boolean(document.querySelector('[data-field200-host] .field200-kpis,#health-stats .stat'));
  return true;
}

function resourceSlice(start, end=Infinity){
  return state.resources.filter(r => r.start >= start && r.start <= end);
}

function finalizeNav(nav, reason='settled'){
  if(!state.activeNav || state.activeNav.id !== nav.id) return;
  const end = now();
  nav.end = round(end);
  nav.settledMs = round(end - nav.start);
  nav.reason = reason;
  const rows = resourceSlice(nav.start, end);
  nav.requests = rows.length;
  nav.apiRequests = rows.filter(r => ['rpc','rest','auth','storage'].includes(r.kind)).length;
  nav.rpcRequests = rows.filter(r => r.kind === 'rpc').length;
  nav.mapRequests = rows.filter(r => r.kind === 'map').length;
  nav.slowest = rows.slice().sort((a,b)=>b.duration-a.duration).slice(0,5).map(r=>({kind:r.kind,name:r.name,duration:r.duration}));
  state.nav.push(nav);
  if(state.nav.length > 30) state.nav.shift();
  state.activeNav = null;
  renderPanel();
}

function monitorNav(nav){
  let readyRecorded=false;
  const tick=()=>{
    if(!state.activeNav || state.activeNav.id !== nav.id) return;
    const t = now();
    if(!readyRecorded && panelReady(nav.view)){
      nav.dataReadyMs = round(t - nav.start);
      readyRecorded=true;
    }
    const last = nav.lastNetworkEnd || nav.start;
    if(t - nav.start >= 900 && t - last >= 800){ finalizeNav(nav,'network-idle'); return; }
    if(t - nav.start >= 10000){ finalizeNav(nav,'timeout-10s'); return; }
    setTimeout(tick,120);
  };
  setTimeout(tick,120);
}

function startNav(view){
  if(state.activeNav) finalizeNav(state.activeNav,'superseded');
  const t=now();
  const nav={id:`${Date.now()}-${Math.random().toString(36).slice(2,7)}`,view,start:t,uiMs:null,dataReadyMs:null,lastNetworkEnd:t};
  state.activeNav=nav;
  requestAnimationFrame(()=>{
    const panel=document.querySelector(`[data-portal-panel="${CSS.escape(view)}"]`);
    nav.uiMs=panel && !panel.hidden ? round(now()-t) : null;
    renderPanel();
  });
  monitorNav(nav);
}

document.addEventListener('click',e=>{
  if(!ENABLED) return;
  const b=e.target.closest?.('#portal-nav [data-portal-view]');
  if(b) startNav(b.dataset.portalView || 'unknown');
},true);

function bootSummary(){
  const rows=state.resources.filter(r=>['script','style'].includes(r.kind));
  return {
    scripts:rows.filter(r=>r.kind==='script').length,
    bytes:rows.reduce((s,r)=>s+(r.transfer||r.encoded||0),0),
    slowest:rows.slice().sort((a,b)=>b.duration-a.duration).slice(0,5),
    fcp:state.paints['first-contentful-paint'] ?? null,
    fp:state.paints['first-paint'] ?? null,
    longTasks:state.longTasks.length,
  };
}

function latestNav(){return state.activeNav || state.nav[state.nav.length-1] || null;}
function report(){
  const navEntries = performance.getEntriesByType?.('navigation') || [];
  const n = navEntries[0];
  return {
    generatedAt:new Date().toISOString(),
    page:location.pathname,
    viewport:{w:innerWidth,h:innerHeight,dpr:devicePixelRatio || 1},
    connection:navigator.connection ? {effectiveType:navigator.connection.effectiveType || '', downlink:navigator.connection.downlink || null, saveData:Boolean(navigator.connection.saveData)} : null,
    navigation:n ? {domContentLoaded:round(n.domContentLoadedEventEnd), load:round(n.loadEventEnd), response:round(n.responseEnd)} : null,
    boot:bootSummary(),
    nav:state.nav,
    activeNav:state.activeNav,
  };
}

let panel=null;
function ensurePanel(){
  if(!ENABLED || panel) return panel;
  const style=document.createElement('style');
  style.textContent=`
  .phc-perf-btn{position:fixed;z-index:99990;right:10px;bottom:calc(92px + env(safe-area-inset-bottom));min-width:70px;min-height:46px;border:0;border-radius:12px;background:#17312d;color:#fff;font:700 13px system-ui;box-shadow:0 5px 20px #0004}.phc-perf-panel{position:fixed;z-index:99991;left:8px;right:8px;bottom:calc(150px + env(safe-area-inset-bottom));max-height:55vh;overflow:auto;padding:12px;border:1px solid #a8c7bc;border-radius:14px;background:#fffffff5;color:#17312d;font:12px/1.45 system-ui;box-shadow:0 12px 40px #0005}.phc-perf-panel[hidden]{display:none!important}.phc-perf-panel h3{margin:0 0 6px;font-size:15px}.phc-perf-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:6px}.phc-perf-kpi{padding:7px;border-radius:9px;background:#edf5f2;text-align:center}.phc-perf-kpi b{display:block;font-size:15px}.phc-perf-list{margin:8px 0;padding-left:18px}.phc-perf-actions{display:grid;grid-template-columns:1fr 1fr;gap:6px}.phc-perf-actions button{min-height:42px;border:1px solid #b7cfc7;border-radius:9px;background:#fff;font:700 12px system-ui}.phc-perf-warn{color:#8b4f0b;font-weight:700}`;
  document.head.appendChild(style);
  const btn=document.createElement('button');btn.type='button';btn.className='phc-perf-btn';btn.textContent='PERF';
  panel=document.createElement('section');panel.className='phc-perf-panel';panel.hidden=true;panel.setAttribute('aria-label','Phase 1 performance diagnostics');
  btn.onclick=()=>{panel.hidden=!panel.hidden;renderPanel();};
  document.body.append(btn,panel);
  return panel;
}

async function copyReport(){
  const text=JSON.stringify(report(),null,2);
  try{await navigator.clipboard.writeText(text);return true;}catch{}
  try{const ta=document.createElement('textarea');ta.value=text;ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();const ok=document.execCommand('copy');ta.remove();return ok;}catch{return false;}
}
function renderPanel(){
  if(!ENABLED) return;
  const p=ensurePanel(); if(!p) return;
  const b=bootSummary(), n=latestNav();
  const slow=(n?.slowest || []).map(x=>`<li>${safeText(x.kind)} · ${safeText(x.name)} · <b>${round(x.duration)} ms</b></li>`).join('') || '<li>ยังไม่มีข้อมูลคำขอหลังแตะเมนู</li>';
  p.innerHTML=`<h3>Phase 1 · Performance</h3><div class="phc-perf-grid"><div class="phc-perf-kpi">UI<b>${n?.uiMs ?? '—'} ms</b></div><div class="phc-perf-kpi">Data<b>${n?.dataReadyMs ?? '—'} ms</b></div><div class="phc-perf-kpi">Settle<b>${n?.settledMs ?? (n?round(now()-n.start):'—')} ms</b></div></div><p>เมนู: <b>${safeText(n?.view || 'ยังไม่แตะ')}</b> · requests ${n?.requests ?? '—'} · API ${n?.apiRequests ?? '—'} · RPC ${n?.rpcRequests ?? '—'} · Map ${n?.mapRequests ?? '—'}</p><p>Boot: script ${b.scripts} ไฟล์ · ${(b.bytes/1024).toFixed(1)} KB · FCP ${b.fcp ?? '—'} ms · Long task ${b.longTasks}</p><strong>คำขอที่ช้าที่สุด</strong><ol class="phc-perf-list">${slow}</ol><div class="phc-perf-actions"><button type="button" data-perf-copy>คัดลอกผล</button><button type="button" data-perf-clear>ล้างรอบนี้</button></div><p class="phc-perf-warn">เก็บเฉพาะชนิด endpoint/ชื่อ RPC และเวลา ไม่เก็บชื่อประชาชน PID HN หรือ query string</p>`;
  p.querySelector('[data-perf-copy]')?.addEventListener('click',async e=>{const ok=await copyReport();e.currentTarget.textContent=ok?'คัดลอกแล้ว':'คัดลอกไม่ได้';});
  p.querySelector('[data-perf-clear]')?.addEventListener('click',()=>{state.nav=[];state.resources=[];state.longTasks=[];state.activeNav=null;performance.clearResourceTimings?.();renderPanel();});
}

if(ENABLED){
  window.PHCPerfDiagnostics={report,clear(){state.nav=[];state.resources=[];state.longTasks=[];state.activeNav=null;performance.clearResourceTimings?.();renderPanel();},disable(){sessionStorage.removeItem('phc.perf.enabled');location.reload();}};
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',()=>{ensurePanel();renderPanel();},{once:true}); else {ensurePanel();renderPanel();}
  setTimeout(renderPanel,1200);
}
