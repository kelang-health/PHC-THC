const VERSION='1.8.25';
let supabase=null,profile=null,rows=[],avatarObserver=null,portalObserver=null,statusFilter='all',searchText='',communityFilter='';
const $=(s,r=document)=>r.querySelector(s);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num=v=>Number(v||0).toLocaleString('th-TH');
const statusOrder={pink:0,orange:1,yellow:2,green:3};

function initials(name){
  const parts=String(name||'อสม').trim().split(/\s+/).filter(Boolean);
  if(!parts.length)return 'อสม';
  return ((parts[0]?.[0]||'')+(parts[1]?.[0]||'')).slice(0,2) || 'อสม';
}
function statusLabel(code){return({green:'พร้อมใช้งาน',yellow:'ติดตาม',orange:'ควรตรวจ',pink:'เร่งแก้ข้อมูล'})[code]||'ติดตาม';}
function statusClass(code){return ['green','yellow','orange','pink'].includes(code)?code:'yellow';}
function setVersion(){const e=$('.login-version');if(e)e.textContent=`Cloud v${VERSION}`;}

function injectStyle(){
  if($('#vreg25-style'))return;
  const s=document.createElement('style');s.id='vreg25-style';s.textContent=`
  [data-portal-panel="volunteers"].vreg25-ready>[data-vol-card-root]{display:none!important}
  .vreg25{display:grid;gap:11px;margin-top:12px}.vreg25-toolbar{display:grid;grid-template-columns:1.4fr 1fr;gap:8px}.vreg25-toolbar input,.vreg25-toolbar select{width:100%;min-height:58px;border:2px solid #c5d9d1;border-radius:14px;padding:10px 13px;background:#fff;font:inherit;font-weight:800;color:#17312d}.vreg25-filter{display:flex;gap:7px;overflow:auto;padding:1px 0 5px;scrollbar-width:none}.vreg25-filter button{flex:0 0 auto;min-height:46px;border:2px solid #d2dfda;border-radius:999px;padding:7px 12px;background:#fff;color:#35564f;font:inherit;font-weight:850}.vreg25-filter button.active{border-color:#176b5e;box-shadow:0 0 0 2px #176b5e19}.vreg25-count{font-size:.82rem;color:#63766f}.vreg25-list{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:10px}
  .vreg25-card{border:2px solid;border-radius:18px;overflow:hidden;transition:.15s ease}.vreg25-card.green{background:#eff8f2;border-color:#b9ddc4}.vreg25-card.yellow{background:#fff9e8;border-color:#eadc9f}.vreg25-card.orange{background:#fff2e8;border-color:#ebc3a5}.vreg25-card.pink{background:#fff0f4;border-color:#e7bbc7}
  .vreg25-summary{width:100%;display:grid;grid-template-columns:auto minmax(0,1fr) auto;align-items:center;gap:11px;border:0;background:transparent;text-align:left;padding:13px;font:inherit;color:#17312d;cursor:pointer}.vreg25-avatar{width:58px;height:58px;border-radius:50%;overflow:hidden;display:grid;place-items:center;background:#dcece7;color:#1b6155;font-size:1.05rem;font-weight:900;border:3px solid #fff;box-shadow:0 2px 9px #17312d18;position:relative}.vreg25-avatar img{width:100%;height:100%;object-fit:cover;position:absolute;inset:0}.vreg25-avatar img[hidden]{display:none!important}.vreg25-name{min-width:0}.vreg25-name strong{display:block;font-size:1.08rem;line-height:1.3;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.vreg25-name small{display:block;color:#60736d;margin-top:3px;line-height:1.35}.vreg25-badge{min-width:86px;text-align:center;border-radius:999px;padding:7px 9px;font-size:.77rem;font-weight:900;white-space:nowrap}.green .vreg25-badge{background:#d8efe0;color:#176247}.yellow .vreg25-badge{background:#f7eebc;color:#765b0b}.orange .vreg25-badge{background:#f7dcc8;color:#8a4c20}.pink .vreg25-badge{background:#f4d5de;color:#8d3850}
  .vreg25-detail{display:grid;gap:10px;padding:0 13px 13px;border-top:1px solid #ffffffaa}.vreg25-detail[hidden]{display:none!important}.vreg25-score{display:flex;justify-content:space-between;align-items:center;gap:10px;padding-top:10px}.vreg25-score strong{font-size:1.15rem}.vreg25-kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:7px}.vreg25-kpi{padding:9px 7px;border-radius:12px;text-align:center;border:1px solid #ffffffc9;background:#ffffffb8}.vreg25-kpi small{display:block;color:#687a74;line-height:1.2}.vreg25-kpi strong{display:block;margin-top:4px;font-size:1.08rem}.vreg25-kpi.good{background:#e5f5ea}.vreg25-kpi.warn{background:#fff4cf}.vreg25-kpi.orange{background:#fee5d5}.vreg25-kpi.bad{background:#fbe0e7}.vreg25-map{min-height:58px;border:0;border-radius:14px;background:#0c7363;color:#fff;font:inherit;font-weight:900;font-size:1.02rem;cursor:pointer}.vreg25-note{padding:10px 12px;border-radius:13px;background:#f1f7f4;color:#506b64;font-size:.85rem;line-height:1.45}
  .vself25{margin:10px 0 12px;border:2px solid #c9ddd5;border-radius:17px;background:#f7fbf9;overflow:hidden}.vself25 summary{list-style:none;display:grid;grid-template-columns:auto minmax(0,1fr) auto;gap:10px;align-items:center;padding:11px 12px;cursor:pointer}.vself25 summary::-webkit-details-marker{display:none}.vself25 .vreg25-avatar{width:54px;height:54px}.vself25-title{min-width:0}.vself25-title strong{display:block;font-size:1.06rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.vself25-title small{display:block;color:#60736d;margin-top:2px}.vself25-more{font-size:.78rem;font-weight:850;color:#176557}.vself25-body{padding:0 12px 12px}.vself25 .vreg25-kpis{grid-template-columns:repeat(3,1fr)}
  .wf22-task.v25-clear{background:#eff8f2!important;border-color:#b9ddc4!important;color:#176247!important}.wf22-task.v25-yellow{background:#fff9e8!important;border-color:#eadc9f!important}.wf22-task.v25-orange{background:#fff2e8!important;border-color:#ebc3a5!important}.wf22-task.v25-pink{background:#fff0f4!important;border-color:#e7bbc7!important}.wf22-task.v25-pink strong{color:#9a3b52!important}.wf22-task.v25-orange strong{color:#995a26!important}.wf22-task.v25-yellow strong{color:#82650f!important}
  @media(max-width:700px){.vreg25-toolbar{grid-template-columns:1fr}.vreg25-toolbar input,.vreg25-toolbar select{min-height:62px;font-size:1.04rem}.vreg25-list{grid-template-columns:1fr}.vreg25-summary{min-height:82px;padding:11px 10px;gap:9px}.vreg25-avatar{width:56px;height:56px}.vreg25-badge{min-width:78px;font-size:.73rem;padding:6px 7px}.vreg25-kpis{grid-template-columns:repeat(2,1fr)}.vreg25-kpi{min-height:68px;display:flex;flex-direction:column;justify-content:center}.vreg25-map{min-height:66px;font-size:1.08rem}.vself25{margin:7px 0 10px}.vself25 summary{padding:9px 10px}.vself25 .vreg25-avatar{width:50px;height:50px}.vself25 .vreg25-kpis{grid-template-columns:repeat(3,1fr)}.vself25 .vreg25-kpi{min-height:62px;padding:7px 4px}}
  @media(max-width:390px){.vreg25-summary{grid-template-columns:auto minmax(0,1fr)}.vreg25-badge{grid-column:2;justify-self:start}.vself25 summary{grid-template-columns:auto minmax(0,1fr)}.vself25-more{display:none}.vself25 .vreg25-kpis{grid-template-columns:1fr 1fr 1fr}.vself25 .vreg25-kpi small{font-size:.69rem}.vself25 .vreg25-kpi strong{font-size:1rem}}
  `;document.head.appendChild(s);
}

