import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js?v=2.0.31';

const supabase=createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
let adminReady=false;
let observing=false;
const $=(s,r=document)=>r.querySelector(s);
const esc=v=>String(v??'').replace(/[&<>"']/g,x=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));

function injectStyle(){
  if($('#line-oauth-settings-v2013-style'))return;
  const s=document.createElement('style');s.id='line-oauth-settings-v2013-style';s.textContent=`
  .line-oauth-settings-overlay{position:fixed;inset:0;z-index:9999;background:rgba(18,38,32,.38);display:grid;place-items:center;padding:18px}.line-oauth-settings-card{width:min(720px,100%);max-height:88vh;overflow:auto;background:#fff;border:1px solid #d6e7e0;border-radius:20px;box-shadow:0 18px 60px rgba(27,62,52,.22);padding:18px;display:grid;gap:14px}.line-oauth-settings-head{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}.line-oauth-settings-head h3{margin:2px 0 4px}.line-oauth-settings-close{border:1px solid #d5e3de;background:#f7faf9;border-radius:12px;min-width:44px;min-height:44px;font:inherit;cursor:pointer}.line-oauth-settings-status{display:grid;gap:8px}.line-oauth-setting-row{display:flex;justify-content:space-between;align-items:center;gap:12px;border:1px solid #dfeae6;border-radius:13px;padding:11px 12px;background:#f9fbfa}.line-oauth-setting-row strong{font-size:.95rem}.line-oauth-pill{display:inline-flex;align-items:center;gap:6px;border-radius:999px;padding:5px 9px;font-size:.82rem;font-weight:900}.line-oauth-pill.ok{background:#e3f5ed;color:#145e4c}.line-oauth-pill.warn{background:#fff4dd;color:#865b0c}.line-oauth-pill.bad{background:#fdeae7;color:#9b4037}.line-oauth-settings-note{border-radius:14px;padding:12px 13px;background:#eef7f3;color:#315c50;line-height:1.5}.line-oauth-settings-code{display:grid;gap:6px}.line-oauth-settings-code code{display:block;overflow-wrap:anywhere;border:1px dashed #bdd8cf;border-radius:12px;background:#fbfdfc;padding:10px;font-size:.82rem}.line-oauth-settings-actions{display:flex;flex-wrap:wrap;gap:8px}.line-oauth-settings-actions button{min-height:44px}.line-oauth-settings-danger{background:#fff4f2;color:#963f35;border:1px solid #efc8c2;border-radius:12px;padding:10px 12px}.line-oauth-settings-muted{color:#687c75;font-size:.88rem;line-height:1.45}.line-oauth-admin-button{position:relative}.line-oauth-admin-button[data-ready="0"]::after{content:"";width:8px;height:8px;border-radius:50%;background:#d68b17;position:absolute;right:8px;top:8px}.line-oauth-admin-button[data-ready="1"]::after{content:"";width:8px;height:8px;border-radius:50%;background:#2c9b70;position:absolute;right:8px;top:8px}@media(max-width:640px){.line-oauth-settings-card{padding:14px}.line-oauth-setting-row{align-items:flex-start;flex-direction:column}.line-oauth-settings-actions{display:grid;grid-template-columns:1fr}.line-oauth-settings-actions button{width:100%}}
  `;document.head.appendChild(s);
}

function edgeHeaders(){return {'content-type':'application/json','apikey':SUPABASE_PUBLISHABLE_KEY,'authorization':`Bearer ${SUPABASE_PUBLISHABLE_KEY}`};}
async function getStatus(){
  const r=await fetch(`${SUPABASE_URL}/functions/v1/line-oauth`,{method:'POST',cache:'no-store',headers:edgeHeaders(),body:JSON.stringify({action:'status'})});
  let data={};try{data=await r.json();}catch{}
  if(!r.ok)throw new Error(data.error||`STATUS_${r.status}`);
  return data;
}
async function checkAdmin(){
  try{
    const {data:{user}}=await supabase.auth.getUser();if(!user){adminReady=false;return false;}
    const {data,error}=await supabase.from('profiles').select('role,active').eq('user_id',user.id).maybeSingle();
    adminReady=!error&&Boolean(data?.active)&&data?.role==='admin';return adminReady;
  }catch{adminReady=false;return false;}
}
function boolPill(ok,okText='มีแล้ว',badText='ยังไม่มี'){return `<span class="line-oauth-pill ${ok?'ok':'warn'}">${ok?okText:badText}</span>`;}
function closeModal(){document.querySelector('.line-oauth-settings-overlay')?.remove();}
async function copyText(text,button){try{await navigator.clipboard.writeText(text);const old=button.textContent;button.textContent='คัดลอกแล้ว';setTimeout(()=>button.textContent=old,1400);}catch{button.textContent='คัดลอกไม่ได้';}}

async function renderStatus(host){
  host.innerHTML='<div class="line-oauth-settings-note">กำลังตรวจสอบสถานะ LINE Login…</div>';
  try{
    const d=await getStatus();const req=d.requirements||{};const ready=Boolean(d.configured);const callback=String(d.callback_url||'');const appUrl=String(d.app_base_url||'https://kelang-health.github.io/PHC-THC/');
    const trigger=$('#line-oauth-settings-btn');if(trigger)trigger.dataset.ready=ready?'1':'0';
    host.innerHTML=`
      <div class="line-oauth-setting-row"><strong>LINE OAuth / OpenID Connect</strong>${boolPill(ready,'พร้อมใช้งาน','ยังไม่พร้อม')}</div>
      <div class="line-oauth-setting-row"><span>LINE Login Channel ID</span>${boolPill(Boolean(req.channel_id_present))}</div>
      <div class="line-oauth-setting-row"><span>LINE Login Channel Secret</span>${boolPill(Boolean(req.channel_secret_present))}</div>
      <div class="line-oauth-setting-row"><span>APP_BASE_URL</span>${boolPill(Boolean(req.app_base_url_present),'กำหนดใน Edge Secret','ใช้ค่า default ที่ปลอดภัย')}</div>
      <div class="line-oauth-settings-note"><strong>Fallback ยังเปิดอยู่:</strong> หาก OAuth ยังไม่พร้อม ปุ่ม “เข้าสู่ระบบด้วย LINE” จะเปลี่ยนไปใช้วิธีส่งรหัส LOGIN ผ่าน LINE OA โดยอัตโนมัติ และ Login ปกติยังคงใช้ได้</div>
      <div class="line-oauth-settings-code"><strong>Callback URL สำหรับ LINE Developers</strong><code>${esc(callback)}</code><button type="button" class="secondary" data-copy-callback>คัดลอก Callback URL</button></div>
      <div class="line-oauth-settings-code"><strong>Web App URL</strong><code>${esc(appUrl)}</code></div>
      <div class="line-oauth-settings-danger"><strong>Channel Secret จะไม่แสดงและไม่รับค่าผ่านหน้าเว็บนี้</strong><br><span class="line-oauth-settings-muted">ค่าจริงต้องเก็บเป็น Supabase Edge Function Secret เท่านั้น หน้าเว็บตรวจได้เพียงว่ามี/ไม่มี</span></div>
      <div class="line-oauth-settings-code"><strong>ชื่อ Secret ที่ต้องมี</strong><code>LINE_LOGIN_CHANNEL_ID<br>LINE_LOGIN_CHANNEL_SECRET<br>APP_BASE_URL</code></div>
    `;
    host.querySelector('[data-copy-callback]')?.addEventListener('click',e=>copyText(callback,e.currentTarget));
  }catch(e){
    host.innerHTML=`<div class="line-oauth-settings-danger"><strong>ตรวจสถานะ Edge Function ไม่สำเร็จ</strong><br><span class="line-oauth-settings-muted">${esc(e?.message||e)}</span></div><div class="line-oauth-settings-note">Login ปกติยังใช้งานได้ หาก LINE OAuth ไม่พร้อมให้ใช้วิธีส่งรหัส LINE OA ชั่วคราว</div>`;
    const trigger=$('#line-oauth-settings-btn');if(trigger)trigger.dataset.ready='0';
  }
}

async function openSettings(){
  if(!adminReady&&!await checkAdmin())return;
  closeModal();injectStyle();
  const overlay=document.createElement('div');overlay.className='line-oauth-settings-overlay';overlay.innerHTML=`<section class="line-oauth-settings-card" role="dialog" aria-modal="true" aria-labelledby="line-oauth-settings-title"><div class="line-oauth-settings-head"><div><small class="line-oauth-settings-muted">ADMIN · AUTHENTICATION</small><h3 id="line-oauth-settings-title">ตั้งค่า LINE Login</h3><div class="line-oauth-settings-muted">ตรวจ readiness ของ one-tap LINE OAuth/OpenID Connect โดยไม่เปิดเผย secret ใน browser</div></div><button type="button" class="line-oauth-settings-close" aria-label="ปิด">×</button></div><div class="line-oauth-settings-status" data-line-oauth-status></div><div class="line-oauth-settings-actions"><button type="button" class="secondary" data-refresh>ตรวจสถานะอีกครั้ง</button><button type="button" class="primary" data-close>ปิด</button></div></section>`;
  document.body.appendChild(overlay);overlay.querySelector('.line-oauth-settings-close').onclick=closeModal;overlay.querySelector('[data-close]').onclick=closeModal;overlay.querySelector('[data-refresh]').onclick=()=>renderStatus(overlay.querySelector('[data-line-oauth-status]'));overlay.addEventListener('click',e=>{if(e.target===overlay)closeModal()});
  await renderStatus(overlay.querySelector('[data-line-oauth-status]'));
}

async function ensureAdminButton(){
  if(!adminReady&&!await checkAdmin())return;
  if($('#line-oauth-settings-btn'))return;
  const anchor=document.querySelector('[data-admin-line]');if(!anchor)return;
  const row=anchor.closest('.phc190-actions')||anchor.parentElement;if(!row)return;
  const b=document.createElement('button');b.type='button';b.id='line-oauth-settings-btn';b.className='phc190-secondary line-oauth-admin-button';b.dataset.ready='0';b.textContent='ตั้งค่า LINE Login';b.onclick=openSettings;row.appendChild(b);
  getStatus().then(s=>{b.dataset.ready=s.configured?'1':'0';}).catch(()=>{b.dataset.ready='0';});
}

async function init(){
  injectStyle();await checkAdmin();await ensureAdminButton();
  if(!observing){observing=true;new MutationObserver(()=>{ensureAdminButton().catch(()=>{});}).observe(document.body,{childList:true,subtree:true});}
  supabase.auth.onAuthStateChange(()=>{setTimeout(async()=>{await checkAdmin();if(!adminReady)$('#line-oauth-settings-btn')?.remove();else await ensureAdminButton();},0);});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
