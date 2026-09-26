import { getSharedSupabase, getSharedProfile, sharedCall, invalidateShared, bindPortalActivation, isPortalViewActive } from './shared-runtime-v2035.mjs?v=2.0.35';
const VERSION=document.querySelector('meta[name="phc-release"]')?.content||'2.0.59';
let supabase=null,profile=null,activeOverlay=null,globalBound=false,toastTimer=null;
const $=(s,r=document)=>r.querySelector(s);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt=v=>{if(!v)return'—';try{return new Intl.DateTimeFormat('th-TH',{dateStyle:'medium'}).format(new Date(v));}catch{return String(v)}};
const wait=ms=>new Promise(r=>setTimeout(r,ms));
const GO_LIVE_V208='2026-10-01';
const thaiDayV208=()=>new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Bangkok'});
const preGoLiveV208=()=>thaiDayV208()<GO_LIVE_V208;

const ADMIN_WORK_CACHE_MS_V2057=15000;
let adminWorkLoadSeqV2057=0;
function adminWorkAliveV2057(root,seq){return seq===adminWorkLoadSeqV2057&&document.body.contains(root)&&isPortalViewActive('work');}
function renderAdminWorkShellV2057(root){
  root.innerHTML=`<h3>ศูนย์ปฏิบัติการ v${VERSION}</h3><div class="phc190-kpis"><div class="phc190-kpi"><small>คำขอเพิ่มสมาชิก</small><strong data-admin-member-kpi>…</strong></div><div class="phc190-kpi"><small>เชื่อม LINE</small><strong data-admin-line-kpi>…</strong></div><div class="phc190-kpi"><small>ส่ง LINE ไม่สำเร็จ</small><strong data-admin-line-failed>…</strong></div></div><div class="phc190-note" data-admin-line-self><strong>LINE ของบัญชีผู้ดูแล</strong><br>กำลังโหลดสถานะ…</div><div data-admin-next-appointment></div><div class="phc190-actions"><button class="phc190-primary" data-admin-requests>ตรวจคำขอสมาชิก</button><button class="phc190-secondary" data-admin-field-house-cancel>จัดการบ้านที่รอ JHCIS</button><button class="phc190-primary" data-admin-line>LINE / นัดหมาย</button><span data-admin-line-action><button class="phc190-secondary" disabled>กำลังโหลด LINE…</button></span></div><button class="phc190-secondary" data-admin-youth-campaign>ตั้งค่าคัดกรองเสริม 15–34 ปี</button><button class="phc190-secondary" data-admin-notices disabled>แจ้งเตือนล่าสุด …</button><div data-admin-test-reset></div><div class="phc190-note">Telegram ใช้เฉพาะ Admin event ผ่าน server worker และไม่ส่งข้อมูลส่วนบุคคลละเอียดในข้อความ</div>`;
  root.querySelector('[data-admin-requests]').onclick=renderAdminMemberQueue;
  root.querySelector('[data-admin-field-house-cancel]').onclick=renderAdminPendingHouseQueueV2070;
  root.querySelector('[data-admin-line]').onclick=openAdminCommunication;
  root.querySelector('[data-admin-youth-campaign]').onclick=openYouthCampaignSettingsV206;
  root.querySelector('[data-admin-notices]').onclick=()=>showNotifications(root.__adminNoticesV2057||[]);
}
function paintAdminLineSelfV2057(root,data){
  const connected=Boolean(data?.connected),note=root.querySelector('[data-admin-line-self]'),action=root.querySelector('[data-admin-line-action]'),appt=root.querySelector('[data-admin-next-appointment]');
  if(note)note.innerHTML=`<strong>LINE ของบัญชีผู้ดูแล</strong><br>${connected?'✅ เชื่อมแล้ว · ใช้ LINE Login ได้':'⚪ ยังไม่ได้เชื่อม · ยังใช้รหัสผ่านปกติได้'}`;
  if(appt)appt.innerHTML=appointmentCardV205(data?.next_appointment);
  if(action){action.innerHTML=connected?'<button class="phc190-secondary" data-admin-unlink-my-line>ยกเลิก LINE ของฉัน</button>':'<button class="phc190-secondary" data-admin-link-my-line>เชื่อม LINE ของฉัน</button>';action.querySelector('[data-admin-link-my-line]')?.addEventListener('click',createLineCode);action.querySelector('[data-admin-unlink-my-line]')?.addEventListener('click',async()=>{if(!confirm('ยืนยันยกเลิกการเชื่อม LINE ของบัญชีผู้ดูแลนี้?'))return;await supabase.rpc('unlink_my_line_v190');invalidateShared('my-line-status-v190');await renderOverview()});}
  bindAppointmentResponseV205(root);
}
function paintAdminTestResetV2057(root,x){
  const host=root.querySelector('[data-admin-test-reset]');if(!host||!x?.reset_open)return;
  host.innerHTML=`<section class="phc190-note phc190-warning"><strong>ข้อมูลทดสอบก่อน 1 ต.ค. 2569</strong><br>Session ${x.sessions||0} · NCD ${x.ncd||0} · Growth ${x.growth||0} · พัฒนาการ ${x.child_development||0} · 2Q ${x.mental_2q||0} · 9 ด้าน ${x.elderly_domains||0}<button type="button" class="phc190-secondary phc190-danger" style="width:100%;margin-top:8px" data-admin-reset-all-test>รีเซ็ตผลคัดกรองในแอปทั้งหมด</button></section>`;
  host.querySelector('[data-admin-reset-all-test]').onclick=async()=>{if(!confirm('รีเซ็ตผลคัดกรองที่บันทึกผ่านหน้าแอปบน Cloud ทั้งหมดก่อน 1 ต.ค. 2569?\n\nจะเก็บ Archive ก่อนล้าง · ไม่ลบประชากร บ้าน อสม. บัญชี LINE, JHCIS, J-Report, 3Doctor หรือประวัติเดิม'))return;const reason=prompt('ระบุเหตุผลการรีเซ็ต','เตรียมระบบก่อนเปิดใช้จริง 1 ต.ค. 2569')||'';if(reason.trim().length<5){showPhcToast('กรุณาระบุเหตุผลอย่างน้อย 5 ตัวอักษร','warn');return}try{const {data,error}=await supabase.rpc('admin_reset_cloud_app_screenings_v2141',{p_reason:reason.trim()});if(error)throw error;showPhcToast(`รีเซ็ตผลคัดกรองในแอปแล้ว · Archive ${data?.archived_rows||0} รายการ`,'success',3200);await renderOverview()}catch(e){showPhcToast(friendlyError(e),'warn',3500)}};
}
async function renderAdminWorkProgressiveV2057(root){
  const seq=++adminWorkLoadSeqV2057;renderAdminWorkShellV2057(root);
  const member=sharedCall('admin-work-member-v2109',()=>supabase.rpc('admin_pending_member_requests_v2109'),ADMIN_WORK_CACHE_MS_V2057);
  const line=sharedCall('admin-work-line-v2057',()=>supabase.rpc('admin_line_overview_v190'),ADMIN_WORK_CACHE_MS_V2057);
  const notices=sharedCall('admin-work-notices-v2057',()=>supabase.rpc('admin_notification_center_v190',{p_limit:5}),ADMIN_WORK_CACHE_MS_V2057);
  const myLine=loadMyLineStatusV2038();
  const reset=preGoLiveV208()?sharedCall('admin-work-reset-v2057',()=>supabase.rpc('admin_cloud_app_screening_reset_preview_v2141'),ADMIN_WORK_CACHE_MS_V2057):Promise.resolve({data:null,error:null});
  member.then(r=>{if(!adminWorkAliveV2057(root,seq))return;const e=root.querySelector('[data-admin-member-kpi]');if(e)e.textContent=r.error?'—':String(r.data?.length||0)});
  line.then(r=>{if(!adminWorkAliveV2057(root,seq))return;const a=root.querySelector('[data-admin-line-kpi]'),b=root.querySelector('[data-admin-line-failed]');if(a)a.textContent=r.error?'—':String(r.data?.line_connected||0);if(b)b.textContent=r.error?'—':String(r.data?.message_failed||0)});
  notices.then(r=>{if(!adminWorkAliveV2057(root,seq))return;root.__adminNoticesV2057=r.error?[]:(r.data||[]).filter(n=>!n.read_at);const b=root.querySelector('[data-admin-notices]');if(b){b.disabled=false;b.textContent=`แจ้งเตือนล่าสุด ${root.__adminNoticesV2057.length}`}});
  myLine.then(r=>{if(!adminWorkAliveV2057(root,seq))return;if(r.error){const n=root.querySelector('[data-admin-line-self]');if(n)n.textContent='ยังโหลดสถานะ LINE ไม่ได้';return}paintAdminLineSelfV2057(root,r.data||{})});
  reset.then(r=>{if(adminWorkAliveV2057(root,seq)&&!r.error)paintAdminTestResetV2057(root,r.data||null)});
}

