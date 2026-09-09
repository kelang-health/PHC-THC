import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});
const $ = s => document.querySelector(s);
const esc = v => String(v ?? '').replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const num = v => Number(v || 0).toLocaleString('th-TH');
let passwordChangeForced = false;
let currentProfile = null;
let portalView = 'overview';
let healthPeople = [];
let selectedHealthPerson = null;
let healthLoaded = false;
let healthSearchTimer = null;

function show(el, visible=true){ el.hidden = !visible; }
function roleLabel(role){ return ({admin:'ผู้ดูแลระบบ',staff:'เจ้าหน้าที่',user:'อสม.'})[role] || role || 'ไม่ระบุ'; }
function setPortalView(next){const allowed=[...document.querySelectorAll('#portal-nav [data-portal-view]')].filter(b=>!b.hidden).map(b=>b.dataset.portalView);portalView=allowed.includes(next)?next:'overview';document.querySelectorAll('[data-portal-panel]').forEach(x=>x.hidden=x.dataset.portalPanel!==portalView);document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>b.classList.toggle('active',b.dataset.portalView===portalView));if(window.innerWidth<640)window.scrollTo({top:0,behavior:'smooth'});}
function configurePortalNav(role){document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>{b.hidden=!(b.dataset.roles||'').split(/\s+/).includes(role);b.onclick=async()=>{setPortalView(b.dataset.portalView);if(b.dataset.portalView==='health'&&!healthLoaded){try{await loadHealthModule();}catch(e){$('#health-person-body').innerHTML=`<tr><td colspan="5">${esc(e.message)}</td></tr>`;}}};});setPortalView('overview');}

