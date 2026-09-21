import {getSharedSupabase,getSharedProfile,bindPortalActivation,sharedCall,isPortalViewActive} from './shared-runtime-v2035.mjs?v=2.0.35';

const $=(selector,root=document)=>root.querySelector(selector);
const esc=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const num=value=>Number(value||0).toLocaleString('th-TH');
let supabase=null,profile=null,requestId=0;

export function aggregateTrainingDashboard(roster,history,role,community='',ownPid=null){
  const visible=(roster||[]).filter(v=>v.active!==false &&
    (role==='admin'||(role==='staff'&&String(v.community||'').trim()===String(community||'').trim())||
     (role==='user'&&String(v.source_pid)===String(ownPid))));
  const byPid=new Map(visible.map(v=>[String(v.source_pid),v]));
  const groups=new Map();
  for(const v of visible){
    const name=role==='user'?'ของฉัน':String(v.community||'ไม่ระบุชุมชน');
    if(!groups.has(name))groups.set(name,{community:name,roster:0,trained:new Set(),records:0,hours:0,lastDate:null});
    groups.get(name).roster++;
  }
  for(const t of history||[]){
    const v=byPid.get(String(t.volunteer_pid));
    if(!v||t.event_status==='cancelled')continue;
    const key=role==='user'?'ของฉัน':String(v.community||'ไม่ระบุชุมชน');
    const g=groups.get(key);if(!g)continue;
    g.trained.add(String(v.source_pid));g.records++;
    const hrs=Number(t.hours);if(Number.isFinite(hrs)&&hrs>0)g.hours+=hrs;
    if(t.event_date&&(!g.lastDate||String(t.event_date)>g.lastDate))g.lastDate=String(t.event_date);
  }
  const items=[...groups.values()].map(g=>({...g,trained:g.trained.size}));
  items.sort((a,b)=>a.community.localeCompare(b.community,'th'));
  return {roster:items.reduce((s,r)=>s+r.roster,0),
    trained:items.reduce((s,r)=>s+r.trained,0),
    records:items.reduce((s,r)=>s+r.records,0),
    hours:Math.round(items.reduce((s,r)=>s+r.hours,0)*10)/10,
    communities:items};
}
function style(){
  if($('#td77-style'))return;
  const el=document.createElement('style');el.id='td77-style';el.textContent=`
  .td77{border:1px solid #c7ddd5;border-radius:16px;background:#f4faf7;margin:12px 0;padding:10px 12px}
  .td77>summary{cursor:pointer;display:flex;justify-content:space-between;align-items:center;gap:10px;min-height:52px;font-size:1rem;color:#175c4e;font-weight:850}
  .td77>summary small{font-weight:650;color:#526a63;font-size:.82rem}
  .td77-body{padding:10px 0 2px;display:grid;gap:10px}
  .td77-stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}
  .td77-stat{background:#fff;border:1px solid #dbe9e2;border-radius:12px;padding:10px}
  .td77-stat small{display:block;color:#5c716a}.td77-stat strong{display:block;margin-top:5px;font-size:1.2rem;color:#165d51}
  .td77-table{overflow-x:auto}.td77-table table{width:100%;border-collapse:collapse;min-width:460px}
  .td77-table td,.td77-table th{padding:9px 7px;border-bottom:1px solid #d9e7e1;text-align:left}
  .td77-note{color:#587069;font-size:.85rem;line-height:1.4}
  .td77-error{color:#a33f33}.td77-refresh{padding:8px 12px;border:1px solid #b6d8cc;border-radius:10px;background:white;font:inherit;color:#15594d}
  @media(max-width:600px){.td77-stats{grid-template-columns:repeat(2,minmax(0,1fr))}.td77>summary{font-size:.93rem}}
  `;document.head.appendChild(el);
}
function ensureShell(){
  const panel=$('[data-portal-panel="work"]');if(!panel||panel.hidden)return null;
  let root=$('[data-training-dashboard-v2077]',panel);
  if(root)return root;
  root=document.createElement('details');root.className='td77';root.dataset.trainingDashboardV2077='1';
  root.innerHTML='<summary><span>สรุปประวัติการอบรม</span><small>แตะดูจำนวนและชั่วโมง ▾</small></summary><div class="td77-body" data-td77-body>กดเปิดเพื่อโหลดข้อมูลตามสิทธิ์</div>';
  const own=$('[data-vwork25]',panel);
  if(own)own.insertAdjacentElement('afterend',root);
  else panel.prepend(root);
  root.addEventListener('toggle',()=>{if(root.open)load(root).catch(()=>{});});
  return root;
}
async function load(root,{force=false}={}){
  if(!root.open||!isPortalViewActive('work'))return;
  const body=$('[data-td77-body]',root);if(!body)return;
  const ticket=++requestId;
  body.innerHTML='<div class="td77-note">กำลังโหลดสรุปประวัติการอบรม…</div>';
  try{
    profile=await getSharedProfile(supabase);
    if(!profile?.active||!['admin','staff','user'].includes(profile.role))return;
    const scope=`${profile.user_id}:${profile.role}:${profile.community||''}:${profile.volunteer_pid||''}`;
    const loader=async()=>{
      let rosterQuery=supabase.from('volunteers')
        .select('source_pid,community,active',{count:'exact'}).eq('active',true);
      if(profile.role==='staff')rosterQuery=rosterQuery.eq('community',profile.community);
      if(profile.role==='user')rosterQuery=rosterQuery.eq('source_pid',profile.volunteer_pid??-1);
      const [r,t]=await Promise.all([
        rosterQuery.range(0,999),
        supabase.from('volunteer_training_history')
          .select('volunteer_pid,event_date,hours,event_status',{count:'exact'})
          .range(0,999),
      ]);
      if(r.error||t.error)throw(r.error||t.error);
      if((r.count??r.data?.length??0)>(r.data||[]).length||
         (t.count??t.data?.length??0)>(t.data||[]).length)
         throw new Error('รายการมากกว่า 1,000 รายการ กรุณาดูรายงานเต็มในระบบ Local');
      return aggregateTrainingDashboard(r.data||[],t.data||[],profile.role,profile.community,profile.volunteer_pid);
    };
    const data=force?await loader():await sharedCall('training-dashboard-v2077:'+scope,loader,120000);
    if(ticket!==requestId||!root.isConnected||!root.open)return;
    const tile=(label,value,suffix='')=>`<div class="td77-stat"><small>${esc(label)}</small><strong>${num(value)}${esc(suffix)}</strong></div>`;
    const rows=data.communities.map(x=>`<tr><td>${esc(x.community)}</td><td>${num(x.roster)}</td><td>${num(x.trained)}</td><td>${num(x.records)}</td><td>${num(Math.round(x.hours*10)/10)}</td></tr>`).join('');
    body.innerHTML=`<div class="td77-stats">${tile('อสม.ในขอบเขต',data.roster,' คน')}${tile('มีประวัติอบรม',data.trained,' คน')}${tile('รายการอบรม',data.records,' ครั้ง')}${tile('ชั่วโมงรวม',data.hours,' ชม.')}</div>
      <div class="td77-note">สรุปจากประวัติที่บันทึกใน Cloud ตามสิทธิ์บัญชี ไม่ใช่คะแนนหรือการรับรองการอบรมครบหลักสูตร</div>
      ${profile.role==='user'?'':`<details><summary>ดูรายชุมชน</summary><div class="td77-table"><table><thead><tr><th>ชุมชน</th><th>อสม.</th><th>มีประวัติ</th><th>รายการ</th><th>ชั่วโมง</th></tr></thead><tbody>${rows}</tbody></table></div></details>`}
      <button type="button" class="td77-refresh" data-td77-refresh>ตรวจข้อมูลใหม่</button>`;
    $('[data-td77-refresh]',body).onclick=()=>load(root,{force:true});
  }catch(error){
    if(ticket!==requestId||!root.isConnected)return;
    body.innerHTML=`<p class="td77-error">โหลดรายงานการอบรมไม่สำเร็จ: ${esc(error?.message||'กรุณาลองใหม่')}</p><button type="button" class="td77-refresh" data-td77-retry>ลองใหม่</button>`;
    $('[data-td77-retry]',body).onclick=()=>load(root,{force:true});
  }
}
export async function initTrainingDashboardV2077(url,key){
  if(window.__PHC_TRAINING_DASHBOARD_2077__)return;
  window.__PHC_TRAINING_DASHBOARD_2077__=true;
  style();supabase=await getSharedSupabase(url,key);
  bindPortalActivation('work',async()=>{
    const p=await getSharedProfile(supabase);
    if(p?.active&&['admin','staff','user'].includes(p.role))ensureShell();
  });
}
