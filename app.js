import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js?v=2.0.55&p=2055b';
import { evaluateMental2Q, mental2QLabel } from './health-2q.mjs?v=1.8.28';
import { getSharedSupabase, setSharedSession, setSharedProfile, clearSharedAuth, sharedCall, invalidateShared } from './shared-runtime-v2035.mjs?v=2.0.35';

const supabase = await getSharedSupabase(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
const $ = s => document.querySelector(s);
const esc = v => String(v ?? '').replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const num = v => Number(v || 0).toLocaleString('th-TH');
let currentProfile = null;
let portalView = 'overview';
let healthPeople = [];
let selectedHealthPerson = null;
let healthLoaded = false;
let healthSearchTimer = null;
let healthFieldStatusTimer = null;
let passwordPanelOpen = false;
let authRequestId = 0;
let authView = 'login';
let renderedPortalUserId = null;
let healthFeedbackModel = null;
let portalCommunityRows = [];
let portalVolunteerRows = [];
let communityRequestId = 0;
let healthCommunityFocus = '';
let careScopeMode = 'self';
let careScopeVolunteerPid = null;
let staffVolunteerOptionsV2033 = [];
let healthAssignmentFilter = 'all';
let healthPageOffset = 0;
let healthHasMore = false;
let healthAbortController = null;
let healthRequestSequence = 0;
let healthViewEpochV2040 = 0;
const healthCoordTraceV2040 = [];
let healthLoadSignature = '';
let healthLoadPromise = null;
let healthLastCompletedSignature = '';
let healthLastCompletedAt = 0;
let healthRefreshTimer = null;
let healthRefreshPromise = null;
let healthRefreshResolve = null;
let healthRefreshReject = null;
let healthActiveViewName = 'health_person_worklist_active_v1847';
let healthTargetSettingsV2026 = null;
const HEALTH_WORKLIST_BASE_COLUMNS='source_pcucode,source_pid,hcode,house_no,moo,community,volunteer_pid,display_name,gender,birth_date,age_years,life_stage,has_ht,has_dm,known_ncd,ncd_target,latest_screened_on,latest_ncd_status,latest_severity,screened_current_fy,previous_screened_on,previous_weight_kg,previous_height_cm,previous_waist_cm,previous_sbp,previous_dbp,previous_glucose_mg_dl,previous_bmi,previous_source,previous_smoking,previous_alcohol,previous_exercise';
const HEALTH_TARGET_FAST_COLUMNS=HEALTH_WORKLIST_BASE_COLUMNS+',has_cvd,cvd_population_eligible,screening_plan_date,screening_age_months,screening_route,screening_route_label,screening_dspm_target_months,field_target_enabled,screening_plan_updated_at';
function healthWorklistColumns(){return healthActiveViewName==='health_person_worklist_active_v1847'?HEALTH_WORKLIST_BASE_COLUMNS+',has_cvd,cvd_population_eligible,screening_plan_date,screening_age_months,screening_route,screening_route_label,screening_dspm_target_months,field_target_enabled,screening_plan_updated_at':HEALTH_WORKLIST_BASE_COLUMNS;}
function healthWorklistSchemaFallbackAllowed(error){const code=String(error?.code||'');const message=String(error?.message||'').toLowerCase();return ['42703','42P01','PGRST204','PGRST205'].includes(code)||message.includes('does not exist')||message.includes('schema cache');}
const PORTAL_NAV_STORAGE = 'phc.portal.nav-collapsed';
const HEALTH_PAGE_SIZE_V2033 = 50;
const HEALTH_WORKLIST_CACHE_MS_V2039 = 30000;
const STAFF_SCOPE_CACHE_MS_V2039 = 300000;
const HOUSEHOLD_CACHE_MS_V2039 = 30000;
const HEALTH_COORD_TRACE_MAX_V2040 = 40;
const CLOUD_RELEASE_VERSION = '2.0.55';
function traceHealthCoordV2040(event,args={},trigger=''){
  const row={at:Date.now(),event:String(event||''),trigger:String(trigger||''),scope:String(args.p_scope||''),filter:String(args.p_filter||''),stage:String(args.p_stage||''),hasSearch:Boolean(args.p_search),hasCommunity:Boolean(args.p_community),assignment:String(args.p_assignment||''),hasOwner:Boolean(args.p_owner_pid),offset:Number(args.p_offset||0)};
  healthCoordTraceV2040.push(row);while(healthCoordTraceV2040.length>HEALTH_COORD_TRACE_MAX_V2040)healthCoordTraceV2040.shift();window.PHCHealthCoordTrace=healthCoordTraceV2040;
}
function cancelScheduledHealthLoadV2040(reason='view-left'){
  if(healthRefreshTimer)clearTimeout(healthRefreshTimer);const resolve=healthRefreshResolve;healthRefreshTimer=null;healthRefreshPromise=null;healthRefreshResolve=null;healthRefreshReject=null;healthViewEpochV2040+=1;healthRequestSequence+=1;healthAbortController?.abort();healthAbortController=null;healthLoadPromise=null;healthLoadSignature='';traceHealthCoordV2040(`cancel:${reason}`);resolve?.();
}
const CLOUD_BRAND_LOGO_URL = `${SUPABASE_URL}/storage/v1/object/public/osm-public-assets/branding/logo`;

function configureCloudBrandLogo(){
  const image=$('#cloud-login-logo');if(!image)return;
  const fallback='./logo.svg?v=2.0.55';
  image.onerror=()=>{image.onerror=null;image.src=fallback;};
  image.src=`${CLOUD_BRAND_LOGO_URL}?t=${Math.floor(Date.now()/300000)}`;
}
function enforceCloudReleaseVersion(){
  const footer=$('.login-version');if(!footer)return;
  const expected=`Cloud v${CLOUD_RELEASE_VERSION}`;
  const restore=()=>{if(footer.textContent!==expected)footer.textContent=expected;};
  restore();
  if(!window.__PHC_RELEASE_VERSION_GUARD__){
    const observer=new MutationObserver(restore);observer.observe(footer,{childList:true,characterData:true,subtree:true});
    window.__PHC_RELEASE_VERSION_GUARD__=observer;
  }
}

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
  clearSharedAuth();
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
function setPortalView(next){const allowed=[...document.querySelectorAll('#portal-nav [data-portal-view]')].filter(b=>!b.hidden).map(b=>b.dataset.portalView);const previous=portalView;portalView=allowed.includes(next)?next:'overview';document.querySelectorAll('[data-portal-panel]').forEach(x=>x.hidden=x.dataset.portalPanel!==portalView);document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>b.classList.toggle('active',b.dataset.portalView===portalView));if(previous!==portalView){if(previous==='health'&&portalView!=='health')cancelScheduledHealthLoadV2040('view-left');document.dispatchEvent(new CustomEvent('phc:portal-view-changed',{detail:{view:portalView,previous}}));}if(window.innerWidth<=900)window.scrollTo({top:0,behavior:'smooth'});}
function configurePortalNav(role){
  const labels={admin:{communities:'ชุมชนทั้งหมด',volunteers:'ทะเบียน อสม.'},staff:{communities:'ชุมชนที่ดูแล',houses:'บ้านของฉัน'},user:{communities:'ชุมชนของฉัน',houses:'บ้านของฉัน'}};
  document.querySelectorAll('#portal-nav [data-portal-view]').forEach(b=>{
    b.hidden=!(b.dataset.roles||'').split(/\s+/).includes(role);
    const label=b.querySelector('.portal-nav-label'),roleLabelText=labels[role]?.[b.dataset.portalView];if(label&&roleLabelText)label.textContent=roleLabelText;
    b.onclick=async()=>{
      const wasActive=portalView===b.dataset.portalView;setPortalView(b.dataset.portalView);
      // Phase 2J: field-work-reporting owns the Work panel snapshot.
      if(b.dataset.portalView==='health'){
        const filter=$('#health-filter'),stage=$('#health-stage');
        if(filter)filter.value='field_targets';
        if(stage)stage.value='';
        syncHealthTargetButtons();
        try{if(!healthLoaded)await loadHealthModule();else if(!wasActive)await scheduleHealthPeopleLoad(160,'nav');}catch(e){$('#health-person-body').innerHTML=`<tr><td colspan="5">${esc(e.message)}</td></tr>`;}
      }
    };
  });
  // Preserve the panel the user is currently working in during session refreshes.
  // setPortalView() falls back to overview only when that panel is unavailable.
  setPortalView(portalView);
}
function configureHealthAdminUI(role){
  const adminIntro=$('#health-admin-intro'),targetAdmin=$('#health-target-admin');
  if(adminIntro)adminIntro.hidden=role!=='admin';
  if(targetAdmin)targetAdmin.hidden=role!=='admin';
  const allOption=$('#health-filter option[value="all"]');
  if(allOption){allOption.hidden=role!=='admin';allOption.disabled=role!=='admin';}
  bindHealthPerformanceControls();
  bindPerformanceScopeControls();
  bindHealthTargetAdminV2026();
  bindReportSnapshotAdminV2031();
  syncPerformanceScopeUI();
}
function renderHealthTargetAdminV2026(data){
  healthTargetSettingsV2026=data||null;
  const host=$('#health-target-admin-groups'),summary=$('#health-target-admin-summary');
  if(summary)summary.innerHTML=`<span>ประชากรเข้าเกณฑ์ <strong>${num(data?.eligible_population)}</strong></span><span>เตรียมแผนแล้ว <strong>${num(data?.prepared_rows)}</strong></span><span>เป้าหมายที่แสดง <strong>${num(data?.field_targets)}</strong></span>`;
  if(!host)return;
  host.innerHTML=(data?.groups||[]).map(g=>`<button type="button" class="health-target-group ${g.enabled?'active':''}" data-target-route="${esc(g.route)}" data-enabled="${g.enabled?'1':'0'}" ${g.locked?'disabled':''}><span><strong>${esc(g.age_label)}</strong><small>${esc(g.label)}</small></span><b>${g.locked?'เปิดถาวร':(g.enabled?'เปิด':'ปิด')}</b></button>`).join('');
  host.querySelectorAll('[data-target-route]:not([disabled])').forEach(b=>b.onclick=()=>setHealthTargetGroupV2026(b.dataset.targetRoute,b.dataset.enabled!=='1'));
}
async function loadHealthTargetSettingsV2026(){const {data,error}=await supabase.rpc('screening_target_settings_v2026');if(error)throw error;renderHealthTargetAdminV2026(data||{});return data;}
async function setHealthTargetGroupV2026(route,enabled){if(currentProfile?.role!=='admin')return;const status=$('#health-target-admin-status');if(status)status.textContent='กำลังประมวลผลเป้าหมายใหม่…';try{const {data,error}=await supabase.rpc('admin_set_screening_target_group_v2026',{p_route:route,p_enabled:Boolean(enabled)});if(error)throw error;renderHealthTargetAdminV2026(data||{});if(status)status.textContent='ประมวลผลเป้าหมายใหม่แล้ว';invalidateHealthWorklistCache();if(healthLoaded)await loadHealthPeople({force:true,trigger:'target-config'});}catch(e){if(status)status.textContent=e.message;}}
async function refreshHealthTargetsV2026(){if(currentProfile?.role!=='admin')return;const b=$('#health-target-refresh'),status=$('#health-target-admin-status');if(b)b.disabled=true;if(status)status.textContent='กำลังประมวลผลเป้าหมายทั้งฐาน…';try{const {data,error}=await supabase.rpc('admin_refresh_screening_targets_v2026');if(error)throw error;const settings=data?.settings||await loadHealthTargetSettingsV2026();renderHealthTargetAdminV2026(settings);if(status)status.textContent=`พร้อมใช้งาน ${num(settings?.field_targets)} เป้าหมาย`;invalidateHealthWorklistCache();if(healthLoaded)await loadHealthPeople({force:true,trigger:'target-refresh'});}catch(e){if(status)status.textContent=e.message;}finally{if(b)b.disabled=false;}}
function bindHealthTargetAdminV2026(){const b=$('#health-target-refresh');if(!b||b.dataset.bound==='1')return;b.dataset.bound='1';b.onclick=refreshHealthTargetsV2026;}
async function refreshReportSnapshotsV2031(){if(currentProfile?.role!=='admin')return;const b=$('#report-snapshot-refresh'),status=$('#report-snapshot-status');if(b)b.disabled=true;if(status)status.textContent='กำลังประมวลผลตัวเลขสรุป…';try{const {data,error}=await supabase.rpc('admin_refresh_report_snapshots_v2031');if(error)throw error;if(!data?.ok)throw new Error(data?.status==='busy'?'มีการประมวลผลอยู่แล้ว กรุณารอสักครู่':(data?.error||'ประมวลผลไม่สำเร็จ'));if(status)status.textContent=`ประมวลผลแล้ว ${num(data.cache_rows)} ขอบเขต ใช้เวลา ${(Number(data.duration_ms||0)/1000).toFixed(1)} วินาที`;invalidateShared('report-snapshot:');document.dispatchEvent(new CustomEvent('phc:report-snapshot-refreshed',{detail:data}));}catch(e){if(status)status.textContent=e.message;}finally{if(b)b.disabled=false;}}
function bindReportSnapshotAdminV2031(){const b=$('#report-snapshot-refresh');if(!b||b.dataset.bound==='1')return;b.dataset.bound='1';b.onclick=refreshReportSnapshotsV2031;}

