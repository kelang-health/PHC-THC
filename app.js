import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js?v=1.8.48';
import { evaluateMental2Q, mental2QLabel } from './health-2q.mjs?v=1.8.28';

const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});
const $ = s => document.querySelector(s);
const esc = v => String(v ?? '').replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const num = v => Number(v || 0).toLocaleString('th-TH');
let currentProfile = null;
let portalView = 'overview';
let healthPeople = [];
let selectedHealthPerson = null;
let healthLoaded = false;
let healthSearchTimer = null;
let passwordPanelOpen = false;
let authRequestId = 0;
let authView = 'login';
let renderedPortalUserId = null;
let healthFeedbackModel = null;
let portalCommunityRows = [];
let portalVolunteerRows = [];
let communityRequestId = 0;
let healthCommunityFocus = '';
let healthActiveViewName = 'health_person_worklist_active_v1847';
const PORTAL_NAV_STORAGE = 'phc.portal.nav-collapsed';

function show(el, visible=true){ if(el) el.hidden = !visible; }
function renderAuthView(view){
  authView = view;
  document.documentElement.dataset.authView = view;
  show($('#login-card'), view === 'login');
  show($('#portal'), view === 'portal');
  show($('#blocked'), view === 'blocked');
  show($('#password-card'), view === 'password');
  show($('#change-password'), view === 'portal');
  show($('#logout'), view === 'portal' || view === 'blocked');
}
function renderLoggedOut(){
  authRequestId += 1;
  currentProfile=null; passwordPanelOpen=false; renderedPortalUserId=null; healthFeedbackModel=null; portalView='overview';
  renderAuthView('login');
}
function roleLabel(role){ return ({admin:'เจ้าหน้าที่',staff:'ประธาน อสม.',user:'อสม.'})[role] || role || 'ไม่ระบุ'; }
function setPortalNavCollapsed(collapsed,persist=true){
  const portal=$('#portal'),toggle=$('#portal-nav-toggle'),isCollapsed=Boolean(collapsed);if(!portal||!toggle)return;
  portal.classList.toggle('nav-collapsed',isCollapsed);toggle.setAttribute('aria-expanded',String(!isCollapsed));toggle.setAttribute('aria-label',isCollapsed?'ขยายเมนู':'ย่อเมนู');
  const text=toggle.querySelector('.portal-nav-toggle-text');if(text)text.textContent=isCollapsed?'ขยายเมนู':'ย่อเมนู';
  if(persist){try{localStorage.setItem(PORTAL_NAV_STORAGE,isCollapsed?'1':'0');}catch{}}
}
function restorePortalNavPreference(){let collapsed=false;try{collapsed=localStorage.getItem(PORTAL_NAV_STORAGE)==='1';}catch{}setPortalNavCollapsed(collapsed,false);}
function setPortalView(next){const allowed=[...document.querySelectorAll('#portal-nav [data-portal-view]')].filter(b=>!b.hidden).map(b=>b.dataset.portalView);portalView=allowed.includes(next)?next:'overview';document.querySelectorAll('[data-portal-panel]').forEach(x=>x.hidden=x.dataset.portalPanel!==portalView);document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>b.classList.toggle('active',b.dataset.portalView===portalView));if(window.innerWidth<=900)window.scrollTo({top:0,behavior:'smooth'});}
function configurePortalNav(role){
  const labels={admin:{communities:'ชุมชนทั้งหมด',volunteers:'ทะเบียน อสม.'},staff:{communities:'ชุมชนที่ดูแล',volunteers:'อสม. ในชุมชน'},user:{communities:'ชุมชนของฉัน',houses:'บ้านของฉัน'}};
  document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>{
    b.hidden=!(b.dataset.roles||'').split(/\s+/).includes(role);
    const label=b.querySelector('.portal-nav-label'),roleLabelText=labels[role]?.[b.dataset.portalView];if(label&&roleLabelText)label.textContent=roleLabelText;
    b.onclick=async()=>{setPortalView(b.dataset.portalView);if(b.dataset.portalView==='health'&&!healthLoaded){try{await loadHealthModule();}catch(e){$('#health-person-body').innerHTML=`<tr><td colspan="5">${esc(e.message)}</td></tr>`;}}};
  });
  // Preserve the panel the user is currently working in during session refreshes.
  // setPortalView() falls back to overview only when that panel is unavailable.
  setPortalView(portalView);
}
function configureHealthAdminUI(role){
  const adminIntro=$('#health-admin-intro');
  if(adminIntro)adminIntro.hidden=role!=='admin';
}