function injectStyle(){if($('#phc190-style'))return;const s=document.createElement('style');s.id='phc190-style';s.textContent=`
.phc190-screen-button,.phc190-primary,.phc190-secondary,.phc190-state{min-height:56px;border-radius:14px;border:2px solid #bcd5cc;background:#fff;color:#174f45;font:inherit;font-weight:900;padding:10px 14px;cursor:pointer}.phc190-primary{background:#0d7766;border-color:#0d7766;color:#fff}.phc190-danger{background:#fff0ed!important;border-color:#dda79d!important;color:#8f392f!important}.phc190-screen-button{width:100%;margin-top:9px;background:#e9f6f2;border-color:#9bcdbd}.phc190-request-wrap{display:grid;gap:9px;margin:12px 0;padding:12px;border:2px solid #d4e4de;border-radius:16px;background:#f8fbfa}.phc190-request-head{display:flex;gap:9px;justify-content:space-between;align-items:center}.phc190-request-head h3{margin:0;font-size:1.08rem}.phc190-request-list{display:grid;gap:7px}.phc190-request{padding:10px;border:1px solid #d9e6e1;border-radius:12px;background:#fff}.phc190-request strong{display:block}.phc190-request small{display:block;margin-top:3px;color:#647871}.phc190-status{display:inline-flex;margin-top:7px;padding:5px 8px;border-radius:999px;font-weight:900;font-size:.78rem}.phc190-status.pending{background:#fff3c8;color:#71570e}.phc190-status.verified{background:#e5f6eb;color:#17623f}.phc190-status.needs_correction{background:#fff0df;color:#92520e}.phc190-status.rejected{background:#fde5e3;color:#8f2f29}
.phc190-overlay{position:fixed;inset:0;z-index:7600;background:#0f2822a8;display:flex;align-items:flex-start;justify-content:center;overflow:auto;padding:12px}.phc190-modal{width:min(780px,100%);margin:auto;background:#fff;border-radius:22px;padding:16px;display:grid;gap:13px;box-shadow:0 30px 90px #0006}.phc190-head{display:flex;justify-content:space-between;gap:12px;align-items:start}.phc190-head h2{margin:2px 0 0;font-size:1.35rem}.phc190-close{min-width:58px;min-height:58px;border:0;border-radius:14px;background:#e8f0ed;font-size:1.55rem;font-weight:900}.phc190-note{padding:10px 12px;border-radius:13px;background:#f2f7f5;color:#536c65;line-height:1.5}.phc190-warning{background:#fff6d8;color:#6e5711}.phc190-alert{background:#fff0e6;color:#874710}.phc190-form{display:grid;gap:12px}.phc190-form label{display:grid;gap:6px;font-weight:850}.phc190-form input,.phc190-form textarea{width:100%;min-height:58px;border:2px solid #bed4cc;border-radius:13px;padding:10px 12px;font:inherit;font-size:1rem;background:#fff}
.phc190-line-contact{width:100%;margin:10px 0 4px;background:#e8f7eb;border-color:#9ed1aa;color:#14592e}.phc190-line-unavailable{color:#647871}.phc190-line-compose{margin:8px 0 12px;padding:12px;border:1px solid #c9e0d3;border-radius:12px;background:#f7fcf8}.phc190-line-compose small{color:#536c65}.phc190-line-compose button{width:100%}
 .phc190-birth-grid{display:grid;grid-template-columns:minmax(0,.85fr) minmax(0,1.15fr) minmax(0,1.3fr);gap:8px}
 .phc190-birth-grid label{min-width:0;font-size:.93rem}
 .phc190-form .phc190-birth-grid select,.phc190-form .phc190-birth-grid input{width:100%;min-width:0;min-height:58px;border:2px solid #bed4cc;border-radius:13px;padding:8px;font:inherit;font-size:1rem;background:#fff;color:#23483f}
 .phc190-birth-grid select:focus-visible,.phc190-birth-grid input:focus-visible{outline:3px solid #126f61;outline-offset:2px}
 @media(max-width:380px){.phc190-birth-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.phc190-birth-year{grid-column:1/-1}}
.phc190-form textarea{min-height:90px;resize:vertical}.phc190-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}.phc190-error{color:#a52f28;font-weight:850;min-height:1.2em}.phc190-overview{display:grid;gap:10px;margin:12px 0;padding:13px;border:2px solid #d3e4de;border-radius:18px;background:#f8fbfa}.phc190-overview h3{margin:0}
 .phc190-overview.phc190-overview--line-compact{padding:0;border:0;background:transparent;margin:8px 0;gap:8px}
 .phc190-line-compact{border:1px solid #d4e4de;background:#fbfefd;border-radius:14px;overflow:hidden}
 .phc190-line-compact summary{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:5px 9px;min-height:52px;padding:9px 12px;list-style:none;cursor:pointer;font:inherit;color:#1c5148}
 .phc190-line-compact summary::-webkit-details-marker{display:none}
 .phc190-line-compact summary:focus-visible{outline:3px solid #0d7766;outline-offset:-3px}
 .phc190-line-compact .phc190-line-title{font-weight:850;white-space:nowrap}
 .phc190-line-compact .phc190-line-status{font-size:.84rem;color:#277252;white-space:nowrap}
 .phc190-line-compact .phc190-line-manage{font-size:.82rem;color:#617972;margin-left:auto;white-space:nowrap}
 .phc190-line-compact[open] .phc190-line-manage{color:#0d7766}
 .phc190-line-settings{padding:10px 12px 12px;border-top:1px solid #e3ece8}
 .phc190-line-settings button{min-height:48px;width:100%;font-size:.9rem}
 @media(max-width:380px){.phc190-line-compact summary{font-size:.91rem;padding:8px 10px}.phc190-line-compact .phc190-line-status,.phc190-line-compact .phc190-line-manage{font-size:.76rem}}.phc190-kpis{display:grid;grid-template-columns:repeat(3,1fr);gap:7px}.phc190-kpi{padding:10px;border-radius:12px;background:#fff;border:1px solid #dce7e3;text-align:center}.phc190-kpi small{display:block;color:#6a7d77}.phc190-kpi strong{display:block;font-size:1.2rem;margin-top:4px}.phc190-code{font-size:1.5rem;letter-spacing:.08em;text-align:center;padding:14px;border:2px dashed #8bbbaa;border-radius:14px;background:#f1faf6;font-weight:900}.phc190-route{display:grid;gap:10px}.phc190-step{padding:12px;border:2px solid #d6e5e0;border-radius:15px;background:#fbfcfc}.phc190-step h3{margin:0 0 5px}.phc190-grow{display:grid;grid-template-columns:1fr 1fr;gap:9px}.phc190-timeline{display:grid;gap:6px}.phc190-timeline>div{padding:8px 10px;border-radius:10px;background:#f4f8f7}.phc190-domain-grid{display:grid;gap:9px}.phc190-domain{padding:11px;border:2px solid #d8e5e0;border-radius:14px;background:#fff}.phc190-domain h4{margin:0 0 4px}.phc190-domain p{margin:0 0 8px;color:#667a73}.phc190-state-row{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px}.phc190-state{min-height:50px;padding:7px}.phc190-state.active.normal{background:#e3f5e9;border-color:#7fc198;color:#155d3b}.phc190-state.active.observation{background:#fff0df;border-color:#dfa365;color:#87450e}.phc190-state.active.not_assessed{background:#edf2f0;border-color:#bccbc6;color:#536761}.phc190-observe{display:none;margin-top:9px;padding:9px;border-radius:11px;background:#fff6eb}.phc190-domain[data-status="observation"] .phc190-observe{display:grid;gap:6px}.phc190-observe label{display:flex;gap:7px;align-items:flex-start;font-weight:650}.phc190-observe input[type=checkbox]{width:20px;height:20px;min-height:20px}.phc190-progress{font-weight:900;padding:9px 11px;border-radius:11px;background:#eaf5f1;color:#205d51}.phc190-toast{position:fixed;left:50%;bottom:calc(24px + env(safe-area-inset-bottom));transform:translateX(-50%);z-index:7900;width:min(92vw,460px);display:grid;grid-template-columns:1fr auto;align-items:center;gap:10px;padding:13px 14px;border:2px solid #9ecfbe;border-radius:16px;background:#e7f6ee;color:#155d3b;box-shadow:0 18px 45px #0f282238;font-weight:900}.phc190-toast.warn{background:#fff6d8;border-color:#ead58e;color:#806000}.phc190-toast button{min-width:70px;min-height:48px;border:0;border-radius:11px;background:#ffffffb8;color:inherit;font:inherit;font-weight:900}.phc190-save-result{margin-top:9px}

.phc207-wizard{display:grid;gap:10px}.phc207-stepbar{position:sticky;top:0;z-index:4;background:#fff;padding:8px 0 10px;border-bottom:1px solid #e1ece8}.phc207-step-tabs{display:grid;grid-template-columns:repeat(9,1fr);gap:5px}.phc207-step-tab{min-width:0;min-height:42px;border:2px solid #d4e2dd;border-radius:12px;background:#f7faf9;color:#667a73;font:inherit;font-weight:900;padding:4px;cursor:pointer}.phc207-step-tab.current{border-color:#0d7766;background:#e5f5ef;color:#0d6658}.phc207-step-tab.done{border-color:#7fc198;background:#e3f5e9;color:#155d3b}.phc207-step-tab.risk{border-color:#dfa365;background:#fff0df;color:#87450e}.phc207-step-tab.urgent{border-color:#d77f78;background:#fde7e5;color:#8b2c29}.phc207-step-title{display:flex;gap:10px;align-items:center}.phc207-step-title .icon{font-size:2rem}.phc207-step-title h3{margin:0}.phc207-step-title small{display:block;color:#6a7d77;margin-top:2px}.phc207-question{display:grid;gap:9px;padding:13px;border:2px solid #d9e7e2;border-radius:15px;background:#fff}.phc207-question>p{margin:0;line-height:1.55;font-weight:750}.phc207-choice-row{display:grid;grid-template-columns:1fr 1fr;gap:7px}.phc207-choice{min-height:54px;border:2px solid #c8d9d3;border-radius:13px;background:#fff;color:#304f48;font:inherit;font-weight:900;padding:8px 10px;cursor:pointer}.phc207-choice.active{border-color:#0d7766;background:#e5f5ef;color:#0d6658}.phc207-choice-grid{display:grid;grid-template-columns:1fr 1fr;gap:7px}.phc207-number{width:100%;min-height:54px;border:2px solid #bed4cc;border-radius:13px;padding:9px 11px;font:inherit}.phc207-timer{display:grid;grid-template-columns:1fr 1fr;gap:7px;align-items:center}.phc207-timer-display{padding:12px;border-radius:13px;background:#f2f7f5;text-align:center;font-size:1.2rem;font-weight:900}.phc207-nav{position:sticky;bottom:0;z-index:4;display:grid;grid-template-columns:1fr 1.4fr;gap:8px;background:#fff;padding:10px 0 max(4px,env(safe-area-inset-bottom));border-top:1px solid #e1ece8}.phc207-result{padding:10px 12px;border-radius:13px;background:#e8f6ef;color:#155d3b;font-weight:850}.phc207-result.risk{background:#fff0df;color:#87450e}.phc207-result.urgent{background:#fde7e5;color:#8b2c29}.phc207-summary{display:grid;gap:7px}.phc207-summary-row{display:grid;grid-template-columns:1fr auto;gap:10px;align-items:center;padding:10px 12px;border:1px solid #dbe7e3;border-radius:12px}.phc207-summary-row strong{font-size:.95rem}.phc207-summary-row span{font-weight:900}.phc207-summary-row.normal span{color:#17623f}.phc207-summary-row.risk span{color:#92520e}.phc207-summary-row.urgent span{color:#9b2c28}.phc207-source{font-size:.82rem;color:#667a73;line-height:1.45}.phc207-miniwords{display:flex;gap:7px;flex-wrap:wrap}.phc207-miniwords span{padding:7px 10px;border-radius:999px;background:#eef6f3;font-weight:900}.phc207-urgent-note{padding:12px;border:2px solid #d77f78;border-radius:14px;background:#fde7e5;color:#8b2c29;font-weight:900;line-height:1.5}
.phc190-modal,[data-phc190-body],.phc190-route,.phc190-step,.phc207-wizard,.phc207-question,.phc207-stepbar,.phc207-step-title,.phc207-nav{min-width:0;max-width:100%;box-sizing:border-box}.phc207-step-title>div{min-width:0;max-width:100%}.phc207-step-title h3,.phc207-step-title small,.phc207-question p,.phc207-question label{max-width:100%;white-space:normal;overflow-wrap:anywhere}.phc207-nav button{min-width:0;width:100%;white-space:normal;padding-left:8px;padding-right:8px}
@media(max-width:700px){.phc190-overlay{padding:0;overflow-x:hidden}.phc190-modal{width:100%;max-width:100vw;min-height:100vh;border-radius:0;margin:0;padding:12px 10px max(22px,env(safe-area-inset-bottom));overflow-x:hidden}.phc190-actions,.phc190-grow{grid-template-columns:1fr}.phc190-primary,.phc190-secondary,.phc190-screen-button{min-height:62px;font-size:1.04rem}.phc190-state-row{grid-template-columns:1fr}.phc190-state{min-height:56px}.phc190-kpis{grid-template-columns:1fr 1fr}.phc190-head h2{font-size:1.25rem}[data-phc190-body],.phc190-route,.phc190-step,.phc207-wizard,.phc207-question{width:100%;max-width:100%;overflow-x:hidden}.phc207-stepbar{margin-left:0;margin-right:0;width:100%;max-width:100%;overflow:hidden}.phc207-step-tabs{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:6px;overflow:visible;padding:2px 0 6px}.phc207-step-tab{width:100%;min-width:0;min-height:46px;border-radius:11px;font-size:1rem;padding:4px}.phc207-step-title{align-items:flex-start;min-width:0}.phc207-step-title .icon{flex:0 0 auto}.phc207-choice-row,.phc207-choice-grid,.phc207-timer{grid-template-columns:1fr}.phc207-nav{grid-template-columns:minmax(0,1fr) minmax(0,1.25fr);width:100%;max-width:100%;gap:7px}.phc207-nav button{font-size:.96rem}}
`;document.head.appendChild(s)}

function friendlyError(e){const m=String(e?.message||e||'');const map={INVALID_THAI_CITIZEN_ID:'เลขประจำตัวประชาชนไม่ถูกต้อง กรุณาตรวจสอบ 13 หลัก',DUPLICATE_MEMBER_REQUEST:'มีคำขอของบุคคลนี้อยู่ระหว่างตรวจสอบแล้ว',PERSON_ALREADY_EXISTS_REVIEW_LINK:'พบบุคคลนี้ในทะเบียนแล้ว กรุณาให้ผู้ดูแลระบบตรวจสอบการเชื่อม',FIRST_NAME_REQUIRED:'กรุณากรอกชื่อ',LAST_NAME_REQUIRED:'กรุณากรอกนามสกุล',HOUSE_OUT_OF_SCOPE:'บัญชีนี้ไม่มีสิทธิ์ดำเนินการกับบ้านนี้',ADMIN_REQUIRED:'ต้องใช้สิทธิ์ผู้ดูแลระบบ',NCD_SCREENING_REQUIRED_FIRST:'ต้องบันทึก NCD Screening ก่อนจึงทำ 9 ด้านต่อได้',NCD_SCREENING_REQUIRED_SAME_DAY:'ยังไม่พบ NCD Screening ของวันนี้ กรุณาบันทึก NCD ก่อน'};return map[m]||(/permission|rls|not authorized/i.test(m)?'ไม่มีสิทธิ์ดำเนินการในข้อมูลนี้':m.replace(/^.*?error:\s*/i,'')||'เกิดข้อผิดพลาด กรุณาลองใหม่')}
function cidValid(cid){const v=String(cid||'').replace(/\s/g,'');if(!/^\d{13}$/.test(v))return false;let sum=0;for(let i=0;i<12;i++)sum+=Number(v[i])*(13-i);return ((11-(sum%11))%10)===Number(v[12])}
function statusLabel(s){return({pending:'🟡 กำลังตรวจสอบ',verified:'🟢 ตรวจสอบแล้ว',needs_correction:'🟠 กรุณาตรวจสอบข้อมูล',rejected:'🔴 ไม่สามารถเพิ่มได้'})[s]||s}

async function copyTextV202(value){
  const text=String(value||'').trim();if(!text)return false;
  try{if(navigator.clipboard?.writeText){await navigator.clipboard.writeText(text);return true}}catch{}
  try{const ta=document.createElement('textarea');ta.value=text;ta.setAttribute('readonly','');ta.style.position='fixed';ta.style.opacity='0';document.body.appendChild(ta);ta.select();ta.setSelectionRange(0,text.length);const ok=document.execCommand('copy');ta.remove();return Boolean(ok)}catch{return false}
}

function openModal(title,subtitle=''){closeModal();const o=document.createElement('div');o.className='phc190-overlay';o.innerHTML=`<section class="phc190-modal" role="dialog" aria-modal="true"><div class="phc190-head"><div><small>OSM-PHC · v${VERSION}</small><h2>${esc(title)}</h2>${subtitle?`<div class="phc190-note">${esc(subtitle)}</div>`:''}</div><button class="phc190-close" type="button" aria-label="ปิด">×</button></div><div data-phc190-body></div></section>`;document.body.appendChild(o);document.body.style.overflow='hidden';o.querySelector('.phc190-close').onclick=closeModal;o.addEventListener('click',e=>{if(e.target===o)closeModal()});activeOverlay=o;return $('[data-phc190-body]',o)}
function closeModal(){if(activeOverlay){activeOverlay.remove();activeOverlay=null}document.body.style.overflow=''}
function showPhcToast(message,tone='success',duration=1800){document.querySelector('.phc190-toast')?.remove();if(toastTimer){clearTimeout(toastTimer);toastTimer=null}const t=document.createElement('div');t.className=`phc190-toast ${tone==='warn'?'warn':''}`;t.setAttribute('role','status');t.setAttribute('aria-live','polite');t.innerHTML=`<span>${esc(message)}</span><button type="button">ปิด</button>`;document.body.appendChild(t);const close=()=>{if(t.isConnected)t.remove();if(toastTimer){clearTimeout(toastTimer);toastTimer=null}};t.querySelector('button').onclick=close;toastTimer=setTimeout(close,duration)}

async function loadProfile(){return getSharedProfile(supabase);}

// The request card is a worklist, not a population list. Once JHCIS has
// verified and linked the existing PID, the person is shown in the normal
// household roster and must not appear a second time as an open request.
// The SQL RPC intentionally retains completed rows for Admin audit/history.
function userVisibleMemberRequestsV2100(records){
  return (Array.isArray(records)?records:[]).filter(r=>{
    if(!r||typeof r!=='object')return false;
    const verified=String(r.status||'').trim().toLowerCase()==='verified';
    const linked=r.linked===true||r.linked_person_id!==null&&r.linked_person_id!==undefined&&String(r.linked_person_id)!=='';
    return !(verified&&linked);
  });
}

async function renderHouseMemberRequests(root,houseId,healthAccess=true){
  if(!root||!houseId||!healthAccess)return;root.querySelector('[data-phc190-requests]')?.remove();
  const sec=document.createElement('section');sec.className='phc190-request-wrap';sec.dataset.phc190Requests='1';sec.innerHTML='<div class="phc190-note">กำลังโหลดรายการเพิ่มสมาชิก…</div>';
  const memberSec=[...root.querySelectorAll('.hq31-section')].find(x=>x.querySelector('h3')?.textContent?.includes('สมาชิกในบ้าน'));if(memberSec)memberSec.insertAdjacentElement('afterend',sec);else root.appendChild(sec);
  let {data,error}=await supabase.rpc('household_member_requests_v2043',{p_house_id:houseId});
  if(error)({data,error}=await supabase.rpc('household_member_requests_v190',{p_house_id:houseId}));
  if(error){sec.innerHTML=`<div class="phc190-note">ยังไม่สามารถโหลดคำขอเพิ่มสมาชิกได้</div>`;return}
  const rows=userVisibleMemberRequestsV2100(data);const {data:editable}=await supabase.rpc('field_editable_member_requests_v2122',{p_house_id:houseId});const editableMap=new Map((editable||[]).map(x=>[String(x.id),x]));sec.innerHTML=`<div class="phc190-request-head"><div><h3>เพิ่ม/เชื่อมสมาชิก</h3><small>คำขอใหม่ยังไม่นับเป็นประชากรหรือ KPI จนกว่าเจ้าหน้าที่จะตรวจและเชื่อมทะเบียนสำเร็จ</small></div><button type="button" class="phc190-primary" data-phc190-add>+ แจ้งเพิ่มสมาชิก</button></div><div class="phc190-request-list">${rows.map(r=>`<article class="phc190-request"><strong>${esc(r.full_name)}</strong><small>${esc(r.display_identifier||r.masked_citizen_id)} · เกิด ${esc(fmt(r.birth_date))}</small><span class="phc190-status ${esc(r.status==='verified'&&!r.linked?'pending':r.status)}">${esc(r.status==='verified'&&!r.linked?'รอเชื่อม PID JHCIS':statusLabel(r.status))}</span>${r.review_note?`<small>${esc(r.review_note)}</small>`:''}${editableMap.has(String(r.id))?`<button type="button" class="phc190-secondary" data-phc190-edit="${esc(r.id)}">แก้ไขข้อมูลที่แจ้ง</button>`:''}</article>`).join('')||'<div class="phc190-note">ยังไม่มีคำขอเพิ่มสมาชิกบ้าน</div>'}</div>`;
  sec.querySelector('[data-phc190-add]').onclick=()=>openMemberRequest(houseId,()=>renderHouseMemberRequests(root,houseId,healthAccess));sec.querySelectorAll('[data-phc190-edit]').forEach(b=>b.onclick=()=>{const record=editableMap.get(b.dataset.phc190Edit);if(record)openMemberCorrectionV2122(record,()=>renderHouseMemberRequests(root,houseId,healthAccess));});
}