function localDate(){return new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Bangkok'});}
function formNumber(value){const n=Number(value);return Number.isFinite(n)?n:null;}
function requestId(){return crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;}

function healthClass(severity){return severity==='urgent'||severity==='alert'?'bad':severity==='risk'?'warn':severity==='normal'?'good':'';}
function personKey(p){return `${p.source_pcucode}|${p.source_pid}`;}
async function loadHealthSummary(){
  const {data,error}=await supabase.from('health_work_summary').select('*').maybeSingle();
  if(error)throw error; const x=data||{};
  $('#health-stats').innerHTML=[
    [x.people,'ประชาชนในสิทธิ์'],[x.ncd_targets,'เป้าหมาย NCD 35+'],[x.ncd_screened_current_fy,'คัดกรองแล้วปีงบฯ'],[x.ncd_due,'คงเหลือ'],[x.known_ncd,'DM/HT เดิม']
  ].map(([v,l])=>`<article class="stat"><small>${esc(l)}</small><strong>${num(v)}</strong></article>`).join('');
  $('#life-stage-stats').innerHTML=[['เด็กปฐมวัย',x.early_child],['เด็กวัยเรียน',x.school_age],['วัยรุ่นและเยาวชน',x.youth],['วัยทำงาน',x.working_age],['ผู้สูงอายุ',x.older_people]].map(([l,v])=>`<div class="life-chip"><span>${esc(l)}</span><strong>${num(v)}</strong></div>`).join('');
}
async function loadHealthPeople(){
  const filter=$('#health-filter').value, stage=$('#health-stage').value, raw=$('#health-search').value.trim();
  let q=supabase.from('health_person_worklist').select('source_pcucode,source_pid,hcode,house_no,moo,community,display_name,gender,birth_date,age_years,life_stage,has_ht,has_dm,known_ncd,ncd_target,latest_screened_on,latest_ncd_status,latest_severity,screened_current_fy').order('community').order('hcode').order('display_name').limit(300);
  if(filter==='due')q=q.eq('ncd_target',true).eq('screened_current_fy',false);
  else if(filter==='targets')q=q.eq('ncd_target',true);
  else if(filter==='known')q=q.eq('known_ncd',true);
  if(stage)q=q.eq('life_stage',stage);
  const term=raw.replace(/[%_,()]/g,'').slice(0,60); if(term)q=q.ilike('display_name',`%${term}%`);
  const {data,error}=await q; if(error)throw error; healthPeople=data||[];
  $('#health-person-body').innerHTML=healthPeople.map((p,i)=>`<tr><td><strong>${esc(p.display_name)}</strong><small>${p.known_ncd?`โรคเดิม: ${p.has_ht?'HT ':''}${p.has_dm?'DM':''}`:'ยังไม่พบ DM/HT ใน personchronic'}</small></td><td>${esc(p.age_years??'—')} ปี<small>${esc(p.life_stage||'—')}</small></td><td>บ้าน ${esc(p.house_no||p.hcode)}<small>หมู่ ${esc(p.moo||'—')} · ${esc(p.community||'—')}</small></td><td class="${healthClass(p.latest_severity)}">${esc(p.latest_ncd_status||'ยังไม่มีผล')}<small>${p.latest_screened_on?esc(p.latest_screened_on):''}</small></td><td><button type="button" class="row-open" data-health-person="${i}">${p.age_years>=18?'คัดกรอง':'ดูข้อมูล'}</button></td></tr>`).join('')||'<tr><td colspan="5">ไม่พบประชาชนตามตัวกรอง</td></tr>';
  $('#health-list-note').textContent=healthPeople.length>=300?'แสดงสูงสุด 300 ราย กรุณาใช้ค้นหาชื่อหรือตัวกรองเพื่อเจาะจงรายการ':'';
  document.querySelectorAll('[data-health-person]').forEach(b=>b.onclick=()=>selectHealthPerson(Number(b.dataset.healthPerson)));
}
async function loadHealthHistory(){
  const {data,error}=await supabase.from('health_ncd_history').select('screened_on,display_name,house_no,hcode,ncd_status,severity').order('screened_on',{ascending:false}).order('recorded_at',{ascending:false}).limit(30);
  if(error)throw error;
  $('#ncd-history-body').innerHTML=(data||[]).map(r=>`<tr><td>${esc(r.screened_on)}</td><td>${esc(r.display_name||'ไม่ระบุชื่อ')}</td><td>${esc(r.house_no||r.hcode||'—')}</td><td class="${healthClass(r.severity)}">${esc(r.ncd_status)}</td></tr>`).join('')||'<tr><td colspan="4">ยังไม่มีผลคัดกรองในขอบเขตของคุณ</td></tr>';
}
function selectHealthPerson(index){
  const p=healthPeople[index]; if(!p)return; selectedHealthPerson=p;
  $('#ncd-person-summary').innerHTML=`<strong>${esc(p.display_name)}</strong> · ${esc(p.age_years??'—')} ปี · ${esc(p.gender)}<br>บ้าน ${esc(p.house_no||p.hcode)} · ${esc(p.community||'—')}<br>${p.known_ncd?`พบประวัติ ${p.has_ht?'HT ':''}${p.has_dm?'DM':''} ใน JHCIS`:'ยังไม่พบ DM/HT ใน personchronic'}`;
  const card=$('#ncd-screen-card'); card.hidden=!(Number(p.age_years)>=18); if(card.hidden){return;}
  const form=$('#ncd-form'); form.reset(); form.elements.screened_on.value=localDate(); form.dataset.requestId=requestId(); $('#ncd-result').hidden=true; $('#ncd-error').textContent=''; card.scrollIntoView({behavior:'smooth',block:'start'});
}
async function saveHealthScreening(event){
  event.preventDefault(); const form=event.currentTarget,error=$('#ncd-error'),result=$('#ncd-result'),button=$('#ncd-submit');
  error.textContent=''; result.hidden=true; if(!selectedHealthPerson){error.textContent='กรุณาเลือกประชาชนจากรายการงาน';return;}
  const d=new FormData(form),p=selectedHealthPerson;
  const payload={p_source_pcucode:p.source_pcucode,p_source_pid:Number(p.source_pid),p_screened_on:d.get('screened_on')||null,p_weight_kg:formNumber(d.get('weight_kg')),p_height_cm:formNumber(d.get('height_cm')),p_waist_cm:formNumber(d.get('waist_cm')),p_sbp:formNumber(d.get('sbp')),p_dbp:formNumber(d.get('dbp')),p_glucose_mg_dl:formNumber(d.get('glucose_mg_dl')),p_glucose_type:d.get('glucose_type'),p_danger_symptoms:d.get('danger_symptoms')==='on',p_smoker:d.get('smoker')==='on',p_alcohol_risk:d.get('alcohol_risk')==='on',p_exercise_sufficient:d.get('exercise_sufficient')==='on',p_note:d.get('note')||'',p_request_id:form.dataset.requestId||requestId()};
  button.disabled=true;
  try{
    const {data:saved,error:saveError}=await supabase.rpc('save_health_ncd_screening',payload); if(saveError)throw saveError;
    result.innerHTML=`<strong>${esc(saved.ncd_status)}</strong><br>${esc(saved.bp_status)} · ${esc(saved.glucose_status)}<br>${esc(saved.advice||'')}`; result.hidden=false; form.dataset.requestId=requestId(); await Promise.all([loadHealthSummary(),loadHealthPeople()]); await loadHealthHistory();
  }catch(e){error.textContent=e.message;}finally{button.disabled=false;}
}
async function loadHealthModule(){
  healthLoaded=true; await loadHealthSummary(); await loadHealthPeople(); await loadHealthHistory();
  $('#ncd-form').onsubmit=saveHealthScreening; $('#ncd-close').onclick=()=>{$('#ncd-screen-card').hidden=true;selectedHealthPerson=null;};
  $('#health-refresh').onclick=async()=>{healthLoaded=false;await loadHealthModule();};
  $('#health-filter').onchange=loadHealthPeople; $('#health-stage').onchange=loadHealthPeople;
  $('#health-search').oninput=()=>{clearTimeout(healthSearchTimer);healthSearchTimer=setTimeout(()=>loadHealthPeople().catch(e=>$('#health-list-note').textContent=e.message),300);};
}

function normalizePhone(value){
  let d=String(value||'').replace(/\D/g,'');
  if(d.startsWith('66')&&d.length===11)d='0'+d.slice(2);
  if(d.length===9&&['6','8','9'].includes(d[0]))d='0'+d;
  return d.length===10&&d.startsWith('0')?d:'';
}
async function loginAlias(login){
  login=String(login||'').trim().toLowerCase();
  if(login.includes('@'))return login;
  const phone=normalizePhone(login);
  if(!phone)throw new Error('อสม. กรุณากรอกเบอร์โทรศัพท์ 10 หลัก');
  const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(phone));
  const hex=[...new Uint8Array(bytes)].map(b=>b.toString(16).padStart(2,'0')).join('');
  return `u-${hex.slice(0,48)}@phc-thc.local`;
}