async function loadProfile(){
  const {data:{session}}=await supabase.auth.getSession();if(!session)return null;
  const {data,error}=await supabase.from('profiles').select('user_id,role,community,volunteer_pid,active').eq('user_id',session.user.id).maybeSingle();
  if(error)throw error;return data;
}
async function loadRows(){const {data,error}=await supabase.rpc('volunteer_registry_profiles');if(error)throw error;rows=data||[];}

function avatarHtml(v,small=false){
  const p=String(v.photo_object_path||'').trim();
  return `<span class="vreg25-avatar${small?' small':''}" data-v25-avatar${p?` data-photo-path="${esc(p)}"`:''} data-photo-name="${esc(v.display_name||'อสม.')}"><span>${esc(initials(v.display_name))}</span>${p?`<img hidden loading="lazy" decoding="async" alt="รูป ${esc(v.display_name||'อสม.')}" referrerpolicy="no-referrer">`:''}</span>`;
}
async function resolveAvatar(el){
  if(!el||el.dataset.photoLoaded==='1')return;el.dataset.photoLoaded='1';
  const path=el.dataset.photoPath;if(!path)return;
  try{
    const {data,error}=await supabase.storage.from('volunteer-profiles').createSignedUrl(path,1800);
    if(error||!data?.signedUrl)return;
    const img=el.querySelector('img');if(!img)return;
    img.onload=()=>{img.hidden=false;const t=el.querySelector('span');if(t)t.hidden=true;};
    img.onerror=()=>{img.hidden=true;};img.src=data.signedUrl;
  }catch{}
}
function observeAvatars(root=document){
  if(!avatarObserver&&'IntersectionObserver'in window){
    avatarObserver=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){avatarObserver.unobserve(e.target);resolveAvatar(e.target);}}),{rootMargin:'180px'});
  }
  root.querySelectorAll?.('[data-v25-avatar][data-photo-path]').forEach(el=>avatarObserver?avatarObserver.observe(el):resolveAvatar(el));
}