function memberBirthISOFromBEV2082(day,month,year){
  const d=String(day??'').trim(),m=String(month??'').trim(),y=String(year??'').trim();
  if(!/^\d{1,2}$/.test(d)||!/^\d{1,2}$/.test(m)||!/^\d{4}$/.test(y))return '';
  const be=Number(y),ad=be-543,mm=Number(m),dd=Number(d);
  // Compare using Thailand's calendar day, independent of the phone's timezone.
  const todayTH=new Date(Date.now()+7*60*60*1000).toISOString().slice(0,10);
  if(be<2300||be>Number(todayTH.slice(0,4))+543||mm<1||mm>12||dd<1||dd>31)return '';
  const date=new Date(Date.UTC(ad,mm-1,dd));
  if(date.getUTCFullYear()!==ad||date.getUTCMonth()+1!==mm||date.getUTCDate()!==dd)return '';
  const iso=String(ad).padStart(4,'0')+'-'+String(mm).padStart(2,'0')+'-'+String(dd).padStart(2,'0');
  return iso<=todayTH?iso:'';
}


function openMemberCorrectionV2122(record,onDone){
  const parts=String(record.full_name||'').trim().split(/\s+/),first=parts.shift()||'',last=parts.join(' ');
  const birth=String(record.birth_date||'').slice(0,10).split('-');
  const body=openModal('แก้ไขคำขอเพิ่มสมาชิก','แก้ข้อมูลที่แจ้งผิดก่อนยืนยัน JHCIS · ใช้คำขอเดิม ไม่เพิ่มคนซ้ำ');
  body.innerHTML=[
    '<form class="phc190-form" data-edit-member>',
    '<label>ชื่อ<input name="first" maxlength="80" value="'+esc(first)+'" required autocomplete="off"></label>',
    '<label>นามสกุล<input name="last" maxlength="100" value="'+esc(last)+'" required autocomplete="off"></label>',
    '<fieldset class="phc190-birth"><legend>วันเดือนปีเกิด</legend><div class="phc190-birth-grid">',
    '<label>วัน<select name="day" required>'+Array.from({length:31},(_,i)=>'<option value="'+(i+1)+'" '+(Number(birth[2])===i+1?'selected':'')+'>'+(i+1)+'</option>').join('')+'</select></label>',
    '<label>เดือน<select name="month" required>'+Array.from({length:12},(_,i)=>'<option value="'+(i+1)+'" '+(Number(birth[1])===i+1?'selected':'')+'>'+(i+1)+'</option>').join('')+'</select></label>',
    '<label>ปี พ.ศ.<input name="year" maxlength="4" inputmode="numeric" pattern="[0-9]{4}" value="'+(birth[0]?Number(birth[0])+543:'')+'" required></label></div></fieldset>',
    '<label><input type="checkbox" data-change-cid> เปลี่ยนเลขประจำตัวประชาชนที่แจ้งผิด</label>',
    '<label data-new-cid hidden>เลขประจำตัวประชาชนใหม่ 13 หลัก<input name="cid" maxlength="13" inputmode="numeric" autocomplete="off"></label>',
    '<p class="phc190-note">ไม่แสดงเลขเดิมเต็ม 13 หลัก · การแก้ไขจะส่งตรวจ JHCIS ใหม่</p>',
    '<p class="phc190-error" data-correction-error role="alert"></p>',
    '<div class="phc190-actions"><button class="phc190-primary" type="submit">บันทึกและส่งตรวจใหม่</button></div></form>'
  ].join('');
  const f=$('[data-edit-member]',body),toggle=$('[data-change-cid]',f),newCid=$('[data-new-cid]',f);
  toggle.onchange=()=>{newCid.hidden=!toggle.checked;f.elements.cid.required=toggle.checked;if(!toggle.checked)f.elements.cid.value='';};
  f.onsubmit=async e=>{
    e.preventDefault();const err=$('[data-correction-error]',f),d=new FormData(f);
    const dob=memberBirthISOFromBEV2082(d.get('day'),d.get('month'),d.get('year'));
    const cid=String(d.get('cid')||'').trim();
    if(!dob){err.textContent='วันเกิดไม่ถูกต้อง';return;}
    if(toggle.checked&&!cidValid(cid)){err.textContent='กรุณาตรวจเลข 13 หลัก';return;}
    const b=f.querySelector('button[type="submit"]');b.disabled=true;err.textContent='กำลังบันทึก…';
    try{
      const {error}=await supabase.rpc('edit_pending_member_request_v2122',{
        p_request_id:record.id,p_expected_updated_at:record.updated_at,
        p_first_name:String(d.get('first')||'').trim(),p_last_name:String(d.get('last')||'').trim(),
        p_birth_date:dob,p_new_citizen_id:toggle.checked?cid:null
      });
      if(error)throw error;
      closeModal();invalidateShared('admin-work-member-v2109');
      showPhcToast('บันทึกคำขอเดิมแล้ว · รอตรวจ JHCIS ใหม่');
      await onDone?.();
    }catch(x){err.textContent=friendlyError(x)+' · หากสถานะเปลี่ยน ให้โหลดคำขอใหม่';}
    finally{b.disabled=false;}
  };
}

function openMemberRequest(houseId,onDone){
  const body=openModal('แจ้งเพิ่มสมาชิกบ้าน','กรอกเฉพาะข้อมูลจำเป็น 4 รายการ ระบบจะตรวจคนเดิมก่อน และจะไม่สร้างประชากรซ้ำ');
  body.innerHTML=`<form class="phc190-form" data-member-form><label>เลขประจำตัวประชาชน 13 หลัก<input name="cid" inputmode="numeric" pattern="[0-9]*" maxlength="13" autocomplete="off" required></label><label>ชื่อ<input name="first_name" maxlength="80" autocomplete="off" required></label><label>นามสกุล<input name="last_name" maxlength="100" autocomplete="off" required></label><fieldset class="phc190-birth" style="min-width:0;border:0;padding:0;margin:0"><legend style="font-weight:850;margin-bottom:7px">วันเดือนปีเกิด</legend><div class="phc190-birth-grid"><label>วัน<select name="birth_day" required><option value="">วัน</option>${Array.from({length:31},(_,i)=>`<option value="${i+1}">${i+1}</option>`).join("")}</select></label><label>เดือน<select name="birth_month" required><option value="">เดือน</option>${["ม.ค.","ก.พ.","มี.ค.","เม.ย.","พ.ค.","มิ.ย.","ก.ค.","ส.ค.","ก.ย.","ต.ค.","พ.ย.","ธ.ค."].map((name,i)=>`<option value="${i+1}">${name}</option>`).join("")}</select></label><label class="phc190-birth-year">ปี พ.ศ.<input name="birth_year_be" type="text" inputmode="numeric" pattern="[0-9]{4}" maxlength="4" placeholder="เช่น 2509" autocomplete="off" required></label></div><small style="color:#526a63;font-size:.87rem">กรอกปี พ.ศ. 4 หลัก ไม่ต้องเลื่อนปฏิทินย้อนหลัง</small></fieldset><div class="phc190-note">หากพบ CID เดิม ระบบจะส่งให้ Admin ตรวจเชื่อมกับ PID เดิมแทนการสร้างคนซ้ำ · เมื่อเชื่อมสำเร็จ หน้านี้จะแสดง PID แทนเลขบัตร</div><div class="phc190-error" data-err></div><button class="phc190-primary">ตรวจสอบและส่งคำขอ</button></form>`;
  const f=$('[data-member-form]',body);f.onsubmit=async e=>{e.preventDefault();const err=$('[data-err]',f);err.textContent='';const d=new FormData(f),cid=String(d.get('cid')||'').trim(),first=String(d.get('first_name')||'').trim(),last=String(d.get('last_name')||'').trim(),birth=memberBirthISOFromBEV2082(d.get('birth_day'),d.get('birth_month'),d.get('birth_year_be'));if(!cidValid(cid)){err.textContent='เลขประจำตัวประชาชนไม่ถูกต้อง กรุณาตรวจสอบ 13 หลัก';return}if(!first){err.textContent='กรุณากรอกชื่อ';return}if(!last){err.textContent='กรุณากรอกนามสกุล';return}if(!birth){err.textContent='วันเดือนปีเกิดไม่ถูกต้อง กรุณาตรวจวัน เดือน และปี พ.ศ. (ห้ามเป็นวันในอนาคต)';return}const btn=f.querySelector('button');btn.disabled=true;try{const {data,error}=await supabase.rpc('submit_household_member_request_v2043',{p_house_id:houseId,p_citizen_id:cid,p_first_name:first,p_last_name:last,p_birth_date:birth});if(error)throw error;closeModal();await onDone?.();showPhcToast(data?.existing_person_found?'พบข้อมูลบุคคลเดิม · ส่งให้ Admin ตรวจเชื่อม PID แล้ว':'ส่งคำขอเพิ่มสมาชิกแล้ว');}catch(x){err.textContent=friendlyError(x)}finally{btn.disabled=false}};
}

function invalidateCancelledFieldCachesV2070(){
  for(const prefix of ['admin-work-member-v2070','admin-work-member-v2109','admin-work-notices-v2057',
    'my-household-cards-v2039:','my-pending-houses-v2055:',
    'house-add-quota-v2055:','staff-community-bundle-v2055:',
    'spatial-community-cards-v1854','spatial-role-dashboard-v1854',
    'community-scope:','field-own-houses-v2037:'])
    invalidateShared(prefix);
  document.dispatchEvent(new CustomEvent('phc:spatial-data-changed',
    {detail:{source:'admin-field-cancellation-v2070'}}));
}

function requestCancelReasonV2070(label){
  const reason=prompt('ระบุเหตุผลยกเลิก'+label+' (อย่างน้อย 5 ตัวอักษร; ไม่กรอกเลขบัตรประชาชนหรือข้อมูลสุขภาพ)')?.trim()||'';
  if(!reason)return null;
  if(reason.length<5||reason.length>200||/[0-9]{13}/.test(reason)){
    showPhcToast('ระบุเหตุผล 5–200 ตัวอักษร โดยไม่ใส่เลขบัตรประชาชน','warn',3500);
    return null;
  }
  return reason;
}

async function cancelMemberRequestV2070(id,label){
  const reason=requestCancelReasonV2070('คำขอเพิ่มสมาชิก');
  if(!reason||!confirm('ยืนยันยกเลิกคำขอเพิ่มสมาชิก '+label+' ?\nข้อมูล JHCIS และประวัติคำขอจะไม่ถูกลบ'))return;
  try{
    const {error}=await supabase.rpc('admin_cancel_member_request_v2070',
      {p_request_id:id,p_reason:reason});
    if(error)throw error;
    invalidateCancelledFieldCachesV2070();
    showPhcToast('ยกเลิกคำขอแล้ว และแจ้งผลไปยัง อสม. ผู้ส่งคำขอ', 'success',3200);
    await renderAdminMemberQueue();
  }catch(e){showPhcToast(friendlyError(e),'warn',4500)}
}

async function renderAdminPendingHouseQueueV2070(){
  const body=openModal('จัดการบ้านที่ อสม. เพิ่ม','ยกเลิกได้เฉพาะบ้านที่ยังไม่ยืนยันกับ JHCIS และไม่มีคำขอสมาชิกค้าง ระบบเก็บประวัติการยกเลิกไว้');
  body.innerHTML='<div class="phc190-note">กำลังตรวจรายการบ้านที่ยังรอ JHCIS…</div>';
  const {data,error}=await supabase.rpc('admin_cancellable_field_houses_v2070');
  if(error){body.innerHTML='<div class="phc190-error">'+esc(friendlyError(error))+'</div>';return;}
  const rows=data||[];
  body.innerHTML='<div class="phc190-request-list">'+rows.map(h=>
    '<article class="phc190-request" data-admin-field-cancel="'+esc(h.id)+'">'+
    '<strong>บ้านเลขที่ '+esc(h.house_no||'ไม่ระบุ')+'</strong>'+
    '<small>หมู่ '+esc(h.moo||'—')+' · '+esc(h.community||'—')+
    ' · รหัสบ้าน '+esc(h.house_id_11||'—')+'</small>'+
    '<small>สถานะ '+esc(h.verification_status)+' · คำขอ/สมาชิกที่ผูกกับบ้าน (รวมตรวจแล้ว) '+Number(h.open_member_requests||0)+'</small>'+
    (h.verification_status!=='pending_jhcis_create'
      ?'<div class="phc190-note">ต้องตรวจทะเบียน JHCIS ก่อน บ้านนี้มีสถานะพบข้อมูลเดิมหรือต้องตรวจเพิ่มเติม จึงยังยกเลิกบน Cloud ไม่ได้</div>'
      :Number(h.open_member_requests||0)>0
      ?'<div class="phc190-note">ยกเลิกบ้านไม่ได้: มีคำขอหรือสมาชิกที่เชื่อมทะเบียนอยู่ โปรดตรวจรายการก่อน</div><button type="button" class="phc190-secondary" data-manage-members>ดูคำขอที่ยังจัดการได้</button>'
      :'<button type="button" class="phc190-secondary phc190-danger" data-cancel-house>ยกเลิกคำขอเพิ่มบ้าน</button>')+
    '</article>').join('')+
    (rows.length?'':'<div class="phc190-note">ไม่มีบ้านจาก อสม. ที่รอยืนยัน JHCIS</div>')+'</div>';
  body.querySelectorAll('[data-admin-field-cancel]').forEach(card=>{
    const h=rows.find(row=>String(row.id)===card.dataset.adminFieldCancel);
    card.querySelector('[data-manage-members]')?.addEventListener('click',renderAdminMemberQueue);
    card.querySelector('[data-cancel-house]')?.addEventListener('click',async e=>{
      const reason=requestCancelReasonV2070('บ้าน');
      if(!reason||!confirm('ยืนยันยกเลิกคำขอเพิ่มบ้านเลขที่ '+String(h?.house_no||'')+
        ' ?\nรายการบ้านจะไม่ถูกลบถาวร และข้อมูล JHCIS จะไม่ถูกแก้ไข'))return;
      const b=e.currentTarget;b.disabled=true;
      try{
        const {error}=await supabase.rpc('admin_cancel_field_house_v2070',
          {p_house_id:h.id,p_reason:reason});
        if(error)throw error;
        invalidateCancelledFieldCachesV2070();
        showPhcToast('ยกเลิกบ้านที่รอ JHCIS แล้ว และแจ้งผลกลับผู้ส่งคำขอ','success',3400);
        await renderAdminPendingHouseQueueV2070();
      }catch(err){showPhcToast(friendlyError(err),'warn',4500);b.disabled=false;}
    });
  });
}