function localDate(){return new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Bangkok'});}
function formNumber(value){const n=Number(value);return Number.isFinite(n)?n:null;}
function requestId(){return crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;}

function personKey(p){return `${p.source_pcucode}:${p.source_pid}`;}

function healthClass(severity){return severity==='urgent'||severity==='alert'?'bad':severity==='risk'?'warn':severity==='normal'?'good':'';}
function formatHealthValue(value,suffix=''){return value===null||value===undefined||value===''?'—':`${value}${suffix}`;}
function healthDateLabel(value){if(!value)return 'ยังไม่มีประวัติคัดกรอง';try{return new Date(value+'T00:00:00').toLocaleDateString('th-TH',{year:'numeric',month:'short',day:'numeric'});}catch{return value;}}
async function loadHealthSummary(){
  const [{data,error},{data:q2Data,error:q2Error}]=await Promise.all([
    supabase.from('health_work_summary').select('*').maybeSingle(),
    supabase.from('health_2q_summary').select('*').maybeSingle()
  ]);
  if(error)throw error;if(q2Error)throw q2Error;const x=data||{},q2=q2Data||{};
  $('#health-stats').innerHTML=[
    [x.people,'ประชาชนในสิทธิ์'],[x.ncd_targets,'เป้าหมาย NCD 35+'],[x.ncd_screened_current_fy,'คัดกรองแล้วปีงบฯ'],[x.ncd_due,'คงเหลือ'],[x.known_ncd,'DM/HT เดิม']
  ].map(([v,l])=>`<article class="stat"><small>${esc(l)}</small><strong>${num(v)}</strong></article>`).join('');
  $('#mental-2q-stats').innerHTML=[
    [q2.mental_2q_assessed,'ประเมินแล้ว','good'],
    [q2.mental_2q_not_assessed,'ไม่ได้ประเมิน',''],
    [q2.mental_2q_incomplete,'ข้อมูลไม่ครบ','warn']
  ].map(([v,l,c])=>`<article class="stat ${c}"><small>${esc(l)}</small><strong>${num(v)}</strong></article>`).join('');
  $('#mental-2q-note').textContent=`สรุปจากผล NCD ล่าสุด ${num(q2.latest_ncd_screenings)} ราย · พบคำตอบบวก ${num(q2.mental_2q_positive)} ราย`;
  $('#life-stage-stats').innerHTML=[['เด็กปฐมวัย',x.early_child],['เด็กวัยเรียน',x.school_age],['วัยรุ่นและเยาวชน',x.youth],['วัยทำงาน',x.working_age],['ผู้สูงอายุ',x.older_people]].map(([l,v])=>`<div class="life-chip"><span>${esc(l)}</span><strong>${num(v)}</strong></div>`).join('');
}
function syncHealthTargetButtons(){
  const filter=$('#health-filter').value;
  $('#health-view-linked-targets').classList.toggle('active',filter==='due');
  $('#health-view-all-targets').classList.toggle('active',filter==='targets');
}
async function setHealthTargetFilter(filter){
  healthCommunityFocus='';
  const focus=$('#health-community-focus');if(focus)focus.hidden=true;
  $('#health-filter').value=filter;syncHealthTargetButtons();await loadHealthPeople();
}
async function loadHealthPeople(){
  const filter=$('#health-filter').value;syncHealthTargetButtons();const stage=$('#health-stage').value, raw=$('#health-search').value.trim();
  let q=supabase.from(healthActiveViewName).select('source_pcucode,source_pid,hcode,house_no,moo,community,display_name,gender,birth_date,age_years,life_stage,has_ht,has_dm,has_cvd,cvd_population_eligible,known_ncd,ncd_target,latest_screened_on,latest_ncd_status,latest_severity,screened_current_fy,previous_screened_on,previous_weight_kg,previous_height_cm,previous_waist_cm,previous_sbp,previous_dbp,previous_glucose_mg_dl,previous_bmi,previous_source,previous_smoking,previous_alcohol,previous_exercise').order('community').order('hcode').order('display_name').limit(300);
  if(healthCommunityFocus)q=q.eq('community',healthCommunityFocus);
  if(filter==='due')q=q.eq('ncd_target',true).eq('screened_current_fy',false);
  else if(filter==='targets')q=q.eq('ncd_target',true);
  else if(filter==='known')q=q.eq('known_ncd',true);
  if(stage)q=q.eq('life_stage',stage);
  const term=raw.replace(/[%_,()]/g,'').slice(0,60); if(term)q=q.ilike('display_name',`%${term}%`);
  const {data,error}=await q;if(error&&healthActiveViewName==='health_person_worklist_active_v1847'){healthActiveViewName='health_person_worklist_active_v1841';return loadHealthPeople();}if(error&&healthActiveViewName==='health_person_worklist_active_v1841'){healthActiveViewName='health_person_worklist';return loadHealthPeople();}if(error)throw error;healthPeople=data||[];
  $('#health-person-body').innerHTML=healthPeople.map((p,i)=>`<tr><td><button type="button" class="health-person-name" data-health-person="${i}">${esc(p.display_name)}</button><small>${p.known_ncd?`โรคเดิม: ${p.has_ht?'HT ':''}${p.has_dm?'DM':''}`:'ยังไม่พบ DM/HT ใน personchronic'}</small></td><td>${esc(p.age_years??'—')} ปี<small>${esc(p.life_stage||'—')}</small></td><td>บ้าน ${esc(p.house_no||p.hcode)}<small>หมู่ ${esc(p.moo||'—')} · ${esc(p.community||'—')}</small></td><td class="${healthClass(p.latest_severity)}">${esc(p.latest_ncd_status||'ยังไม่มีผล')}<small>${p.latest_screened_on?esc(healthDateLabel(p.latest_screened_on)):''}</small></td><td><button type="button" class="row-open" data-health-person="${i}">${Number(p.age_years)>=18?'เปิดคัดกรอง':'ดูข้อมูล'}</button></td></tr>`).join('')||'<tr><td colspan="5">ไม่พบประชาชนตามตัวกรอง</td></tr>';
  $('#health-list-note').textContent=healthPeople.length>=300?'แสดงสูงสุด 300 ราย กรุณาใช้ค้นหาชื่อหรือตัวกรองเพื่อเจาะจงรายการ':'';
  document.querySelectorAll('[data-health-person]').forEach(b=>b.onclick=()=>selectHealthPerson(Number(b.dataset.healthPerson)));
}
async function loadHealthHistory(){
  const {data,error}=await supabase.from('health_ncd_history').select('screened_on,display_name,house_no,hcode,ncd_status,severity,source_label,quality_valid,quality_issues,legacy_cvd_risk,recorded_at,mental_2q_status,mental_2q_result,cvd_risk_percent,cvd_risk_level,cvd_risk_eligible,cvd_risk_reason,cvd_model_version').order('screened_on',{ascending:false}).order('recorded_at',{ascending:false}).limit(50);
  if(error)throw error;
  $('#ncd-history-body').innerHTML=(data||[]).map(r=>{
    const quality=r.quality_valid===false?'<small class="bad">ข้อมูลเดิมต้องตรวจสอบ</small>':'';
    const source=`<span class="source-pill">${esc(r.source_label||'อสม. พลัส')}</span>${quality}`;
    const cvd=r.cvd_risk_eligible?`<small>Thai CV Risk: ${esc(Number(r.cvd_risk_percent).toFixed(1))}% · ${esc(thaiCvLevelLabel(r.cvd_risk_level))}</small>`:(r.legacy_cvd_risk?`<small>CVD เดิม: ${esc(r.legacy_cvd_risk)} · ใช้อ้างอิงย้อนหลังเท่านั้น</small>`:'');
    const mental=`<span class="mental-2q-status ${r.mental_2q_status||'not_assessed'}">${esc(mental2QLabel(r.mental_2q_status,r.mental_2q_result))}</span>`;
    return `<tr><td>${esc(healthDateLabel(r.screened_on))}</td><td>${esc(r.display_name||'ไม่ระบุชื่อ')}</td><td>${esc(r.house_no||r.hcode||'—')}</td><td>${source}</td><td class="${healthClass(r.severity)}">${esc(r.ncd_status||'—')}${cvd}</td><td>${mental}</td></tr>`;
  }).join('')||'<tr><td colspan="6">ยังไม่มีผลคัดกรองในขอบเขตของคุณ</td></tr>';
}
function fmtPrevious(value,unit=''){return value===null||value===undefined||value===''?'—':`${value}${unit?` ${unit}`:''}`;}
function setPreviousText(id,value){const el=$(id);if(el)el.textContent=value;}
function renderPreviousPanel(p){
  const panel=$('#ncd-previous-panel'),has=Boolean(p.previous_screened_on);
  panel.hidden=!has;
  if(!has)return;
  setPreviousText('#ncd-previous-date',healthDateLabel(p.previous_screened_on));
  setPreviousText('#ncd-previous-source',p.previous_source||'ประวัติเดิม');
  setPreviousText('#prev-weight',fmtPrevious(p.previous_weight_kg,'กก.'));
  setPreviousText('#prev-height',fmtPrevious(p.previous_height_cm,'ซม.'));
  setPreviousText('#prev-waist',fmtPrevious(p.previous_waist_cm,'ซม.'));
  setPreviousText('#prev-bp',(p.previous_sbp&&p.previous_dbp)?`${p.previous_sbp}/${p.previous_dbp}`:'—');
  setPreviousText('#prev-glucose',fmtPrevious(p.previous_glucose_mg_dl,'mg/dL'));
  setPreviousText('#prev-bmi',fmtPrevious(p.previous_bmi,''));
  const b=[p.previous_smoking&&`สูบบุหรี่: ${p.previous_smoking}`,p.previous_alcohol&&`แอลกอฮอล์: ${p.previous_alcohol}`,p.previous_exercise&&`ออกกำลังกาย: ${p.previous_exercise}`].filter(Boolean);
  const be=$('#ncd-previous-behavior');be.hidden=!b.length;be.textContent=b.join(' · ');
}
function previousHint(value,unit=''){return value===null||value===undefined||value===''?'':'ครั้งก่อน '+value+(unit?' '+unit:'');}
function syncBehaviorPanels(form){
  const smoke=form.querySelector('[name="smoking_state"]:checked')?.value;
  const alc=form.querySelector('[name="alcohol_state"]:checked')?.value;
  const sw=$('#smoking-frequency-wrap'),aw=$('#alcohol-frequency-wrap');
  sw.hidden=smoke!=='yes';aw.hidden=alc!=='yes';
  const syncFrequency=(name,enabled)=>{const choices=[...form.querySelectorAll(`[name="${name}"]`)];choices.forEach((choice,index)=>{choice.required=enabled&&index===0;if(!enabled)choice.checked=false;});};
  syncFrequency('smoking_frequency',smoke==='yes');syncFrequency('alcohol_frequency',alc==='yes');
}
function renderNcdPreview(){
  const form=$('#ncd-form');if(!form||!selectedHealthPerson)return;
  const n=name=>Number(form.elements[name]?.value||0),w=n('weight_kg'),h=n('height_cm'),waist=n('waist_cm'),sbp=n('sbp'),dbp=n('dbp'),g=n('glucose_mg_dl'),gt=form.elements.glucose_type.value;
  $('#preview-bmi').textContent=w>0&&h>0?(w/((h/100)**2)).toFixed(1):'—';
  $('#preview-bp').textContent=!sbp||!dbp?'รอกรอก':(sbp>=180||dbp>=120?'สูงมาก':sbp>=140||dbp>=90?'สูง':sbp>=120||dbp>=80?'เริ่มสูง':sbp<90||dbp<60?'ต่ำ':'ช่วงปกติ');
  $('#preview-glucose').textContent=!g?'รอกรอก':g<70?'ต่ำ':gt==='fasting'?(g>=126?'สูง':g>=100?'เริ่มสูง':'ช่วงปกติ'):gt==='random'?(g>=200?'สูง':'ยังสรุปไม่ได้'):'เลือกสถานะก่อนตรวจ';
  const limit=selectedHealthPerson.gender==='ชาย'?90:selectedHealthPerson.gender==='หญิง'?80:null;
  $('#preview-waist').textContent=!waist?'รอกรอก':limit===null?'ตรวจข้อมูลเพศ':waist>=limit?'เกินเกณฑ์':'ไม่เกินเกณฑ์';
  renderThaiCvPreview();
}
function renderMental2QPreview(){
  const form=$('#ncd-form');if(!form)return;
  const state=evaluateMental2Q(
    form.querySelector('[name="mental_2q_q1"]:checked')?.value,
    form.querySelector('[name="mental_2q_q2"]:checked')?.value
  );
  const output=$('#mental-2q-preview');
  output.dataset.status=state.status;
  output.textContent=mental2QLabel(state.status,state.result);
}

const THAI_CV_MODEL='thai-ascvd-score5-nolab-moph-2026-09';
function thaiCvLevelLabel(level){return ({low:'ต่ำ',moderate:'ปานกลาง',high:'สูง',very_high:'สูงมาก',dangerous:'สูงอันตราย'})[level]||'—';}
function thaiCvReasonLabel(reason){return ({assessed:'ประเมินอัตโนมัติ',population_not_eligible:'ไม่อยู่ในกลุ่มประชากรที่สูตรกำหนด',age_outside_35_70:'ใช้สำหรับอายุ 35–70 ปี',known_cvd_excluded:'มีประวัติโรคหัวใจ/หลอดเลือด — ไม่ใช้คะแนนนี้',gender_unavailable:'ข้อมูลเพศไม่ครบ',required_data_incomplete:'ข้อมูลคำนวณไม่ครบ'})[reason]||'ไม่ประเมิน';}
function calculateThaiCvPreview(person,form){
  const age=Number(person?.age_years),sbp=Number(form?.elements?.sbp?.value),waist=Number(form?.elements?.waist_cm?.value),height=Number(form?.elements?.height_cm?.value);
  if(!person?.cvd_population_eligible)return {eligible:false,reason:'population_not_eligible'};
  if(!Number.isFinite(age)||age<35||age>70)return {eligible:false,reason:'age_outside_35_70'};
  if(person?.has_cvd)return {eligible:false,reason:'known_cvd_excluded'};
  if(!['ชาย','หญิง'].includes(person?.gender))return {eligible:false,reason:'gender_unavailable'};
  const smoke=form?.querySelector('[name="smoking_state"]:checked')?.value;
  if(!sbp||!waist||!height||!smoke)return {eligible:false,reason:'required_data_incomplete'};
  const sex=person.gender==='ชาย'?1:0,dm=person.has_dm?1:0,smoker=smoke==='yes'?1:0;
  const score=(0.079*age)+(0.128*sex)+(0.019350987*sbp)+(0.58454*dm)+(3.512566*(waist/height))+(0.459*smoker);
  const risk=Math.max(0,Math.min(100,(1-Math.pow(0.978296,Math.exp(score-7.720484)))*100));
  const level=risk<10?'low':risk<20?'moderate':risk<30?'high':risk<40?'very_high':'dangerous';
  return {eligible:true,riskPercent:risk,level,reason:'assessed',modelVersion:THAI_CV_MODEL};
}
function renderThaiCvPreview(){
  const el=$('#preview-cvd'),form=$('#ncd-form');if(!el||!form||!selectedHealthPerson)return;
  const cvd=calculateThaiCvPreview(selectedHealthPerson,form);
  el.textContent=cvd.eligible?`${cvd.riskPercent.toFixed(1)}% ${thaiCvLevelLabel(cvd.level)}`:thaiCvReasonLabel(cvd.reason);
  el.className=cvd.eligible?(cvd.riskPercent>=20?'bad':cvd.riskPercent>=10?'warn':'good'):'';
}
function savedThaiCvLabel(saved){return saved?.cvd_risk_eligible?`${Number(saved.cvd_risk_percent).toFixed(1)}% ${thaiCvLevelLabel(saved.cvd_risk_level)}`:thaiCvReasonLabel(saved?.cvd_risk_reason);}

function feedbackBmiLabel(value){
  if(!Number.isFinite(value))return 'รอข้อมูล';
  if(value<18.5)return 'ต่ำกว่าเกณฑ์';
  if(value<23)return 'ช่วงคัดกรองปกติ';
  if(value<25)return 'เริ่มสูง';
  if(value<30)return 'สูง';
  return 'สูงมาก';
}
function feedbackWaistLabel(value,gender){
  const limit=gender==='ชาย'?90:gender==='หญิง'?80:null;
  if(!Number.isFinite(value)||limit===null)return 'ตรวจข้อมูลเพศ';
  return value>=limit?`เกินเกณฑ์ ${limit} ซม.`:`ไม่เกินเกณฑ์ ${limit} ซม.`;
}
function feedbackDelta(label,current,previous,unit='',digits=0){
  const now=Number(current),before=Number(previous);
  if(!Number.isFinite(now)||!Number.isFinite(before))return null;
  const delta=now-before,threshold=digits?0.05:0.5;
  if(Math.abs(delta)<threshold)return null;
  const shown=(digits?delta.toFixed(digits):Math.round(delta));
  return `${label} ${delta>0?'+':''}${shown}${unit?` ${unit}`:''}`;
}
function feedbackActions(saved,mental){
  const actions=[];
  if(saved.severity==='urgent')actions.push('ประสานเจ้าหน้าที่สาธารณสุขทันที และตรวจซ้ำตามแนวทางหน่วยบริการ');
  else if(saved.severity==='alert')actions.push('ประสานเจ้าหน้าที่เพื่อตรวจยืนยันและกำหนดการติดตาม');
  else if(saved.severity==='risk')actions.push('ปรับพฤติกรรมสุขภาพและติดตามค่าตามรอบที่หน่วยบริการกำหนด');
  else if(saved.severity==='normal')actions.push('รักษาพฤติกรรมสุขภาพที่ดีและตรวจติดตามตามรอบ');
  else actions.push('ทบทวนข้อมูลกับเจ้าหน้าที่ก่อนสรุปผล');
  if(saved.cvd_risk_eligible && Number(saved.cvd_risk_percent)>=20) actions.push('Thai CV Risk ตั้งแต่ 20% ขึ้นไป ควรให้เจ้าหน้าที่ประเมินปัจจัยเสี่ยงร่วมและวางแผนติดตาม');
  if((saved.mental_2q_status??mental.status)==='assessed' && (saved.mental_2q_result??mental.result)===true) actions.push('2Q พบคำตอบบวก ควรประสานเจ้าหน้าที่เพื่อประเมินสุขภาพจิตต่อ');
  if(saved.advice && !actions.some(x=>saved.advice.includes(x))) actions.push(String(saved.advice).replace(/\s+/g,' ').trim());
  return actions.filter(Boolean).slice(0,3);
}
function buildHealthFeedbackModel(saved,mental,person,formData){
  const w=Number(saved.weight_kg??formData.get('weight_kg')),h=Number(saved.height_cm??formData.get('height_cm'));
  const bmi=Number(saved.bmi??(w>0&&h>0?w/((h/100)**2):NaN));
  const waist=Number(saved.waist_cm??formData.get('waist_cm'));
  const sbp=Number(saved.sbp??formData.get('sbp')),dbp=Number(saved.dbp??formData.get('dbp'));
  const glucose=Number(saved.glucose_mg_dl??formData.get('glucose_mg_dl'));
  const mentalStatus=saved.mental_2q_status??mental.status,mentalResult=saved.mental_2q_result??mental.result;
  const screenedOn=saved.screened_on||formData.get('screened_on')||localDate();
  const metrics=[
    {label:'BMI',value:Number.isFinite(bmi)?bmi.toFixed(1):'—',detail:feedbackBmiLabel(bmi)},
    {label:'รอบเอว',value:Number.isFinite(waist)?`${waist.toFixed(1)} ซม.`:'—',detail:feedbackWaistLabel(waist,person.gender)},
    {label:'ความดัน',value:Number.isFinite(sbp)&&Number.isFinite(dbp)?`${sbp}/${dbp}`:'—',detail:saved.bp_status||'รอผล'},
    {label:'น้ำตาล',value:Number.isFinite(glucose)?`${glucose} mg/dL`:'—',detail:saved.glucose_status||'รอผล'},
    {label:'Thai CV Risk',value:saved.cvd_risk_eligible?`${Number(saved.cvd_risk_percent).toFixed(1)}%`:'ไม่ประเมิน',detail:saved.cvd_risk_eligible?thaiCvLevelLabel(saved.cvd_risk_level):thaiCvReasonLabel(saved.cvd_risk_reason)},
    {label:'สุขภาพจิต 2Q',value:mental2QLabel(mentalStatus,mentalResult),detail:mentalStatus==='assessed'?'ประเมินครบ 2 ข้อ':'ไม่ใช้สรุปแทนการประเมิน'}
  ];
  const changes=[
    feedbackDelta('น้ำหนัก',w,person.previous_weight_kg,'กก.',1),
    feedbackDelta('รอบเอว',waist,person.previous_waist_cm,'ซม.',1),
    feedbackDelta('SYS',sbp,person.previous_sbp,'',0),
    feedbackDelta('น้ำตาล',glucose,person.previous_glucose_mg_dl,'mg/dL',0)
  ].filter(Boolean);
  return {
    personLabel:`${person.display_name} · ${person.age_years??'—'} ปี · ${person.gender||'—'}`,
    dateLabel:healthDateLabel(screenedOn),
    status:saved.ncd_status||'ผลคัดกรอง',severity:saved.severity||'incomplete',metrics,changes,
    actions:feedbackActions(saved,mental)
  };
}
function renderHealthFeedbackCard(model){
  healthFeedbackModel=model;
  const card=$('#health-feedback-card');if(!card)return;
  $('#health-feedback-person').textContent=`${model.personLabel} · ${model.dateLabel}`;
  const status=$('#health-feedback-status');status.textContent=model.status;status.className=`health-feedback-status ${healthClass(model.severity)}`;
  $('#health-feedback-metrics').innerHTML=model.metrics.map(m=>`<article><small>${esc(m.label)}</small><strong>${esc(m.value)}</strong><span>${esc(m.detail)}</span></article>`).join('');
  const changes=$('#health-feedback-changes');changes.hidden=!model.changes.length;$('#health-feedback-change-list').innerHTML=model.changes.map(x=>`<span>${esc(x)}</span>`).join('');
  $('#health-feedback-advice-list').innerHTML=model.actions.map(x=>`<li>${esc(x)}</li>`).join('');
  card.hidden=false;
}
function viewHealthFeedback(){
  const card=$('#health-feedback-card');if(!card||card.hidden)return;
  card.scrollIntoView({behavior:'smooth',block:'start'});
}
function closeHealthFeedbackCard(){const card=$('#health-feedback-card');if(card)card.hidden=true;}
function wrapCanvasText(ctx,text,maxWidth){
  const words=String(text||'').split(/\s+/).filter(Boolean),lines=[];let line='';
  for(const word of words){const test=line?`${line} ${word}`:word;if(ctx.measureText(test).width<=maxWidth){line=test;continue;}if(line)lines.push(line);line=word;}
  if(line)lines.push(line);return lines.length?lines:[''];
}
function createHealthFeedbackCanvas(model){
  const canvas=document.createElement('canvas');canvas.width=1080;canvas.height=1700;const ctx=canvas.getContext('2d');
  ctx.fillStyle='#ffffff';ctx.fillRect(0,0,canvas.width,canvas.height);
  ctx.fillStyle='#126f61';ctx.fillRect(0,0,canvas.width,22);
  ctx.fillStyle='#17312d';ctx.font='800 54px system-ui, sans-serif';ctx.fillText('บัตรสรุปสุขภาพ',70,105);
  ctx.fillStyle='#667a74';ctx.font='500 30px system-ui, sans-serif';ctx.fillText(`วันที่ตรวจ ${model.dateLabel}`,70,155);
  ctx.fillStyle=model.severity==='urgent'||model.severity==='alert'?'#a53f32':model.severity==='risk'?'#946113':'#176557';ctx.font='800 34px system-ui, sans-serif';
  wrapCanvasText(ctx,model.status,930).slice(0,2).forEach((line,i)=>ctx.fillText(line,70,220+i*42));
  let y=310;
  for(const metric of model.metrics){
    ctx.fillStyle='#f3f7f5';ctx.fillRect(60,y-48,960,102);
    ctx.fillStyle='#526b65';ctx.font='700 29px system-ui, sans-serif';ctx.fillText(metric.label,85,y);
    ctx.fillStyle='#17312d';ctx.font='800 34px system-ui, sans-serif';ctx.fillText(metric.value,350,y);
    ctx.fillStyle='#526b65';ctx.font='500 25px system-ui, sans-serif';
    wrapCanvasText(ctx,metric.detail,410).slice(0,2).forEach((line,i)=>ctx.fillText(line,585,y-5+i*31));
    y+=120;
  }
  if(model.changes.length){ctx.fillStyle='#17312d';ctx.font='800 29px system-ui, sans-serif';ctx.fillText('เปลี่ยนแปลงจากครั้งก่อน',70,y+8);y+=50;ctx.fillStyle='#526b65';ctx.font='500 25px system-ui, sans-serif';wrapCanvasText(ctx,model.changes.join(' · '),930).slice(0,2).forEach((line,i)=>ctx.fillText(line,70,y+i*32));y+=78;}
  ctx.fillStyle='#17312d';ctx.font='800 29px system-ui, sans-serif';ctx.fillText('สิ่งที่ควรทำต่อ',70,y);y+=42;ctx.fillStyle='#405e57';ctx.font='500 25px system-ui, sans-serif';
  for(const action of model.actions.slice(0,3)){const lines=wrapCanvasText(ctx,`• ${action}`,900).slice(0,2);for(const line of lines){ctx.fillText(line,85,y);y+=32;}y+=9;}
  ctx.fillStyle='#75857f';ctx.font='500 22px system-ui, sans-serif';ctx.fillText('ผลนี้เป็นการคัดกรองเบื้องต้น ไม่ใช่การวินิจฉัยโรค',70,1610);ctx.fillText('ภาพนี้ไม่แสดงชื่อ PID, HN, บ้าน หรือข้อมูลติดต่อ',70,1650);
  return canvas;
}
async function shareHealthFeedback(){
  if(!healthFeedbackModel)return;const button=$('#health-feedback-share');if(button)button.disabled=true;$('#ncd-error').textContent='';
  try{
    const canvas=createHealthFeedbackCanvas(healthFeedbackModel);const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/png',0.94));if(!blob)throw new Error('สร้างภาพไม่สำเร็จ');
    const file=new File([blob],`health-feedback-${Date.now()}.png`,{type:'image/png'});
    if(navigator.share&&navigator.canShare?.({files:[file]})){await navigator.share({files:[file],title:'บัตรสรุปสุขภาพ'});}
    else{const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=file.name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1500);}
  }catch(error){if(error?.name!=='AbortError')$('#ncd-error').textContent=`ไม่สามารถแชร์ภาพได้: ${error.message}`;}
  finally{if(button)button.disabled=false;}
}

