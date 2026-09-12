import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js?v=2.0.13';

const supabase=createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
const $=(s,r=document)=>r.querySelector(s);
const OAUTH_STORAGE='phc.line.oauth.v2012';
let pollTimer=null,countdownTimer=null,current=null,busy=false;

function injectStyle(){
  if($('#line-login-v201-style'))return;
  const s=document.createElement('style');s.id='line-login-v201-style';s.textContent=`
  .line-login-v201{display:grid;gap:10px;margin-top:12px;padding-top:12px;border-top:1px solid #dfe9e5}.line-login-or{display:flex;align-items:center;gap:10px;color:#72827d;font-size:.82rem;font-weight:800}.line-login-or:before,.line-login-or:after{content:"";height:1px;flex:1;background:#dfe9e5}.line-login-button{width:100%;min-height:58px;border:1px solid #8fc7b5;border-radius:14px;background:#e8f7f0;color:#0f604c;font:inherit;font-weight:950;cursor:pointer}.line-login-button:disabled{opacity:.58;cursor:wait}.line-login-help{margin:0;text-align:center;color:#657a73;font-size:.86rem;line-height:1.45}.line-login-state{display:grid;gap:9px;padding:12px;border:1px solid #cfe1da;border-radius:14px;background:#f8fbfa}.line-login-state[hidden]{display:none!important}.line-login-code{font-size:1.25rem;font-weight:950;letter-spacing:.06em;text-align:center;padding:11px;border:2px dashed #86bbaa;border-radius:12px;background:#fff}.line-login-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}.line-login-actions button{min-height:48px}.line-login-status{margin:0;color:#557069;line-height:1.45}.line-login-status.error{color:#a23f34}.line-login-status.success{color:#12614e}.line-login-count{font-weight:900;color:#0b6f60}@media(max-width:640px){.line-login-button{min-height:60px;font-size:1.04rem}.line-login-actions{grid-template-columns:1fr}.line-login-code{font-size:1.18rem}}
  `;document.head.appendChild(s);
}
function headers(){return {'content-type':'application/json','apikey':SUPABASE_PUBLISHABLE_KEY,'authorization':`Bearer ${SUPABASE_PUBLISHABLE_KEY}`};}
async function callEdge(name,payload={}){
  const r=await fetch(`${SUPABASE_URL}/functions/v1/${name}`,{method:'POST',cache:'no-store',headers:headers(),body:JSON.stringify(payload)});
  let data={};try{data=await r.json();}catch{}
  if(!r.ok)throw new Error(data.error||`${name.toUpperCase()}_${r.status}`);
  return data;
}
async function callCode(action,payload={}){return callEdge('line-auth',{action,...payload});}
async function callOauth(action,payload={}){return callEdge('line-oauth',{action,...payload});}
function stopTimers(){if(pollTimer){clearTimeout(pollTimer);pollTimer=null}if(countdownTimer){clearInterval(countdownTimer);countdownTimer=null}}
function stateBox(){return $('#line-login-state');}
function reset(){stopTimers();current=null;busy=false;const btn=$('#line-login-start'),state=stateBox();if(btn){btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE'}if(state){state.hidden=true;state.innerHTML=''}}
function statusText(text,error=false){const e=$('#line-login-status');if(e){e.textContent=text;e.classList.toggle('error',error)}}
function cleanOauthQuery(){try{const u=new URL(location.href);u.searchParams.delete('line_oauth');u.searchParams.delete('request_id');u.searchParams.delete('line_oauth_error');history.replaceState({},'',u.pathname+(u.search?u.search:'')+u.hash);}catch{}}
function saveOauth(data){try{sessionStorage.setItem(OAUTH_STORAGE,JSON.stringify({request_id:data.request_id,browser_secret:data.browser_secret,expires_at:data.expires_at}))}catch{}}
function readOauth(){try{return JSON.parse(sessionStorage.getItem(OAUTH_STORAGE)||'null')}catch{return null}}
function clearOauth(){try{sessionStorage.removeItem(OAUTH_STORAGE)}catch{}}
async function applySession(session){
  const {data:setData,error}=await supabase.auth.setSession({access_token:session.access_token,refresh_token:session.refresh_token});
  if(error||!setData.session)throw error||new Error('SESSION_SETUP_FAILED');
  try{sessionStorage.setItem('phc.auth.login-success','1')}catch{}
  window.location.reload();
}

async function startDirectLineLogin(){
  if(busy)return;busy=true;stopTimers();const btn=$('#line-login-start'),state=stateBox();btn.disabled=true;btn.textContent='กำลังเปิด LINE…';state.hidden=false;state.innerHTML='<p class="line-login-status">กำลังเตรียม LINE Login แบบกดครั้งเดียว…</p>';
  try{
    const data=await callOauth('start');
    if(!data.configured){busy=false;btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';state.innerHTML='<p class="line-login-status">LINE Login แบบกดครั้งเดียวยังอยู่ระหว่างตั้งค่า ระบบจะใช้วิธียืนยันผ่าน LINE OA สำรองให้ก่อน</p>';await startCodeLogin(true);return;}
    if(!data.authorize_url||!data.request_id||!data.browser_secret)throw new Error('OAUTH_START_INCOMPLETE');
    saveOauth(data);state.innerHTML='<p class="line-login-status">กำลังพาไปยืนยันกับ LINE…</p>';window.location.assign(data.authorize_url);
  }catch(e){state.innerHTML='<p class="line-login-status error">ยังไม่สามารถเปิด LINE Login ได้ กรุณาใช้การเข้าสู่ระบบปกติหรือลองใหม่</p>';btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';busy=false;}
}

async function resumeOauth(){
  const u=new URL(location.href),flag=u.searchParams.get('line_oauth'),err=u.searchParams.get('line_oauth_error');
  if(!flag&&!err)return;
  const state=stateBox(),btn=$('#line-login-start');state.hidden=false;btn.disabled=true;busy=true;
  if(err){
    cleanOauthQuery();clearOauth();busy=false;btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';
    const msg=err==='line_not_registered'?'LINE นี้ยังไม่ได้เชื่อมกับบัญชี อสม. พลัส กรุณาเข้าสู่ระบบปกติก่อนแล้วเชื่อม LINE ครั้งแรก':err==='cancelled'||err==='access_denied'?'ยกเลิกการเข้าสู่ระบบด้วย LINE แล้ว':'LINE Login ยังไม่สำเร็จ กรุณาลองใหม่';
    state.innerHTML=`<p class="line-login-status error">${msg}</p>`;return;
  }
  const requestId=String(u.searchParams.get('request_id')||''),saved=readOauth();cleanOauthQuery();
  if(!saved||saved.request_id!==requestId||!saved.browser_secret){clearOauth();busy=false;btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';state.innerHTML='<p class="line-login-status error">ข้อมูลยืนยันในเบราว์เซอร์หมดอายุ กรุณากด LINE Login ใหม่</p>';return;}
  state.innerHTML='<p class="line-login-status success">LINE ยืนยันแล้ว กำลังเข้าสู่ระบบ…</p>';
  try{
    const data=await callOauth('claim',{request_id:requestId,browser_secret:saved.browser_secret});
    if(data.status==='approved'&&data.session?.access_token&&data.session?.refresh_token){clearOauth();await applySession(data.session);return;}
    throw new Error(data.status||'OAUTH_CLAIM_FAILED');
  }catch(e){clearOauth();busy=false;btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';state.innerHTML='<p class="line-login-status error">ยืนยัน LINE แล้วแต่สร้าง session ไม่สำเร็จ กรุณาลองใหม่หรือเข้าสู่ระบบปกติ</p>';}
}

function startCountdown(expiresAt){
  const render=()=>{const el=$('#line-login-countdown');if(!el)return;const sec=Math.max(0,Math.ceil((new Date(expiresAt).getTime()-Date.now())/1000));el.textContent=`${Math.floor(sec/60)}:${String(sec%60).padStart(2,'0')}`;if(sec<=0){statusText('รหัสหมดอายุ กรุณาสร้างรหัสใหม่',true);stopTimers();busy=false;current=null;const btn=$('#line-login-start');if(btn){btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE'}}};
  render();countdownTimer=setInterval(render,1000);
}
async function poll(){
  if(!current)return;
  try{
    const data=await callCode('poll',{request_id:current.request_id,browser_secret:current.browser_secret});
    if(data.status==='approved'&&data.session?.access_token&&data.session?.refresh_token){stopTimers();statusText('ยืนยันจาก LINE แล้ว กำลังเข้าสู่ระบบ…');await applySession(data.session);return;}
    if(['expired','consumed','not_found'].includes(data.status)){statusText(data.status==='expired'?'รหัสหมดอายุ กรุณาสร้างใหม่':'คำขอนี้ไม่สามารถใช้งานต่อได้ กรุณาสร้างใหม่',true);stopTimers();busy=false;current=null;const btn=$('#line-login-start');if(btn){btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE'}return;}
    pollTimer=setTimeout(poll,2000);
  }catch(e){statusText('ยังตรวจสอบ LINE ไม่สำเร็จ ระบบจะลองใหม่อัตโนมัติ');pollTimer=setTimeout(poll,3500);}
}
async function startCodeLogin(fromFallback=false){
  if(busy)return;busy=true;stopTimers();const btn=$('#line-login-start'),state=stateBox();btn.disabled=true;btn.textContent='กำลังสร้างรหัสสำรอง…';state.hidden=false;state.innerHTML='<p class="line-login-status">กำลังเตรียมการยืนยันผ่าน LINE OA…</p>';
  try{
    const data=await callCode('start');current=data;
    state.innerHTML=`<p class="line-login-status" id="line-login-status">${fromFallback?'โหมดสำรอง: ':''}เปิด LINE OA ของหน่วยงาน แล้วส่งข้อความนี้ภายใน <span class="line-login-count" id="line-login-countdown">3:00</span></p><div class="line-login-code" id="line-login-code">LOGIN ${String(data.code||'')}</div><div class="line-login-actions"><button type="button" class="secondary" id="line-login-copy">คัดลอกรหัส</button><button type="button" class="secondary" id="line-login-cancel">ยกเลิก</button></div><p class="line-login-status">เมื่อ LINE ตอบว่าอนุมัติแล้ว หน้านี้จะเข้าสู่ระบบอัตโนมัติ</p>`;
    $('#line-login-copy').onclick=async()=>{try{await navigator.clipboard.writeText(`LOGIN ${data.code}`);statusText('คัดลอกรหัสแล้ว นำไปส่งที่ LINE OA ของหน่วยงาน')}catch{statusText('คัดลอกอัตโนมัติไม่ได้ กรุณากดค้างที่รหัสเพื่อคัดลอก',true)}};
    $('#line-login-cancel').onclick=reset;btn.textContent='กำลังรอการยืนยันจาก LINE';startCountdown(data.expires_at);pollTimer=setTimeout(poll,1200);
  }catch(e){state.innerHTML='<p class="line-login-status error">ยังไม่สามารถเริ่ม LINE Login ได้ กรุณาลองใหม่</p>';btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';busy=false;}
}
function init(){
  injectStyle();const form=$('#login-form');if(!form||$('#line-login-v201'))return;
  const box=document.createElement('section');box.id='line-login-v201';box.className='line-login-v201';box.innerHTML='<div class="line-login-or">หรือ</div><button type="button" class="line-login-button" id="line-login-start">เข้าสู่ระบบด้วย LINE</button><p class="line-login-help">สำหรับบัญชีที่เชื่อม LINE แล้ว · กดครั้งเดียว ไม่ต้องส่งรหัสเมื่อ LINE Login พร้อมใช้งาน</p><div class="line-login-state" id="line-login-state" hidden></div>';
  form.insertAdjacentElement('afterend',box);$('#line-login-start').onclick=startDirectLineLogin;
  window.addEventListener('pagehide',stopTimers,{once:true});resumeOauth().catch(()=>{});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