async function renderAdminMemberQueue(){
  const body=openModal('คำขอเพิ่มสมาชิกที่รอตรวจ','แสดงเฉพาะคำขอที่ยังต้องตัดสินใจ เมื่อยืนยัน ส่งกลับแก้ไข หรือยกเลิกแล้ว รายการจะออกจากคิว แต่ยังเก็บประวัติไว้');
  body.innerHTML='<div class="phc190-note">กำลังโหลด…</div>';
  const {data,error}=await supabase.rpc('admin_pending_member_requests_v2109');
  if(error){body.innerHTML=`<div class="phc190-error">${esc(friendlyError(error))}</div>`;return}
  const rows=data||[];
  body.innerHTML=`<div class="phc190-request-list">${rows.map(r=>`<article class="phc190-request" data-admin-request="${esc(r.id)}"><strong>${esc(r.full_name)}</strong><small>บ้าน ${esc(r.house_no)} · ${esc(r.community)} · ${esc(r.masked_citizen_id)} · เกิด ${esc(fmt(r.birth_date))}</small><small class="phc190-requester">ผู้แจ้ง: <strong>${esc(r.requester_name||'ไม่ระบุ')}</strong> · ชุมชนผู้แจ้ง: <strong>${esc(r.requester_community||'ไม่ระบุ')}</strong></small>${r.requester_line_connected&&r.requester_user_id?'<button type="button" class="phc190-secondary phc190-line-contact" data-line-contact>ติดต่อผู้แจ้งทาง LINE</button>':'<small class="phc190-line-unavailable">ผู้แจ้งยังไม่เชื่อม LINE</small>'}<div data-line-compose></div><div class="phc190-actions"><button class="phc190-secondary" data-sensitive>ดูเลขเพื่อเทียบ</button><button class="phc190-secondary" data-match>ค้นหาบุคคลเดิม</button></div><div class="phc190-actions"><button class="phc190-primary" data-verify>ยืนยันข้อมูล / รอ Sync</button><button class="phc190-secondary" data-correct>ขอแก้ไข</button></div><button class="phc190-secondary phc190-danger" data-cancel>ยกเลิกคำขอ</button><div data-detail></div></article>`).join('')||'<div class="phc190-note">ไม่มีคำขอรอตรวจ</div>'}</div>`;
  body.querySelectorAll('[data-admin-request]').forEach(card=>{
    const id=card.dataset.adminRequest,box=card.querySelector('[data-detail]');
     const item=rows.find(r=>String(r.id)===id);
    card.querySelector('[data-line-contact]')?.addEventListener('click',()=>{
      const host=card.querySelector('[data-line-compose]');
      if(host.childElementCount){host.replaceChildren();return}
      host.innerHTML='<form class="phc190-form phc190-line-compose" data-line-form><label>ข้อความถึงผู้แจ้ง<textarea name="body" maxlength="500" required>มีข้อมูลคำขอเพิ่มสมาชิกที่ต้องตรวจเพิ่มเติม กรุณาเปิดระบบ อสม. พลัส หรือติดต่อหน่วยบริการ</textarea></label><small>ส่งผ่าน LINE ที่เชื่อมกับบัญชีผู้แจ้ง ไม่ใส่เลขบัตรประชาชนหรือข้อมูลสุขภาพ</small><div class="phc190-error" data-err></div><button type="submit" class="phc190-primary">เข้าคิวส่ง LINE</button></form>';
      const form=host.querySelector('[data-line-form]');
      form.onsubmit=async e=>{
        e.preventDefault();const message=form.elements.body.value.trim(),err=form.querySelector('[data-err]');err.textContent='';
        if(!message||/\d{13}/.test(message)||/(password|api[ _-]?key|service[ _-]?role|bot[ _-]?token|secret)\s*[:=]/i.test(message)){err.textContent='กรุณาใช้ข้อความทั่วไป โดยไม่ใส่เลขบัตรหรือข้อมูลอ่อนไหว';return}
        const button=form.querySelector('button');button.disabled=true;
        try{
          const {error}=await supabase.rpc('admin_queue_line_message_v190',{p_recipient_user_id:item.requester_user_id,p_body:message,p_action_path:'?panel=overview',p_message_type:'notice'});
          if(error)throw error;
          host.replaceChildren();showPhcToast('เข้าคิวส่ง LINE ถึงผู้แจ้งแล้ว','success',3200);
        }catch(ex){err.textContent=friendlyError(ex);button.disabled=false}
      };
    });
    card.querySelector('[data-sensitive]').onclick=async()=>{const {data,error}=await supabase.rpc('admin_member_request_sensitive_v190',{p_request_id:id});box.innerHTML=error?`<div class="phc190-error">${esc(friendlyError(error))}</div>`:`<div class="phc190-note">เลขสำหรับตรวจสอบ: <strong>${esc(data.citizen_id)}</strong><br>การเปิดดูครั้งนี้ถูกบันทึก Audit แล้ว</div>`};
    card.querySelector('[data-match]').onclick=async()=>{
      box.innerHTML='<div class="phc190-note">กำลังตรวจทะเบียนเดิม…</div>';
      const {data:matches,error}=await supabase.rpc('admin_member_request_match_v190',{p_request_id:id});
      if(error){box.innerHTML=`<div class="phc190-error">${esc(friendlyError(error))}</div>`;return}
      box.innerHTML=(matches||[]).map(m=>`<div class="phc190-note"><strong>${esc(m.display_name)}</strong><br>บ้าน ${esc(m.house_no)} · ${esc(m.community)} · ${m.match_type==='citizen_id_hash'?'ตรงจากรหัสบุคคลแบบ Hash':'ชื่อ + วันเกิดตรงกัน'}<br>${m.same_house?'🟢 บ้านตรงกัน':'🟠 อยู่บ้านอื่น ต้องตรวจ/ย้ายใน JHCIS ก่อน'}${m.same_house?`<button type="button" class="phc190-primary" style="width:100%;margin-top:8px" data-link-pcucode="${esc(m.source_pcucode)}" data-link-pid="${esc(m.source_pid)}">ยืนยันและเชื่อมบุคคลนี้</button>`:''}</div>`).join('')||'<div class="phc190-note">ไม่พบบุคคลเดิมที่ตรงกัน ระบบจะรอ JHCIS Sync หลัง Admin ยืนยันข้อมูล</div>';
      box.querySelectorAll('[data-link-pid]').forEach(b=>b.onclick=()=>reviewRequest(id,'verify','',b.dataset.linkPcucode,Number(b.dataset.linkPid)));
    };
    card.querySelector('[data-correct]')?.addEventListener('click',()=>reviewRequest(id,'needs_correction'));
    card.querySelector('[data-cancel]').onclick=()=>cancelMemberRequestV2070(id,card.querySelector('strong')?.textContent||'');
    card.querySelector('[data-verify]')?.addEventListener('click',()=>reviewRequest(id,'verify'));
  });
}
async function reviewRequest(id,decision,note='',linkPcucode=null,linkPid=null){
  if(decision!=='verify'&&!note)note=prompt(decision==='reject'?'เหตุผลที่ไม่อนุมัติ':'ข้อความที่ต้องการให้ผู้ส่งตรวจแก้')||'';
  if(decision!=='verify'&&!note)return;
  try{
    const {data,error}=await supabase.rpc('review_household_member_request_v190',{p_request_id:id,p_decision:decision,p_note:note,p_link_pcucode:linkPcucode,p_link_pid:linkPid});
    if(error)throw error;
    if(data?.message)alert(data.message);else if(linkPid)alert('ยืนยันและเชื่อมกับบุคคลเดิมสำเร็จ');
    invalidateShared('admin-work-member-v2109');
    await renderAdminMemberQueue();
  }catch(e){alert(friendlyError(e))}
}
function openExistingNcd(personName,pcucode,pid){closeModal();window.PHCSetHealthIntentV2058?.({filter:'all',stage:'',assignment:'all',search:personName||''});document.querySelector('[data-portal-view="health"]')?.click();setTimeout(()=>{if(window.PHCOpenLegacyNcd190?.(pcucode,pid)){document.querySelector('#ncd-screen-card')?.scrollIntoView({behavior:'smooth',block:'start'});return}const names=[...document.querySelectorAll('.health-person-name')];const b=names.find(x=>x.textContent.trim()===(personName||'').trim());if(b)window.PHCOpenLegacyNcd190?.(pcucode,pid)},900)}

const SCREENING_ROUTES_V2023=new Set(['child_0_5','school_6_14','youth_15_34','ncd_35_59','elderly_60_plus']);
function normalizeScreeningSeedV2023(seed,pcucode,pid,personName=''){
  if(!seed||!SCREENING_ROUTES_V2023.has(String(seed.route||'')))return null;
  const planDate=String(seed.plan_date||seed.screening_plan_date||'').slice(0,10);
  if(planDate!==thaiDayV208())return null;
  const ageYears=Number(seed.age_years),ageMonths=Number(seed.age_months??seed.screening_age_months);
  if(!Number.isFinite(ageYears)||!Number.isFinite(ageMonths))return null;
  const ncdComplete=String(seed.ncd_status||'')==='complete'||String(seed.latest_screened_on||'').slice(0,10)===thaiDayV208();
  return {source_pcucode:String(pcucode),source_pid:Number(pid),display_name:personName||seed.display_name||'',age_years:ageYears,age_months:ageMonths,route:String(seed.route),route_label:String(seed.route_label||seed.screening_route_label||''),dspm_target_months:seed.dspm_target_months??seed.screening_dspm_target_months??null,plan_date:planDate,plan_source:'worklist_precomputed',record_mode:preGoLiveV208()?'test':'production',session_id:seed.session_id||null,ncd_screening_id:seed.ncd_screening_id||null,ncd_status:['ncd_35_59','elderly_60_plus'].includes(String(seed.route))?(ncdComplete?'complete':'required'):'not_required',elderly9_status:String(seed.route)==='elderly_60_plus'?(ncdComplete?'in_progress':'blocked_by_ncd'):'not_required',completed_domains:Array.isArray(seed.completed_domains)?seed.completed_domains:[]};
}
async function ensureScreeningSessionV2023(s){
  if(s?.session_id)return s;
  if(s?._sessionPromise)return s._sessionPromise;
  s._sessionPromise=(async()=>{const {data,error}=await supabase.rpc('ensure_screening_session_v2023',{p_source_pcucode:s.source_pcucode,p_source_pid:Number(s.source_pid),p_screening_date:thaiDayV208()});if(error)throw error;Object.assign(s,data||{});return s})().finally(()=>{delete s._sessionPromise});
  return s._sessionPromise;
}
async function openAgeScreening(pcucode,pid,personName='',seed=null){
  const body=openModal('คัดกรองตามช่วงวัย','ระบบเตรียมกลุ่มอายุและแบบคัดกรองไว้ล่วงหน้า เพื่อเปิดใช้งานภาคสนามได้เร็วขึ้น');
  const prepared=normalizeScreeningSeedV2023(seed,pcucode,pid,personName);
  if(prepared){await renderScreenRoute(body,prepared,personName||prepared.display_name);return}
  body.innerHTML='<div class="phc190-note">กำลังอ่านแผนคัดกรองที่เตรียมไว้…</div>';
  const {data,error}=await supabase.rpc('screening_plan_for_person_v2023',{p_source_pcucode:pcucode,p_source_pid:Number(pid),p_screening_date:thaiDayV208()});
  if(error){body.innerHTML=`<div class="phc190-error">${esc(friendlyError(error))}</div>`;return}
  await renderScreenRoute(body,data,personName||data.display_name);
}

function testResetBannerV208(s){
  if(profile?.role!=='admin')return'';
  if(!preGoLiveV208()&&s?.record_mode!=='test')return'';
  return `<section class="phc190-note phc190-warning" data-test-mode-v208><strong>โหมดทดสอบก่อน 1 ต.ค. 2569</strong><br>ผลที่บันทึกช่วงนี้ไม่ถูกนับเป็นผลงานจริง · ประวัติเดิมจาก JHCIS / J-Report / 3Doctor ไม่ถูกลบ<button type="button" class="phc190-secondary phc190-danger" style="width:100%;margin-top:9px" data-reset-test-v208>รีเซทข้อมูลทดสอบ</button></section>`;
}
function resetRouteLabelV208(route){return ({child_0_5:'เด็ก 0–5 ปี',school_6_14:'เด็ก 6–14 ปี',youth_15_34:'วัย 15–34 ปี',ncd_35_59:'NCD 35–59 ปี',elderly_60_plus:'NCD + ผู้สูงอายุ 9 ด้าน'})[route]||'ช่วงวัยนี้'}
async function bindTestResetV208(body,s,personName){
  const b=body.querySelector('[data-reset-test-v208]');if(!b)return;
  b.onclick=async()=>{if(!confirm(`รีเซทผลทดสอบ ${resetRouteLabelV208(s.route)} ของ ${personName}?\n\nระบบจะเก็บสำเนาไว้ใน Audit Archive และจะไม่ลบประวัติเดิมจาก JHCIS / J-Report / 3Doctor`))return;b.disabled=true;try{const {error}=await supabase.rpc('admin_reset_person_test_screening_v2022',{p_source_pcucode:s.source_pcucode,p_source_pid:Number(s.source_pid),p_route:s.route,p_reason:'ผู้ใช้กดรีเซทข้อมูลทดสอบก่อนเปิดใช้จริง'});if(error)throw error;showPhcToast('รีเซทข้อมูลทดสอบแล้ว');const {data:fresh,error:e}=await supabase.rpc('screening_plan_for_person_v2023',{p_source_pcucode:s.source_pcucode,p_source_pid:Number(s.source_pid),p_screening_date:thaiDayV208()});if(e)throw e;await renderScreenRoute(body,fresh,personName)}catch(e){showPhcToast(friendlyError(e),'warn',3200);b.disabled=false}};
}
async function renderScreenRoute(body,s,personName){body.innerHTML=`<div class="phc190-progress">${esc(personName)} · อายุ ${s.age_years} ปี (${s.age_months} เดือน)<br>${esc(s.route_label)}</div>${testResetBannerV208(s)}<div class="phc190-route" data-route></div>`;await bindTestResetV208(body,s,personName);const root=$('[data-route]',body);if(s.route==='child_0_5'){root.innerHTML=growthHtml()+developmentHtml(s.dspm_target_months);bindGrowth(root,s);bindDevelopment(root,s)}else if(s.route==='school_6_14'){root.innerHTML=growthHtml();bindGrowth(root,s)}else if(s.route==='youth_15_34'){await renderYouthRouteV206(root,s,personName)}else if(s.route==='ncd_35_59'){root.innerHTML=`<div class="phc190-step"><h3>NCD Screening</h3><p>${s.ncd_status==='complete'?'🟢 บันทึก NCD วันนี้แล้ว':'🟡 ต้องทำ NCD Screening'}</p><button class="phc190-primary" data-open-ncd>เปิด NCD Screening</button></div>`;root.querySelector('[data-open-ncd]').onclick=()=>openExistingNcd(personName,s.source_pcucode,s.source_pid)}else{await renderElderlyRoute(root,s,personName)}}