function setMeasurementValue(form,name,value){
  const input=form.elements[name],range=form.querySelector(`[data-range-for="${name}"]`);if(!input)return;
  const min=Number(input.min),max=Number(input.max),step=Number(input.step||1),n=Math.min(max,Math.max(min,Number(value)));
  if(!Number.isFinite(n))return;
  const decimals=(String(step).split('.')[1]||'').length;input.value=n.toFixed(decimals);
  if(range)range.value=String(Math.min(Number(range.max),Math.max(Number(range.min),n)));
  renderNcdPreview();
}
function bindMeasurementControls(form){
  if(form.dataset.measurementsBound==='1')return;form.dataset.measurementsBound='1';
  form.querySelectorAll('[data-range-for]').forEach(range=>range.addEventListener('input',()=>setMeasurementValue(form,range.dataset.rangeFor,range.value)));
  form.querySelectorAll('[data-step-for]').forEach(button=>button.addEventListener('click',()=>{
    const input=form.elements[button.dataset.stepFor],delta=Number(button.dataset.delta),start=Number(input.value||form.querySelector(`[data-range-for="${button.dataset.stepFor}"]`)?.value||input.min);
    setMeasurementValue(form,button.dataset.stepFor,start+delta);
    input.focus({preventScroll:true});
  }));
  ['weight_kg','height_cm','waist_cm','sbp','dbp','glucose_mg_dl'].forEach(name=>form.elements[name].addEventListener('input',()=>{
    const n=Number(form.elements[name].value),range=form.querySelector(`[data-range-for="${name}"]`);if(range&&Number.isFinite(n)&&form.elements[name].value!=='')range.value=String(Math.min(Number(range.max),Math.max(Number(range.min),n)));
  }));
}
function setActiveNcdSection(targetId,scroll=false){
  document.querySelectorAll('[data-ncd-section-target]').forEach(button=>button.classList.toggle('active',button.dataset.ncdSectionTarget===targetId));
  const target=document.getElementById(targetId);if(scroll&&target)target.scrollIntoView({behavior:'smooth',block:'start'});
}
function bindNcdSectionNav(){
  const nav=$('#ncd-section-nav');if(!nav||nav.dataset.bound==='1')return;nav.dataset.bound='1';
  nav.querySelectorAll('[data-ncd-section-target]').forEach(button=>button.onclick=()=>setActiveNcdSection(button.dataset.ncdSectionTarget,true));
}

