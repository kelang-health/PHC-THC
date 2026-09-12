import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js?v=2.0.1';

const supabase=createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
const $=(s,r=document)=>r.querySelector(s);
let pollTimer=null,countdownTimer=null,current=null,busy=false;

function injectStyle(){
  if($('#line-login-v201-style'))return;
  const s=document.createElement('style');s.id='line-login-v201-style';s.textContent=`
  .line-login-v201{display:grid;gap:10px;margin-top:12px;padding-top:12px;border-top:1px solid #dfe9e5}.line-login-or{display:flex;align-items:center;gap:10px;color:#72827d;font-size:.82rem;font-weight:800}.line-login-or:before,.line-login-or:after{content:"";height:1px;flex:1;background:#dfe9e5}.line-login-button{width:100%;min-height:56px;border:1px solid #97c8b8;border-radius:13px;background:#eaf8f1;color:#12614e;font:inherit;font-weight:900;cursor:pointer}.line-login-button:disabled{opacity:.55;cursor:wait}.line-login-state{display:grid;gap:9px;padding:12px;border:1px solid #cfe1da;border-radius:14px;background:#f8fbfa}.line-login-state[hidden]{display:none!important}.line-login-code{font-size:1.25rem;font-weight:950;letter-spacing:.06em;text-align:center;padding:11px;border:2px dashed #86bbaa;border-radius:12px;background:#fff}.line-login-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}.line-login-actions button{min-height:44px}.line-login-status{margin:0;color:#557069;line-height:1.45}.line-login-status.error{color:#a23f34}.line-login-count{font-weight:900;color:#0b6f60}@media(max-width:640px){.line-login-button{min-height:58px;font-size:1.02rem}.line-login-actions{grid-template-columns:1fr}.line-login-code{font-size:1.18rem}}
  `;document.head.appendChild(s);
}

function headers(){return {'content-type':'application/json','apikey':SUPABASE_PUBLISHABLE_KEY,'authorization':`Bearer ${SUPABASE_PUBLISHABLE_KEY}`};}
async function call(action,payload={}){
  const r=await fetch(`${SUPABASE_URL}/functions/v1/line-auth`,{method:'POST',cache:'no-store',headers:headers(),body:JSON.stringify({action,...payload})});
  let data={};try{data=await r.json();}catch{}
  if(!r.ok)throw new Error(data.error||`LINE_AUTH_${r.status}`);
  return data;
}
function stopTimers(){if(pollTimer){clearTimeout(pollTimer);pollTimer=null}if(countdownTimer){clearInterval(countdownTimer);countdownTimer=null}}
function reset(){stopTimers();current=null;busy=false;const btn=$('#line-login-start'),state=$('#line-login-state');if(btn){btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE ที่ลงทะเบียน'}if(state){state.hidden=true;state.innerHTML=''}}
function statusText(text,error=false){const e=$('#line-login-status');if(e){e.textContent=text;e.classList.toggle('error',error)}}
function startCountdown(expiresAt){
  const render=()=>{const el=$('#line-login-countdown');if(!el)return;const sec=Math.max(0,Math.ceil((new Date(expiresAt).getTime()-Date.now())/1000));el.textContent=`${Math.floor(sec/60)}:${String(sec%60).padStart(2,'0')}`;if(sec<=0){statusText('รหัสหมดอายุ กรุณาสร้างรหัสใหม่',true);stopTimers();busy=false;current=null;const btn=$('#line-login-start');if(btn){btn.disabled=false;btn.textContent='สร้างรหัส LINE ใหม่'}}};
  render();countdownTimer=setInterval(render,1000);
}
async function poll(){
  if(!current)return;
  try{
    const data=await call('poll',{request_id:current.request_id,browser_secret:current.browser_secret});
    if(data.status==='approved'&&data.session?.access_token&&data.session?.refresh_token){
      stopTimers();statusText('ยืนยันจาก LINE แล้ว กำลังเข้าสู่ระบบ…');
      const {data:setData,error}=await supabase.auth.setSession({access_token:data.session.access_token,refresh_token:data.session.refresh_token});
      if(error||!setData.session)throw error||new Error('SESSION_SETUP_FAILED');
      try{sessionStorage.setItem('phc.auth.login-success','1')}catch{}
      window.location.reload();return;
    }
    if(['expired','consumed','not_found'].includes(data.status)){statusText(data.status==='expired'?'รหัสหมดอายุ กรุณาสร้างใหม่':'คำขอนี้ไม่สามารถใช้งานต่อได้ กรุณาสร้างใหม่',true);stopTimers();busy=false;current=null;const btn=$('#line-login-start');if(btn){btn.disabled=false;btn.textContent='สร้างรหัส LINE ใหม่'}return;}
    pollTimer=setTimeout(poll,2000);
  }catch(e){statusText('ยังตรวจสอบ LINE ไม่สำเร็จ ระบบจะลองใหม่อัตโนมัติ');pollTimer=setTimeout(poll,3500);}
}
async function startLineLogin(){
  if(busy)return;busy=true;stopTimers();const btn=$('#line-login-start'),state=$('#line-login-state');btn.disabled=true;btn.textContent='กำลังสร้างรหัส…';state.hidden=false;state.innerHTML='<p class="line-login-status">กำลังเตรียมการเข้าสู่ระบบด้วย LINE…</p>';
  try{
    const data=await call('start');current=data;
    state.innerHTML=`<p class="line-login-status" id="line-login-status">เปิด NCD OA ที่เคยเชื่อมกับ OSM-PHC แล้วส่งข้อความนี้ภายใน <span class="line-login-count" id="line-login-countdown">3:00</span></p><div class="line-login-code" id="line-login-code">LOGIN ${String(data.code||'')}</div><div class="line-login-actions"><button type="button" class="secondary" id="line-login-copy">คัดลอกรหัส</button><button type="button" class="secondary" id="line-login-cancel">ยกเลิก</button></div><p class="line-login-status">เมื่อ LINE ตอบว่าอนุมัติแล้ว หน้านี้จะเข้าสู่ระบบอัตโนมัติ ไม่ต้องกรอกรหัสผ่าน</p>`;
    $('#line-login-copy').onclick=async()=>{try{await navigator.clipboard.writeText(`LOGIN ${data.code}`);statusText('คัดลอกรหัสแล้ว นำไปส่งที่ NCD OA')}catch{statusText('คัดลอกอัตโนมัติไม่ได้ กรุณากดค้างที่รหัสเพื่อคัดลอก',true)}};
    $('#line-login-cancel').onclick=reset;
    btn.textContent='กำลังรอการยืนยันจาก LINE';
    startCountdown(data.expires_at);pollTimer=setTimeout(poll,1200);
  }catch(e){state.innerHTML='<p class="line-login-status error">ยังไม่สามารถเริ่ม LINE Login ได้ กรุณาลองใหม่</p>';btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE ที่ลงทะเบียน';busy=false;}
}
function init(){
  injectStyle();const form=$('#login-form');if(!form||$('#line-login-v201'))return;
  const box=document.createElement('section');box.id='line-login-v201';box.className='line-login-v201';box.innerHTML='<div class="line-login-or">หรือ</div><button type="button" class="line-login-button" id="line-login-start">เข้าสู่ระบบด้วย LINE ที่ลงทะเบียน</button><div class="line-login-state" id="line-login-state" hidden></div>';
  form.insertAdjacentElement('afterend',box);$('#line-login-start').onclick=startLineLogin;
  window.addEventListener('pagehide',stopTimers,{once:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