function setMentalAnswerV206(card,value){card.dataset.value=String(value);card.querySelectorAll('[data-mental-answer]').forEach(b=>{const active=b.dataset.mentalAnswer===String(value);b.classList.toggle('active',active);b.classList.toggle('normal',active&&String(value)==='false');b.classList.toggle('observation',active&&String(value)==='true')})}
async function renderYouthRouteV206(root,s,personName){
  const {data:campaign,error}=await supabase.rpc('youth_campaign_status_v206');
  if(error){root.innerHTML=`<div class="phc190-note">ยังไม่สามารถอ่านสถานะช่วงคัดกรองเสริมได้</div>`;return}
  if(!campaign?.visible_now){root.innerHTML=`<div class="phc190-note"><strong>ช่วงอายุ 15–34 ปี</strong><br>ขณะนี้ไม่มีรอบคัดกรองเสริมที่เปิดใช้งาน จึงไม่ถูกนับเป็นเป้าหมายหลักของ อสม.</div>`;return}
  const ncdAvailable=Boolean(campaign.ncd_enabled)&&Number(s.age_years)>=18;
  const mentalAvailable=Boolean(campaign.mental_2q_enabled);
  root.innerHTML=`<section class="phc190-step"><h3>${esc(campaign.title||'คัดกรองเสริมวัย 15–34 ปี')}</h3><div class="phc190-note">เปิดใช้ ${esc(fmt(campaign.start_date))} – ${esc(fmt(campaign.end_date))} · เป็นงานเสริม ไม่รวมเป้าหมายหลัก/Operational Task Completion</div>${campaign.ncd_enabled?(ncdAvailable?`<button class="phc190-primary" data-youth-ncd>เปิดคัดกรอง NCD (งานเสริม)</button>`:`<div class="phc190-note">NCD ใช้เครื่องมือผู้ใหญ่ตั้งแต่อายุ 18 ปีขึ้นไป; อายุ 15–17 ปีจึงไม่เปิด NCD ในระบบนี้</div>`):''}</section>${mentalAvailable?mental2qHtmlV206():''}`;
  root.querySelector('[data-youth-ncd]')?.addEventListener('click',()=>openExistingNcd(personName,s.source_pcucode,s.source_pid));
  if(mentalAvailable)await bindMental2qV206(root,s);
}
function mental2qHtmlV206(){return `<section class="phc190-step" data-mental2q><h3>สุขภาพจิต · 2Q เบื้องต้น</h3><div class="phc190-note">อสม./เจ้าหน้าที่ถามเพียง 2 ข้อ หากพบสัญญาณ ระบบจะส่งงานให้เจ้าหน้าที่ประเมินต่อ ไม่ให้อสม.วินิจฉัยหรือปิดเคสเอง</div><article class="phc190-domain" data-mental-q="q1" data-value=""><h4>ข้อ 1</h4><p>ใน 2 สัปดาห์ที่ผ่านมา มีช่วงที่รู้สึกเศร้าหรือหมดหวังหรือไม่?</p><div class="phc190-state-row"><button type="button" class="phc190-state" data-mental-answer="false">ไม่</button><button type="button" class="phc190-state" data-mental-answer="true">ใช่</button></div></article><article class="phc190-domain" data-mental-q="q2" data-value=""><h4>ข้อ 2</h4><p>ใน 2 สัปดาห์ที่ผ่านมา เบื่อหรือไม่สนใจสิ่งต่าง ๆ มากกว่าปกติหรือไม่?</p><div class="phc190-state-row"><button type="button" class="phc190-state" data-mental-answer="false">ไม่</button><button type="button" class="phc190-state" data-mental-answer="true">ใช่</button></div></article><div class="phc190-note phc190-save-result" data-mental-result hidden></div><div class="phc190-error" data-mental-error></div><button type="button" class="phc190-primary" data-mental-save>บันทึก 2Q</button></section>`}
async function bindMental2qV206(root,s){
  const sec=root.querySelector('[data-mental2q]'),err=sec.querySelector('[data-mental-error]'),result=sec.querySelector('[data-mental-result]');
  sec.querySelectorAll('[data-mental-q]').forEach(card=>card.querySelectorAll('[data-mental-answer]').forEach(b=>b.onclick=()=>setMentalAnswerV206(card,b.dataset.mentalAnswer==='true')));
  const prevResult=s.session_id?await supabase.from('mental_health_2q_screenings_v206').select('q1,q2,positive,result_label').eq('session_id',s.session_id).maybeSingle():{data:null};
  const prev=prevResult.data;
  if(prev){setMentalAnswerV206(sec.querySelector('[data-mental-q="q1"]'),Boolean(prev.q1));setMentalAnswerV206(sec.querySelector('[data-mental-q="q2"]'),Boolean(prev.q2));result.textContent=`ผลล่าสุด · ${prev.result_label}`;result.className=`phc190-note phc190-save-result ${prev.positive?'phc190-warning':''}`;result.hidden=false}
  sec.querySelector('[data-mental-save]').onclick=async()=>{const q1=sec.querySelector('[data-mental-q="q1"]').dataset.value,q2=sec.querySelector('[data-mental-q="q2"]').dataset.value;err.textContent='';if(!q1||!q2){err.textContent='กรุณาตอบทั้ง 2 ข้อ';return}const btn=sec.querySelector('[data-mental-save]');btn.disabled=true;try{await ensureScreeningSessionV2023(s);const {data,error}=await supabase.rpc('save_mental_health_2q_v206',{p_session_id:s.session_id,p_q1:q1==='true',p_q2:q2==='true'});if(error)throw error;result.textContent=`บันทึกแล้ว · ${data.result_label}${data.followup_created?' · ส่งงานติดตามให้เจ้าหน้าที่แล้ว':''}`;result.className=`phc190-note phc190-save-result ${data.positive?'phc190-warning':''}`;result.hidden=false;showPhcToast(data.positive?'บันทึกแล้ว · ส่งต่อเจ้าหน้าที่ติดตาม':'บันทึก 2Q แล้ว',data.positive?'warn':'success')}catch(e){err.textContent=friendlyError(e)}finally{btn.disabled=false}};
}
async function openYouthCampaignSettingsV206(){
  const body=openModal('ตั้งค่าคัดกรองเสริม 15–34 ปี','Admin กำหนดช่วงเวลาและเครื่องมือที่เปิดให้ user/staff ใช้งาน งานนี้ไม่ถูกนับเป็นเป้าหมายหลัก');
  body.innerHTML='<div class="phc190-note">กำลังโหลดการตั้งค่า…</div>';
  const {data,error}=await supabase.rpc('youth_campaign_status_v206');if(error){body.innerHTML=`<div class="phc190-error">${esc(friendlyError(error))}</div>`;return}
  body.innerHTML=`<form class="phc190-form" data-youth-campaign-form><label><span><input name="enabled" type="checkbox" ${data.enabled?'checked':''}> เปิดรอบคัดกรองเสริม</span></label><label>วันเริ่ม<input name="start" type="date" value="${esc(data.start_date||'')}"></label><label>วันสิ้นสุด<input name="end" type="date" value="${esc(data.end_date||'')}"></label><label><span><input name="ncd" type="checkbox" ${data.ncd_enabled?'checked':''}> เปิด NCD สำหรับอายุ 18–34 ปี</span></label><label><span><input name="mental" type="checkbox" ${data.mental_2q_enabled?'checked':''}> เปิดสุขภาพจิต 2Q สำหรับอายุ 15–34 ปี</span></label><label>หมายเหตุ<textarea name="note" maxlength="500">${esc(data.note||'')}</textarea></label><div class="phc190-note">สถานะตอนนี้: ${data.active_now?'🟢 อยู่ในช่วงเปิดใช้งาน':'⚪ ยังไม่อยู่ในช่วงเปิดใช้งาน'} · User/Staff จะเห็นแบบคัดกรองเฉพาะช่วงวันที่กำหนด · ไม่รวม Coverage หลัก</div><div class="phc190-error" data-err></div><button class="phc190-primary">บันทึกการตั้งค่า</button></form>`;
  const f=body.querySelector('[data-youth-campaign-form]');f.onsubmit=async e=>{e.preventDefault();const d=new FormData(f),enabled=f.elements.enabled.checked,ncd=f.elements.ncd.checked,mental=f.elements.mental.checked,err=f.querySelector('[data-err]');err.textContent='';if(enabled&&(!d.get('start')||!d.get('end'))){err.textContent='เมื่อเปิดใช้งาน ต้องกำหนดวันเริ่มและวันสิ้นสุด';return}if(enabled&&!ncd&&!mental){err.textContent='เลือกอย่างน้อย 1 เครื่องมือ';return}const btn=f.querySelector('button');btn.disabled=true;try{const {error}=await supabase.rpc('admin_set_youth_campaign_v206',{p_enabled:enabled,p_start_date:d.get('start')||null,p_end_date:d.get('end')||null,p_ncd_enabled:ncd,p_mental_2q_enabled:mental,p_note:d.get('note')||''});if(error)throw error;showPhcToast('บันทึกช่วงคัดกรองเสริมแล้ว');closeModal();await renderOverview()}catch(x){err.textContent=friendlyError(x)}finally{btn.disabled=false}};
}