function selectHealthPerson(index){
  const p=healthPeople[index]; if(!p)return; selectedHealthPerson=p;
  $('#ncd-person-summary').innerHTML=`<strong>${esc(p.display_name)}</strong><span>${esc(p.age_years??'—')} ปี · ${esc(p.gender)} · ${esc(p.community||'—')}</span>`;
  const conditions=[];if(p.has_ht)conditions.push('<span class="condition-badge disease">มีประวัติ HT</span>');if(p.has_dm)conditions.push('<span class="condition-badge disease">มีประวัติ DM</span>');if(!p.known_ncd)conditions.push('<span class="condition-badge clear">ยังไม่พบ DM/HT ใน JHCIS</span>');if(p.has_cvd)conditions.push('<span class="condition-badge disease">มีประวัติ CVD · ไม่ใช้ Thai CV Risk</span>');else if(p.cvd_population_eligible&&Number(p.age_years)>=35&&Number(p.age_years)<=70)conditions.push('<span class="condition-badge clear">Thai CV Risk คำนวณอัตโนมัติ</span>');$('#ncd-condition-badges').innerHTML=conditions.join('');
  const card=$('#ncd-screen-card'); card.hidden=!(Number(p.age_years)>=18); if(card.hidden){return;}
  const form=$('#ncd-form'); form.reset(); form.elements.screened_on.value=localDate(); form.dataset.requestId=requestId(); $('#ncd-result').hidden=true; healthFeedbackModel=null; closeHealthFeedbackCard(); closeNcdSaveConfirmation(false); $('#ncd-error').textContent=''; setActiveNcdSection('ncd-section-measure',false);
  renderPreviousPanel(p);
  form.elements.height_cm.value=p.previous_height_cm||'';
  setPreviousText('#hint-weight',previousHint(p.previous_weight_kg,'กก.'));setPreviousText('#hint-height',previousHint(p.previous_height_cm,'ซม.'));setPreviousText('#hint-waist',previousHint(p.previous_waist_cm,'ซม.'));setPreviousText('#hint-sbp',previousHint(p.previous_sbp));setPreviousText('#hint-dbp',previousHint(p.previous_dbp));setPreviousText('#hint-glucose',previousHint(p.previous_glucose_mg_dl,'mg/dL'));
  bindMeasurementControls(form);
  form.querySelectorAll('[data-range-for]').forEach(range=>{const input=form.elements[range.dataset.rangeFor];if(input?.value)range.value=String(Math.min(Number(range.max),Math.max(Number(range.min),Number(input.value))));});
  const previousBody=$('#ncd-use-previous-body'),hasPreviousBody=[p.previous_weight_kg,p.previous_height_cm,p.previous_waist_cm].some(v=>v!==null&&v!==undefined&&v!=='');
  previousBody.hidden=!hasPreviousBody;previousBody.onclick=()=>{[['weight_kg',p.previous_weight_kg],['height_cm',p.previous_height_cm],['waist_cm',p.previous_waist_cm]].forEach(([name,value])=>{if(value!==null&&value!==undefined&&value!=='')setMeasurementValue(form,name,value);});};
  syncBehaviorPanels(form);renderNcdPreview();renderMental2QPreview();
  form.querySelectorAll('input,select').forEach(el=>{el.oninput=()=>{renderNcdPreview();renderMental2QPreview();};el.onchange=()=>{renderNcdPreview();renderMental2QPreview();};});
  card.scrollIntoView({behavior:'smooth',block:'start'});
}
function closeNcdSaveConfirmation(restoreFocus=true){
  const dialog=$('#ncd-save-confirmation');if(!dialog)return;dialog.hidden=true;if(restoreFocus)$('#ncd-submit')?.focus();
}
function showNcdSaveConfirmation(){
  const dialog=$('#ncd-save-confirmation');if(!dialog)return;dialog.hidden=false;$('#ncd-save-confirmation-ok')?.focus();
}
async function saveHealthScreening(event){
  event.preventDefault(); const form=event.currentTarget,error=$('#ncd-error'),result=$('#ncd-result'),button=$('#ncd-submit');
  error.textContent=''; result.hidden=true; if(!selectedHealthPerson){error.textContent='กรุณาเลือกประชาชนจากรายการงาน';return;}
  if(!form.reportValidity())return;
  const d=new FormData(form),p=selectedHealthPerson;
  const smokeState=d.get('smoking_state'),alcoholState=d.get('alcohol_state'),glucoseType=d.get('glucose_type');
  const mental=evaluateMental2Q(d.get('mental_2q_q1'),d.get('mental_2q_q2'));
  if(!glucoseType){error.textContent='กรุณาเลือกสถานะก่อนตรวจน้ำตาล';setActiveNcdSection('ncd-section-measure',true);return;}
  if(!smokeState||!alcoholState||!d.get('exercise_frequency')){error.textContent='กรุณาเลือกพฤติกรรมสุขภาพให้ครบ';setActiveNcdSection('ncd-section-behavior',true);return;}
  const smokingFrequency=smokeState==='no'?'ไม่สูบ':d.get('smoking_frequency');
  const alcoholFrequency=alcoholState==='no'?'ไม่ดื่ม':d.get('alcohol_frequency');
  if(!smokingFrequency||!alcoholFrequency){error.textContent='กรุณาเลือกความถี่ของพฤติกรรมสุขภาพ';return;}
  const payload={p_source_pcucode:p.source_pcucode,p_source_pid:Number(p.source_pid),p_screened_on:d.get('screened_on')||null,p_weight_kg:formNumber(d.get('weight_kg')),p_height_cm:formNumber(d.get('height_cm')),p_waist_cm:formNumber(d.get('waist_cm')),p_sbp:formNumber(d.get('sbp')),p_dbp:formNumber(d.get('dbp')),p_glucose_mg_dl:formNumber(d.get('glucose_mg_dl')),p_glucose_type:glucoseType,p_danger_symptoms:false,p_smoking_frequency:smokingFrequency,p_alcohol_frequency:alcoholFrequency,p_exercise_frequency:d.get('exercise_frequency'),p_note:d.get('note')||'',p_request_id:form.dataset.requestId||requestId(),p_mental_2q_q1:mental.q1,p_mental_2q_q2:mental.q2};
  button.disabled=true;
  try{
    const {data:saved,error:saveError}=await supabase.rpc('save_health_ncd_screening_v4',payload); if(saveError)throw saveError;
    result.innerHTML=`<strong>${esc(saved.ncd_status)}</strong><span>${esc(saved.bp_status)} · ${esc(saved.glucose_status)} · CVD: ${esc(savedThaiCvLabel(saved))} · 2Q: ${esc(mental2QLabel(saved.mental_2q_status,saved.mental_2q_result))}</span>`; result.hidden=false; renderHealthFeedbackCard(buildHealthFeedbackModel(saved,mental,p,d)); form.dataset.requestId=requestId(); showNcdSaveConfirmation();
    const key=personKey(p); await Promise.all([loadHealthSummary(),loadHealthPeople()]); await loadHealthHistory(); const refreshed=healthPeople.find(x=>personKey(x)===key); if(refreshed){selectedHealthPerson=refreshed;renderPreviousPanel(refreshed);}
    result.scrollIntoView({behavior:'smooth',block:'nearest'});
  }catch(e){error.textContent=e.message;}finally{button.disabled=false;}
}
async function loadHealthModule(){
  const focus=$('#health-community-focus');focus.hidden=!healthCommunityFocus;focus.querySelector('strong').textContent=healthCommunityFocus||'';
  if(!healthLoaded&&profile.role==='staff')$('#health-filter').value='due';
  $('#health-target-scope-note').textContent=profile.role==='staff'?`ชุมชน ${profile.community||'ที่ได้รับมอบหมาย'} · แสดงงานที่ผูกไว้ก่อน`:profile.role==='user'?'บ้านในความรับผิดชอบ · แสดงงานที่ผูกไว้ก่อน':'ทุกพื้นที่ · เลือกดูเป้าหมายทั้งหมดได้';
  syncHealthTargetButtons();
  await loadHealthSummary(); await loadHealthPeople(); await loadHealthHistory(); healthLoaded=true;
  bindNcdSectionNav();
  $('#ncd-form').onsubmit=saveHealthScreening; $('#ncd-close').onclick=()=>{closeNcdSaveConfirmation(false);closeHealthFeedbackCard();healthFeedbackModel=null;$('#ncd-screen-card').hidden=true;selectedHealthPerson=null;};
  $('#ncd-clear-2q').onclick=()=>{$('#ncd-form').querySelectorAll('[name^="mental_2q_"]').forEach(el=>{el.checked=false;});renderMental2QPreview();};
  const saveConfirmation=$('#ncd-save-confirmation');$('#ncd-save-confirmation-ok').onclick=()=>{closeNcdSaveConfirmation(false);viewHealthFeedback();};$('#ncd-save-confirmation-close').onclick=()=>closeNcdSaveConfirmation();saveConfirmation.onclick=e=>{if(e.target===saveConfirmation)closeNcdSaveConfirmation();};saveConfirmation.onkeydown=e=>{if(e.key==='Escape')closeNcdSaveConfirmation();};
  $('#health-feedback-share').onclick=shareHealthFeedback;$('#health-feedback-close').onclick=closeHealthFeedbackCard;
  $('#health-refresh').onclick=async()=>{healthLoaded=false;await loadHealthModule();};
  $('#health-clear-community').onclick=async()=>{healthCommunityFocus='';focus.hidden=true;await loadHealthPeople();};
  $('#health-view-linked-targets').onclick=()=>setHealthTargetFilter('due'); $('#health-view-all-targets').onclick=()=>setHealthTargetFilter('targets');
  $('#health-filter').onchange=()=>{syncHealthTargetButtons();return loadHealthPeople();}; $('#health-stage').onchange=loadHealthPeople;
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

function communityHouseRows(rows){
  return rows.map(h=>{
    const hasMap=h.latitude!==null&&h.latitude!==undefined&&h.longitude!==null&&h.longitude!==undefined;
    const map=hasMap?`<a class="community-map-link" href="https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${h.latitude},${h.longitude}`)}" target="_blank" rel="noopener noreferrer">แผนที่</a>`:'<span class="muted">ไม่มีพิกัด</span>';
    return `<tr><td><strong>บ้าน ${esc(h.house_no||'ไม่ระบุ')}</strong><small>${esc(h.hcode||'—')}</small></td><td>${esc(h.moo||'—')}</td><td>${esc(h.record_status||'—')}</td><td class="${h.review_required?'warn':'good'}">${h.review_required?`ต้องตรวจ<small>${esc(h.review_reason||'')}</small>`:'ปกติ'}</td><td>${map}</td></tr>`;
  }).join('')||'<tr><td colspan="5">ไม่พบข้อมูลตามสิทธิ์</td></tr>';
}