function effectivePerformanceScope(){
  if(currentProfile?.role==='admin')return 'all';
  if(currentProfile?.role==='staff')return ['self','volunteer','community'].includes(careScopeMode)?careScopeMode:'self';
  return 'self';
}
function renderStaffVolunteerOptionsV2033(){
  const select=$('#performance-owner');if(!select)return;
  const current=String(careScopeVolunteerPid??'');
  select.innerHTML=staffVolunteerOptionsV2033.map(v=>`<option value="${esc(v.volunteer_pid)}">${esc(v.display_name||'ไม่ระบุชื่อ')}</option>`).join('');
  if(current&&staffVolunteerOptionsV2033.some(v=>String(v.volunteer_pid)===current))select.value=current;
  else if(staffVolunteerOptionsV2033.length){careScopeVolunteerPid=Number(staffVolunteerOptionsV2033[0].volunteer_pid);select.value=String(careScopeVolunteerPid);}
}
async function loadStaffVolunteerOptionsV2033(){
  if(currentProfile?.role!=='staff')return [];
  const {data,error}=await sharedCall('staff-volunteer-scope-v2033',()=>supabase.rpc('staff_volunteer_scope_v2033'),STAFF_SCOPE_CACHE_MS_V2039);if(error)throw error;
  staffVolunteerOptionsV2033=Array.isArray(data)?data:[];renderStaffVolunteerOptionsV2033();return staffVolunteerOptionsV2033;
}
function syncHealthAssignmentControl(){
  const wrap=$('#health-assignment-wrap'),select=$('#health-assignment');
  const isAdmin=currentProfile?.role==='admin';
  const enabled=isAdmin||(currentProfile?.role==='staff'&&effectivePerformanceScope()==='community');
  if(wrap)wrap.hidden=!enabled;
  if(!enabled){healthAssignmentFilter='all';if(select)select.value='all';return;}
  const allowed=isAdmin?['all','assigned','fallback','unresolved']:['all','assigned','fallback'];
  if(!allowed.includes(healthAssignmentFilter))healthAssignmentFilter='all';
  const unresolved=select?.querySelector('option[value="unresolved"]');if(unresolved)unresolved.hidden=!isAdmin;
  if(select)select.value=healthAssignmentFilter;
}
function syncPerformanceScopeUI(){
  const control=$('#performance-scope-control'),note=$('#performance-scope-note'),ownerWrap=$('#performance-owner-wrap');
  if(control){
    control.hidden=currentProfile?.role!=='staff';
    control.querySelectorAll('[data-performance-scope]').forEach(button=>{
      const active=button.dataset.performanceScope===effectivePerformanceScope();
      button.classList.toggle('active',active);
      button.setAttribute('aria-pressed',String(active));
    });
  }
  if(ownerWrap)ownerWrap.hidden=!(currentProfile?.role==='staff'&&effectivePerformanceScope()==='volunteer');
  renderStaffVolunteerOptionsV2033();
  if(note){
    if(currentProfile?.role==='staff')note.textContent=effectivePerformanceScope()==='community'?'แสดงผลงานรวมชุมชน '+(currentProfile.community||'ที่ได้รับมอบหมาย')+' · รวมงาน Staff ดูแลแทน':effectivePerformanceScope()==='volunteer'?'แสดงเฉพาะงานของ อสม. ที่เลือก โดยตรวจสิทธิ์จากชุมชนบนเซิร์ฟเวอร์':'แสดงเฉพาะผลงานจากบ้านและประชาชนที่ฉันรับผิดชอบ';
    else if(currentProfile?.role==='user')note.textContent='แสดงเฉพาะผลงานจากบ้านและประชาชนที่ฉันรับผิดชอบ';
    else note.textContent='แสดงผลงานทุกพื้นที่ตามขอบเขตสิทธิ์เจ้าหน้าที่';
  }
  syncHealthAssignmentControl();
}
async function setPerformanceScope(next){
  if(currentProfile?.role!=='staff')return;
  careScopeMode=['self','volunteer','community'].includes(next)?next:'self';
  if(careScopeMode==='volunteer'&&!staffVolunteerOptionsV2033.length){try{await loadStaffVolunteerOptionsV2033();}catch(e){careScopeMode='self';const note=$('#performance-scope-note');if(note)note.textContent=e.message;}}
  if(careScopeMode==='volunteer'&&!careScopeVolunteerPid&&staffVolunteerOptionsV2033.length)careScopeVolunteerPid=Number(staffVolunteerOptionsV2033[0].volunteer_pid);
  if(careScopeMode==='volunteer'&&!careScopeVolunteerPid)careScopeMode='self';
  if(careScopeMode!=='community')healthAssignmentFilter='all';
  try{localStorage.setItem('phc.care.scope',careScopeMode);localStorage.setItem('phc.field.scope',careScopeMode);if(careScopeVolunteerPid)localStorage.setItem('phc.care.volunteer',String(careScopeVolunteerPid));}catch{}
  syncPerformanceScopeUI();
  document.dispatchEvent(new CustomEvent('phc:care-scope-changed',{detail:{scope:careScopeMode,volunteer_pid:careScopeVolunteerPid,source:'performance'}}));
  if(healthLoaded&&portalView==='health')await scheduleHealthPeopleLoad(160,'scope-control');
}
function bindPerformanceScopeControls(){
  const control=$('#performance-scope-control');
  if(!control||control.dataset.bound==='1')return;
  control.dataset.bound='1';
  control.querySelectorAll('[data-performance-scope]').forEach(button=>button.onclick=()=>setPerformanceScope(button.dataset.performanceScope));
  const owner=$('#performance-owner');if(owner)owner.onchange=async()=>{careScopeVolunteerPid=Number(owner.value)||null;if(careScopeMode==='volunteer')await setPerformanceScope('volunteer');};
}
function bindHealthPerformanceControls(){
  const refresh=$('#health-refresh');if(!refresh||refresh.dataset.bound==='1')return;
  refresh.dataset.bound='1';
  refresh.onclick=async()=>{
    refresh.disabled=true;
    try{invalidateShared('report-snapshot:');invalidateHealthWorklistCache();await loadHealthSummary();if(healthLoaded){await loadHealthPeople({force:true,trigger:'refresh'});await loadHealthHistory();}}
    catch(e){const box=$('#health-stats');if(box)box.innerHTML=`<article class="stat"><small>รีเฟรชไม่สำเร็จ</small><strong>—</strong></article>`;}
    finally{refresh.disabled=false;}
  };
}