function filteredRows(){
  let out=rows;
  if(profile?.role==='admin'&&communityFilter)out=out.filter(v=>String(v.community||'')===communityFilter);
  if(statusFilter!=='all')out=out.filter(v=>statusClass(v.status_code)===statusFilter);
  if(searchText){const q=searchText.toLowerCase();out=out.filter(v=>String(v.display_name||'').toLowerCase().includes(q)||String(v.community||'').toLowerCase().includes(q));}
  return out.slice().sort((a,b)=>String(a.display_name||'').localeCompare(String(b.display_name||''),'th'));
}
function cardHtml(v){
  const code=statusClass(v.status_code),issues=Number(v.issue_house_count||0),house=Number(v.house_count||0);
  return `<article class="vreg25-card ${code}" data-v25-card="${esc(v.source_pid)}"><button type="button" class="vreg25-summary" data-v25-toggle="${esc(v.source_pid)}">${avatarHtml(v)}<span class="vreg25-name"><strong>${esc(v.display_name||'ไม่ระบุชื่อ')}</strong><small>${esc(v.community||'—')} · หมู่ ${esc(v.moo||'—')} · บ้าน ${num(house)} หลัง</small></span><span class="vreg25-badge">${esc(v.status_label||statusLabel(code))}</span></button><div class="vreg25-detail" data-v25-detail="${esc(v.source_pid)}" hidden><div class="vreg25-score"><span>ความพร้อมของข้อมูลพื้นที่</span><strong>${Number(v.ready_pct||0).toLocaleString('th-TH')}%</strong></div><div class="vreg25-kpis"><div class="vreg25-kpi"><small>บ้านรับผิดชอบ</small><strong>${num(house)}</strong></div><div class="vreg25-kpi good"><small>ปักหมุดแล้ว</small><strong>${num(v.pinned_count)}</strong></div><div class="vreg25-kpi good"><small>ยืนยันภาคสนาม</small><strong>${num(v.field_confirmed_count)}</strong></div><div class="vreg25-kpi ${Number(v.missing_count)>0?'warn':'good'}"><small>ไม่มีพิกัด</small><strong>${num(v.missing_count)}</strong></div><div class="vreg25-kpi ${Number(v.review_count)>0?'orange':'good'}"><small>ต้องตรวจ</small><strong>${num(v.review_count)}</strong></div><div class="vreg25-kpi ${Number(v.outside_community_count)>0?'orange':'good'}"><small>ข้ามชุมชน</small><strong>${num(v.outside_community_count)}</strong></div><div class="vreg25-kpi ${Number(v.outside_tambon_count)>0?'bad':'good'}"><small>นอก ต.พระบาท</small><strong>${num(v.outside_tambon_count)}</strong></div><div class="vreg25-kpi ${issues>0?'warn':'good'}"><small>รายการต้องจัดการ</small><strong>${num(issues)}</strong></div></div><button type="button" class="vreg25-map" data-v25-map="${esc(v.source_pid)}">ดูบ้านของ อสม. คนนี้บนแผนที่</button></div></article>`;
}
function triggerExistingMap(pid){
  const btn=[...document.querySelectorAll('[data-vol-map]')].find(b=>String(b.dataset.volMap)===String(pid));
  if(btn){btn.click();return;}
  setTimeout(()=>{const retry=[...document.querySelectorAll('[data-vol-map]')].find(b=>String(b.dataset.volMap)===String(pid));if(retry)retry.click();},500);
}
function drawRegistry(root){
  const list=$('[data-v25-list]',root),count=$('[data-v25-count]',root);if(!list)return;
  const data=filteredRows();list.innerHTML=data.map(cardHtml).join('')||'<div class="vreg25-note">ไม่พบรายชื่อ อสม. ตามตัวกรอง</div>';if(count)count.textContent=`แสดง ${num(data.length)} คน`;
  list.querySelectorAll('[data-v25-toggle]').forEach(b=>b.onclick=()=>{const d=list.querySelector(`[data-v25-detail="${CSS.escape(String(b.dataset.v25Toggle))}"]`);if(!d)return;const open=d.hidden;list.querySelectorAll('[data-v25-detail]').forEach(x=>x.hidden=true);d.hidden=!open;if(open)setTimeout(()=>b.scrollIntoView({behavior:'smooth',block:'nearest'}),60);});
  list.querySelectorAll('[data-v25-map]').forEach(b=>b.onclick=()=>triggerExistingMap(b.dataset.v25Map));observeAvatars(list);
}
function renderRegistry(){
  const panel=$('[data-portal-panel="volunteers"]');if(!panel||!['admin','staff'].includes(profile?.role))return;
  let root=$('[data-vreg25]',panel);if(!root){root=document.createElement('section');root.className='vreg25';root.dataset.vreg25='1';const head=panel.querySelector('.section-head');head?.insertAdjacentElement('afterend',root);}
  panel.classList.add('vreg25-ready');const communities=[...new Set(rows.map(x=>x.community).filter(Boolean))].sort((a,b)=>String(a).localeCompare(String(b),'th'));
  root.innerHTML=`<div class="vreg25-note">รูป อสม. แสดงเฉพาะทะเบียนตามขอบเขตสิทธิ์ · สีเป็นสถานะความครบถ้วนของข้อมูลพื้นที่ ไม่ใช่การให้คะแนนบุคคล</div><div class="vreg25-toolbar"><input data-v25-search type="search" placeholder="ค้นหาชื่อ อสม." value="${esc(searchText)}">${profile.role==='admin'?`<select data-v25-community><option value="">ทุกชุมชน</option>${communities.map(c=>`<option ${communityFilter===c?'selected':''}>${esc(c)}</option>`).join('')}</select>`:`<div class="vreg25-count" data-v25-count></div>`}</div><div class="vreg25-filter"><button class="${statusFilter==='all'?'active':''}" data-v25-status="all">ทั้งหมด</button><button class="${statusFilter==='green'?'active':''}" data-v25-status="green">พร้อม</button><button class="${statusFilter==='yellow'?'active':''}" data-v25-status="yellow">ติดตาม</button><button class="${statusFilter==='orange'?'active':''}" data-v25-status="orange">ควรตรวจ</button><button class="${statusFilter==='pink'?'active':''}" data-v25-status="pink">เร่งแก้</button></div>${profile.role==='admin'?'<div class="vreg25-count" data-v25-count></div>':''}<div class="vreg25-list" data-v25-list></div>`;
  root.querySelector('[data-v25-search]').oninput=e=>{searchText=e.target.value.trim();drawRegistry(root);};
  const community=root.querySelector('[data-v25-community]');if(community)community.onchange=e=>{communityFilter=e.target.value;drawRegistry(root);};
  root.querySelectorAll('[data-v25-status]').forEach(b=>b.onclick=()=>{statusFilter=b.dataset.v25Status;root.querySelectorAll('[data-v25-status]').forEach(x=>x.classList.toggle('active',x===b));drawRegistry(root);});drawRegistry(root);
}
function renderSelfProfile(){
  if(profile?.role!=='user')return;const panel=$('[data-portal-panel="houses"]');if(!panel)return;const v=rows.find(x=>String(x.source_pid)===String(profile.volunteer_pid))||rows[0];if(!v)return;
  let root=$('[data-vself25]',panel);if(!root){root=document.createElement('details');root.className='vself25';root.dataset.vself25='1';const head=panel.querySelector('.section-head');head?.insertAdjacentElement('afterend',root);}
  const code=statusClass(v.status_code);root.innerHTML=`<summary>${avatarHtml(v,true)}<span class="vself25-title"><strong>${esc(v.display_name||'อสม.')}</strong><small>อสม. · ${esc(v.community||'—')} · ${esc(v.status_label||statusLabel(code))}</small></span><span class="vself25-more">ดูโปรไฟล์</span></summary><div class="vself25-body"><div class="vreg25-kpis"><div class="vreg25-kpi"><small>บ้านรับผิดชอบ</small><strong>${num(v.house_count)}</strong></div><div class="vreg25-kpi good"><small>ปักหมุดแล้ว</small><strong>${num(v.pinned_count)}</strong></div><div class="vreg25-kpi ${Number(v.issue_house_count)>0?'warn':'good'}"><small>ต้องจัดการ</small><strong>${num(v.issue_house_count)}</strong></div></div></div>`;observeAvatars(root);
}
function paintWorkflowTasks(){
  document.querySelectorAll('.wf22-task[data-wf-task]').forEach(b=>{b.classList.remove('v25-clear','v25-yellow','v25-orange','v25-pink');const raw=(b.querySelector('strong')?.textContent||'').replace(/[^0-9]/g,'');const n=Number(raw||0),type=b.dataset.wfTask;if(n===0)b.classList.add('v25-clear');else if(type==='outside')b.classList.add('v25-pink');else if(type==='review')b.classList.add('v25-orange');else b.classList.add('v25-yellow');});
}
async function enhance(){
  profile=await loadProfile();if(!profile?.active)return;await loadRows();renderRegistry();renderSelfProfile();paintWorkflowTasks();setVersion();
}
function start(){
  enhance().catch(()=>{});setTimeout(()=>enhance().catch(()=>{}),500);setTimeout(()=>enhance().catch(()=>{}),1500);
  const portal=$('#portal');if(portal&&'MutationObserver'in window){portalObserver=new MutationObserver(m=>{if(m.some(x=>x.type==='attributes'&&x.attributeName==='hidden')){setTimeout(()=>{renderRegistry();renderSelfProfile();paintWorkflowTasks();},80);}});portalObserver.observe(portal,{subtree:true,attributes:true,attributeFilter:['hidden']});}
}
export async function initVolunteerProfileRegistry1825(url,key){
  if(window.__PHC_VOLUNTEER_PROFILE_REGISTRY_1825__)return;window.__PHC_VOLUNTEER_PROFILE_REGISTRY_1825__=true;injectStyle();
  const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');supabase=createClient(url,key,{auth:{persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
}
