// Additive admin queue + field confirmation, isolated from legacy screen modules.
import { SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY } from './config.js?v=2.0.168-house-number-sort&p=2221';
import { getSharedSupabase,getSharedProfile,bindPortalActivation } from './shared-runtime-v2035.mjs?v=2.0.126-log-usage';
import { openAdminMemberWorklistV2215,renderFieldMemberVisibilityV2215 } from './member-request-workflow-v2215.mjs?v=2215';
const sb=await getSharedSupabase(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt=v=>{try{return v?new Date(v).toLocaleDateString('th-TH',{day:'numeric',month:'short',year:'numeric'}):'—';}catch{return String(v);}};
const friendlyError=e=>String(e?.message||e||'เกิดข้อผิดพลาด');
function toast(message){const b=document.createElement('div');b.className='member-2215-toast';b.setAttribute('role','status');b.textContent=message;document.body.appendChild(b);setTimeout(()=>b.remove(),3500);}
function closeModal(){document.getElementById('member-2215-overlay')?.remove();document.body.classList.remove('member-2215-locked');}
function openModal(title,subtitle){
 closeModal();
 const veil=document.createElement('div');veil.id='member-2215-overlay';veil.className='member-2215-overlay';
 veil.innerHTML='<section class="member-2215-modal" role="dialog" aria-modal="true"><header><div><h2>'+esc(title)+'</h2><small>'+esc(subtitle||'')+'</small></div><button type="button" data-close aria-label="ปิด">×</button></header><div data-member-2215-body></div></section>';
 veil.querySelector('[data-close]').onclick=closeModal;veil.onclick=e=>{if(e.target===veil)closeModal();};
 document.body.appendChild(veil);document.body.classList.add('member-2215-locked');
 return veil.querySelector('[data-member-2215-body]');
}
function openWorklist(){return openAdminMemberWorklistV2215({
 supabase:sb,openModal,esc,fmt,showPhcToast:toast,friendlyError,
 reviewRequest:async (id,decision,note='',pcucode=null,pid=null)=>{
   if(decision!=='verify'&&!note)note=prompt('ระบุเหตุผลสำหรับส่งกลับแก้ไข (ไม่ใส่เลข 13 หลัก)')||'';
   if(decision!=='verify'&&!note)return;
   if(decision==='verify'&&!confirm('ยืนยันว่าตรวจคำขอแล้ว (ยังไม่ถือว่าปิดงานจนกว่า JHCIS และ อสม. จะยืนยัน)?'))return;
   const {data,error}=await sb.rpc('review_household_member_request_v190',{p_request_id:id,p_decision:decision,p_note:note,p_link_pcucode:pcucode,p_link_pid:pid});
   if(error){alert(friendlyError(error));return;}
   toast(data?.message||'อัปเดตสถานะคำขอแล้ว');return openWorklist();
 },
 cancelMemberRequestV2070:async (id,name)=>{
   const reason=prompt('เหตุผลที่ต้องยกเลิกคำขอของ '+name+' (อย่างน้อย 5 ตัวอักษร ไม่ใส่เลขบัตร)')||'';
   if(reason.trim().length<5)return;
   if(!confirm('ยกเลิกคำขอเดิมโดยคงประวัติ และไม่ลบข้อมูลใน JHCIS?'))return;
   const {error}=await sb.rpc('admin_cancel_member_request_v2070',{p_request_id:id,p_reason:reason.trim()});
   if(error){alert(friendlyError(error));return;}
   toast('บันทึกการยกเลิกพร้อมเหตุผลแล้ว');return openWorklist();
 }
});}
function injectCSS(){
 const style=document.createElement('style');style.textContent=[
 '.member-2215-locked{overflow:hidden!important}',
 '.member-2215-overlay{position:fixed;inset:0;z-index:9998;background:#081f22b5;display:flex;justify-content:center;align-items:flex-start;overflow:auto;padding:12px}',
 '.member-2215-modal{background:#fff;color:#123e36;width:min(760px,100%);margin:auto;padding:18px;border-radius:18px;box-shadow:0 20px 80px #0005}',
 '.member-2215-modal header{display:flex;justify-content:space-between;gap:12px;align-items:start;margin-bottom:12px}',
 '.member-2215-modal h2{font-size:1.25rem;margin:0}.member-2215-modal header small{display:block;line-height:1.5;margin-top:6px}',
 '.member-2215-modal header button{font-size:2rem;padding:2px 14px;border:0;background:#e8f2ee;border-radius:8px}',
 '.member-2215-modal .phc190-request-list{display:grid;gap:9px}.member-2215-modal .phc190-request{border:1px solid #d9e4df;border-radius:12px;padding:12px;margin:6px 0}',
 '.member-2215-modal .phc190-request small{display:block;margin:4px 0}.member-2215-modal .phc190-note{padding:10px;background:#f1f7f4;border-radius:10px;margin:5px 0}',
 '.member-2215-modal .phc190-warning{background:#fff2d1}.member-2215-modal .phc190-status{display:inline-block;background:#f5f0d9;border-radius:9px;padding:4px 8px;font-size:.82rem}',
 '.member-2215-modal .phc190-actions{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0}.member-2215-modal .phc190-actions button{flex:1 1 130px}',
 '.member-2215-modal button{min-height:44px;padding:8px 12px}.member-2215-modal .phc190-primary{background:#087966;color:#fff;border:0;border-radius:10px}',
 '.member-2215-modal .phc190-secondary{background:#f1f8f5;color:#115d50;border:1px solid #b3d2c6;border-radius:10px}',
 '.member-2215-modal textarea{width:100%;min-height:82px}',
 '.member-2215-toast{position:fixed;z-index:9999;bottom:20px;left:14px;right:14px;max-width:600px;margin:auto;background:#084c42;color:white;padding:15px;border-radius:12px;text-align:center}',
 '.member-2215-admin-button{border:1px solid #92cbbb;color:#075d4a;background:#e7f8f2;border-radius:12px;padding:12px;min-height:52px;font:inherit;font-weight:700;width:100%;text-align:left}',
 '.member-2215-field{margin:10px 0;padding:12px;border:2px solid #b2dac8;border-radius:12px;background:#f2fbf6}',
 '.member-2215-field .phc190-request{padding:10px;border:1px solid #d5e9df;border-radius:9px;background:#fff}',
 '.member-2215-field button{padding:10px;border-radius:8px;min-height:44px;background:#087966;color:white;border:0}'
 ].join('\n');
 document.head.appendChild(style);
}
injectCSS();
bindPortalActivation('work',async()=>{
 const p=await getSharedProfile(sb),host=document.querySelector('[data-portal-panel="work"]');
 if(!host)return;
 const old=host.querySelector('[data-member-2215-admin]');
 if(!p?.active||p.role!=='admin'){old?.remove();return;}
 if(old)return;
 const button=document.createElement('button');button.type='button';button.className='member-2215-admin-button';button.dataset.member2215Admin='1';
 button.textContent='ติดตามคำขอเพิ่มสมาชิก · รอ JHCIS / รอ อสม. ยืนยัน / ส่งแก้ไข';
 button.onclick=openWorklist;host.insertAdjacentElement('afterbegin',button);
});
let fieldSeq=0;
document.addEventListener('phc:open-house-detail',async event=>{
 const houseId=event.detail?.houseId;if(!houseId)return;
 const seq=++fieldSeq,p=await getSharedProfile(sb);
 if(!p?.active||p.role!=='user')return;
 let found=false;
 const check=async()=>{
   if(seq!==fieldSeq||found)return true;
   const sections=[...document.querySelectorAll('.hq31-section,section,article')];
   const member=sections.find(el=>el.querySelector('h3')?.textContent?.includes('สมาชิกในบ้าน')&&el.offsetParent!==null);
   if(!member)return false;
   found=true;
   document.querySelector('[data-member-2215-field]')?.remove();
   const panel=document.createElement('section');panel.className='member-2215-field';panel.dataset.member2215Field='1';
   panel.textContent='ตรวจสอบการเชื่อมสมาชิกในบ้าน';
   member.insertAdjacentElement('afterend',panel);
   await renderFieldMemberVisibilityV2215({supabase:sb,houseId,sec:panel,esc,showPhcToast:toast,friendlyError});
   if(!panel.querySelector('[data-visibility-id]'))panel.remove();
   return true;
 };
 if(await check())return;
 const observer=new MutationObserver(async()=>{if(await check())observer.disconnect();});
 observer.observe(document.body,{subtree:true,childList:true});
 setTimeout(()=>observer.disconnect(),6500);
});
