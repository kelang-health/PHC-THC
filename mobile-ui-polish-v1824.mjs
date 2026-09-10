const VERSION='1.8.24';
let supabase=null;
const $=(s,r=document)=>r.querySelector(s);

function injectStyle(){
  if($('#mobile-ui-polish-1824-style')) return;
  const s=document.createElement('style');
  s.id='mobile-ui-polish-1824-style';
  s.textContent=`
  .welcome.session-compact{position:relative}
  .session-last-login{color:#6a7d77;font-size:.78rem;line-height:1.35;margin-top:3px}
  .session-last-login::before{content:'•';margin-right:6px;color:#7aa99d}
  @media(max-width:700px){
    .welcome.session-compact{display:grid!important;grid-template-columns:minmax(0,1fr) auto!important;align-items:center!important;gap:3px 9px!important;padding:9px 11px!important;margin-bottom:8px!important;border-radius:14px!important;min-height:0!important}
    .welcome.session-compact>div:first-child{min-width:0;display:grid;gap:2px}
    .welcome.session-compact .eyebrow{display:none!important}
    .welcome.session-compact h2{margin:0!important;font-size:1.02rem!important;line-height:1.25!important;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .welcome.session-compact #scope-label{margin:0!important;font-size:.78rem!important;line-height:1.25!important;color:#62736f;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .welcome.session-compact #role-badge{align-self:center;justify-self:end;font-size:.72rem!important;padding:5px 8px!important;white-space:nowrap}
    .welcome.session-compact .session-last-login{grid-column:1/-1;margin:1px 0 0;font-size:.70rem;line-height:1.25}

    [data-portal-panel="communities"]{scroll-margin-top:128px}
    .wf22{gap:10px!important;margin-top:9px!important}
    .wf22-progress{padding:11px 12px!important;border-radius:15px!important}
    .wf22-progress-head{align-items:center!important}
    .wf22-progress-head small{font-size:.78rem!important;line-height:1.25}
    .wf22-progress-head strong{font-size:1.08rem!important;line-height:1.25}
    .wf22-progress-head b{font-size:1.18rem!important}
    .wf22-bar{height:11px!important;margin:8px 0 4px!important}
    .wf22-task{min-height:74px!important;padding:8px!important;border-radius:14px!important}
    .wf22-task strong{font-size:1.24rem!important}
    .wf22-quick,.wf22-report{padding:11px!important;border-radius:15px!important}
    .wf22-quick input,.wf22-report select{min-height:60px!important;font-size:1.05rem!important}
    .wf22-report-kpi{padding:9px!important}
    .wf22-report-kpi strong{font-size:1.12rem!important}

    .cgis22{gap:9px!important;margin-top:10px!important}
    .cgis22-head h3{font-size:1.18rem!important}
    .cgis22-progress{padding:9px 11px!important}
    .cgis22-chip{min-height:52px!important;padding:8px 11px!important;font-size:.98rem!important}
    .cgis22-tools{padding:10px!important}
    .cgis22-tools input,.cgis22-tools select{min-height:60px!important;font-size:1.05rem!important}
    .cgis22-map{height:45vh!important;min-height:330px!important;max-height:440px!important}
    .cgis22-card{padding:12px!important}
    .cgis22-btn,.cgis22-link{min-height:64px!important;font-size:1.06rem!important}

    .spatial-community-card{padding:13px!important}
    .spatial-mini{padding:8px!important}
    .spatial-card-open{min-height:58px!important}
    .vol-card-summary{min-height:70px!important}
    .vol-detail-kpi{min-height:68px!important}
    .vol-map-canvas{height:50vh!important;min-height:340px!important}
  }
  @media(max-width:390px){
    .welcome.session-compact h2{font-size:.98rem!important}
    .welcome.session-compact #scope-label{font-size:.74rem!important}
    .wf22-actions{gap:6px!important}
    .wf22-task{min-height:70px!important;font-size:.94rem!important}
    .wf22-task strong{font-size:1.18rem!important}
    .cgis22-map{height:43vh!important;min-height:315px!important}
  }
  `;
  document.head.appendChild(s);
}

function formatLogin(value){
  if(!value) return '';
  const d=new Date(value);
  if(Number.isNaN(d.getTime())) return '';
  return d.toLocaleString('th-TH',{
    timeZone:'Asia/Bangkok',
    day:'numeric',month:'short',year:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false
  }).replace(' เวลา ',' · ')+' น.';
}

async function compactSessionHeader(){
  const welcome=$('.welcome');
  if(!welcome) return;
  welcome.classList.add('session-compact');
  let note=$('.session-last-login',welcome);
  if(!note){
    note=document.createElement('div');
    note.className='session-last-login';
    note.setAttribute('aria-label','เวลาเข้าสู่ระบบล่าสุด');
    const first=welcome.querySelector(':scope > div:first-child');
    (first||welcome).appendChild(note);
  }
  try{
    const {data:{session}}=await supabase.auth.getSession();
    const text=formatLogin(session?.user?.last_sign_in_at);
    note.textContent=text?`เข้าระบบล่าสุด ${text}`:'กำลังใช้งานบัญชีนี้';
  }catch{
    note.textContent='กำลังใช้งานบัญชีนี้';
  }
}

function start(){
  compactSessionHeader();
  const portal=$('#portal');
  if(!portal) return;
  const ob=new MutationObserver(()=>compactSessionHeader());
  ob.observe(portal,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});
}

export async function initMobileUIPolish1824(url,key){
  if(window.__PHC_MOBILE_UI_POLISH_1824__) return;
  window.__PHC_MOBILE_UI_POLISH_1824__=true;
  injectStyle();
  const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');
  supabase=createClient(url,key,{auth:{persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',start,{once:true});
  else start();
}