async function fetchCommunityHouses(community){
  const rows=[];for(let from=0;;from+=1000){
    const {data,error}=await supabase.from('houses').select('hcode,house_no,moo,community,latitude,longitude,coordinate_status,record_status,review_required,review_reason,volunteer_pid').eq('community',community).order('house_no').range(from,from+999);
    if(error)throw error;rows.push(...(data||[]));if(!data||data.length<1000)break;
  }return rows;
}

async function openCommunity(index){
  const row=portalCommunityRows[index],workspace=$('#community-workspace');if(!row||!workspace)return;
  const request=++communityRequestId;workspace.hidden=false;workspace.innerHTML='<div class="community-loading">กำลังเปิดศูนย์งานชุมชน…</div>';
  workspace.scrollIntoView({behavior:'smooth',block:'start'});
  try{
    const houses=await fetchCommunityHouses(row.community);if(request!==communityRequestId)return;
    const volunteers=portalVolunteerRows.filter(v=>String(v.community||'').trim()===String(row.community||'').trim());
    const review=houses.filter(h=>h.review_required),mapped=houses.filter(h=>h.latitude!==null&&h.longitude!==null);
    const volunteerRows=volunteers.map(v=>`<tr><td><strong>${esc(v.display_name||'ไม่ระบุ')}</strong></td><td>${esc(anchorLabel(v.anchor_status))}</td><td>${num(v.house_count)}</td><td class="${Number(v.review_count)>0?'warn':'good'}">${num(v.review_count)}</td><td>${num(v.cross_community_count)}</td></tr>`).join('')||'<tr><td colspan="5">ไม่พบข้อมูล อสม. ตามสิทธิ์</td></tr>';
    workspace.innerHTML=`<div class="community-workspace-head"><div><p class="eyebrow">OSM-PHC COMMUNITY WORKSPACE</p><h3>${esc(row.community||'ไม่ระบุชุมชน')}</h3><p>ข้อมูลครัวเรือน อสม. พิกัด และงานสุขภาพที่บัญชี ${esc(roleLabel(currentProfile?.role))} มีสิทธิ์เห็น</p></div><button type="button" class="secondary" data-community-close>ปิด</button></div><div class="community-actions"><button type="button" class="active" data-community-action="overview"><span>◫</span><strong>สรุปชุมชน</strong><small>${num(houses.length)} หลัง</small></button><button type="button" data-community-action="houses"><span>⌂</span><strong>ครัวเรือน</strong><small>เปิดทะเบียนบ้าน</small></button><button type="button" data-community-action="volunteers"><span>♧</span><strong>อสม.</strong><small>${num(volunteers.length)} คนในสิทธิ์</small></button><button type="button" data-community-action="review"><span>✓</span><strong>ตรวจข้อมูล</strong><small>${num(review.length)} รายการ</small></button><button type="button" data-community-action="health"><span>✚</span><strong>งานสุขภาพ</strong><small>NCD และ 2Q</small></button></div><section class="community-view" data-community-view="overview"><div class="community-metrics"><article><small>ครัวเรือนในสิทธิ์</small><strong>${num(houses.length)}</strong></article><article><small>มอบหมาย อสม.</small><strong>${num(houses.filter(h=>h.volunteer_pid!==null).length)}</strong></article><article><small>มีพิกัด</small><strong>${num(mapped.length)}</strong></article><article><small>ต้องตรวจข้อมูล</small><strong>${num(review.length)}</strong></article></div><p class="community-scope-note">ระบบใช้ RLS กรองข้อมูลอัตโนมัติ ไม่สามารถเปิดชุมชนหรือบ้านนอกขอบเขตของบัญชีนี้ได้</p></section><section class="community-view" data-community-view="houses" hidden><h4>ทะเบียนครัวเรือน</h4><div class="table-wrap"><table><thead><tr><th>บ้าน</th><th>หมู่</th><th>สถานะ</th><th>คุณภาพข้อมูล</th><th>พิกัด</th></tr></thead><tbody>${communityHouseRows(houses)}</tbody></table></div></section><section class="community-view" data-community-view="volunteers" hidden><h4>ทะเบียน อสม. และเขตรับผิดชอบ</h4><div class="table-wrap"><table><thead><tr><th>อสม.</th><th>Anchor</th><th>บ้าน</th><th>ต้องตรวจ</th><th>ข้ามชุมชน</th></tr></thead><tbody>${volunteerRows}</tbody></table></div></section><section class="community-view" data-community-view="review" hidden><h4>รายการที่ต้องตรวจสอบ</h4><div class="table-wrap"><table><thead><tr><th>บ้าน</th><th>หมู่</th><th>สถานะ</th><th>คุณภาพข้อมูล</th><th>พิกัด</th></tr></thead><tbody>${communityHouseRows(review)}</tbody></table></div></section>`;
    workspace.querySelector('[data-community-close]').onclick=()=>{communityRequestId+=1;workspace.hidden=true;};
    workspace.querySelectorAll('[data-community-action]').forEach(button=>button.onclick=async()=>{
      const action=button.dataset.communityAction;if(action==='health'){healthCommunityFocus=row.community;setPortalView('health');try{if(!healthLoaded)await loadHealthModule();else{const focus=$('#health-community-focus');focus.hidden=false;focus.querySelector('strong').textContent=healthCommunityFocus;await loadHealthPeople();}}catch(e){$('#health-list-note').textContent=e.message;}return;}
      workspace.querySelectorAll('[data-community-action]').forEach(x=>x.classList.toggle('active',x===button));workspace.querySelectorAll('[data-community-view]').forEach(x=>x.hidden=x.dataset.communityView!==action);
    });
  }catch(error){if(request===communityRequestId)workspace.innerHTML=`<p class="error">${esc(error.message)}</p>`;}
}