function growthHtml(){return `<section class="phc190-step"><h3>น้ำหนัก / ส่วนสูง</h3><div class="phc190-note" data-growth-latest>กำลังโหลดประวัติน้ำหนัก/ส่วนสูงล่าสุด…</div><div class="phc190-grow"><label>น้ำหนัก (กก.)<input data-growth-weight type="number" inputmode="decimal" min="0.1" max="300" step="0.1"></label><label>ส่วนสูง (ซม.)<input data-growth-height type="number" inputmode="decimal" min="30" max="250" step="0.1"></label></div><div class="phc190-error" data-growth-error></div><button class="phc190-primary" data-growth-save>บันทึกและแปลผล</button><div class="phc190-note phc190-save-result" data-growth-result hidden></div><div class="phc190-note">แปลผลตามเกณฑ์กรมอนามัยที่ใช้ใน JHCIS/HDC · อายุ 0–5 ปีใช้ น้ำหนักตามอายุ + ส่วนสูงตามอายุ + น้ำหนักตามส่วนสูง · อายุ 6–14 ปีใช้ ส่วนสูงตามอายุ + น้ำหนักตามส่วนสูง ตามเกณฑ์ 6–19 ปี พ.ศ. 2564</div><div class="phc190-timeline" data-growth-timeline></div></section>`}
function nutritionMetricV204(label,item){return `<article class="phc190-kpi"><small>${esc(label)}</small><strong>${esc(item?.label||'แปลผลไม่ได้')}</strong></article>`}
function renderGrowthNutritionV204(result,nutrition,s){if(!result)return;const n=nutrition||{},cards=[];if(Number(s.age_months)<72)cards.push(nutritionMetricV204('น้ำหนักตามอายุ',n.weight_for_age));cards.push(nutritionMetricV204('ส่วนสูงตามอายุ',n.height_for_age),nutritionMetricV204('น้ำหนักตามส่วนสูง',n.weight_for_height));const refLabel=Number(s.age_months)<72?'กรมอนามัย / เกณฑ์เด็ก 0–5 ปี':'กรมอนามัย พ.ศ. 2564 / เกณฑ์เด็ก 6–19 ปี';result.innerHTML=`<strong>ผลภาวะโภชนาการ: ${esc(n.overall_label||'บันทึกค่าแล้ว')}</strong><div class="phc190-kpis" style="margin-top:8px">${cards.join('')}</div><small style="display:block;margin-top:8px">${esc(refLabel)} · ${esc(n.reference_version||'ไม่ระบุเวอร์ชัน')}</small>`;result.hidden=false}
function bindGrowth(root,s){
  const box=$('[data-growth-timeline]',root),result=root.querySelector('[data-growth-result]'),latestBox=root.querySelector('[data-growth-latest]'),weightInput=root.querySelector('[data-growth-weight]'),heightInput=root.querySelector('[data-growth-height]');
  const load=async()=>{
    let {data,error}=await supabase.rpc('growth_timeline_v204',{p_source_pcucode:s.source_pcucode,p_source_pid:Number(s.source_pid)});
    if(error){const legacy=await supabase.rpc('growth_timeline_v190',{p_source_pcucode:s.source_pcucode,p_source_pid:Number(s.source_pid)});data=legacy.data||[]}
    const rows=data||[],latest=rows[0];
    if(latestBox){
      if(latest){
        const source=latest.id?'อสม.พลัส':'JHCIS';
        latestBox.innerHTML=`<strong>ประวัติล่าสุด ${esc(fmt(latest.screened_at))}</strong><br>น้ำหนัก ${esc(latest.weight_kg)} กก. · ส่วนสูง ${esc(latest.height_cm)} ซม. · ที่มา ${esc(source)}<button type="button" class="phc190-secondary" data-growth-use-latest style="width:100%;margin-top:8px">ใช้ค่าล่าสุดเป็นค่าเริ่มต้น</button>`;
        latestBox.querySelector('[data-growth-use-latest]')?.addEventListener('click',()=>{weightInput.value=latest.weight_kg??'';heightInput.value=latest.height_cm??'';showPhcToast('นำค่าล่าสุดมาใส่แล้ว กรุณาตรวจวัดและแก้ไขก่อนบันทึก','warn',2800)});
      }else latestBox.textContent='ยังไม่มีประวัติน้ำหนัก/ส่วนสูงจาก JHCIS หรือ อสม.พลัส';
    }
    if(box)box.innerHTML=rows.slice(0,5).map(x=>`<div>${esc(fmt(x.screened_at))} · ${x.weight_kg} กก. · ${x.height_cm} ซม. · อายุ ${x.age_months??'—'} เดือน${x.interpretation_label?`<br><strong>${esc(x.interpretation_label)}</strong>`:''}${x.id?'':'<br><small>ที่มา: JHCIS</small>'}</div>`).join('')||'<div>ยังไม่มีประวัติ</div>';
  };
  root.querySelector('[data-growth-save]').onclick=async()=>{
    const w=Number(weightInput.value),h=Number(heightInput.value),err=root.querySelector('[data-growth-error]');err.textContent='';if(result)result.hidden=true;
    try{await ensureScreeningSessionV2023(s);const {data,error}=await supabase.rpc('save_growth_screening_v190',{p_session_id:s.session_id,p_weight_kg:w,p_height_cm:h});if(error)throw error;if(data?.nutrition)renderGrowthNutritionV204(result,data.nutrition,s);else if(result){result.textContent=String(data?.interpretation||'บันทึกผลแล้ว');result.hidden=false}showPhcToast('บันทึกผลการเจริญเติบโตแล้ว');load().catch(()=>{})}catch(e){err.textContent=friendlyError(e)}
  };
  if(box)box.innerHTML='<div>กำลังโหลดประวัติ…</div>';
  load().catch(()=>{if(latestBox)latestBox.textContent='โหลดประวัติเดิมไม่ได้ แต่ยังบันทึกผลใหม่ได้';if(box)box.innerHTML='<div>ยังโหลดประวัติไม่ได้</div>'});
}
const DEV=[['gross_motor','การเคลื่อนไหว','การเดิน วิ่ง ทรงตัว และใช้กล้ามเนื้อใหญ่ตามวัย',['เดิน/วิ่ง/ทรงตัวน้อยกว่าที่คาด','ใช้แขนขาไม่สมดุล','เปลี่ยนท่าหรือลุกนั่งลำบาก']],['fine_motor_intelligence','กล้ามเนื้อมัดเล็ก/สติปัญญา','การหยิบจับ ประสานมือ และแก้ปัญหาง่าย ๆ',['หยิบจับของชิ้นเล็กไม่คล่อง','ใช้มือประสานกันยาก','ทำกิจกรรมแก้ปัญหาง่าย ๆ ไม่ได้']],['receptive_language','การเข้าใจภาษา','การฟังและเข้าใจคำพูดหรือคำสั่งตามวัย',['ไม่ทำตามคำสั่งง่าย ๆ','ไม่ตอบสนองเมื่อเรียกหรือสื่อสาร','เข้าใจคำพูดน้อยกว่าที่คาด']],['expressive_language','การใช้ภาษา','การพูดหรือสื่อความต้องการตามวัย',['พูดน้อยกว่าที่คาด','สื่อความต้องการไม่ได้','พูดไม่ชัด/เข้าใจยาก','ไม่ตอบสนองต่อการสื่อสาร']],['personal_social','การช่วยเหลือตนเอง/สังคม','การช่วยตนเอง เล่น และมีปฏิสัมพันธ์ตามวัย',['ช่วยเหลือตนเองตามวัยได้ยาก','เล่นหรือมีปฏิสัมพันธ์กับผู้อื่นน้อย','ปรับตัวกับกิจวัตรได้ยาก']]];
function developmentHtml(target){return `<section class="phc190-step" data-dev><h3>พัฒนาการเบื้องต้น 5 ด้าน</h3><div class="phc190-note">อายุจริงใช้คำนวณทุกครั้ง · ช่วงอ้างอิงที่ใกล้เคียง ${target||'—'} เดือน · ใช้เพื่อคัดกรองเบื้องต้น ไม่ใช้คำว่า “พัฒนาการล่าช้า” อัตโนมัติ</div><button class="phc190-secondary" data-all-normal>✓ ทุกด้านปกติ</button><div class="phc190-domain-grid">${DEV.map(([k,l,tip,items])=>`<article class="phc190-domain" data-dev-domain="${k}" data-status="not_assessed"><h4>${l}</h4><p>${tip}</p><div class="phc190-state-row"><button class="phc190-state normal" type="button" data-state="normal">✓ ปกติ</button><button class="phc190-state observation" type="button" data-state="observation">พบข้อสังเกต</button><button class="phc190-state not_assessed active" type="button" data-state="not_assessed">ไม่ได้ประเมิน</button></div><div class="phc190-observe">${items.map(x=>`<label><input type="checkbox" value="${esc(x)}">${esc(x)}</label>`).join('')}</div></article>`).join('')}</div><label>หมายเหตุสั้น<textarea data-dev-note maxlength="500"></textarea></label><div class="phc190-note phc190-save-result" data-dev-result hidden></div><div class="phc190-error" data-dev-error></div><button class="phc190-primary" data-dev-save>บันทึกพัฒนาการ</button></section>`}
function setDomainState(card,state){card.dataset.status=state;card.querySelectorAll('.phc190-state').forEach(b=>b.classList.toggle('active',b.dataset.state===state))}
function bindDevelopment(root,s){const dev=$('[data-dev]',root),result=dev.querySelector('[data-dev-result]');dev.querySelectorAll('[data-dev-domain]').forEach(card=>card.querySelectorAll('[data-state]').forEach(b=>b.onclick=()=>setDomainState(card,b.dataset.state)));dev.querySelector('[data-all-normal]').onclick=()=>dev.querySelectorAll('[data-dev-domain]').forEach(c=>setDomainState(c,'normal'));dev.querySelector('[data-dev-save]').onclick=async()=>{const domains={},notes=[];dev.querySelectorAll('[data-dev-domain]').forEach(card=>{domains[card.dataset.devDomain]=card.dataset.status;if(card.dataset.status==='observation'){const checked=[...card.querySelectorAll('input:checked')].map(x=>x.value);if(checked.length)notes.push(`${DEV.find(x=>x[0]===card.dataset.devDomain)?.[1]||card.dataset.devDomain}: ${checked.join(', ')}`)}});const note=[dev.querySelector('[data-dev-note]').value.trim(),...notes].filter(Boolean).join(' | ').slice(0,500),err=dev.querySelector('[data-dev-error]');err.textContent='';if(result)result.hidden=true;try{await ensureScreeningSessionV2023(s);const {data,error}=await supabase.rpc('save_child_development_v190',{p_session_id:s.session_id,p_domains:domains,p_note:note});if(error)throw error;const label=String(data?.overall_label||'บันทึกพัฒนาการแล้ว'),handoff=/ควร|เพิ่มเติม|ติดตาม/.test(label);if(result){result.textContent=`บันทึกแล้ว · ${label}${handoff?' · ส่งงานติดตามให้เจ้าหน้าที่แล้ว':''}`;result.className=`phc190-note phc190-save-result ${/ควร|เพิ่มเติม|ติดตาม|ไม่ครบ/.test(label)?'phc190-warning':''}`;result.hidden=false}showPhcToast('บันทึกพัฒนาการแล้ว',/ควร|เพิ่มเติม|ติดตาม|ไม่ครบ/.test(label)?'warn':'success')}catch(e){err.textContent=friendlyError(e)}}}
const ELDER_V207=[
  {code:'cognition',label:'ความคิดความจำ',icon:'🧠',tool:'Mini-Cog'},
  {code:'mobility',label:'การเคลื่อนไหวร่างกาย',icon:'🚶',tool:'Timed Up and Go + ประวัติหกล้ม'},
  {code:'nutrition',label:'การขาดสารอาหาร',icon:'🍚',tool:'คำถาม 2 ข้อ'},
  {code:'vision',label:'การมองเห็น',icon:'👁️',tool:'คำถาม 1 ข้อ'},
  {code:'hearing',label:'การได้ยิน',icon:'👂',tool:'Finger rub test'},
  {code:'depression',label:'ซึมเศร้า/ความเสี่ยงฆ่าตัวตาย',icon:'💬',tool:'2Q plus'},
  {code:'urinary',label:'การกลั้นปัสสาวะ',icon:'🚻',tool:'คำถาม 1 ข้อ'},
  {code:'adl',label:'การปฏิบัติกิจวัตรประจำวัน',icon:'🧍',tool:'คำถาม 1 ข้อ'},
  {code:'oral',label:'สุขภาพช่องปาก',icon:'🦷',tool:'คำถาม 2 ข้อ'}
];
const elderBoolValueV207=(r,k)=>typeof r?.checklist?.[k]==='boolean'?r.checklist[k]:null;
function elderBoolChoiceV207(name,value,trueLabel='มี',falseLabel='ไม่มี'){
  const v=value===true?'true':value===false?'false':'';
  return `<div class="phc207-choice-row" data-bool-group="${esc(name)}" data-value="${v}"><button type="button" class="phc207-choice ${v==='false'?'active':''}" data-bool-value="false">${esc(falseLabel)}</button><button type="button" class="phc207-choice ${v==='true'?'active':''}" data-bool-value="true">${esc(trueLabel)}</button></div>`;
}
function elderEnumChoiceV207(name,value,items){return `<div class="phc207-choice-grid" data-enum-group="${esc(name)}" data-value="${esc(value||'')}">${items.map(([v,l])=>`<button type="button" class="phc207-choice ${value===v?'active':''}" data-enum-value="${esc(v)}">${esc(l)}</button>`).join('')}</div>`}
function elderRiskClassV207(r){if(!r)return'';if(r.status==='normal')return'done';if(r.status==='observation'&&r.checklist?.priority==='red')return'urgent';if(r.status==='observation')return'risk';return''}
function elderlyQuestionHtmlV207(def,r){
  const c=r?.checklist||{};
  if(def.code==='cognition')return `<div class="phc207-question"><p>1) บอกคำ 3 คำ ให้ผู้สูงอายุพูดตามและจำไว้ก่อน</p><div class="phc207-miniwords"><span>หลานสาว</span><span>สวรรค์</span><span>ภูเขา</span></div><p>2) ให้ผู้สูงอายุวาดนาฬิกา ใส่ตัวเลข และเข็มนาฬิกาเวลา 11.10 น.</p><label>ใส่ตัวเลขหน้าปัดถูกต้องหรือไม่${elderBoolChoiceV207('clock_numbers_correct',elderBoolValueV207(r,'clock_numbers_correct'),'ถูกต้อง','ไม่ถูกต้อง')}</label><label>ใส่เข็มนาฬิกาถูกต้องหรือไม่${elderBoolChoiceV207('clock_hands_correct',elderBoolValueV207(r,'clock_hands_correct'),'ถูกต้อง','ไม่ถูกต้อง')}</label><label>3) ทวนคำได้กี่คำ<select class="phc207-number" data-elder-select="recall_count"><option value="">เลือกจำนวนคำ</option>${[0,1,2,3].map(n=>`<option value="${n}" ${Number(c.recall_count)===n?'selected':''}>${n} คำ</option>`).join('')}</select></label><div class="phc207-source">ระบบคำนวณ Mini-Cog เต็ม 5 คะแนน; ≤3 คะแนน = ส่งต่อเจ้าหน้าที่ประเมินเพิ่มเติม</div></div>`;
  if(def.code==='mobility')return `<div class="phc207-question"><p>ให้ลุกจากเก้าอี้ เดิน 3 เมตร หมุนตัว เดินกลับ 3 เมตร และนั่งลงตามปกติ</p><label>สามารถทำการทดสอบได้หรือไม่${elderBoolChoiceV207('unable',elderBoolValueV207(r,'unable')===null?null:!elderBoolValueV207(r,'unable'),'ทำได้','ทำไม่ได้').replace('data-bool-group="unable"','data-bool-group="able"')}</label><div class="phc207-timer"><button type="button" class="phc190-secondary" data-tug-timer>▶ เริ่มจับเวลา</button><div class="phc207-timer-display" data-tug-display>${c.tug_seconds?`${Number(c.tug_seconds).toFixed(1)} วินาที`:'—'}</div></div><label>เวลาที่ใช้ (วินาที)<input class="phc207-number" data-tug-seconds type="number" inputmode="decimal" min="0.1" max="300" step="0.1" value="${esc(c.tug_seconds??'')}"></label><p>มีประวัติหกล้มภายใน 6 เดือนอย่างน้อย 1 ครั้งหรือไม่?</p>${elderBoolChoiceV207('fall_6m',elderBoolValueV207(r,'fall_6m'))}<div class="phc207-source">≥12 วินาที / ทำไม่ได้ / มีประวัติหกล้ม = เสี่ยง</div></div>`;
  if(def.code==='nutrition')return `<div class="phc207-question"><p>น้ำหนักลดมากกว่า 3 กิโลกรัมในช่วง 3 เดือนที่ผ่านมา โดยไม่ได้ตั้งใจลดน้ำหนักหรือไม่?</p>${elderBoolChoiceV207('weight_loss_3kg_3m',elderBoolValueV207(r,'weight_loss_3kg_3m'))}<p>ความอยากอาหารลดลงหรือไม่?</p>${elderBoolChoiceV207('appetite_loss',elderBoolValueV207(r,'appetite_loss'))}</div>`;
  if(def.code==='vision')return `<div class="phc207-question"><p>มีปัญหาเกี่ยวกับดวงตา เช่น การมองระยะไกล หรือการอ่านหนังสือหรือไม่? หากมีแว่น ให้ประเมินขณะสวมแว่นที่ใช้เป็นประจำ</p>${elderBoolChoiceV207('vision_problem',elderBoolValueV207(r,'vision_problem'))}</div>`;
  if(def.code==='hearing')return `<div class="phc207-question"><p>ถูนิ้วโป้งกับนิ้วชี้ห่างจากหูประมาณ 1 นิ้ว ทดสอบทีละข้างทั้งขวาและซ้าย</p>${elderEnumChoiceV207('hearing_result',c.hearing_result,[['both','ได้ยินทั้ง 2 ข้าง'],['left_only','ได้ยินเฉพาะข้างซ้าย'],['right_only','ได้ยินเฉพาะข้างขวา'],['none','ไม่ได้ยินทั้ง 2 ข้าง']])}</div>`;
  if(def.code==='depression')return `<div class="phc207-question"><p><strong>ใน 2 สัปดาห์ที่ผ่านมา รวมวันนี้</strong> รู้สึกไม่สบายใจ เซ็ง ทุกข์ใจ เศร้า ท้อแท้ ซึม หรือหงอยหรือไม่?</p>${elderBoolChoiceV207('q1',elderBoolValueV207(r,'q1'))}<p>เบื่อ ไม่อยากพูด ไม่อยากทำอะไร หรือทำอะไรก็ไม่สนุกเพลิดเพลินเหมือนเดิมหรือไม่?</p>${elderBoolChoiceV207('q2',elderBoolValueV207(r,'q2'))}<p><strong>ใน 1 เดือนที่ผ่านมา รวมวันนี้</strong> มีความรู้สึกทุกข์ใจจนไม่อยากมีชีวิตอยู่หรือไม่?</p>${elderBoolChoiceV207('q3',elderBoolValueV207(r,'q3'))}<div class="phc207-source">ข้อ 1–2 มีอย่างน้อย 1 ข้อ = ส่งเจ้าหน้าที่ประเมิน 9Q ต่อ · ข้อ 3 มี = งานติดตามเร่งด่วน</div></div>`;
  if(def.code==='urinary')return `<div class="phc207-question"><p>มีปัสสาวะเล็ดหรือปัสสาวะราดจนทำให้เกิดปัญหาในการใช้ชีวิตประจำวันหรือไม่?</p>${elderBoolChoiceV207('urinary_problem',elderBoolValueV207(r,'urinary_problem'))}</div>`;
  if(def.code==='adl')return `<div class="phc207-question"><p>ความสามารถช่วยเหลือตนเองในการทำกิจวัตรประจำวันโดยไม่ต้องพึ่งคนอื่นลดลงหรือไม่? เช่น กินอาหาร ล้างหน้า แปรงฟัน/หวีผม ลุกนั่ง เข้าห้องน้ำ เดินในบ้าน สวมเสื้อผ้า ขึ้นลงบันได อาบน้ำ กลั้นอุจจาระ/ปัสสาวะ</p>${elderBoolChoiceV207('adl_decline',elderBoolValueV207(r,'adl_decline'))}</div>`;
  if(def.code==='oral')return `<div class="phc207-question"><p>มีความยากลำบากในการเคี้ยวอาหารแข็งหรือไม่?</p>${elderBoolChoiceV207('chewing_hard_problem',elderBoolValueV207(r,'chewing_hard_problem'))}<p>มีอาการเจ็บปวดในช่องปากหรือไม่?</p>${elderBoolChoiceV207('oral_pain',elderBoolValueV207(r,'oral_pain'))}</div>`;
  return '';
}
function bindElderlyChoiceControlsV207(step){
  step.querySelectorAll('[data-bool-group]').forEach(g=>g.querySelectorAll('[data-bool-value]').forEach(b=>b.onclick=()=>{g.dataset.value=b.dataset.boolValue;g.querySelectorAll('[data-bool-value]').forEach(x=>x.classList.toggle('active',x===b))}));
  step.querySelectorAll('[data-enum-group]').forEach(g=>g.querySelectorAll('[data-enum-value]').forEach(b=>b.onclick=()=>{g.dataset.value=b.dataset.enumValue;g.querySelectorAll('[data-enum-value]').forEach(x=>x.classList.toggle('active',x===b))}));
  const timer=step.querySelector('[data-tug-timer]');if(timer){let interval=null,start=0;const display=step.querySelector('[data-tug-display]'),input=step.querySelector('[data-tug-seconds]');timer.onclick=()=>{if(!start){start=Date.now();timer.textContent='■ หยุดจับเวลา';interval=setInterval(()=>{display.textContent=((Date.now()-start)/1000).toFixed(1)+' วินาที'},100)}else{const sec=Math.max(.1,(Date.now()-start)/1000);clearInterval(interval);interval=null;start=0;input.value=sec.toFixed(1);display.textContent=sec.toFixed(1)+' วินาที';timer.textContent='▶ เริ่มจับเวลา'}};}
}
function boolFromStepV207(step,name){const v=step.querySelector(`[data-bool-group="${name}"]`)?.dataset.value;return v==='true'?true:v==='false'?false:null}
function collectElderlyAnswersV207(step,code){
  const need=(v,msg)=>v===null||v===''?{ok:false,error:msg}:{ok:true};let x;
  if(code==='cognition'){const a=boolFromStepV207(step,'clock_numbers_correct'),b=boolFromStepV207(step,'clock_hands_correct'),r=step.querySelector('[data-elder-select="recall_count"]')?.value;if(!(x=need(a,'กรุณาระบุผลตัวเลขหน้าปัด')).ok)return x;if(!(x=need(b,'กรุณาระบุผลเข็มนาฬิกา')).ok)return x;if(r==='')return{ok:false,error:'กรุณาระบุจำนวนคำที่ทวนได้'};return{ok:true,answers:{clock_numbers_correct:a,clock_hands_correct:b,recall_count:Number(r)}}}
  if(code==='mobility'){const able=boolFromStepV207(step,'able'),fall=boolFromStepV207(step,'fall_6m');if(able===null)return{ok:false,error:'กรุณาระบุว่าสามารถทำ TUG ได้หรือไม่'};if(fall===null)return{ok:false,error:'กรุณาตอบประวัติหกล้ม'};const sec=Number(step.querySelector('[data-tug-seconds]')?.value||0);if(able&&(!sec||sec<=0))return{ok:false,error:'กรุณาจับเวลาหรือกรอกเวลา TUG'};return{ok:true,answers:{unable:!able,fall_6m:fall,...(able?{tug_seconds:sec}:{})}}}
  if(code==='nutrition'){const a=boolFromStepV207(step,'weight_loss_3kg_3m'),b=boolFromStepV207(step,'appetite_loss');if(a===null||b===null)return{ok:false,error:'กรุณาตอบทั้ง 2 ข้อ'};return{ok:true,answers:{weight_loss_3kg_3m:a,appetite_loss:b}}}
  if(code==='vision'){const a=boolFromStepV207(step,'vision_problem');return a===null?{ok:false,error:'กรุณาตอบคำถามการมองเห็น'}:{ok:true,answers:{vision_problem:a}}}
  if(code==='hearing'){const v=step.querySelector('[data-enum-group="hearing_result"]')?.dataset.value||'';return v?{ok:true,answers:{hearing_result:v}}:{ok:false,error:'กรุณาเลือกผลการทดสอบการได้ยิน'}}
  if(code==='depression'){const q1=boolFromStepV207(step,'q1'),q2=boolFromStepV207(step,'q2'),q3=boolFromStepV207(step,'q3');if(q1===null||q2===null||q3===null)return{ok:false,error:'กรุณาตอบ 2Q plus ให้ครบ 3 ข้อ'};return{ok:true,answers:{q1,q2,q3}}}
  if(code==='urinary'){const a=boolFromStepV207(step,'urinary_problem');return a===null?{ok:false,error:'กรุณาตอบคำถามการกลั้นปัสสาวะ'}:{ok:true,answers:{urinary_problem:a}}}
  if(code==='adl'){const a=boolFromStepV207(step,'adl_decline');return a===null?{ok:false,error:'กรุณาตอบคำถามกิจวัตรประจำวัน'}:{ok:true,answers:{adl_decline:a}}}
  if(code==='oral'){const a=boolFromStepV207(step,'chewing_hard_problem'),b=boolFromStepV207(step,'oral_pain');if(a===null||b===null)return{ok:false,error:'กรุณาตอบสุขภาพช่องปากทั้ง 2 ข้อ'};return{ok:true,answers:{chewing_hard_problem:a,oral_pain:b}}}
  return{ok:false,error:'ไม่รู้จักแบบคัดกรองด้านนี้'};
}
async function renderElderlyRoute(root,s,personName){root.innerHTML=`<section class="phc190-step"><h3>ขั้นที่ 1 · NCD Screening</h3><p data-ncd-state>${s.ncd_status==='complete'?'🟢 เรียบร้อยแล้ว':'🟡 ต้องทำก่อน 9 ด้าน'}</p>${s.ncd_status==='complete'?'':`<button class="phc190-primary" data-open-ncd>เปิด NCD Screening</button><button class="phc190-secondary" data-check-ncd>ตรวจสอบ NCD ที่บันทึกวันนี้</button>`}</section><section class="phc190-step" data-elderly ${s.ncd_status==='complete'?'':'hidden'}><div class="phc190-progress" data-elderly-progress>${s.ncd_status==='complete'?'กำลังเปิด 9 ด้าน…':'รอ NCD Screening'}</div><div data-elderly-wizard></div></section>`;root.querySelector('[data-open-ncd]')?.addEventListener('click',()=>openExistingNcd(personName,s.source_pcucode,s.source_pid));root.querySelector('[data-check-ncd]')?.addEventListener('click',async()=>{try{const {data:latest,error:planError}=await supabase.rpc('screening_plan_for_person_v2023',{p_source_pcucode:s.source_pcucode,p_source_pid:Number(s.source_pid),p_screening_date:thaiDayV208()});if(planError)throw planError;Object.assign(s,latest||{});if(s.ncd_status!=='complete'||!s.ncd_screening_id){showPhcToast('ยังไม่พบ NCD Screening ที่บันทึกวันนี้ กรุณาเปิด NCD Screening และบันทึกให้เสร็จก่อน','warn',3200);return}await ensureScreeningSessionV2023(s);const {data,error}=await supabase.rpc('attach_ncd_to_screening_session_v190',{p_session_id:s.session_id,p_ncd_screening_id:s.ncd_screening_id});if(error)throw error;Object.assign(s,data||{});await renderElderlyRoute(root,s,personName)}catch(e){showPhcToast(friendlyError(e),'warn',3200)}});if(s.ncd_status==='complete'){ensureScreeningSessionV2023(s).then(()=>loadElderlyWizardV207(root,s)).catch(e=>{const p=root.querySelector('[data-elderly-progress]');if(p)p.textContent=friendlyError(e)})}}
async function loadElderlyWizardV207(root,s,preferredIndex=null){
  const {data,error}=await supabase.rpc('elderly9_progress_v190',{p_session_id:s.session_id});const progress=root.querySelector('[data-elderly-progress]'),host=root.querySelector('[data-elderly-wizard]');if(error){progress.textContent=friendlyError(error);return}const saved=new Map((data.results||[]).map(x=>[x.domain_code,x]));progress.textContent=`คัดกรองผู้สูงอายุ 9 ด้าน · ทำแล้ว ${data.completed}/9 · เหลือ ${data.remaining} · พบความเสี่ยง ${data.observations} ด้าน`;let index=preferredIndex;if(index===null||index===undefined){index=ELDER_V207.findIndex(d=>!saved.has(d.code)||!['normal','observation'].includes(saved.get(d.code)?.status));if(index<0)index=9}if(index>=9){renderElderlySummaryV207(host,s,saved,data);return}index=Math.max(0,Math.min(8,index));const def=ELDER_V207[index],r=saved.get(def.code);host.innerHTML=`<div class="phc207-wizard"><div class="phc207-stepbar"><div class="phc207-step-tabs">${ELDER_V207.map((d,i)=>`<button type="button" class="phc207-step-tab ${i===index?'current':''} ${elderRiskClassV207(saved.get(d.code))}" data-elder-step="${i}" aria-label="ด้าน ${i+1} ${esc(d.label)}">${i+1}</button>`).join('')}</div></div><div class="phc207-step-title"><span class="icon">${def.icon}</span><div><h3>${index+1}. ${esc(def.label)}</h3><small>${esc(def.tool)} · อสม.ตอบคำถาม/ทดสอบ ระบบแปลผลอัตโนมัติ</small></div></div>${elderlyQuestionHtmlV207(def,r)}<label>หมายเหตุเพิ่มเติม (ไม่บังคับ)<textarea data-elder-note maxlength="500">${esc(r?.note||'')}</textarea></label><div class="phc190-error" data-elder-error></div>${r?`<div class="phc207-result ${r.status==='observation'?(r.checklist?.priority==='red'?'urgent':'risk'):''}">ผลที่บันทึกไว้: ${r.status==='normal'?'ปกติ':'พบความเสี่ยง'}${r.checklist?.score!==undefined?` · ${r.checklist.score}/5 คะแนน`:''}${r.status==='observation'?' · ส่งงานให้เจ้าหน้าที่ติดตามแล้ว':''}</div>`:''}<div class="phc207-nav"><button type="button" class="phc190-secondary" data-elder-prev ${index===0?'disabled':''}>← ก่อนหน้า</button><button type="button" class="phc190-primary" data-elder-next>${index===8?'บันทึกและสรุป':'บันทึก · ถัดไป →'}</button></div></div>`;const step=host.querySelector('.phc207-wizard');bindElderlyChoiceControlsV207(step);host.querySelectorAll('[data-elder-step]').forEach(b=>b.onclick=()=>loadElderlyWizardV207(root,s,Number(b.dataset.elderStep)));host.querySelector('[data-elder-prev]').onclick=()=>loadElderlyWizardV207(root,s,index-1);host.querySelector('[data-elder-next]').onclick=async()=>{const out=collectElderlyAnswersV207(step,def.code),err=step.querySelector('[data-elder-error]');err.textContent='';if(!out.ok){err.textContent=out.error;return}const btn=host.querySelector('[data-elder-next]');btn.disabled=true;try{const {data:res,error:e}=await supabase.rpc('save_elderly9_community_v207',{p_session_id:s.session_id,p_domain_code:def.code,p_answers:out.answers,p_note:step.querySelector('[data-elder-note]').value.trim()});if(e)throw e;if(res?.urgent){showPhcToast('พบความเสี่ยงเร่งด่วน · ส่งงานให้เจ้าหน้าที่แล้ว','warn',4000)}else if(res?.status==='observation'){showPhcToast('บันทึกแล้ว · ส่งงานให้เจ้าหน้าที่ติดตาม','warn',2400)}else showPhcToast('บันทึกด้านนี้แล้ว');await loadElderlyWizardV207(root,s,index+1)}catch(e){err.textContent=friendlyError(e);btn.disabled=false}};
}
function renderElderlySummaryV207(host,s,saved,data){const obs=[...saved.values()].filter(r=>r.status==='observation').length;host.innerHTML=`<div class="phc207-wizard"><div class="phc207-stepbar"><div class="phc207-step-tabs">${ELDER_V207.map((d,i)=>`<button type="button" class="phc207-step-tab ${elderRiskClassV207(saved.get(d.code))}" data-elder-summary-step="${i}">${i+1}</button>`).join('')}</div></div><div class="phc207-step-title"><span class="icon">✅</span><div><h3>สรุปคัดกรองผู้สูงอายุ 9 ด้าน</h3><small>คัดกรองครบ ${data.completed}/9 ด้าน</small></div></div>${[...saved.values()].some(r=>r.checklist?.priority==='red')?'<div class="phc207-urgent-note">พบผลสุขภาพจิตเร่งด่วน ระบบสร้างงานติดตามระดับสีแดงแล้ว กรุณาแจ้งเจ้าหน้าที่/หน่วยบริการทันที</div>':''}<div class="phc207-summary">${ELDER_V207.map((d,i)=>{const r=saved.get(d.code),urgent=r?.checklist?.priority==='red';return `<div class="phc207-summary-row ${r?.status==='normal'?'normal':urgent?'urgent':'risk'}"><strong>${i+1}. ${esc(d.label)}</strong><span>${r?.status==='normal'?'ปกติ':urgent?'เร่งด่วน':'เสี่ยง'}</span></div>`}).join('')}</div><div class="phc190-note">${obs?`พบความเสี่ยง ${obs} ด้าน · ระบบส่งงานติดตามให้ Staff/Admin แล้ว อสม.ไม่ต้องปิดเคสเอง`:'ผลเบื้องต้นปกติครบ 9 ด้าน'}</div><div class="phc207-source">อ้างอิง Community Screening กระทรวงสาธารณสุข / กรมอนามัย / กรมการแพทย์ / กรมสุขภาพจิต · ผลนี้เป็นการคัดกรอง ไม่ใช่การวินิจฉัยโรค</div><div class="phc190-actions"><button type="button" class="phc190-secondary" data-elder-edit>แก้ไขรายด้าน</button><button type="button" class="phc190-primary" data-elder-close>เสร็จสิ้น</button></div></div>`;host.querySelector('[data-elder-edit]').onclick=()=>loadElderlyWizardV207(host.closest('[data-route]'),s,0);host.querySelector('[data-elder-close]').onclick=closeModal;host.querySelectorAll('[data-elder-summary-step]').forEach(b=>b.onclick=()=>loadElderlyWizardV207(host.closest('[data-route]'),s,Number(b.dataset.elderSummaryStep)))}