function localDate(){return new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Bangkok'});}
const GO_LIVE_V208='2026-10-01';
function preGoLiveTestModeV208(){return localDate()<GO_LIVE_V208;}
function formNumber(value){const n=Number(value);return Number.isFinite(n)?n:null;}
function requestId(){return crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;}

function personKey(p){return `${p.source_pcucode}:${p.source_pid}`;}

function healthClass(severity){return severity==='urgent'?'bad':severity==='alert'?'attention':severity==='risk'?'warn':severity==='normal'?'good':'';}
function formatHealthValue(value,suffix=''){return value===null||value===undefined||value===''?'—':`${value}${suffix}`;}
function healthDateLabel(value){if(!value)return 'ยังไม่มีประวัติคัดกรอง';try{return new Date(value+'T00:00:00').toLocaleDateString('th-TH',{year:'numeric',month:'short',day:'numeric'});}catch{return value;}}
function confirmRepeatNcdV2033(person){
  const last=String(person?.latest_screened_on||'').slice(0,10);if(!last)return Promise.resolve(true);
  const sameDay=last===localDate(),label=healthDateLabel(last);
  return new Promise(resolve=>{
    document.querySelector('.repeat-screening-dialog')?.remove();
    const overlay=document.createElement('div');overlay.className='repeat-screening-dialog';overlay.setAttribute('role','dialog');overlay.setAttribute('aria-modal','true');overlay.setAttribute('aria-labelledby','repeat-screening-title');
    overlay.innerHTML=`<section class="repeat-screening-card ${sameDay?'same-day':''}"><div class="repeat-screening-icon">${sameDay?'!':'↻'}</div><h2 id="repeat-screening-title">${sameDay?'มีผลคัดกรองของวันนี้แล้ว':'พบประวัติคัดกรองเดิม'}</h2><p><strong>${esc(person?.display_name||'บุคคลนี้')}</strong> คัดกรองแล้วเมื่อวันที่ ${esc(label)}</p><p>${sameDay?'หากดำเนินการต่อ ระบบจะบันทึกผลวันนี้เพิ่มเป็นอีกรายการ และไม่ทับผลเดิม':'ต้องการคัดกรองซ้ำหรือไม่? ผลใหม่จะถูกเก็บเพิ่มในประวัติและไม่ทับผลเดิม'}</p><div class="repeat-screening-actions"><button type="button" class="secondary" data-repeat-cancel>ยกเลิก</button><button type="button" class="primary" data-repeat-confirm>คัดกรองซ้ำ</button></div></section>`;
    const finish=value=>{overlay.remove();resolve(value);};
    overlay.querySelector('[data-repeat-cancel]').onclick=()=>finish(false);overlay.querySelector('[data-repeat-confirm]').onclick=()=>finish(true);
    overlay.onclick=e=>{if(e.target===overlay)finish(false);};overlay.onkeydown=e=>{if(e.key==='Escape')finish(false);};document.body.append(overlay);overlay.querySelector('[data-repeat-cancel]').focus();
  });
}
async function loadHealthSummary(){
  const scope=effectivePerformanceScope(),owner=scope==='volunteer'?(careScopeVolunteerPid??null):null;
  let {data,error}=await sharedCall(`report-snapshot:care:${scope}:${owner??''}`,()=>supabase.rpc('report_snapshot_v2033',{p_report_key:'care',p_scope:scope,p_owner_pid:owner}),30000);
  if((error||!data)&&effectivePerformanceScope()!=='volunteer'){const legacy=await supabase.rpc('report_snapshot_v2031',{p_report_key:'care',p_scope:careScopeMode});data=legacy.data;error=legacy.error;}
  if((error||!data)&&effectivePerformanceScope()!=='volunteer'){const live=await supabase.rpc('care_dashboard_v1861',{p_scope:careScopeMode});data=live.data;error=live.error;}
  if(error)throw error;const x=data||{};
  $('#health-stats').innerHTML=[
    [x.people,'ประชาชนในสิทธิ์'],[x.ncd_targets,'เป้าหมาย NCD 35+'],[x.ncd_done,'คัดกรองแล้วปีงบฯ'],[x.ncd_due,'คงเหลือ'],[x.known_ncd,'DM/HT เดิม']
  ].map(([v,l])=>`<article class="stat"><small>${esc(l)}</small><strong>${num(v)}</strong></article>`).join('');
  $('#mental-2q-stats').innerHTML=[
    [x.mental_2q_assessed,'ประเมินแล้ว','good'],
    [x.mental_2q_not_assessed,'ไม่ได้ประเมิน',''],
    [x.mental_2q_incomplete,'ข้อมูลไม่ครบ','warn']
  ].map(([v,l,c])=>`<article class="stat ${c}"><small>${esc(l)}</small><strong>${num(v)}</strong></article>`).join('');
  $('#mental-2q-note').textContent=`พบคำตอบบวก ${num(x.mental_2q_positive)} ราย · ขอบเขต ${x.scope_label||'ตามสิทธิ์'}`;
  $('#life-stage-stats').innerHTML=[['เด็กปฐมวัย',x.early_child],['เด็กวัยเรียน',x.school_age],['วัยรุ่นและเยาวชน',x.youth],['วัยทำงาน',x.working_age],['ผู้สูงอายุ',x.older_people]].map(([l,v])=>`<div class="life-chip"><span>${esc(l)}</span><strong>${num(v)}</strong></div>`).join('');
}
function syncHealthTargetButtons(){
  const filter=$('#health-filter').value;
  $('#health-view-linked-targets').classList.toggle('active',filter==='field_targets');
  $('#health-view-all-targets').classList.toggle('active',filter==='targets');
}
async function setHealthTargetFilter(filter){
  healthCommunityFocus='';
  const focus=$('#health-community-focus');if(focus)focus.hidden=true;
  $('#health-filter').value=filter;syncHealthTargetButtons();await loadHealthPeople({trigger:'filter'});
}
async function loadFastHealthTargetsV2030(stage,raw){
  const term=String(raw||'').replace(/[%_,()]/g,'').slice(0,60).trim();
  const args={p_scope:careScopeMode,p_stage:stage||null,p_search:term||null,p_community:healthCommunityFocus||null,p_limit:300};
  let lastError=null;
  for(let attempt=0;attempt<3;attempt++){
    const {data,error}=await supabase.rpc('my_screening_targets_json_v2030',args);
    if(!error)return Array.isArray(data)?data:[];
    lastError=error;
    const timeout=String(error?.code||'')==='57014'||String(error?.message||'').toLowerCase().includes('statement timeout');
    if(!timeout||attempt===2)break;
    await new Promise(resolve=>setTimeout(resolve,120+(Math.random()*260)+(attempt*180)));
  }
  throw lastError||new Error('ไม่สามารถโหลดเป้าหมายคัดกรองได้');
}
function assignmentRpcUnavailableV2054(error){
  const code=String(error?.code||'');const message=String(error?.message||'').toLowerCase();
  return ['42883','PGRST202','PGRST204'].includes(code)||message.includes('health_worklist_assignment_json_v2054')||message.includes('could not find the function');
}
function assignmentRpcUnavailableV2033(error){
  const code=String(error?.code||'');const message=String(error?.message||'').toLowerCase();
  return ['42883','PGRST202','PGRST204'].includes(code)||message.includes('health_worklist_assignment_json_v2033')||message.includes('could not find the function');
}
function healthWorklistArgsV2040(filter,stage,raw,offset=0){
  const scope=effectivePerformanceScope(),term=String(raw||'').replace(/[%_,()]/g,'').slice(0,60).trim(),community=String(healthCommunityFocus||'').trim()||null;
  const assignmentAllowed=currentProfile?.role==='admin'||(currentProfile?.role==='staff'&&scope==='community');
  const owner=scope==='volunteer'?(Number(careScopeVolunteerPid)||null):null;
  return {p_scope:scope,p_filter:String(filter||'field_targets'),p_stage:String(stage||'').trim()||null,p_search:term||null,p_community:community,p_assignment:assignmentAllowed?(healthAssignmentFilter||'all'):'all',p_owner_pid:owner,p_limit:HEALTH_PAGE_SIZE_V2033,p_offset:Number(offset||0)};
}
function healthFieldQueuePendingV2042(row){
  if(!row)return false;if(Boolean(row.screened_current_fy))return false;
  const latest=String(row.latest_screened_on||'').slice(0,10);return !latest||latest!==localDate();
}
async function loadScopedHealthPeopleV2033(filter,stage,raw,offset=0,signal=null,{force=false,argsOverride=null}={}){
  const args=argsOverride||healthWorklistArgsV2040(filter,stage,raw,offset);
  const stableKey=`health-worklist-v2054:${JSON.stringify(args)}`;
  if(force)invalidateShared(stableKey);
  const loader=async()=>{
    let response=await supabase.rpc('health_worklist_assignment_json_v2054',args);
    if(response?.error&&assignmentRpcUnavailableV2054(response.error)){
      response=await supabase.rpc('health_worklist_assignment_json_v2033',args);
    }
    return response;
  };
  let response;
  if(offset===0&&!force){response=await sharedCall(stableKey,loader,HEALTH_WORKLIST_CACHE_MS_V2039);}
  else{let request=loader();if(signal&&typeof request.abortSignal==='function')request=request.abortSignal(signal);response=await request;}
  const {data,error}=response||{};if(error)throw error;
  if(Array.isArray(data))return {rows:data,has_more:data.length>=HEALTH_PAGE_SIZE_V2033};
  return {rows:Array.isArray(data?.rows)?data.rows:[],has_more:Boolean(data?.has_more)};
}
function scheduleHealthPeopleLoad(delay=160,trigger='scheduled'){
  if(portalView!=='health'){traceHealthCoordV2040('schedule-skip:inactive',{},trigger);return Promise.resolve();}
  healthRequestSequence+=1;healthAbortController?.abort();healthAbortController=null;healthLoadPromise=null;healthLoadSignature='';traceHealthCoordV2040('scheduled',{},trigger);
  clearTimeout(healthRefreshTimer);if(!healthRefreshPromise)healthRefreshPromise=new Promise((resolve,reject)=>{healthRefreshResolve=resolve;healthRefreshReject=reject;});healthRefreshTimer=setTimeout(async()=>{const resolve=healthRefreshResolve,reject=healthRefreshReject;healthRefreshTimer=null;healthRefreshPromise=null;healthRefreshResolve=null;healthRefreshReject=null;if(portalView!=='health'){traceHealthCoordV2040('schedule-skip:left',{},trigger);resolve?.();return;}try{resolve?.(await loadHealthPeople({trigger}));}catch(e){reject?.(e);}},delay);return healthRefreshPromise;
}
function invalidateHealthWorklistCache(){healthLastCompletedSignature='';healthLastCompletedAt=0;invalidateShared('health-worklist-v2054:');}
async function loadHealthPeople(options={}){
  const append=Boolean(options?.append),force=Boolean(options?.force),allowInactive=Boolean(options?.allowInactive),trigger=String(options?.trigger||'direct');
  if(!allowInactive&&portalView!=='health'){traceHealthCoordV2040('load-skip:inactive',{},trigger);return;}
  if(!append)healthPageOffset=0;
  let filter=$('#health-filter').value;
  if(filter==='all'&&currentProfile?.role!=='admin'){filter='field_targets';$('#health-filter').value=filter;}
  syncHealthTargetButtons();syncHealthAssignmentControl();
  const stage=$('#health-stage').value,raw=$('#health-search').value.trim(),requestArgs=healthWorklistArgsV2040(filter,stage,raw,healthPageOffset);
  const signature=JSON.stringify({mode:append?'append':'base',...requestArgs});traceHealthCoordV2040('load',requestArgs,trigger);
  if(healthLoadPromise&&healthLoadSignature===signature){traceHealthCoordV2040('coalesced',requestArgs,trigger);return healthLoadPromise;}
  if(!force&&!append&&healthLastCompletedSignature===signature&&(Date.now()-healthLastCompletedAt)<HEALTH_WORKLIST_CACHE_MS_V2039){traceHealthCoordV2040('recent-hit',requestArgs,trigger);return;}
  if(healthLoadPromise&&healthLoadSignature!==signature)traceHealthCoordV2040('supersede-key',requestArgs,trigger);
  healthAbortController?.abort();healthAbortController=new AbortController();const requestSequence=++healthRequestSequence,requestEpoch=healthViewEpochV2040;
  const run=(async()=>{
  let data=null,error=null,usedAssignmentRpc=false,pageResult=null;
  try{pageResult=await loadScopedHealthPeopleV2033(filter,stage,raw,healthPageOffset,healthAbortController.signal,{force,argsOverride:requestArgs});data=pageResult.rows;usedAssignmentRpc=true;}
  catch(e){
    if(e?.name==='AbortError'||requestSequence!==healthRequestSequence||requestEpoch!==healthViewEpochV2040||(!allowInactive&&portalView!=='health')){traceHealthCoordV2040('discarded',requestArgs,trigger);return;}
    if(!assignmentRpcUnavailableV2033(e)||requestArgs.p_assignment!=='all'||requestArgs.p_scope==='volunteer')throw e;
    const fastTarget=filter==='field_targets';
    if(fastTarget){try{data=await loadFastHealthTargetsV2030(stage,raw);}catch(inner){error=inner;}}
    else{
      let q=supabase.from(healthActiveViewName).select(healthWorklistColumns()).order('community').order('hcode').order('display_name').limit(300);
      if(requestArgs.p_community)q=q.eq('community',requestArgs.p_community);
      if(currentProfile?.role==='staff'&&requestArgs.p_scope==='self'&&currentProfile?.volunteer_pid!=null)q=q.eq('volunteer_pid',currentProfile.volunteer_pid);
      if(filter==='due')q=q.eq('ncd_target',true).eq('screened_current_fy',false);else if(filter==='targets')q=q.eq('ncd_target',true);else if(filter==='known')q=q.eq('known_ncd',true);
      if(requestArgs.p_stage)q=q.eq('life_stage',requestArgs.p_stage);const term=requestArgs.p_search||'';if(term)q=q.ilike('display_name',`%${term}%`);
      const res=await q;data=res.data;error=res.error;
    }
  }
  if(requestSequence!==healthRequestSequence||requestEpoch!==healthViewEpochV2040||(!allowInactive&&portalView!=='health')){traceHealthCoordV2040('discarded',requestArgs,trigger);return;}
  if(error&&!usedAssignmentRpc&&healthWorklistSchemaFallbackAllowed(error)&&healthActiveViewName==='health_person_worklist_active_v1847'){healthActiveViewName='health_person_worklist_active_v1841';return loadHealthPeople({trigger});}
  if(error&&!usedAssignmentRpc&&healthWorklistSchemaFallbackAllowed(error)&&healthActiveViewName==='health_person_worklist_active_v1841'){healthActiveViewName='health_person_worklist';return loadHealthPeople({trigger});}
  if(error)throw error;
  const rawPageRows=(data||[]).map(p=>({...p,has_cvd:Boolean(p.has_cvd),cvd_population_eligible:Boolean(p.cvd_population_eligible)}));
  const pageRows=filter==='field_targets'?rawPageRows.filter(healthFieldQueuePendingV2042):rawPageRows;
  healthPeople=append?[...healthPeople,...pageRows]:pageRows;healthPageOffset=usedAssignmentRpc?(Number(requestArgs.p_offset||0)+rawPageRows.length):healthPeople.length;healthHasMore=usedAssignmentRpc?Boolean(pageResult?.has_more):false;
  $('#health-person-body').innerHTML=healthPeople.map((p,i)=>{
    const status=p.latest_ncd_status||(p.known_ncd?'มี DM/HT เดิม':'ยังไม่มีผล');
    const fallback=p.assignment_status==='staff_fallback';
    const assignment=fallback?`<small class="assignment-fallback">${esc(p.assignment_label||'ยังไม่มีผู้รับผิดชอบ · Staff ดูแลชั่วคราว')}</small>`:(currentProfile?.role==='staff'&&careScopeMode==='community'&&p.assignment_status==='assigned'?'<small class="assignment-ok">มีผู้รับผิดชอบ</small>':'');
    return `<tr><td><button type="button" class="health-person-name" data-health-person="${i}">${esc(p.display_name)}</button><small>${p.known_ncd?`โรคเดิม: ${p.has_ht?'HT ':''}${p.has_dm?'DM':''}`:'ยังไม่พบ DM/HT ใน personchronic'}</small></td><td>${esc(p.age_years??'—')} ปี<small>${esc(p.life_stage||'—')}</small></td><td>บ้าน ${esc(p.house_no||p.hcode)}<small>หมู่ ${esc(p.moo||'—')} · ${esc(p.community||'—')}</small>${assignment}</td><td class="${healthClass(p.latest_severity)}">${esc(status)}<small>${p.latest_screened_on?esc(healthDateLabel(p.latest_screened_on)):''}</small></td><td><button type="button" class="row-open" data-phc190-screen data-pcucode="${esc(p.source_pcucode)}" data-pid="${esc(p.source_pid)}" data-name="${esc(p.display_name)}" data-plan-date="${esc(p.screening_plan_date||'')}" data-age-years="${esc(p.age_years??'')}" data-age-months="${esc(p.screening_age_months??'')}" data-screen-route="${esc(p.screening_route||'')}" data-route-label="${esc(p.screening_route_label||'')}" data-dspm-target="${esc(p.screening_dspm_target_months??'')}" data-latest-screened="${esc(p.latest_screened_on||'')}">คัดกรอง</button></td></tr>`;
  }).join('')||'<tr><td colspan="5">ไม่พบประชาชนตามตัวกรอง</td></tr>';
  const fallbackNote=healthAssignmentFilter==='fallback'?' · แสดงเฉพาะประชาชนที่ Staff ต้องดูแลแทน':healthAssignmentFilter==='unresolved'?' · คิวไม่ทราบชุมชนสำหรับ Admin ตรวจสอบ':'';
  const queueNote=filter==='field_targets'?' · แสดงผู้ที่ยังไม่ได้คัดกรองในรอบงานก่อน':'';
  $('#health-list-note').textContent=`แสดง ${num(healthPeople.length)} ราย · โหลดครั้งละ ${HEALTH_PAGE_SIZE_V2033} ราย${queueNote}${fallbackNote}`;
  const more=$('#health-load-more');if(more){more.hidden=!healthHasMore;more.disabled=false;more.textContent='โหลดรายชื่อเพิ่ม';}
  document.querySelectorAll('[data-health-person]').forEach(b=>b.onclick=()=>selectHealthPerson(Number(b.dataset.healthPerson)));
  })();
  healthLoadSignature=signature;healthLoadPromise=run;
  try{const result=await run;if(requestSequence===healthRequestSequence&&requestEpoch===healthViewEpochV2040&&(allowInactive||portalView==='health')){healthLastCompletedSignature=signature;healthLastCompletedAt=Date.now();traceHealthCoordV2040('complete',requestArgs,trigger);}return result;}
  finally{if(healthLoadPromise===run){healthLoadPromise=null;healthLoadSignature='';}}
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
  const panel=$('#ncd-previous-panel'),grid=$('#ncd-previous-grid'),empty=$('#ncd-previous-empty');
  const has=Boolean(p.previous_screened_on||p.previous_weight_kg||p.previous_height_cm||p.previous_waist_cm||p.previous_sbp||p.previous_dbp||p.previous_glucose_mg_dl||p.previous_bmi);
  panel.hidden=false;
  if(grid)grid.hidden=!has;if(empty)empty.hidden=has;
  if(!has){
    setPreviousText('#ncd-previous-date','ยังไม่พบประวัติเดิม');
    setPreviousText('#ncd-previous-source','ตรวจสอบแล้ว');
    const be=$('#ncd-previous-behavior');if(be){be.hidden=true;be.textContent='';}
    return;
  }
  setPreviousText('#ncd-previous-date',p.previous_screened_on?healthDateLabel(p.previous_screened_on):'มีค่าจากประวัติเดิม');
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

function ncdRequiredComplete(form){
  if(!form)return false;
  const required=['screened_on','weight_kg','height_cm','waist_cm','sbp','dbp','glucose_mg_dl'];
  if(required.some(name=>!String(form.elements[name]?.value||'').trim()))return false;
  if(!form.querySelector('[name="glucose_type"]:checked'))return false;
  const smoke=form.querySelector('[name="smoking_state"]:checked')?.value;
  const alcohol=form.querySelector('[name="alcohol_state"]:checked')?.value;
  if(!smoke||!alcohol||!form.querySelector('[name="exercise_frequency"]:checked'))return false;
  if(smoke==='yes'&&!form.querySelector('[name="smoking_frequency"]:checked'))return false;
  if(alcohol==='yes'&&!form.querySelector('[name="alcohol_frequency"]:checked'))return false;
  return form.checkValidity();
}
function syncNcdSubmitState(form=$('#ncd-form')){
  const button=$('#ncd-submit'),hint=$('#ncd-submit-hint');if(!button||!form)return;
  const ready=ncdRequiredComplete(form);
  button.disabled=!ready;
  button.setAttribute('aria-disabled',String(!ready));
  if(hint)hint.textContent=ready?'ข้อมูลที่จำเป็นครบแล้ว · ตรวจสอบแล้วกดบันทึก':'กรอกข้อมูลที่จำเป็นใน ค่าที่วัด และพฤติกรรม ให้ครบก่อนบันทึก';
}
async function hydratePreviousScreening(p){
  if(!p?.source_pcucode||p?.source_pid==null)return p;
  const dateValue=v=>{const n=Date.parse(String(v||''));return Number.isFinite(n)?n:0;};
  let best={
    screened_on:p.previous_screened_on||null,weight_kg:p.previous_weight_kg,height_cm:p.previous_height_cm,
    waist_cm:p.previous_waist_cm,sbp:p.previous_sbp,dbp:p.previous_dbp,glucose_mg_dl:p.previous_glucose_mg_dl,
    bmi:p.previous_bmi,source:p.previous_source||'',smoking:p.previous_smoking||'',alcohol:p.previous_alcohol||'',exercise:p.previous_exercise||''
  };
  try{
    const {data,error}=await supabase.from('health_persons')
      .select('previous_screened_on,previous_weight_kg,previous_height_cm,previous_waist_cm,previous_sbp,previous_dbp,previous_glucose_mg_dl,previous_bmi,previous_source')
      .eq('source_pcucode',p.source_pcucode).eq('source_pid',Number(p.source_pid)).maybeSingle();
    if(!error&&data&&dateValue(data.previous_screened_on)>=dateValue(best.screened_on))best={...best,
      screened_on:data.previous_screened_on,weight_kg:data.previous_weight_kg,height_cm:data.previous_height_cm,waist_cm:data.previous_waist_cm,
      sbp:data.previous_sbp,dbp:data.previous_dbp,glucose_mg_dl:data.previous_glucose_mg_dl,bmi:data.previous_bmi,source:data.previous_source||'JHCIS / J-Report'};
  }catch{}
  // Test-mode OSM-PHC records remain historical reference only. They never count as FY2570 output,
  // but keeping the latest values visible prevents the field form from appearing to have lost history.
  try{
    const {data,error}=await supabase.from('health_ncd_history')
      .select('screened_on,weight_kg,height_cm,waist_cm,sbp,dbp,glucose_mg_dl,bmi,smoking_frequency,alcohol_frequency,exercise_frequency,source_label,recorded_at')
      .eq('source_pcucode',p.source_pcucode).eq('source_pid',Number(p.source_pid))
      .order('screened_on',{ascending:false}).order('recorded_at',{ascending:false}).limit(1).maybeSingle();
    if(!error&&data&&dateValue(data.screened_on)>=dateValue(best.screened_on))best={
      screened_on:data.screened_on,weight_kg:data.weight_kg,height_cm:data.height_cm,waist_cm:data.waist_cm,
      sbp:data.sbp,dbp:data.dbp,glucose_mg_dl:data.glucose_mg_dl,bmi:data.bmi,source:data.source_label||'อสม. พลัส',
      smoking:data.smoking_frequency||'',alcohol:data.alcohol_frequency||'',exercise:data.exercise_frequency||''};
  }catch{}
  Object.assign(p,{
    previous_screened_on:best.screened_on||null,previous_weight_kg:best.weight_kg??null,previous_height_cm:best.height_cm??null,
    previous_waist_cm:best.waist_cm??null,previous_sbp:best.sbp??null,previous_dbp:best.dbp??null,
    previous_glucose_mg_dl:best.glucose_mg_dl??null,previous_bmi:best.bmi??null,previous_source:best.source||'',
    previous_smoking:best.smoking||'',previous_alcohol:best.alcohol||'',previous_exercise:best.exercise||''
  });
  return p;
}

function syncBehaviorPanels(form){
  const smoke=form.querySelector('[name="smoking_state"]:checked')?.value;
  const alc=form.querySelector('[name="alcohol_state"]:checked')?.value;
  const sw=$('#smoking-frequency-wrap'),aw=$('#alcohol-frequency-wrap');
  sw.hidden=smoke!=='yes';aw.hidden=alc!=='yes';
  const syncFrequency=(name,enabled)=>{const choices=[...form.querySelectorAll(`[name="${name}"]`)];choices.forEach((choice,index)=>{choice.required=enabled&&index===0;if(!enabled)choice.checked=false;});};
  syncFrequency('smoking_frequency',smoke==='yes');syncFrequency('alcohol_frequency',alc==='yes');syncNcdSubmitState(form);
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
  el.className=cvd.eligible?(cvd.riskPercent>=30?'bad':cvd.riskPercent>=20?'attention':cvd.riskPercent>=10?'warn':'good'):'';
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

function syncNcdTestResetV208(){const adminTest=Boolean(currentProfile?.role==='admin'&&preGoLiveTestModeV208());const b=$('#ncd-reset-test'),note=$('#ncd-test-mode-note');if(b)b.hidden=!(adminTest&&selectedHealthPerson);if(note)note.hidden=!adminTest;}
function routeForAgeV208(age){age=Number(age);return age<6?'child_0_5':age<15?'school_6_14':age<35?'youth_15_34':age<60?'ncd_35_59':'elderly_60_plus';}
async function resetSelectedNcdTestV208(){const p=selectedHealthPerson;if(!p||currentProfile?.role!=='admin'||!preGoLiveTestModeV208())return;if(!confirm(`รีเซทข้อมูลทดสอบของ ${p.display_name}?\n\nหากเป็นผู้สูงอายุ ระบบจะรีเซท NCD ทดสอบและ 9 ด้านของช่วงทดสอบร่วมกัน ประวัติเดิมจาก JHCIS / J-Report / 3Doctor จะไม่ถูกลบ`))return;const b=$('#ncd-reset-test');if(b)b.disabled=true;try{const {error}=await supabase.rpc('admin_reset_person_test_screening_v2022',{p_source_pcucode:p.source_pcucode,p_source_pid:Number(p.source_pid),p_route:routeForAgeV208(p.age_years),p_reason:'ผู้ใช้กดรีเซทข้อมูลทดสอบจากหน้า NCD'});if(error)throw error;$('#ncd-form').reset();$('#ncd-result').hidden=true;closeHealthFeedbackCard();healthFeedbackModel=null;await Promise.all([loadHealthSummary(),loadHealthPeople({trigger:'reset-test'}),loadHealthHistory()]);const fresh=healthPeople.find(x=>personKey(x)===personKey(p));if(fresh){selectedHealthPerson=fresh;renderPreviousPanel(fresh)}alert('รีเซทข้อมูลทดสอบแล้ว');}catch(e){$('#ncd-error').textContent=e.message;}finally{if(b)b.disabled=false;syncNcdTestResetV208();}}

async function selectHealthPerson(index,forceNcd=false){
  const p=healthPeople[index]; if(!p)return; if(!forceNcd&&window.PHCFiveFeatures190?.openAgeScreening){const seed={plan_date:p.screening_plan_date||'',age_years:Number(p.age_years),age_months:Number(p.screening_age_months),route:p.screening_route||'',route_label:p.screening_route_label||'',dspm_target_months:p.screening_dspm_target_months??null,latest_screened_on:p.latest_screened_on||''};window.PHCFiveFeatures190.openAgeScreening(p.source_pcucode,Number(p.source_pid),p.display_name,seed);return;} await hydratePreviousScreening(p); selectedHealthPerson=p;
  $('#ncd-person-summary').innerHTML=`<strong>${esc(p.display_name)}</strong><span>${esc(p.age_years??'—')} ปี · ${esc(p.gender)} · ${esc(p.community||'—')}</span>`;
  const conditions=[];if(p.has_ht)conditions.push('<span class="condition-badge disease">มีประวัติ HT</span>');if(p.has_dm)conditions.push('<span class="condition-badge disease">มีประวัติ DM</span>');if(!p.known_ncd)conditions.push('<span class="condition-badge clear">ยังไม่พบ DM/HT ใน JHCIS</span>');if(p.has_cvd)conditions.push('<span class="condition-badge disease">มีประวัติ CVD · ไม่ใช้ Thai CV Risk</span>');else if(p.cvd_population_eligible&&Number(p.age_years)>=35&&Number(p.age_years)<=70)conditions.push('<span class="condition-badge clear">Thai CV Risk คำนวณอัตโนมัติ</span>');$('#ncd-condition-badges').innerHTML=conditions.join('');
  const card=$('#ncd-screen-card'); card.hidden=!(Number(p.age_years)>=18); syncNcdTestResetV208(); if(card.hidden){return;}
  const form=$('#ncd-form'); form.reset(); form.elements.screened_on.value=localDate(); form.dataset.requestId=requestId(); $('#ncd-result').hidden=true; healthFeedbackModel=null; closeHealthFeedbackCard(); closeNcdSaveConfirmation(false); $('#ncd-error').textContent=''; setActiveNcdSection('ncd-section-measure',false);
  renderPreviousPanel(p);
  form.elements.height_cm.value=p.previous_height_cm||'';
  setPreviousText('#hint-weight',previousHint(p.previous_weight_kg,'กก.'));setPreviousText('#hint-height',previousHint(p.previous_height_cm,'ซม.'));setPreviousText('#hint-waist',previousHint(p.previous_waist_cm,'ซม.'));setPreviousText('#hint-sbp',previousHint(p.previous_sbp));setPreviousText('#hint-dbp',previousHint(p.previous_dbp));setPreviousText('#hint-glucose',previousHint(p.previous_glucose_mg_dl,'mg/dL'));
  bindMeasurementControls(form);
  form.querySelectorAll('[data-range-for]').forEach(range=>{const input=form.elements[range.dataset.rangeFor];if(input?.value)range.value=String(Math.min(Number(range.max),Math.max(Number(range.min),Number(input.value))));});
  const previousBody=$('#ncd-use-previous-body'),hasPreviousBody=[p.previous_weight_kg,p.previous_height_cm,p.previous_waist_cm].some(v=>v!==null&&v!==undefined&&v!=='');
  previousBody.hidden=false;previousBody.disabled=!hasPreviousBody;previousBody.textContent=hasPreviousBody?'ใช้ส่วนสูง น้ำหนัก และรอบเอวครั้งก่อน':'ยังไม่มีส่วนสูง น้ำหนัก และรอบเอวครั้งก่อน';
  previousBody.onclick=()=>{if(!hasPreviousBody)return;[['weight_kg',p.previous_weight_kg],['height_cm',p.previous_height_cm],['waist_cm',p.previous_waist_cm]].forEach(([name,value])=>{if(value!==null&&value!==undefined&&value!=='')setMeasurementValue(form,name,value);});syncNcdSubmitState(form);};
  syncBehaviorPanels(form);renderNcdPreview();renderMental2QPreview();syncNcdSubmitState(form);
  form.querySelectorAll('input,select').forEach(el=>{el.oninput=()=>{renderNcdPreview();renderMental2QPreview();syncNcdSubmitState(form);};el.onchange=()=>{renderNcdPreview();renderMental2QPreview();syncNcdSubmitState(form);};});
  card.scrollIntoView({behavior:'smooth',block:'start'});
}
function closeNcdSaveConfirmation(restoreFocus=true){
  const dialog=$('#ncd-save-confirmation');if(!dialog)return;dialog.hidden=true;if(restoreFocus)$('#ncd-submit')?.focus();
}
function showNcdSaveConfirmation(){
  const dialog=$('#ncd-save-confirmation');if(!dialog)return;dialog.hidden=false;$('#ncd-save-confirmation-ok')?.focus();
}
function showHealthFieldStatus(saved,person){
  const box=$('#health-field-status');if(!box)return;
  if(healthFieldStatusTimer){clearTimeout(healthFieldStatusTimer);healthFieldStatusTimer=null;}
  const severity=String(saved?.severity||'');
  const tone=['urgent','alert'].includes(severity)?'danger':severity==='risk'?'warn':'success';
  const suffix=tone==='danger'?' · พบผลเร่งด่วน กรุณาประสานเจ้าหน้าที่':tone==='warn'?' · พบความเสี่ยง ระบบบันทึกงานติดตามแล้ว':' · พร้อมคัดกรองรายถัดไป';
  box.dataset.tone=tone;box.textContent=`บันทึก ${person?.display_name||'รายการนี้'} เรียบร้อย${suffix}`;box.hidden=false;
  healthFieldStatusTimer=setTimeout(()=>{if(box){box.hidden=true;box.textContent='';delete box.dataset.tone;}healthFieldStatusTimer=null;},tone==='danger'?7000:4200);
}
async function resetHealthWorkQueueV2042({refresh=false}={}){
  const search=$('#health-search'),filter=$('#health-filter');
  if(search)search.value='';if(filter)filter.value='field_targets';healthPageOffset=0;syncHealthTargetButtons();
  if(refresh&&healthLoaded&&portalView==='health')await loadHealthPeople({trigger:'work-queue-reset'});
}
function returnToHealthWorklist(saved,person){
  closeNcdSaveConfirmation(false);closeHealthFeedbackCard();healthFeedbackModel=null;
  const card=$('#ncd-screen-card');if(card)card.hidden=true;selectedHealthPerson=null;
  const search=$('#health-search'),filter=$('#health-filter');if(search)search.value='';if(filter)filter.value='field_targets';healthPageOffset=0;syncHealthTargetButtons();
  showHealthFieldStatus(saved,person);
  if(Number(person?.age_years)>=60&&window.PHCFiveFeatures190?.openAgeScreening){
    const box=$('#health-field-status');if(box&&!box.hidden)box.textContent+=' · ไปต่อคัดกรองผู้สูงอายุ 9 ด้าน';
    setTimeout(()=>window.PHCFiveFeatures190.openAgeScreening(person.source_pcucode,Number(person.source_pid),person.display_name,{plan_date:localDate(),age_years:Number(person.age_years),age_months:Number(person.screening_age_months??(Number(person.age_years)*12)),route:'elderly_60_plus',route_label:'NCD Screening ก่อน แล้วทำผู้สูงอายุ 9 ด้าน',dspm_target_months:null,ncd_status:'complete',latest_screened_on:localDate()}),80);
    return;
  }
  const list=$('#health-person-list')||$('#health-worklist-start');
  requestAnimationFrame(()=>{list?.scrollIntoView({behavior:'smooth',block:'start'});setTimeout(()=>document.querySelector('#health-person-body .row-open')?.focus({preventScroll:true}),350);});
}
async function refreshHealthAfterSaveV2022(){
  invalidateHealthWorklistCache();invalidateShared('report-snapshot:');invalidateShared('assignment-summary:');
  try{await loadHealthPeople({force:true,trigger:'post-save'});}catch(e){console.warn('[NCD post-save refresh] รายชื่อ',e);}
  setTimeout(()=>loadHealthHistory().catch(e=>console.warn('[NCD post-save refresh] ประวัติ',e)),1400+Math.floor(Math.random()*1200));
  if(portalView==='work')setTimeout(()=>loadHealthSummary().catch(e=>console.warn('[NCD post-save refresh] สรุปผลงาน',e)),500+Math.floor(Math.random()*700));
}
async function saveHealthScreening(event){
  event.preventDefault(); const form=event.currentTarget,error=$('#ncd-error'),result=$('#ncd-result'),button=$('#ncd-submit');
  error.textContent=''; result.hidden=true; if(!selectedHealthPerson){error.textContent='กรุณาเลือกประชาชนจากรายการงาน';return;}
  syncNcdSubmitState(form);if(!ncdRequiredComplete(form)){error.textContent='กรุณากรอกข้อมูลที่จำเป็นให้ครบก่อนบันทึก';form.reportValidity();return;}
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
    const {data:saved,error:saveError}=await supabase.rpc('save_health_ncd_screening_v4',payload);if(saveError)throw saveError;
    invalidateHealthWorklistCache();invalidateShared('report-snapshot:');invalidateShared('assignment-summary:');
    // A successful RPC is the commit boundary. Post-save reporting refresh must never turn a saved record into a red error.
    form.dataset.requestId=requestId();form.reset();result.hidden=true;returnToHealthWorklist(saved,p);
    setTimeout(()=>{refreshHealthAfterSaveV2022().catch(e=>console.warn('[NCD post-save refresh]',e));},Number(p?.age_years)>=60?1200:80);
  }catch(e){error.textContent=e.message;}finally{button.disabled=false;}
}
async function loadHealthModule(){
  const focus=$('#health-community-focus');focus.hidden=!healthCommunityFocus;focus.querySelector('strong').textContent=healthCommunityFocus||'';
  if(!healthLoaded)$('#health-filter').value='field_targets';
  $('#health-target-scope-note').textContent=currentProfile?.role==='staff'?(careScopeMode==='community'?`ชุมชน ${currentProfile.community||'ที่ได้รับมอบหมาย'} · รวมประชาชนที่ Staff ต้องดูแลแทน`:careScopeMode==='volunteer'?'งานของ อสม. ที่เลือกในชุมชนเดียวกัน':'บ้านและประชาชนที่ฉันรับผิดชอบ') : currentProfile?.role==='user'?'บ้านในความรับผิดชอบ · แสดงงานที่ผูกไว้ก่อน':'ทุกพื้นที่ · เลือกดูเป้าหมายทั้งหมดได้';
  syncHealthAssignmentControl();
  syncHealthTargetButtons();
  if(currentProfile?.role==='admin')loadHealthTargetSettingsV2026().catch(e=>{const x=$('#health-target-admin-status');if(x)x.textContent=e.message;});
  const targetBody=$('#health-person-body');if(targetBody&&!targetBody.children.length)targetBody.innerHTML='<tr><td colspan="5">กำลังโหลดรายชื่อเป้าหมาย…</td></tr>';
  await loadHealthPeople({trigger:'module-init'}); healthLoaded=true;
  // Health field work must become interactive first; history is secondary and staggered to avoid concurrent spikes.
  setTimeout(()=>loadHealthHistory().catch(e=>console.warn('[health history]',e)),1600+Math.floor(Math.random()*1400));
  bindNcdSectionNav();
  $('#ncd-form').onsubmit=saveHealthScreening; $('#ncd-close').onclick=async()=>{closeNcdSaveConfirmation(false);closeHealthFeedbackCard();healthFeedbackModel=null;$('#ncd-screen-card').hidden=true;selectedHealthPerson=null;try{await resetHealthWorkQueueV2042({refresh:true});}catch(e){$('#health-list-note').textContent=e.message;}};
  $('#ncd-clear-2q').onclick=()=>{$('#ncd-form').querySelectorAll('[name^="mental_2q_"]').forEach(el=>{el.checked=false;});renderMental2QPreview();};
  $('#ncd-reset-test').onclick=resetSelectedNcdTestV208;syncNcdTestResetV208();
  const saveConfirmation=$('#ncd-save-confirmation');$('#ncd-save-confirmation-ok').onclick=()=>{closeNcdSaveConfirmation(false);viewHealthFeedback();};$('#ncd-save-confirmation-close').onclick=()=>closeNcdSaveConfirmation();saveConfirmation.onclick=e=>{if(e.target===saveConfirmation)closeNcdSaveConfirmation();};saveConfirmation.onkeydown=e=>{if(e.key==='Escape')closeNcdSaveConfirmation();};
  $('#health-feedback-share').onclick=shareHealthFeedback;$('#health-feedback-close').onclick=closeHealthFeedbackCard;
  bindHealthPerformanceControls();
  $('#health-clear-community').onclick=async()=>{healthCommunityFocus='';focus.hidden=true;await scheduleHealthPeopleLoad(160,'community-focus');};
  $('#health-view-linked-targets').onclick=()=>setHealthTargetFilter('field_targets'); $('#health-view-all-targets').onclick=()=>setHealthTargetFilter('targets');
  $('#health-filter').onchange=()=>{syncHealthTargetButtons();return scheduleHealthPeopleLoad(160,'filter');}; $('#health-stage').onchange=()=>scheduleHealthPeopleLoad(160,'stage');
  const assignmentSelect=$('#health-assignment');if(assignmentSelect)assignmentSelect.onchange=()=>{healthAssignmentFilter=assignmentSelect.value||'all';return scheduleHealthPeopleLoad(160,'assignment');};
  const loadMore=$('#health-load-more');if(loadMore)loadMore.onclick=async()=>{loadMore.disabled=true;loadMore.textContent='กำลังโหลด…';try{await loadHealthPeople({append:true,trigger:'pagination'});}catch(e){$('#health-list-note').textContent=e.message;loadMore.disabled=false;}};
  $('#health-search').oninput=()=>{clearTimeout(healthSearchTimer);healthSearchTimer=setTimeout(()=>loadHealthPeople({trigger:'search'}).catch(e=>$('#health-list-note').textContent=e.message),300);};
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

async function monitoredCloudSignIn(email,password){
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),15000);
  try{
    const res=await fetch(`${SUPABASE_URL}/functions/v1/cloud-login`,{
      method:'POST',
      headers:{'content-type':'application/json','apikey':SUPABASE_PUBLISHABLE_KEY,'x-client-info':'osm-phc-web/2.0.45'},
      body:JSON.stringify({email,password}),
      signal:controller.signal,
    });
    const payload=await res.json().catch(()=>({}));
    if(!res.ok){
      const code=String(payload?.error||'');
      if(code==='INVALID_CREDENTIALS')return {data:null,error:new Error('INVALID_CREDENTIALS')};
      if(res.status===429)return {data:null,error:new Error('AUTH_RATE_LIMITED')};
      return {data:null,error:new Error('AUTH_SERVICE_UNAVAILABLE')};
    }
    if(!payload.access_token||!payload.refresh_token)return {data:null,error:new Error('AUTH_SESSION_MISSING')};
    return supabase.auth.setSession({access_token:payload.access_token,refresh_token:payload.refresh_token});
  }catch(error){
    return {data:null,error:new Error(error?.name==='AbortError'?'AUTH_TIMEOUT':'AUTH_SERVICE_UNAVAILABLE')};
  }finally{clearTimeout(timer);}
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
      const action=button.dataset.communityAction;if(action==='health'){healthCommunityFocus=row.community;setPortalView('health');try{if(!healthLoaded)await loadHealthModule();else{const focus=$('#health-community-focus');focus.hidden=false;focus.querySelector('strong').textContent=healthCommunityFocus;await loadHealthPeople({trigger:'community-focus'});}}catch(e){$('#health-list-note').textContent=e.message;}return;}
      workspace.querySelectorAll('[data-community-action]').forEach(x=>x.classList.toggle('active',x===button));workspace.querySelectorAll('[data-community-view]').forEach(x=>x.hidden=x.dataset.communityView!==action);
    });
  }catch(error){if(request===communityRequestId)workspace.innerHTML=`<p class="error">${esc(error.message)}</p>`;}
}