async function getProfile(userId){
  const { data, error } = await supabase.from('profiles').select('user_id,display_name,role,community,volunteer_pid,active,must_change_password').eq('user_id', userId).maybeSingle();
  if(error) throw error;
  return data;
}

async function loadPortal(session, requestId){
  const profile = await getProfile(session.user.id);
  if(requestId !== authRequestId || passwordPanelOpen) return;
  currentProfile = profile;
  if(!profile || !profile.active){
    renderAuthView('blocked'); return;
  }
  const [{data: master, error: mErr}, {data: communities, error: cErr}, {data: workload, error: wErr}] = await Promise.all([
    supabase.from('communities').select('name,moo,active').eq('active', true).order('moo').order('name'),
    supabase.from('community_report_summary').select('*').order('community'),
    supabase.from('volunteer_workload').select('*').order('community').order('display_name')
  ]);
  if(requestId !== authRequestId || passwordPanelOpen) return;
  if(mErr) throw mErr; if(cErr) throw cErr; if(wErr) throw wErr;
  let myHouses=[];
  if(profile.role==='user'){const {data,error}=await supabase.from('houses').select('house_no,moo,community,record_status,coordinate_status,review_required').order('house_no');if(error)throw error;myHouses=data||[];}
  if(requestId !== authRequestId || passwordPanelOpen) return;

  const activeNames = new Set((master || []).map(x => x.name));
  const allSummary = communities || [];
  const rows = allSummary.filter(r => activeNames.has(r.community));
  const unknownRows = allSummary.filter(r => !activeNames.has(r.community));
  const unknownHouses = unknownRows.reduce((s,r)=>s+Number(r.houses||0),0);
  const vols = workload || [];
  portalCommunityRows=rows;portalVolunteerRows=vols;communityRequestId+=1;healthCommunityFocus='';
  const workspace=$('#community-workspace');workspace.hidden=true;workspace.innerHTML='';
  const totals = rows.reduce((a,r)=>({
    houses:a.houses+Number(r.houses||0),
    assigned:a.assigned+Number(r.assigned_houses||0),
    review:a.review+Number(r.review_houses||0),
    outside:a.outside+Number(r.outside_tambon||0),
    missing:a.missing+Number(r.missing_coordinates||0)
  }),{houses:0,assigned:0,review:0,outside:0,missing:0});

  $('#welcome-name').textContent = profile.display_name || session.user.email || 'ภาพรวมพื้นที่';
  $('#scope-label').textContent = profile.role==='admin' ? 'ทุก 16 ชุมชนในระบบ' : profile.role==='staff' ? `ดูแลชุมชน ${profile.community||'ยังไม่ได้กำหนดชุมชน'}` : 'บ้านและประชาชนในความรับผิดชอบของคุณ';
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
  $('#community-body').innerHTML = rows.map((r,index)=>`<tr><td><strong>${esc(r.community||'ไม่ระบุ')}</strong></td><td>${esc(r.moo||'—')}</td><td>${num(r.houses)}</td><td>${num(r.assigned_houses)}</td><td class="${Number(r.review_houses)>0?'warn':'good'}">${num(r.review_houses)}</td><td class="${Number(r.outside_tambon)>0?'bad':'good'}">${num(r.outside_tambon)}</td><td><button type="button" class="community-open" data-community-open="${index}">เปิดชุมชน</button></td></tr>`).join('') || '<tr><td colspan="7">ไม่พบข้อมูลตามสิทธิ์</td></tr>';
  document.querySelectorAll('[data-community-open]').forEach(button=>button.onclick=()=>openCommunity(Number(button.dataset.communityOpen)));
  $('#volunteer-body').innerHTML = vols.map(v=>`<tr><td><strong>${esc(v.display_name||'ไม่ระบุ')}</strong></td><td>${esc(v.community||'—')}</td><td>${esc(anchorLabel(v.anchor_status))}</td><td>${num(v.house_count)}</td><td class="${Number(v.review_count)>0?'warn':'good'}">${num(v.review_count)}</td><td>${num(v.cross_community_count)}</td></tr>`).join('') || '<tr><td colspan="6">ไม่พบข้อมูล อสม. ตามสิทธิ์</td></tr>';
  $('#my-house-count').textContent=`${num(myHouses.length)} หลัง`;
  $('#my-house-body').innerHTML=myHouses.map(h=>`<tr><td><strong>${esc(h.house_no||'ไม่ระบุ')}</strong></td><td>${esc(h.moo||'—')}</td><td>${esc(h.community||'—')}</td><td>${esc(h.record_status||'—')}</td><td>${esc(h.coordinate_status||'—')}</td><td class="${h.review_required?'warn':'good'}">${h.review_required?'ต้องตรวจ':'ปกติ'}</td></tr>`).join('')||'<tr><td colspan="6">ยังไม่มีบ้านในความรับผิดชอบ</td></tr>';
  healthLoaded=false; selectedHealthPerson=null; healthPeople=[];
  configurePortalNav(profile.role);
  configureHealthAdminUI(profile.role);

  if(requestId !== authRequestId || passwordPanelOpen) return;
  renderAuthView('portal');
  renderedPortalUserId=session.user.id;
}