function appointmentResponseLabelV205(value){return ({accepted:'ตอบรับแล้ว',declined:'ไม่สะดวก',acknowledged:'รับทราบแล้ว'})[value]||''}
function appointmentCardV205(a){if(!a)return'';const status=appointmentResponseLabelV205(a.response);return `<section class="phc190-request" data-my-appointment="${esc(a.id)}"><strong>นัดถัดไป: ${esc(a.title||'นัดหมาย')}</strong><small>${esc(fmt(a.appointment_at))}${a.location?` · ${esc(a.location)}`:''}</small>${status?`<div class="phc190-status verified">${esc(status)}</div>`:'<div class="phc190-note">กรุณาตอบรับนัดหมาย</div>'}<div class="phc190-actions"><button type="button" class="phc190-primary" data-appointment-response="accepted">รับนัด</button><button type="button" class="phc190-secondary" data-appointment-response="declined">ไม่สะดวก</button></div><button type="button" class="phc190-secondary" style="width:100%;margin-top:8px" data-appointment-response="acknowledged">รับทราบ</button></section>`}
function bindAppointmentResponseV205(root){root?.querySelectorAll('[data-my-appointment]').forEach(card=>card.querySelectorAll('[data-appointment-response]').forEach(button=>button.onclick=async()=>{button.disabled=true;try{const {error}=await supabase.rpc('respond_appointment_v190',{p_appointment_id:card.dataset.myAppointment,p_response:button.dataset.appointmentResponse});if(error)throw error;showPhcToast('บันทึกการตอบรับนัดหมายแล้ว');await renderOverview()}catch(e){showPhcToast(friendlyError(e),'warn',2600)}finally{button.disabled=false}}))}