function anchorLabel(status){ return ({confirmed:'ยืนยัน',community_review:'ตรวจชุมชน',outside_tambon:'นอกตำบล',missing:'ไม่มีพิกัด'})[status] || status || '—'; }

async function getProfile(userId){
  const { data, error } = await supabase.from('profiles').select('user_id,display_name,role,community,volunteer_pid,active,must_change_password').eq('user_id', userId).maybeSingle();
  if(error) throw error;
  return data;
}

async function loadPortal(session){
  const profile = await getProfile(session.user.id);
  currentProfile = profile;
  if(!profile || !profile.active){
    show($('#login-card'), false); show($('#portal'), false); show($('#blocked'), true); show($('#logout'), true); return;
  }
  if(profile.must_change_password){
    passwordChangeForced = true;
    $('#password-title').textContent = 'ต้องเปลี่ยนรหัสผ่านก่อนใช้งาน';
    $('#password-help').textContent = 'บัญชีนี้ใช้รหัสชั่วคราว กรุณากำหนดรหัสผ่านใหม่อย่างน้อย 12 ตัวอักษรก่อนเข้าถึงข้อมูล';
    show($('#login-card'), false); show($('#portal'), false); show($('#blocked'), false); show($('#password-card'), true); show($('#change-password'), false); show($('#logout'), true); show($('#cancel-password'), false); return;
  }
  const [{data: master, error: mErr}, {data: communities, error: cErr}, {data: workload, error: wErr}] = await Promise.all([
    supabase.from('communities').select('name,moo,active').eq('active', true).order('moo').order('name'),
    supabase.from('community_report_summary').select('*').order('community'),
    supabase.from('volunteer_workload').select('*').order('community').order('display_name')
  ]);
  if(mErr) throw mErr; if(cErr) throw cErr; if(wErr) throw wErr;
  let myHouses=[];
  if(profile.role==='user'){const {data,error}=await supabase.from('houses').select('house_no,moo,community,record_status,coordinate_status,review_required').order('house_no');if(error)throw error;myHouses=data||[];}

  const activeNames = new Set((master || []).map(x => x.name));
  const allSummary = communities || [];
  const rows = allSummary.filter(r => activeNames.has(r.community));
  const unknownRows = allSummary.filter(r => !activeNames.has(r.community));
  const unknownHouses = unknownRows.reduce((s,r)=>s+Number(r.houses||0),0);
  const vols = workload || [];
  const totals = rows.reduce((a,r)=>({
    houses:a.houses+Number(r.houses||0),
    assigned:a.assigned+Number(r.assigned_houses||0),
    review:a.review+Number(r.review_houses||0),
    outside:a.outside+Number(r.outside_tambon||0),
    missing:a.missing+Number(r.missing_coordinates||0)
  }),{houses:0,assigned:0,review:0,outside:0,missing:0});

  $('#welcome-name').textContent = profile.display_name || session.user.email || 'ภาพรวมพื้นที่';
  $('#scope-label').textContent = ['admin','staff'].includes(profile.role) ? 'ทุก 16 ชุมชนในระบบ' : 'บ้านและประชาชนในความรับผิดชอบของคุณ';
  $('#role-badge').textContent = roleLabel(profile.role);
  $('#community-count').textContent = `${num(rows.length)} ชุมชน`;
  $('#stats').innerHTML = [
    [totals.houses,'ครัวเรือน'],
    [totals.assigned,'มอบหมาย อสม.'],
    [vols.length,'อสม. ในขอบเขต'],
    [totals.review,'ต้องตรวจ'],
    [totals.outside,'นอก ต.พระบาท'],
    [totals.missing,'ไม่มีพิกัด'],
    [unknownHouses,'บ้านไม่ระบุ/นอก 16 ชุมชน']
  ].map(([v,l])=>`<article class="stat"><small>${esc(l)}</small><strong>${num(v)}</strong></article>`).join('');
  $('#community-body').innerHTML = rows.map(r=>`<tr><td><strong>${esc(r.community||'ไม่ระบุ')}</strong></td><td>${esc(r.moo||'—')}</td><td>${num(r.houses)}</td><td>${num(r.assigned_houses)}</td><td class="${Number(r.review_houses)>0?'warn':'good'}">${num(r.review_houses)}</td><td class="${Number(r.outside_tambon)>0?'bad':'good'}">${num(r.outside_tambon)}</td></tr>`).join('') || '<tr><td colspan="6">ไม่พบข้อมูลตามสิทธิ์</td></tr>';
  $('#volunteer-body').innerHTML = vols.map(v=>`<tr><td><strong>${esc(v.display_name||'ไม่ระบุ')}</strong></td><td>${esc(v.community||'—')}</td><td>${esc(anchorLabel(v.anchor_status))}</td><td>${num(v.house_count)}</td><td class="${Number(v.review_count)>0?'warn':'good'}">${num(v.review_count)}</td><td>${num(v.cross_community_count)}</td></tr>`).join('') || '<tr><td colspan="6">ไม่พบข้อมูล อสม. ตามสิทธิ์</td></tr>';
  $('#my-house-count').textContent=`${num(myHouses.length)} หลัง`;
  $('#my-house-body').innerHTML=myHouses.map(h=>`<tr><td><strong>${esc(h.house_no||'ไม่ระบุ')}</strong></td><td>${esc(h.moo||'—')}</td><td>${esc(h.community||'—')}</td><td>${esc(h.record_status||'—')}</td><td>${esc(h.coordinate_status||'—')}</td><td class="${h.review_required?'warn':'good'}">${h.review_required?'ต้องตรวจ':'ปกติ'}</td></tr>`).join('')||'<tr><td colspan="6">ยังไม่มีบ้านในความรับผิดชอบ</td></tr>';
  healthLoaded=false; selectedHealthPerson=null; healthPeople=[];
  configurePortalNav(profile.role);

  show($('#login-card'), false); show($('#blocked'), false); show($('#password-card'), false); show($('#portal'), true); show($('#change-password'), true); show($('#logout'), true);
}