async function applyAuthSession(session){
  if(!session){ renderLoggedOut(); return; }
  if(passwordPanelOpen) return;
  // INITIAL_SESSION/SIGNED_IN may be emitted repeatedly for the same user.
  // Avoid rebuilding a completed portal because that can interrupt the active menu.
  if(authView==='portal' && renderedPortalUserId===session.user.id && currentProfile?.user_id===session.user.id) return;
  const requestId = ++authRequestId;
  try{ await loadPortal(session, requestId); }
  catch(error){
    if(requestId !== authRequestId || passwordPanelOpen) return;
    currentProfile = null;
    $('#blocked').innerHTML = `<p class="eyebrow">ACCESS ERROR</p><h2>ไม่สามารถอ่านข้อมูลได้</h2><p>${esc(error.message)}</p>`;
    renderAuthView('blocked');
  }
}
async function refreshAuth(){
  const { data: { session } } = await supabase.auth.getSession();
  await applyAuthSession(session);
}

function setLoginPasswordVisibility(visible){
  const input=$('#login-password'),button=$('#toggle-login-password');if(!input||!button)return;
  input.type=visible?'text':'password';button.setAttribute('aria-pressed',String(visible));
  const label=visible?'ซ่อนรหัสผ่าน':'แสดงรหัสผ่าน';button.setAttribute('aria-label',label);button.title=label;
}
const loginPasswordToggle=$('#toggle-login-password');
loginPasswordToggle.addEventListener('click',()=>setLoginPasswordVisibility($('#login-password').type==='password'));
loginPasswordToggle.dataset.ready='true';