async function openAdminCommunication(){
  const body=openModal('LINE / นัดหมาย','ส่งเฉพาะข้อความสรุปที่จำเป็น ห้ามใส่เลขบัตรประชาชนเต็มหรือรายละเอียดสุขภาพพร้อมระบุตัวบุคคล');
  body.innerHTML='<div class="phc190-note">กำลังโหลดผู้ใช้และกลุ่ม…</div>';
  const [pr,gr]=await Promise.all([supabase.from('profiles').select('user_id,display_name,role,community').eq('active',true).order('display_name'),supabase.from('line_message_groups').select('id,name').eq('active',true).order('name')]);
  if(pr.error){body.innerHTML=`<div class="phc190-error">${esc(friendlyError(pr.error))}</div>`;return}
  const users=pr.data||[],groups=gr.data||[];
  const userOptions=users.map(u=>`<option value="${esc(u.user_id)}">${esc(u.display_name)} · ${esc(u.role)} · ${esc(u.community||'—')}</option>`).join('');
  const groupOptions=groups.map(g=>`<option value="${esc(g.id)}">${esc(g.name)}</option>`).join('');
  body.innerHTML=`
  <form class="phc190-form" data-line-individual><h3>ส่งข้อความรายบุคคล</h3><label>ผู้รับ<select name="user" required>${userOptions}</select></label><label>ข้อความ<textarea name="body" maxlength="500" required placeholder="เช่น มีงานติดตามในพื้นที่รับผิดชอบ กรุณาเปิด OSM-PHC"></textarea></label><div class="phc190-error" data-err></div><button class="phc190-primary">เข้าคิวส่ง LINE</button></form>
  <form class="phc190-form" data-line-broadcast><h3>ส่งข้อความเป็นกลุ่ม</h3><label>ขอบเขต<select name="scope"><option value="all">ผู้ใช้ที่เชื่อม LINE ทั้งหมด</option><option value="community">ตามชุมชน</option><option value="role">ตาม Role</option><option value="urgent">กลุ่มงานเร่งด่วน</option><option value="group">กลุ่มงานที่สร้างไว้</option></select></label><label data-scope-value>ค่าอ้างอิง<input name="value" placeholder="ชื่อชุมชน หรือ role: user/staff"></label><label data-group-value hidden>กลุ่ม<select name="group">${groupOptions}</select></label><label>ข้อความ<textarea name="body" maxlength="500" required></textarea></label><div class="phc190-error" data-err></div><button class="phc190-primary">เข้าคิวส่งกลุ่ม</button></form>
  <form class="phc190-form" data-appointment><h3>สร้างนัดหมาย</h3><label>ผู้รับ<select name="user" required>${userOptions}</select></label><label>หัวข้อ<input name="title" maxlength="160" required></label><label>วันเวลา<input name="at" type="datetime-local" required></label><label>สถานที่<input name="location" maxlength="240"></label><div class="phc190-error" data-err></div><button class="phc190-primary">สร้างนัดหมาย</button></form>
  <form class="phc190-form" data-line-group><h3>สร้างกลุ่มงาน LINE</h3><label>ชื่อกลุ่ม<input name="name" maxlength="120" required></label><label>สมาชิก<select name="members" multiple size="8" style="min-height:180px">${userOptions}</select></label><div class="phc190-note">บนมือถือกดเลือกสมาชิกทีละรายได้ตามความสามารถของเบราว์เซอร์</div><div class="phc190-error" data-err></div><button class="phc190-secondary">บันทึกกลุ่ม</button></form>`;
  const unsafe=v=>/\d{13}/.test(v)||/(password|api[ _-]?key|service[ _-]?role|bot[ _-]?token|secret)\s*[:=]/i.test(v);
  const fi=body.querySelector('[data-line-individual]');fi.onsubmit=async e=>{e.preventDefault();const d=new FormData(fi),msg=String(d.get('body')||''),err=fi.querySelector('[data-err]');err.textContent='';if(unsafe(msg)){err.textContent='ข้อความมีข้อมูลอ่อนไหวที่ห้ามส่ง';return}const {error}=await supabase.rpc('admin_queue_line_message_v190',{p_recipient_user_id:d.get('user'),p_body:msg,p_action_path:'?panel=overview',p_message_type:'notice'});if(error)err.textContent=friendlyError(error);else{alert('เข้าคิวส่ง LINE แล้ว');fi.reset()}};
  const fb=body.querySelector('[data-line-broadcast]'),scope=fb.elements.scope,valWrap=fb.querySelector('[data-scope-value]'),groupWrap=fb.querySelector('[data-group-value]');const syncScope=()=>{valWrap.hidden=['all','urgent','group'].includes(scope.value);groupWrap.hidden=scope.value!=='group'};scope.onchange=syncScope;syncScope();fb.onsubmit=async e=>{e.preventDefault();const d=new FormData(fb),msg=String(d.get('body')||''),err=fb.querySelector('[data-err]');err.textContent='';if(unsafe(msg)){err.textContent='ข้อความมีข้อมูลอ่อนไหวที่ห้ามส่ง';return}const st=String(d.get('scope')),sv=st==='group'?String(d.get('group')||''):String(d.get('value')||'');const {data,error}=await supabase.rpc('admin_queue_line_broadcast_v190',{p_scope_type:st,p_scope_value:sv,p_body:msg,p_action_path:'?panel=overview',p_message_type:st==='urgent'?'urgent_task':'notice'});if(error)err.textContent=friendlyError(error);else{alert(`เข้าคิวส่ง ${data.queued||0} ราย`);fb.reset();syncScope()}};
  const fa=body.querySelector('[data-appointment]');fa.onsubmit=async e=>{e.preventDefault();const d=new FormData(fa),err=fa.querySelector('[data-err]');err.textContent='';const at=new Date(String(d.get('at')));if(!Number.isFinite(at.getTime())){err.textContent='กรุณาระบุวันเวลา';return}const {error}=await supabase.rpc('admin_create_appointment_v190',{p_app_user_id:d.get('user'),p_title:d.get('title'),p_appointment_at:at.toISOString(),p_location:d.get('location')||'',p_note:''});if(error)err.textContent=friendlyError(error);else{alert('สร้างนัดหมายแล้ว');fa.reset()}};
  const fg=body.querySelector('[data-line-group]');fg.onsubmit=async e=>{e.preventDefault();const err=fg.querySelector('[data-err]');err.textContent='';const ids=[...fg.elements.members.selectedOptions].map(o=>o.value);if(!ids.length){err.textContent='เลือกสมาชิกอย่างน้อย 1 คน';return}const {error}=await supabase.rpc('admin_save_line_group_v190',{p_group_id:null,p_name:fg.elements.name.value,p_user_ids:ids});if(error)err.textContent=friendlyError(error);else{alert('บันทึกกลุ่มแล้ว');closeModal();await openAdminCommunication()}};
}
const LINE_STATUS_CACHE_MS_V2039=180000;
async function loadMyLineStatusV2038(){return sharedCall('my-line-status-v190',()=>supabase.rpc('my_line_status_v190'),LINE_STATUS_CACHE_MS_V2039);}
function armLineLinkReturnRefreshV2039(){window.__PHC_LINE_LINK_AWAITING_V2039__=true;}
function bindLineLinkReturnRefreshV2039(){if(window.__PHC_LINE_LINK_VISIBILITY_V2039__)return;window.__PHC_LINE_LINK_VISIBILITY_V2039__=true;document.addEventListener('visibilitychange',()=>{if(document.visibilityState!=='visible'||!window.__PHC_LINE_LINK_AWAITING_V2039__)return;window.__PHC_LINE_LINK_AWAITING_V2039__=false;invalidateShared('my-line-status-v190');if(isPortalViewActive('work'))renderOverview().catch(()=>{});});}
async function renderOverview(){
  const panel=$('[data-portal-panel="work"]');if(!panel||!profile?.active)return;
  let root=$('[data-phc190-overview]');
  if(!root){root=document.createElement('section');root.className='phc190-overview';root.dataset.phc190Overview='1'}
  if(root.parentElement!==panel){const fieldHost=panel.querySelector('[data-field200-host]');if(fieldHost)panel.insertBefore(root,fieldHost);else panel.prepend(root)}
  if(profile.role==='admin'){
    await renderAdminWorkProgressiveV2057(root);
  }else{
    const {data,error}=await loadMyLineStatusV2038();
    const connected=!error&&Boolean(data?.connected);
    root.classList.toggle('phc190-overview--line-compact',connected);
    root.innerHTML=connected
      ? `<details class="phc190-line-compact"><summary aria-label="LINE ของฉัน เชื่อมต่อแล้ว เปิดเพื่อจัดการการเชื่อมต่อ"><span class="phc190-line-title">LINE ของฉัน</span><span class="phc190-line-status">● เชื่อมต่อแล้ว</span><span class="phc190-line-manage" aria-hidden="true">จัดการ ›</span></summary><div class="phc190-line-settings"><button type="button" class="phc190-secondary" data-unlink-line>ยกเลิกการเชื่อม LINE</button></div></details>${appointmentCardV205(data?.next_appointment)}`
      : `<h3>LINE ของฉัน</h3>${error?'<div class="phc190-note">ยังไม่สามารถอ่านสถานะ LINE ได้</div>':`<div class="phc190-note">🟡 ยังไม่ได้เชื่อมบัญชี</div><button class="phc190-primary" data-link-line>เชื่อม LINE</button>`}`;
    bindAppointmentResponseV205(root);
    root.querySelector('[data-link-line]')?.addEventListener('click',createLineCode);
    root.querySelector('[data-unlink-line]')?.addEventListener('click',async()=>{
      if(!confirm('ยืนยันยกเลิกการเชื่อม LINE?'))return;
      const {error:unlinkError}=await supabase.rpc('unlink_my_line_v190');
      if(unlinkError){showPhcToast(friendlyError(unlinkError),'warn',3000);return;}
      invalidateShared('my-line-status-v190');await renderOverview();
    });
  }
}
function showNotifications(rows){const body=openModal('การแจ้งเตือน Admin','ข้อความแจ้งเตือนเก็บเฉพาะข้อมูลสรุป ไม่แสดงเลขบัตรหรือรายละเอียดสุขภาพพร้อมตัวบุคคล');body.innerHTML=(rows||[]).map(r=>`<article class="phc190-request"><strong>${esc(r.title)}</strong><small>${esc(r.body)} · ${esc(fmt(r.created_at))}</small></article>`).join('')||'<div class="phc190-note">ยังไม่มีการแจ้งเตือน</div>'}
async function createLineCode(){
  const body=openModal('เชื่อม LINE','รหัสใช้ครั้งเดียวและหมดอายุใน 10 นาที');
  body.innerHTML='<div class="phc190-note">กำลังสร้างรหัส…</div>';
  const {data,error}=await supabase.rpc('create_line_link_code_v190');
  if(error){body.innerHTML=`<div class="phc190-error">${esc(friendlyError(error))}</div>`;return}
  armLineLinkReturnRefreshV2039();const linkText=`LINK ${String(data.code||'')}`;
  body.innerHTML=`<div class="phc190-note">ส่งข้อความนี้ไปที่ LINE OA ของหน่วยงาน</div><div class="phc190-code" data-line-link-code>${esc(linkText)}</div><button type="button" class="phc190-primary" data-copy-line-link>คัดลอกรหัส LINE</button><div class="phc190-note" data-copy-line-status>หลัง LINE ยืนยันสำเร็จ กลับมาเปิดเมนู “ผลงาน/ติดตาม” อีกครั้งเพื่อดูสถานะ</div>`;
  const btn=body.querySelector('[data-copy-line-link]'),status=body.querySelector('[data-copy-line-status]');
  btn.onclick=async()=>{const ok=await copyTextV202(linkText);if(ok){btn.textContent='✓ คัดลอกแล้ว';status.textContent='คัดลอกแล้ว นำข้อความไปวางใน LINE OA ของหน่วยงานได้ทันที';setTimeout(()=>{if(document.body.contains(btn))btn.textContent='คัดลอกรหัส LINE'},1600)}else{status.textContent='คัดลอกอัตโนมัติไม่ได้ กรุณากดค้างที่รหัสเพื่อคัดลอก'}};
}

function bindGlobal(){if(globalBound)return;globalBound=true;document.addEventListener('click',e=>{const b=e.target.closest?.('[data-phc190-screen]');if(b){e.preventDefault();e.stopPropagation();const seed={plan_date:b.dataset.planDate||'',age_years:Number(b.dataset.ageYears),age_months:Number(b.dataset.ageMonths),route:b.dataset.screenRoute||'',route_label:b.dataset.routeLabel||'',dspm_target_months:b.dataset.dspmTarget?Number(b.dataset.dspmTarget):null,latest_screened_on:b.dataset.latestScreened||''};openAgeScreening(b.dataset.pcucode,Number(b.dataset.pid),b.dataset.name||'',seed).catch(x=>alert(friendlyError(x)));return}},true)}
async function start(){const ver=$('.login-version');if(ver)ver.textContent=`Cloud v${VERSION}`;window.PHCFiveFeatures190={renderHouseMemberRequests,openAgeScreening,renderAdminMemberQueue,refreshOverview:renderOverview};bindGlobal();bindLineLinkReturnRefreshV2039();bindPortalActivation('work',async()=>{profile=await loadProfile();if(profile?.active)await renderOverview();});}
export async function initPHCFiveFeatures190(url,key){if(window.__PHC_FIVE_FEATURES_190__)return;window.__PHC_FIVE_FEATURES_190__=true;injectStyle();supabase=await getSharedSupabase(url,key);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else await start()}