async function refreshAuth(){
  const { data: { session } } = await supabase.auth.getSession();
  if(!session){ show($('#login-card'), true); show($('#portal'), false); show($('#blocked'), false); show($('#password-card'), false); show($('#change-password'), false); show($('#logout'), false); return; }
  try{ await loadPortal(session); }
  catch(error){ show($('#portal'), false); show($('#blocked'), true); $('#blocked').innerHTML = `<p class="eyebrow">ACCESS ERROR</p><h2>ไม่สามารถอ่านข้อมูลได้</h2><p>${esc(error.message)}</p>`; show($('#logout'), true); }
}

$('#login-form').addEventListener('submit', async e => {
  e.preventDefault();
  $('#login-error').textContent = '';
  const f = new FormData(e.target);
  let email;
  try{ email = await loginAlias(f.get('login')); }
  catch(error){ $('#login-error').textContent = error.message; return; }
  const { error } = await supabase.auth.signInWithPassword({ email, password:f.get('password') });
  if(error){ $('#login-error').textContent = 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'; return; }
  e.target.reset(); await refreshAuth();
});

$('#change-password').addEventListener('click', ()=>{
  passwordChangeForced = false;
  $('#password-title').textContent = 'เปลี่ยนรหัสผ่าน';
  $('#password-help').textContent = currentProfile?.role==='user' ? 'กำหนด PIN ตัวเลข 6–12 หลัก' : 'กำหนดรหัสผ่านใหม่อย่างน้อย 12 ตัวอักษร';
  $('#password-error').textContent = '';
  show($('#portal'), false); show($('#password-card'), true); show($('#change-password'), false); show($('#cancel-password'), true);
});
$('#cancel-password').addEventListener('click', ()=>{ if(!passwordChangeForced) refreshAuth(); });
$('#password-form').addEventListener('submit', async e => {
  e.preventDefault();
  const f = new FormData(e.target), password = String(f.get('password') || ''), confirmPassword = String(f.get('confirm_password') || '');
  $('#password-error').textContent = '';
  if(currentProfile?.role==='user'){ if(!/^\d{6,12}$/.test(password)){ $('#password-error').textContent='PIN ต้องเป็นตัวเลข 6–12 หลัก'; return; } } else if(password.length < 12){ $('#password-error').textContent='รหัสผ่านต้องมีอย่างน้อย 12 ตัวอักษร'; return; }
  if(password !== confirmPassword){ $('#password-error').textContent = 'ยืนยันรหัสผ่านไม่ตรงกัน'; return; }
  const { error } = await supabase.auth.updateUser({ password });
  if(error){ $('#password-error').textContent = error.message; return; }
  const { error: rpcError } = await supabase.rpc('complete_password_change');
  if(rpcError){ $('#password-error').textContent = rpcError.message; return; }
  e.target.reset(); passwordChangeForced = false; await refreshAuth();
});

$('#logout').addEventListener('click', async ()=>{ await supabase.auth.signOut(); await refreshAuth(); });
supabase.auth.onAuthStateChange(()=>refreshAuth());
refreshAuth();