const PORTAL_QUERY_BUDGET_MS_V2029=2500;
async function safePortalQueryV2029(label,promise,fallback=[]){
  let timer=null;
  try{
    const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('PORTAL_QUERY_BUDGET_EXCEEDED')),PORTAL_QUERY_BUDGET_MS_V2029);});
    const result=await Promise.race([promise,timeout]);
    if(result?.error)throw result.error;
    return result?.data??fallback;
  }catch(error){console.warn(`[portal ${label}]`,error?.message||error);return fallback;}
  finally{if(timer)clearTimeout(timer);}
}
function summarizeMyHousesV2029(rows,fallbackCommunity=''){
  const map=new Map();
  for(const h of rows||[]){
    const community=String(h.community||fallbackCommunity||'ไม่ระบุ').trim()||'ไม่ระบุ';
    if(!map.has(community))map.set(community,{community,moo:h.moo||null,houses:0,assigned_houses:0,review_houses:0,outside_tambon:0,missing_coordinates:0,volunteers_with_work:1});
    const x=map.get(community);x.houses+=1;x.assigned_houses+=h.volunteer_pid!=null?1:0;x.review_houses+=h.review_required?1:0;x.missing_coordinates+=(h.latitude==null||h.longitude==null)?1:0;
  }
  return [...map.values()];
}

