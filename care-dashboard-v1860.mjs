import { getSharedSupabase, getSharedProfile, sharedCall, invalidateShared, bindPortalActivation, isPortalViewActive } from './shared-runtime-v2035.mjs?v=2.0.126-log-usage';
const VERSION=document.querySelector('meta[name="phc-release"]')?.content||'2.0.135';
let supabase=null,profile=null,observer=null,loading=false,scope='self',ownerPid=null,staffVolunteers=[],loadEpochV2040=0;
const $=(s,r=document)=>r.querySelector(s);
const num=v=>Number(v||0).toLocaleString('th-TH');
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const snapshotLabel=v=>{if(!v)return'';try{return ` · ข้อมูล ณ ${new Date(v).toLocaleString('th-TH',{timeZone:'Asia/Bangkok',dateStyle:'short',timeStyle:'short'})} น.`}catch{return''}};
const SPECIAL_GROUP_V20135={
  disabled:{label:'ผู้พิการ',icon:'♿'},
  homebound:{label:'ผู้สูงอายุติดบ้าน',icon:'🏠',adl:'1B1281'},
  bedridden:{label:'ผู้สูงอายุติดเตียง',icon:'🛏️',adl:'1B1282'}
};
const houseKeyV20135=(pcucode,hcode)=>String(pcucode||'')+'|'+String(hcode||'');
function ageYearsV20135(birthDate){
  if(!birthDate)return null;
  const p=String(birthDate).slice(0,10).split('-').map(Number);
  if(p.length!==3||!p[0])return null;
  const today=String(new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Bangkok'})).split('-').map(Number);
  let age=today[0]-p[0];if(today[1]<p[1]||(today[1]===p[1]&&today[2]<p[2]))age-=1;
  return age>=0?age:null;
}
function currentScopeLabelV20135(){
  const rs=roleScope();
  if(profile?.role==='admin')return'ทุกพื้นที่ตามสิทธิ์ Admin';
  if(profile?.role==='user')return'บ้านที่ฉันรับผิดชอบ';
  if(rs==='community')return'ชุมชนของฉัน';
  if(rs==='volunteer'){
    const v=staffVolunteers.find(x=>Number(x.volunteer_pid)===Number(ownerPid));
    return v?.display_name?'อสม. '+v.display_name:'ราย อสม. ที่เลือก';
  }
  return'บ้านที่ฉันรับผิดชอบ';
}
async function scopedHouseMapV20135(){
  const rs=roleScope();
  let targetPid=null;
  if(profile?.role==='user')targetPid=Number(profile.volunteer_pid)||null;
  else if(profile?.role==='staff'&&rs==='self')targetPid=Number(profile.volunteer_pid)||null;
  else if(profile?.role==='staff'&&rs==='volunteer')targetPid=Number(ownerPid)||null;
  if((profile?.role==='user'||(profile?.role==='staff'&&rs!=='community'))&&!targetPid)return new Map();
  const out=new Map();let from=0;
  while(true){
    let q=supabase.from('houses').select('source_pcucode,hcode,house_no,moo,community,volunteer_pid')
      .eq('verification_status','verified_jhcis').is('superseded_by',null).order('hcode').range(from,from+999);
    if(targetPid)q=q.eq('volunteer_pid',targetPid);
    const {data,error}=await q;if(error)throw error;
    for(const h of data||[])out.set(houseKeyV20135(h.source_pcucode,h.hcode),h);
    if(!data||data.length<1000)break;from+=1000;if(from>=10000)break;
  }
  return out;
}
async function specialPeopleV20135(group){
  const cfg=SPECIAL_GROUP_V20135[group];if(!cfg)throw new Error('SPECIAL_GROUP_INVALID');
  const houses=await scopedHouseMapV20135();if(!houses.size)return[];
  const people=[];let from=0;
  while(true){
    let q=supabase.from('health_persons')
      .select('source_pcucode,source_pid,house_pcucode,hcode,display_name,birth_date,is_disabled,adl_group_code,adl_assessed_on,service_population_eligible')
      .eq('active',true).eq('service_population_eligible',true).order('display_name').range(from,from+999);
    q=group==='disabled'?q.eq('is_disabled',true):q.eq('adl_group_code',cfg.adl);
    const {data,error}=await q;if(error)throw error;
    for(const p of data||[]){
      const h=houses.get(houseKeyV20135(p.house_pcucode,p.hcode));if(!h)continue;
      const age=ageYearsV20135(p.birth_date);
      if(group!=='disabled'&&(age==null||age<60))continue;
      people.push({...p,age_years:age,house_no:h.house_no,moo:h.moo,community:h.community});
    }
    if(!data||data.length<1000)break;from+=1000;if(from>=10000)break;
  }
  people.sort((a,b)=>String(a.display_name||'').localeCompare(String(b.display_name||''),'th'));
  return people;
}
function closeSpecialPeopleV20135(){document.querySelector('[data-care60-special-overlay]')?.remove();}
async function openSpecialPeopleV20135(group){
  const cfg=SPECIAL_GROUP_V20135[group];if(!cfg)return;
  closeSpecialPeopleV20135();
  const overlay=document.createElement('div');overlay.className='care60-special-overlay';overlay.dataset.care60SpecialOverlay='1';
  overlay.innerHTML=`<section class="care60-special-modal" role="dialog" aria-modal="true" aria-label="${esc(cfg.label)}"><div class="care60-special-modal-head"><div><small>${esc(currentScopeLabelV20135())}</small><h3>${cfg.icon} ${esc(cfg.label)}</h3></div><button type="button" data-care60-special-close aria-label="ปิด">×</button></div><div class="care60-special-loading">กำลังโหลดรายชื่อ…</div></section>`;
  overlay.addEventListener('click',e=>{if(e.target===overlay)closeSpecialPeopleV20135()});overlay.querySelector('[data-care60-special-close]').onclick=closeSpecialPeopleV20135;document.body.appendChild(overlay);
  try{
    const rows=await specialPeopleV20135(group);
    if(!document.body.contains(overlay))return;
    const box=overlay.querySelector('.care60-special-modal');
    const list=rows.map((p,i)=>`<article class="care60-special-person" data-care60-person-row data-search="${esc((p.display_name||'')+' '+(p.house_no||'')+' '+(p.community||''))}"><b>${i+1}. ${esc(p.display_name||'ไม่ระบุชื่อ')}</b><small>บ้าน ${esc(p.house_no||'—')} · หมู่ ${esc(p.moo||'—')} · ${esc(p.community||'—')}</small><small>${p.age_years!=null?'อายุ '+num(p.age_years)+' ปี · ':''}${group==='disabled'?'ทะเบียนผู้พิการ':'ADL ล่าสุด '+esc(p.adl_assessed_on||'ไม่ระบุวันที่')}</small></article>`).join('');
    box.innerHTML=`<div class="care60-special-modal-head"><div><small>${esc(currentScopeLabelV20135())}</small><h3>${cfg.icon} ${esc(cfg.label)} <span>${num(rows.length)} คน</span></h3></div><button type="button" data-care60-special-close aria-label="ปิด">×</button></div>${rows.length>8?'<input class="care60-special-search" data-care60-special-search type="search" placeholder="ค้นหาชื่อ / บ้าน / ชุมชน">':''}<div class="care60-special-list">${list||'<div class="care60-special-empty">ไม่พบรายชื่อในขอบเขตสิทธิ์ปัจจุบัน</div>'}</div><div class="care60-note">รายชื่อแสดงตามสิทธิ์บัญชีและขอบเขตที่เลือกอยู่ในหน้า Dashboard · ไม่เปิดข้อมูลข้ามสิทธิ์</div>`;
    box.querySelector('[data-care60-special-close]').onclick=closeSpecialPeopleV20135;
    const search=box.querySelector('[data-care60-special-search]');if(search)search.oninput=()=>{const q=search.value.trim().toLocaleLowerCase('th');box.querySelectorAll('[data-care60-person-row]').forEach(el=>{el.hidden=!!q&&!String(el.dataset.search||'').toLocaleLowerCase('th').includes(q)})};
  }catch(e){
    const loading=overlay.querySelector('.care60-special-loading');if(loading)loading.innerHTML='<strong>โหลดรายชื่อไม่สำเร็จ</strong><br><small>'+esc(e.message||e)+'</small>';
  }
}

function injectStyle(){if($('#care-dashboard-v1860-style'))return;const s=document.createElement('style');s.id='care-dashboard-v1860-style';s.textContent=`
#stats.care60-host{display:block!important}#stats.care60-host[hidden]{display:none!important}.care60{display:grid;gap:14px;width:100%}.care60-head{display:flex;justify-content:space-between;gap:10px;align-items:flex-start;flex-wrap:wrap}.care60-head h2{margin:.15rem 0;font-size:1.35rem}.care60-head p{margin:.2rem 0 0;color:#60736d;line-height:1.45}.care60-scope{display:flex;gap:7px;padding:5px;border:1px solid #cfe0d9;border-radius:14px;background:#f3f8f6}.care60-scope button{min-height:48px;border:0;border-radius:11px;padding:8px 14px;background:transparent;color:#385a52;font:inherit;font-weight:900;cursor:pointer}.care60-scope button.active{background:#0b6f60;color:#fff}.care60-kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:9px}.care60-kpi{min-height:100px;border:1px solid #d5e4de;border-radius:16px;background:#fff;padding:13px;text-align:left;color:#17312d;font:inherit}.care60-kpi button{all:unset;display:block;width:100%;cursor:pointer}.care60-kpi small{display:block;color:#657872;line-height:1.25}.care60-kpi strong{display:block;margin-top:6px;font-size:1.55rem}.care60-progress{padding:13px 14px;border:1px solid #cfe0d9;border-radius:16px;background:#f7fbf9}.care60-progress-head{display:flex;justify-content:space-between;gap:12px;align-items:end}.care60-progress-head strong{font-size:1.2rem}.care60-progress-head b{font-size:1.4rem;color:#0b6f60}.care60-bar{height:14px;border-radius:99px;background:#dfeae6;overflow:hidden;margin-top:9px}.care60-bar i{display:block;height:100%;background:#148a76;border-radius:inherit}.care60-section{display:grid;gap:9px}.care60-section h3{margin:0;font-size:1.12rem}.care60-stage-grid{display:grid;grid-template-columns:repeat(5,1fr);gap:9px}.care60-stage{min-height:118px;border:2px solid #d5e4de;border-radius:17px;background:#fff;padding:10px 8px;color:#17312d;font:inherit;text-align:center;cursor:pointer}.care60-stage .ico{display:block;font-size:1.8rem;line-height:1.1}.care60-stage strong{display:block;font-size:1.35rem;margin-top:5px}.care60-stage small{display:block;color:#60736d;margin-top:3px;line-height:1.25}.care60-special{display:grid;grid-template-columns:repeat(3,1fr);gap:9px}.care60-special button{min-height:90px;padding:11px;border:1px solid #d5e4de;border-radius:15px;background:#fff;text-align:center;color:#17312d;font:inherit;cursor:pointer}.care60-special button:hover,.care60-special button:focus-visible{border-color:#0b6f60;box-shadow:0 0 0 2px rgba(11,111,96,.12)}.care60-special .ico{font-size:1.45rem}.care60-special strong{display:block;font-size:1.35rem;margin-top:3px}.care60-special small{display:block;color:#60736d}.care60-next{display:grid;grid-template-columns:repeat(3,1fr);gap:9px}.care60-next button{min-height:82px;border:1px solid #d5e4de;border-radius:15px;background:#fff8df;color:#5f4b13;font:inherit;font-weight:900;padding:10px;cursor:pointer}.care60-next button.bad{background:#fff0ed;color:#8b372d}.care60-next button.map{background:#eef6f3;color:#1c5f53}.care60-note{font-size:.86rem;color:#687b75;line-height:1.45}.care60-source{padding:10px 12px;border-radius:12px;background:#f3f8f6}.care60-section-head{display:flex;justify-content:space-between;gap:8px;align-items:baseline;flex-wrap:wrap}.care60-section-head small{color:#687b75}.care60-hdc{padding:13px;border:1px solid #d9e5e0;border-radius:16px;background:#fbfdfc}.care60-ref-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}.care60-ref-card{padding:11px;border:1px solid #d5e4de;border-radius:14px;background:#fff}.care60-ref-card small{display:block;color:#60736d;line-height:1.3}.care60-ref-card strong{display:block;margin-top:5px;font-size:1.08rem}.care60-ref-card b{display:block;margin-top:2px;color:#0b6f60;font-size:1.12rem}
.care60-special-overlay{position:fixed;inset:0;z-index:10040;background:rgba(16,38,34,.52);display:grid;place-items:center;padding:16px}.care60-special-modal{width:min(720px,100%);max-height:min(82vh,760px);overflow:auto;background:#fff;border-radius:20px;padding:16px;box-shadow:0 20px 60px rgba(0,0,0,.24);display:grid;gap:11px}.care60-special-modal-head{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;position:sticky;top:-16px;background:#fff;padding:4px 0 8px;z-index:2}.care60-special-modal-head h3{margin:2px 0 0}.care60-special-modal-head h3 span{font-size:.9rem;color:#60736d}.care60-special-modal-head small{color:#60736d}.care60-special-modal-head button{width:44px;height:44px;border:0;border-radius:12px;background:#eaf3ef;color:#17312d;font-size:1.7rem;cursor:pointer}.care60-special-search{width:100%;min-height:46px;border:1px solid #cfe0d9;border-radius:12px;padding:9px 12px;font:inherit}.care60-special-list{display:grid;gap:8px}.care60-special-person{border:1px solid #dce8e3;border-radius:13px;padding:10px 12px;background:#fbfdfc}.care60-special-person b,.care60-special-person small{display:block}.care60-special-person small{margin-top:3px;color:#60736d;line-height:1.35}.care60-special-empty,.care60-special-loading{padding:24px;text-align:center;color:#60736d}.care60-owner{display:flex;align-items:center;gap:8px;width:100%;font-weight:850;color:#385a52}.care60-owner select{min-height:48px;min-width:260px;border:1px solid #cfe0d9;border-radius:12px;background:#fff;padding:8px 11px;font:inherit}.care60-next button small{display:block;margin-top:5px;font-weight:700;line-height:1.35}.care60-followup-modal{position:fixed;inset:0;z-index:5000;background:rgba(12,33,29,.46);display:grid;align-items:end;padding:14px}.care60-followup-sheet{width:min(720px,100%);max-height:min(82vh,760px);margin:0 auto;background:#fff;border-radius:22px 22px 16px 16px;box-shadow:0 18px 60px rgba(0,0,0,.25);display:grid;grid-template-rows:auto auto minmax(0,1fr);overflow:hidden;padding-bottom:max(10px,env(safe-area-inset-bottom))}.care60-followup-head{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:16px 16px 10px;border-bottom:1px solid #e1ebe7}.care60-followup-head h3{margin:0;font-size:1.12rem}.care60-followup-head button{border:0;background:#edf5f2;color:#245e53;border-radius:12px;min-width:44px;min-height:44px;font:inherit;font-weight:900;cursor:pointer}.care60-followup-count{padding:9px 16px;color:#637871;background:#f8fbfa;font-size:.88rem}.care60-followup-list{overflow:auto;padding:10px 14px 16px;display:grid;gap:9px}.care60-followup-card{border:1px solid #e2dfd8;border-left:5px solid #e1ae24;border-radius:14px;padding:11px 12px;background:#fff}.care60-followup-card.red{border-left-color:#c9382e;background:#fff8f7}.care60-followup-card.orange{border-left-color:#e18427;background:#fffaf3}.care60-followup-card strong{display:block;color:#213d37}.care60-followup-card small{display:block;color:#687b75;line-height:1.4;margin-top:4px}.care60-followup-empty{padding:28px 16px;text-align:center;color:#687b75}
@media(max-width:700px){.care60{gap:12px}.care60-head h2{font-size:1.25rem}.care60-scope{width:100%;display:grid;grid-template-columns:repeat(3,1fr)}.care60-scope button{min-height:56px;font-size:.95rem;padding:7px}.care60-owner{display:grid}.care60-owner select{width:100%;min-width:0}.care60-kpis{grid-template-columns:1fr 1fr}.care60-kpi{min-height:94px;padding:12px}.care60-kpi strong{font-size:1.5rem}.care60-stage-grid{grid-template-columns:1fr 1fr}.care60-stage{min-height:105px;font-size:1.02rem}.care60-stage:last-child{grid-column:1/-1}.care60-special{grid-template-columns:1fr 1fr 1fr}.care60-special article{padding:9px 5px}.care60-special small{font-size:.82rem}.care60-next{grid-template-columns:1fr}.care60-next button{min-height:68px;font-size:1.05rem}.care60-ref-grid{grid-template-columns:1fr 1fr}.care60-ref-card{min-height:88px}}
`;document.head.appendChild(s);}
function setVersion(){const e=$('.login-version');if(e)e.textContent=`Cloud v${VERSION}`;}
async function loadProfile(){return getSharedProfile(supabase);}
function roleScope(){if(profile?.role==='admin')return'all';if(profile?.role==='staff')return ['self','volunteer','community'].includes(scope)?scope:'self';return'self';}
function broadcastScope(){window.__PHC_CARE_SCOPE__=roleScope();document.dispatchEvent(new CustomEvent('phc:care-scope-changed',{detail:{scope:roleScope(),volunteer_pid:ownerPid,source:'care-dashboard'}}));}
async function loadStaffVolunteers(){if(profile?.role!=='staff')return[];const {data,error}=await sharedCall('staff-volunteer-scope-v2033',()=>supabase.rpc('staff_volunteer_scope_v2033'),300000);if(error)throw error;staffVolunteers=Array.isArray(data)?data:[];if(ownerPid&&!staffVolunteers.some(v=>Number(v.volunteer_pid)===Number(ownerPid)))ownerPid=null;if(!ownerPid&&staffVolunteers.length)ownerPid=Number(staffVolunteers[0].volunteer_pid);return staffVolunteers;}
function openPanel(name){const b=$(`#portal-nav [data-portal-view="${name}"]`);if(b&&!b.hidden){b.click();return true;}return false;}
function openHealth(filter='all',stage='',assignment='all'){broadcastScope();window.PHCSetHealthIntentV2058?.({filter,stage,assignment,search:''});openPanel('health');}
const followTypeText=v=>({ncd:'NCD',elderly9:'ผู้สูงอายุ 9 ด้าน',growth:'น้ำหนัก/ส่วนสูง',child_dev:'พัฒนาการเด็ก'}[String(v||'').toLowerCase()]||String(v||'ติดตาม'));
const followStatusText=v=>String(v||'')==='in_progress'?'กำลังติดตาม':'เปิดติดตาม';
const followPriorityText=v=>({red:'เร่งด่วน',orange:'ควรเร่งติดตาม',yellow:'ติดตาม'}[String(v||'').toLowerCase()]||String(v||''));
const followDate=v=>{if(!v)return'—';try{return new Date(v).toLocaleString('th-TH',{timeZone:'Asia/Bangkok',dateStyle:'short',timeStyle:'short'})+' น.'}catch{return String(v)}};
async function openFollowups(){
  document.querySelector('.care60-followup-modal')?.remove();
  const modal=document.createElement('div');modal.className='care60-followup-modal';
  modal.innerHTML='<section class="care60-followup-sheet" role="dialog" aria-modal="true" aria-label="เคสที่ต้องติดตามหลังคัดกรอง"><div class="care60-followup-head"><h3>เคสที่ต้องติดตามหลังคัดกรอง</h3><button type="button" data-care60-followup-close aria-label="ปิด">×</button></div><div class="care60-followup-count">กำลังโหลดรายชื่อ…</div><div class="care60-followup-list"><div class="care60-followup-empty">กำลังอ่านข้อมูล…</div></div></section>';
  const close=()=>modal.remove();modal.querySelector('[data-care60-followup-close]').onclick=close;modal.onclick=e=>{if(e.target===modal)close()};document.body.appendChild(modal);
  const rs=roleScope(),op=rs==='volunteer'?(ownerPid??null):null;
  const {data,error}=await supabase.rpc('screening_followup_worklist_v2195',{p_scope:rs,p_owner_pid:op,p_limit:200,p_offset:0});
  const count=modal.querySelector('.care60-followup-count'),list=modal.querySelector('.care60-followup-list');
  if(error){count.textContent='โหลดรายชื่อไม่สำเร็จ';list.innerHTML='<div class="care60-followup-empty">'+esc(error.message)+'</div>';return}
  const rows=Array.isArray(data)?data:[];
  count.textContent='พบ '+num(rows.length)+' เคส · แสดงเฉพาะสถานะเปิดและกำลังติดตามตามขอบเขตสิทธิ์';
  list.innerHTML=rows.map(r=>'<article class="care60-followup-card '+esc(r.priority||'')+'"><strong>'+esc(r.display_name)+' · '+esc(followTypeText(r.followup_type))+(r.domain_code?' / '+esc(r.domain_code):'')+'</strong><small>บ้าน '+esc(r.house_no||'—')+' · '+esc(r.community||'—')+'</small><small>'+esc(r.summary||'')+'</small><small>'+esc(followPriorityText(r.priority))+' · '+esc(followStatusText(r.status))+' · '+esc(followDate(r.created_at))+'</small></article>').join('')||'<div class="care60-followup-empty">ไม่มีเคสติดตามค้างในขอบเขตนี้</div>';
}

function metricRefCard(label,item){if(!item||item.target==null||item.result==null)return'';const p=Number(item.percentage||0);return `<article class="care60-ref-card"><small>${esc(label)}</small><strong>${num(item.result)} / ${num(item.target)}</strong><b>${Number.isFinite(p)?p.toFixed(1):'0.0'}%</b></article>`;}
function render(d){
  const host=$('#stats');if(!host)return;
  host.classList.add('care60-host');
  const target=Number(d.ncd_targets||0),done=Number(d.ncd_done||0),pct=target?Math.round(done*1000/target)/10:0;
  const scopeToggle=profile.role==='staff'?`<div class="care60-scope" role="group" aria-label="ขอบเขตข้อมูล"><button type="button" data-care60-scope="self" class="${scope==='self'?'active':''}">ของฉัน</button><button type="button" data-care60-scope="volunteer" class="${scope==='volunteer'?'active':''}">ราย อสม.</button><button type="button" data-care60-scope="community" class="${scope==='community'?'active':''}">ชุมชนของฉัน</button></div>${scope==='volunteer'?`<label class="care60-owner">เลือก อสม.<select data-care60-owner>${staffVolunteers.map(v=>`<option value="${esc(v.volunteer_pid)}" ${Number(v.volunteer_pid)===Number(ownerPid)?'selected':''}>${esc(v.display_name)}</option>`).join('')}</select></label>`:''}`:'';
  const assignment=d.assignment_summary||null;
  const assignedPeople=Number(assignment?.assigned_people||0),fallbackPeople=Number(assignment?.fallback_people||0),unresolvedPeople=Number(assignment?.unresolved_people||0),noVolunteer=Number(assignment?.no_volunteer_people||0),inactiveVolunteer=Number(assignment?.inactive_volunteer_people||0),noActiveUser=Number(assignment?.no_active_user_people||0);
  const assignmentBlock=assignment?`<section class="care60-section"><h3>ความครอบคลุมผู้รับผิดชอบ</h3><div class="care60-next"><button type="button" class="map" data-care60-assignment="assigned">✅ มีผู้รับผิดชอบ ${num(assignedPeople)} คน</button><button type="button" class="${fallbackPeople>0?'bad':''}" data-care60-fallback>👥 Staff ดูแลแทน ${num(fallbackPeople)} คน<small>ไม่มี อสม. ${num(noVolunteer)} · อสม.หยุดปฏิบัติงาน ${num(inactiveVolunteer)} · ยังไม่มีบัญชี ${num(noActiveUser)}</small></button><button type="button" class="${unresolvedPeople>0?'bad':''}" data-care60-unresolved>⚠️ ไม่ทราบชุมชน ${num(unresolvedPeople)} คน<small>ส่งให้ Admin ตรวจสอบ ไม่มอบหมายโดยการเดา</small></button></div></section>`:'';
  const h=d.hdc_reference||null;
  const hdcBlock=(profile.role==='admin'&&h)?`<section class="care60-section care60-hdc"><div class="care60-section-head"><h3>เทียบตัวชี้วัด HDC ปี ${esc(h.fiscal_year_be||'')}</h3><small>ภาพรวมหน่วยบริการ ${esc(h.hospcode||'')}</small></div><div class="care60-ref-grid">${metricRefCard('ประเมิน ADL ผู้สูงอายุ',h.elderly_adl)}${metricRefCard('คัดกรองผู้สูงอายุ 9 ด้าน',h.elderly_9_domains)}${metricRefCard('คัดกรองเบาหวาน',h.dm_screen)}${metricRefCard('คัดกรองความดัน',h.ht_screen)}</div><div class="care60-note">แหล่งอ้างอิง: MoPH Open Data ผ่าน hdc-app · เป็นยอดรวมทางการระดับหน่วยบริการ จึงอาจไม่เท่ารายชื่อปฏิบัติงาน JHCIS/J-Report หลังการตัดซ้ำและประมวลผลส่วนกลาง</div></section>`:'';
  host.innerHTML=`<section class="care60">
    <div class="care60-head"><div><p class="eyebrow">CARE DASHBOARD</p><h2>ภาพรวมการดูแลประชากร</h2><p>${esc(d.scope_label||'ข้อมูลตามสิทธิ์')} · ${num(d.houses)} หลัง${esc(snapshotLabel(d.snapshot_generated_at))}</p></div>${scopeToggle}</div>
    <div class="care60-kpis">
      <article class="care60-kpi tone-info"><button type="button" data-care60-open="houses"><small>ประชากรฐานบริการ</small><strong>${num(d.service_people??d.people)} คน</strong></button></article>
      <article class="care60-kpi tone-info"><button type="button" data-care60-health="targets"><small>เป้าหมาย NCD งานเชิงรุก</small><strong>${num(d.ncd_targets)}</strong></button></article>
      <article class="care60-kpi ${Number(d.ncd_done)>0?'tone-success':'tone-neutral'}"><button type="button" data-care60-health="targets"><small>คัดกรองแล้วปีงบฯ</small><strong>${num(d.ncd_done)}</strong></button></article>
      <article class="care60-kpi ${Number(d.ncd_due)>0?'tone-warning':'tone-neutral'}"><button type="button" data-care60-health="due"><small>คงเหลือ</small><strong>${num(d.ncd_due)}</strong></button></article>
    </div>
    <div class="care60-progress"><div class="care60-progress-head"><div><small>ความก้าวหน้า NCD ตามบัญชีปฏิบัติงาน J-Report/JHCIS</small><strong>${num(done)} / ${num(target)} คน</strong></div><b>${pct}%</b></div><div class="care60-bar"><i style="width:${Math.min(100,pct)}%"></i></div></div>
    <div class="care60-note care60-source">ตัวเลขรายบุคคลใช้ JHCIS/J-Report แบบอ่านอย่างเดียว · ฐานประชากรปฏิบัติงาน = JHCIS Type 1 และ 3 เท่านั้น · สถานะอยู่จริง/คุณภาพข้อมูลติดตามแยกต่างหาก · HDC ใช้เป็นตัวเลขอ้างอิงทางการ</div>
    <div class="care60-status-legend" aria-label="ความหมายของสีสถานะ"><span class="green"><i></i>ปกติ / สำเร็จ</span><span class="yellow"><i></i>ต้องติดตาม</span><span class="orange"><i></i>ควรตรวจ / เร่งดำเนินการ</span><span class="red"><i></i>เร่งด่วน / เสี่ยงสูง</span></div>
    <section class="care60-section"><h3>กลุ่มประชากรที่ต้องดูแล</h3><div class="care60-stage-grid">
      <button class="care60-stage" data-care60-stage="เด็กปฐมวัย"><span class="ico">👶</span><strong>${num(d.early_child)}</strong><small>เด็ก 0–5 ปี</small></button>
      <button class="care60-stage" data-care60-stage="เด็กวัยเรียน"><span class="ico">🎒</span><strong>${num(d.school_age)}</strong><small>วัยเรียน</small></button>
      <button class="care60-stage" data-care60-stage="วัยรุ่นและเยาวชน"><span class="ico">🧑</span><strong>${num(d.youth)}</strong><small>วัยรุ่น/เยาวชน</small></button>
      <button class="care60-stage" data-care60-stage="วัยทำงาน"><span class="ico">👷</span><strong>${num(d.working_age)}</strong><small>วัยทำงาน</small></button>
      <button class="care60-stage" data-care60-stage="ผู้สูงอายุ"><span class="ico">👴</span><strong>${num(d.older_people)}</strong><small>ผู้สูงอายุ</small></button>
    </div></section>
    <section class="care60-section"><h3>กลุ่มดูแลเป็นพิเศษ</h3><div class="care60-special">
      <button type="button" data-care60-special="disabled"><span class="ico">♿</span><strong>${num(d.disabled_people)}</strong><small>พิการ</small></button>
      <button type="button" data-care60-special="homebound"><span class="ico">🏠</span><strong>${num(d.homebound_people)}</strong><small>ติดบ้าน · ADL ล่าสุด</small></button>
      <button type="button" data-care60-special="bedridden"><span class="ico">🛏️</span><strong>${num(d.bedridden_people)}</strong><small>ติดเตียง · ADL ล่าสุด</small></button>
    </div><div class="care60-note">ADL ล่าสุดที่พบ ${num(d.adl_assessed_people)} คน · ติดสังคม ${num(d.social_people)} คน · ใช้รหัส SPECIALPP 1B1280/1B1281/1B1282 ตามนิยาม HDC</div></section>
    ${hdcBlock}
    ${assignmentBlock}
    <section class="care60-section"><h3>งานที่ต้องทำต่อ</h3><div class="care60-next"><button type="button" class="map" data-care60-open="houses">📍 ไม่มีพิกัด ${num(d.missing_coordinates)} หลัง · ต้องตรวจ ${num(d.review_houses)} หลัง</button><button type="button" data-care60-health="due">🟡 NCD คงเหลือ ${num(d.ncd_due)} คน</button><button type="button" class="bad" data-care60-followup>🔴 เคสที่ต้องติดตามหลังคัดกรอง ${num(d.followup_open)} เคส<small>กดดูรายชื่อ</small></button></div></section>
  </section>`;
  host.querySelectorAll('[data-care60-scope]').forEach(b=>b.onclick=async()=>{scope=b.dataset.care60Scope;if(scope==='volunteer'&&!staffVolunteers.length)await loadStaffVolunteers();if(scope==='volunteer'&&!ownerPid){scope='self';}try{localStorage.setItem('phc.care.scope',scope);if(ownerPid)localStorage.setItem('phc.care.volunteer',String(ownerPid));}catch{}broadcastScope();await load();});
  const owner=host.querySelector('[data-care60-owner]');if(owner)owner.onchange=async()=>{ownerPid=Number(owner.value)||null;try{if(ownerPid)localStorage.setItem('phc.care.volunteer',String(ownerPid));}catch{}broadcastScope();await load();};
  host.querySelectorAll('[data-care60-open]').forEach(b=>b.onclick=()=>{const name=b.dataset.care60Open;if(name==='houses'&&!openPanel('houses'))openPanel('communities');});
  host.querySelectorAll('[data-care60-health]').forEach(b=>b.onclick=()=>openHealth(b.dataset.care60Health||'all',''));
  host.querySelector('[data-care60-followup]')?.addEventListener('click',openFollowups);
  host.querySelector('[data-care60-fallback]')?.addEventListener('click',()=>openHealth('field_targets','','fallback'));
  host.querySelector('[data-care60-unresolved]')?.addEventListener('click',()=>{if(profile.role==='admin')openHealth('field_targets','','unresolved');});
  host.querySelectorAll('[data-care60-stage]').forEach(b=>b.onclick=()=>openHealth('field_targets',b.dataset.care60Stage));
  host.querySelectorAll('[data-care60-special]').forEach(b=>b.onclick=()=>openSpecialPeopleV20135(b.dataset.care60Special));
}
function ownsCareLoadV2040(epoch){return epoch===loadEpochV2040&&isPortalViewActive('overview');}
async function load(){if(loading||!profile?.active||!isPortalViewActive('overview'))return;const epoch=++loadEpochV2040;loading=true;try{const rs=roleScope(),op=rs==='volunteer'?(ownerPid??null):null;let {data,error}=await sharedCall(`report-snapshot:care-v2195:${rs}:${op??''}`,()=>supabase.rpc('report_snapshot_care_v2195',{p_scope:rs,p_owner_pid:op}),120000);if(!ownsCareLoadV2040(epoch))return;if((error||!data)&&roleScope()!=='volunteer'){const legacy=await supabase.rpc('report_snapshot_v2031',{p_report_key:'care',p_scope:roleScope()});data=legacy.data;error=legacy.error;if(!ownsCareLoadV2040(epoch))return;}if((error||!data)&&roleScope()!=='volunteer'){const live=await supabase.rpc('care_dashboard_v1861',{p_scope:roleScope()});data=live.data;error=live.error;if(!ownsCareLoadV2040(epoch))return;}if(error)throw error;data=data||{};if(data.followup_open==null){const f=await supabase.rpc('screening_followup_count_v2195',{p_scope:rs,p_owner_pid:op});if(!f.error)data={...data,followup_open:Number(f.data||0)}}if((profile?.role==='staff'&&roleScope()==='community')||profile?.role==='admin'){if(!ownsCareLoadV2040(epoch))return;const a=await sharedCall(`assignment-summary-v2058:${roleScope()}:`,async()=>{let r=await supabase.rpc('assignment_summary_fast_v2058',{p_scope:roleScope(),p_owner_pid:null});if(r.error)r=await supabase.rpc('assignment_summary_v2033',{p_scope:roleScope(),p_owner_pid:null});return r;},300000);if(!ownsCareLoadV2040(epoch))return;if(!a.error&&a.data)data={...data,assignment_summary:a.data};}if(ownsCareLoadV2040(epoch))render(data);}catch(e){const host=$('#stats');if(ownsCareLoadV2040(epoch)&&host)host.innerHTML=`<article class="stat"><small>Dashboard</small><strong>โหลดไม่สำเร็จ</strong><span>${esc(e.message)}</span></article>`;}finally{if(epoch===loadEpochV2040)loading=false;}}
async function enhance(){profile=await loadProfile();if(!profile?.active)return;if(profile.role==='staff'){try{const saved=localStorage.getItem('phc.care.scope')||localStorage.getItem('phc.field.scope');scope=['self','volunteer','community'].includes(saved)?saved:'self';ownerPid=Number(localStorage.getItem('phc.care.volunteer'))||null;}catch{scope='self';}try{await loadStaffVolunteers();}catch{if(scope==='volunteer')scope='self';}}else scope=profile.role==='admin'?'all':'self';broadcastScope();await load();}
async function syncSharedScope(event){if(profile?.role!=='staff'||event.detail?.source==='care-dashboard')return;const next=['self','volunteer','community'].includes(event.detail?.scope)?event.detail.scope:'self';const nextOwner=Number(event.detail?.volunteer_pid)||ownerPid;if(scope===next&&ownerPid===nextOwner)return;scope=next;ownerPid=nextOwner;try{localStorage.setItem('phc.care.scope',scope);localStorage.setItem('phc.field.scope',scope);if(ownerPid)localStorage.setItem('phc.care.volunteer',String(ownerPid));}catch{}const overview=$('[data-portal-panel="overview"]');if(overview&&!overview.hidden)await load();}
function start(){setVersion();bindPortalActivation('overview',enhance);document.addEventListener('phc:portal-view-changed',e=>{if(e.detail?.view!=='overview'){loadEpochV2040+=1;loading=false;}});document.addEventListener('phc:care-scope-changed',event=>{syncSharedScope(event).catch(()=>{})});document.addEventListener('phc:report-snapshot-refreshed',()=>{invalidateShared('report-snapshot:care:');if(isPortalViewActive('overview'))load().catch(()=>{});});}
export async function initCareDashboard1860(url,key){if(window.__PHC_CARE_DASHBOARD_1860__)return;window.__PHC_CARE_DASHBOARD_1860__=true;injectStyle();supabase=await getSharedSupabase(url,key);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();}