$('#login-form').addEventListener('submit', async e => {
  e.preventDefault();
  $('#login-error').textContent = '';
  const f = new FormData(e.target);
  let email;
  try{ email = await loginAlias(f.get('login')); }
  catch(error){ $('#login-error').textContent = error.message; return; }
  const { data, error } = await supabase.auth.signInWithPassword({ email, password:f.get('password') });
  if(error){ $('#login-error').textContent = 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'; return; }
  e.target.reset(); setLoginPasswordVisibility(false); await applyAuthSession(data.session);
});

$('#change-password').addEventListener('click', ()=>{
  passwordPanelOpen = true;
  authRequestId += 1;
  $('#password-title').textContent = 'เปลี่ยนรหัสผ่าน';
  $('#password-help').textContent = currentProfile?.role==='user' ? 'กำหนด PIN ตัวเลข 6–12 หลัก' : 'กำหนดรหัสผ่านใหม่อย่างน้อย 12 ตัวอักษร';
  $('#password-error').textContent = '';
  renderAuthView('password'); show($('#cancel-password'), true);
});
$('#cancel-password').addEventListener('click', ()=>{ passwordPanelOpen=false; refreshAuth(); });
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
  e.target.reset(); passwordPanelOpen=false; await refreshAuth();
});

$('#logout').addEventListener('click', async ()=>{
  passwordPanelOpen=false; renderLoggedOut();
  await supabase.auth.signOut();
});
supabase.auth.onAuthStateChange((event,session)=>{
  if(event==='SIGNED_OUT'){ renderLoggedOut(); return; }
  if(passwordPanelOpen) return;
  if((event==='INITIAL_SESSION' || event==='SIGNED_IN') && session){
    setTimeout(()=>applyAuthSession(session),0);
  }
});
$('#portal-nav-toggle').addEventListener('click',()=>setPortalNavCollapsed(!$('#portal').classList.contains('nav-collapsed')));
$('#ncd-form').addEventListener('change',event=>{if(event.target.matches('[name="smoking_state"],[name="alcohol_state"]'))syncBehaviorPanels(event.currentTarget);});
restorePortalNavPreference();
refreshAuth();