async function getProfile(userId){
  let lastError=null;
  for(let attempt=0;attempt<2;attempt++){
    const {data,error}=await supabase.from('profiles').select('user_id,display_name,role,community,volunteer_pid,active,must_change_password').eq('user_id',userId).maybeSingle();
    if(!error)return data;
    lastError=error;
    if(!String(error?.message||'').toLowerCase().includes('statement timeout')||attempt===1)break;
    await new Promise(resolve=>setTimeout(resolve,220));
  }
  throw lastError||new Error('ไม่สามารถอ่านโปรไฟล์ได้');
}

async function loadPortal(session, requestId){
  const profile = await getProfile(session.user.id);
  if(requestId !== authRequestId || passwordPanelOpen) return;
  currentProfile = profile;
  setSharedSession(session);
  setSharedProfile(profile);
  if(!profile || !profile.active){
    renderAuthView('blocked'); return;
  }
  if(profile.role==='staff'){
    try{const saved=localStorage.getItem('phc.care.scope')||localStorage.getItem('phc.field.scope');careScopeMode=['self','volunteer','community'].includes(saved)?saved:'self';careScopeVolunteerPid=Number(localStorage.getItem('phc.care.volunteer'))||null;}
    catch{careScopeMode='self';}
    try{await loadStaffVolunteerOptionsV2033();}catch{if(careScopeMode==='volunteer')careScopeMode='self';}
  }else careScopeMode=profile.role==='admin'?'all':'self';
  healthAssignmentFilter='all';
  let master=[],communities=[],workload=[],myHouses=[];
  if(profile.role==='admin'){
    [master,communities,workload]=await Promise.all([
      safePortalQueryV2029('communities',supabase.from('communities').select('name,moo,active').eq('active',true).order('moo').order('name'),[]),
      safePortalQueryV2029('community summary',supabase.from('community_report_summary').select('*').order('community'),[]),
      safePortalQueryV2029('volunteer workload',supabase.from('volunteer_workload').select('*').order('community').order('display_name'),[])
    ]);
  }else{
    let masterQuery=supabase.from('communities').select('name,moo,active').eq('active',true);
    if(profile.community)masterQuery=masterQuery.eq('name',profile.community);
    const fallbackMaster=profile.community?[{name:profile.community,moo:null,active:true}]:[];
    const houseKey=`my-household-cards-v2039:${profile.user_id}:${profile.volunteer_pid||''}`;
    const housePromise=profile.volunteer_pid!=null?safePortalQueryV2029('my houses',sharedCall(houseKey,()=>supabase.rpc('my_household_cards_v1860'),HOUSEHOLD_CACHE_MS_V2039),[]):Promise.resolve([]);
    if(profile.role==='staff'){
      let summaryQuery=supabase.from('community_report_summary').select('*');
      let workloadQuery=supabase.from('volunteer_workload').select('*');
      if(profile.community){summaryQuery=summaryQuery.eq('community',profile.community);workloadQuery=workloadQuery.eq('community',profile.community);}
      [master,myHouses,communities,workload]=await Promise.all([
        safePortalQueryV2029('communities',masterQuery,fallbackMaster),housePromise,
        safePortalQueryV2029('staff community summary',summaryQuery,[]),
        safePortalQueryV2029('staff volunteer workload',workloadQuery,[])
      ]);
      if(!master.length)master=fallbackMaster;
      if(!communities.length&&myHouses.length)communities=summarizeMyHousesV2029(myHouses,profile.community);
    }else{
      // User bootstrap stays to one scoped household RPC after profile; community metadata is already present on the profile/houses.
      master=fallbackMaster;
      myHouses=await housePromise;
      communities=summarizeMyHousesV2029(myHouses,profile.community);
      workload=[];
    }
  }
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
  $('#scope-label').textContent = profile.role==='admin' ? 'ทุก 16 ชุมชนในระบบ' : profile.role==='staff' ? `อสม.ในพื้นที่รับผิดชอบ · ประธานชุมชน ${profile.community||'ยังไม่ได้กำหนดชุมชน'}` : 'บ้านและประชาชนในความรับผิดชอบของคุณ';
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
  document.dispatchEvent(new CustomEvent('phc:auth-ready',{detail:{userId:session.user.id,role:profile.role,view:portalView}}));
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
  const { data, error } = await monitoredCloudSignIn(email,String(f.get('password')||''));
  if(error){
    $('#login-error').textContent = error.message==='INVALID_CREDENTIALS'?'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง':error.message==='AUTH_RATE_LIMITED'?'ลองเข้าสู่ระบบหลายครั้งเกินไป กรุณารอสักครู่':'ระบบเข้าสู่ระบบไม่พร้อม กรุณาลองใหม่';
    return;
  }
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
document.addEventListener('phc:care-scope-changed',async event=>{
  if(event.detail?.source==='performance')return;
  const previousScope=careScopeMode,previousOwner=careScopeVolunteerPid,previousAssignment=healthAssignmentFilter,previousEffectiveOwner=previousScope==='volunteer'?Number(previousOwner||0):0;
  const next=event.detail?.scope;careScopeMode=['self','volunteer','community','all'].includes(next)?next:'self';const incomingOwner=Number(event.detail?.volunteer_pid)||null;if(incomingOwner)careScopeVolunteerPid=incomingOwner;
  if(currentProfile?.role==='user')careScopeMode='self';
  if(currentProfile?.role==='admin')careScopeMode='all';
  if(careScopeMode!=='community')healthAssignmentFilter='all';
  const nextEffectiveOwner=careScopeMode==='volunteer'?Number(careScopeVolunteerPid||0):0;
  const changed=previousScope!==careScopeMode||previousEffectiveOwner!==nextEffectiveOwner||previousAssignment!==healthAssignmentFilter;
  if(!changed)return;
  if(currentProfile?.role==='staff'){try{localStorage.setItem('phc.care.scope',careScopeMode);localStorage.setItem('phc.field.scope',careScopeMode);if(careScopeVolunteerPid)localStorage.setItem('phc.care.volunteer',String(careScopeVolunteerPid));}catch{}}
  syncPerformanceScopeUI();syncHealthAssignmentControl();
  try{if(healthLoaded&&portalView==='health')await scheduleHealthPeopleLoad(160,'scope-event');}catch{}
});
$('#portal-nav-toggle').addEventListener('click',()=>setPortalNavCollapsed(!$('#portal').classList.contains('nav-collapsed')));
$('#ncd-form').addEventListener('change',event=>{if(event.target.matches('[name="smoking_state"],[name="alcohol_state"]'))syncBehaviorPanels(event.currentTarget);});
restorePortalNavPreference();
enforceCloudReleaseVersion();
configureCloudBrandLogo();
refreshAuth();


window.PHCOpenLegacyNcd190=(pcucode,pid)=>{const i=healthPeople.findIndex(p=>String(p.source_pcucode)===String(pcucode)&&Number(p.source_pid)===Number(pid));if(i<0)return false;const person=healthPeople[i];(async()=>{if(!await confirmRepeatNcdV2033(person))return;await selectHealthPerson(i,true);})().catch(e=>{const x=$('#ncd-error');if(x)x.textContent=e.message;});return true;};
