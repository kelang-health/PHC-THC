import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js?v=2.0.25';

const supabase=createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
const $=(s,r=document)=>r.querySelector(s);
const OAUTH_STORAGE='phc.line.oauth.v2012';
let pollTimer=null,countdownTimer=null,oauthRefreshTimer=null,current=null,busy=false,oauthPreparePromise=null;

function injectStyle(){
  if($('#line-login-v201-style'))return;
  const s=document.createElement('style');s.id='line-login-v201-style';s.textContent=`
  .login-card{gap:14px}
  .line-login-v201{display:grid;gap:9px;margin-top:0;padding-top:9px;border-top:1px solid #dfe9e5}
  .line-login-or{display:flex;align-items:center;gap:10px;color:#71827d;font-size:.82rem;font-weight:850;margin:0}
  .line-login-or:before,.line-login-or:after{content:"";height:1px;flex:1;background:#dfe9e5}
  .line-login-ready{display:grid;gap:8px}
  .line-login-button,.line-login-web,.line-login-legacy{width:100%;min-height:54px;display:flex;align-items:center;justify-content:center;text-align:center;text-decoration:none;box-sizing:border-box;border-radius:14px;font:inherit;font-size:.98rem;font-weight:900;line-height:1.25;padding:10px 14px;white-space:normal;overflow-wrap:anywhere;touch-action:manipulation}
  .line-login-button{border:1px solid #80c4b0;background:#e7f6f0;color:#0f6653;cursor:pointer}
  .line-login-button:disabled,.line-login-button[aria-disabled="true"]{opacity:.58;cursor:wait;pointer-events:none}
  .line-login-web{border:1px solid #cadbd5;background:#fff;color:#46645c}
  .line-login-legacy{border:1px dashed #9bbcaf;background:#f7faf9;color:#315f52;cursor:pointer}
  .line-login-button:focus-visible,.line-login-web:focus-visible,.line-login-legacy:focus-visible{outline:3px solid #83bfb0;outline-offset:2px}
  .line-login-help{margin:0;text-align:center;color:#657a73;font-size:.8rem;line-height:1.4}
  .line-login-browser-note{margin:0;padding:9px 11px;border-radius:12px;background:#f4f8f6;color:#58716a;font-size:.78rem;line-height:1.45;text-align:center}
  .line-login-browser-note.warn{background:#fff8e7;color:#735b17;border:1px solid #efe0ac}
  .line-login-state{display:grid;gap:8px;padding:11px;border:1px solid #cfe1da;border-radius:13px;background:#f8fbfa}
  .line-login-state[hidden]{display:none!important}
  .line-login-code{font-size:1.18rem;font-weight:950;letter-spacing:.05em;text-align:center;padding:10px;border:2px dashed #86bbaa;border-radius:12px;background:#fff}
  .line-login-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}
  .line-login-actions button{min-height:46px}
  .line-login-status{margin:0;color:#557069;line-height:1.45;text-align:center}
  .line-login-status.error{color:#a23f34}.line-login-status.success{color:#12614e}.line-login-count{font-weight:900;color:#0b6f60}
  .login-card .login-version{margin-top:0;padding-top:10px}
  @media(max-width:640px){
    .login-card{gap:12px}
    .line-login-v201{gap:8px;padding-top:7px}
    .line-login-ready{gap:7px}
    .line-login-button,.line-login-web,.line-login-legacy{min-height:52px;font-size:.95rem;padding:9px 12px;border-radius:13px}
    .line-login-help{font-size:.78rem}
    .line-login-browser-note{font-size:.76rem;padding:8px 10px}
    .line-login-actions{grid-template-columns:1fr}
    .line-login-code{font-size:1.1rem}
  }
  @media(max-width:380px){
    .line-login-button,.line-login-web,.line-login-legacy{font-size:.92rem;padding-left:10px;padding-right:10px}
    .line-login-browser-note{font-size:.74rem}
  }
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
function stopTimers(){if(pollTimer){clearTimeout(pollTimer);pollTimer=null}if(countdownTimer){clearInterval(countdownTimer);countdownTimer=null}if(oauthRefreshTimer){clearTimeout(oauthRefreshTimer);oauthRefreshTimer=null}}
function stateBox(){return $('#line-login-state');}
function reset(){stopTimers();current=null;busy=false;const btn=$('#line-login-start'),state=stateBox();if(btn){btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';btn.onclick=prepareDirectLineLogin}if(state){state.hidden=true;state.innerHTML=''}}
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

function hasOauthReturn(){try{const u=new URL(location.href);return u.searchParams.has('line_oauth')||u.searchParams.has('line_oauth_error')}catch{return false}}
function webLoginUrl(url){try{const u=new URL(url);u.searchParams.set('disable_auto_login','true');return u.toString()}catch{return url}}
function browserEnvironment(){
  const ua=navigator.userAgent||'';
  const ios=/iPhone|iPad|iPod/i.test(ua),android=/Android/i.test(ua);
  const line=/\bLine\//i.test(ua),facebook=/FBAN|FBAV|FB_IAB|Messenger/i.test(ua),instagram=/Instagram/i.test(ua),twitter=/Twitter/i.test(ua);
  const genericWebView=!line&&(/;\s*wv\)/i.test(ua)||(android&&/\bwv\b/i.test(ua)));
  const iosSafari=ios&&/Safari/i.test(ua)&&!/(CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo|GSA)/i.test(ua);
  const androidChrome=android&&/Chrome\//i.test(ua)&&!/(EdgA|OPR|SamsungBrowser|;\s*wv\))/i.test(ua);
  const constrained=!line&&(facebook||instagram||twitter||genericWebView);
  const mobile=ios||android;
  let note='',warn=false;
  if(line)note='เปิดจาก LINE แล้ว · เลือกวิธีเข้าสู่ระบบที่ต้องการได้ทันที';
  else if(constrained){note='เบราว์เซอร์ในแอปอาจไม่เปิด LINE อัตโนมัติ · ใช้ “LINE ผ่านเว็บ” หรือ “LINE เดิม” ได้';warn=true;}
  else if(iosSafari)note='iPhone/iPad: หากแอป LINE ไม่เปิด ให้เลือก “LINE ผ่านเว็บ” หรือ “LINE เดิม (LINE OA)”';
  else if(ios){note='iPhone/iPad: แนะนำ Safari · หากแอปไม่เปิด ให้ใช้ “LINE ผ่านเว็บ” หรือ “LINE เดิม”';warn=true;}
  else if(androidChrome)note='Android: ระบบจะลองเปิดแอป LINE ก่อน หากไม่สำเร็จให้ใช้ “LINE ผ่านเว็บ”';
  else if(android)note='Android: หากแอป LINE ไม่เปิด สามารถใช้ “LINE ผ่านเว็บ” หรือ “LINE เดิม” ได้';
  else note='คอมพิวเตอร์: ใช้ LINE Login/QR หรือ LINE เดิมได้';
  return {ios,android,line,constrained,iosSafari,androidChrome,mobile,note,warn};
}
function scheduleOauthRefresh(data){
  if(oauthRefreshTimer)clearTimeout(oauthRefreshTimer);
  const exp=new Date(data?.expires_at||0).getTime();
  const delay=Math.max(30000,Math.min(210000,exp-Date.now()-60000));
  oauthRefreshTimer=setTimeout(()=>refreshPreparedOauth().catch(()=>{}),Number.isFinite(delay)?delay:180000);
}
async function refreshPreparedOauth(){
  const link=$('#line-login-start'),web=$('#line-login-web');if(!link||link.tagName!=='A'||busy||hasOauthReturn())return;
  const data=await callOauth('start');
  if(!data.configured||!data.authorize_url||!data.request_id||!data.browser_secret)return;
  saveOauth(data);link.href=data.authorize_url;if(web)web.href=webLoginUrl(data.authorize_url);scheduleOauthRefresh(data);
}
function renderPreparedOauth(btn,data,help){
  const state=stateBox(),env=browserEnvironment();
  const ready=document.createElement('div');ready.className='line-login-ready';
  const link=document.createElement('a');link.id='line-login-start';link.className='line-login-button';link.href=data.authorize_url;link.textContent=env.mobile?'เปิดแอป LINE':'LINE Login';link.setAttribute('aria-label','เข้าสู่ระบบด้วย LINE');
  link.addEventListener('click',()=>{busy=true;stopTimers();state.hidden=false;state.innerHTML='<p class="line-login-status">กำลังเปิด LINE เพื่อยืนยันตัวตน… หากไม่เปิดแอป คุณยังสามารถย้อนกลับมาใช้ LINE ผ่านเว็บได้</p>';});
  ready.appendChild(link);
  if(env.mobile){
    const web=document.createElement('a');web.id='line-login-web';web.className='line-login-web';web.href=webLoginUrl(data.authorize_url);web.textContent='LINE ผ่านเว็บ';
    web.addEventListener('click',()=>{busy=true;stopTimers();state.hidden=false;state.innerHTML='<p class="line-login-status">กำลังเปิด LINE Login ผ่านเว็บ โดยปิด Auto login สำหรับรอบนี้…</p>';});
    ready.appendChild(web);
  }
  const legacy=document.createElement('button');legacy.type='button';legacy.id='line-login-legacy';legacy.className='line-login-legacy';legacy.textContent='LINE เดิม (LINE OA)';
  legacy.addEventListener('click',()=>{busy=false;stopTimers();clearOauth();startCodeLogin(false).catch(()=>{})});
  ready.appendChild(legacy);
  const note=document.createElement('p');note.className=`line-login-browser-note${env.warn?' warn':''}`;note.textContent=env.note;ready.appendChild(note);
  btn.replaceWith(ready);
  if(help)help.textContent=env.mobile?'เลือกวิธี LINE ที่สะดวกกับอุปกรณ์ของคุณ':'เลือก LINE Login หรือ LINE เดิม';
  scheduleOauthRefresh(data);
}

async function prepareDirectLineLogin(){
  if(oauthPreparePromise)return oauthPreparePromise;
  let btn=$('#line-login-start'),state=stateBox(),help=$('.line-login-help');
  if(!btn)return;
  if(btn.tagName==='A')return;
  const oldReady=btn.closest('.line-login-ready');if(oldReady){const fresh=document.createElement('button');fresh.type='button';fresh.id='line-login-start';fresh.className='line-login-button';fresh.disabled=true;fresh.setAttribute('aria-disabled','true');fresh.textContent='กำลังเตรียม LINE…';oldReady.replaceWith(fresh);btn=fresh;}
  btn.disabled=true;btn.textContent='กำลังเตรียม LINE…';btn.setAttribute('aria-disabled','true');
  if(help)help.textContent='กำลังเตรียมการยืนยันตัวตนอย่างปลอดภัย…';
  oauthPreparePromise=(async()=>{
    try{
      const data=await callOauth('start');
      if(!data.configured){
        btn.disabled=false;btn.removeAttribute('aria-disabled');btn.textContent='เข้าสู่ระบบด้วย LINE';
        btn.onclick=()=>startCodeLogin(true);
        if(help)help.textContent='LINE Login ยังตั้งค่าไม่ครบ · ใช้วิธียืนยันผ่าน LINE OA สำรองได้';
        return data;
      }
      if(!data.authorize_url||!data.request_id||!data.browser_secret)throw new Error('OAUTH_START_INCOMPLETE');
      saveOauth(data);renderPreparedOauth(btn,data,help);return data;
    }catch(e){
      btn.disabled=false;btn.removeAttribute('aria-disabled');btn.textContent='ลองเข้าสู่ระบบด้วย LINE อีกครั้ง';btn.onclick=prepareDirectLineLogin;
      if(help)help.textContent='ยังเตรียม LINE Login ไม่สำเร็จ · Login ปกติยังใช้งานได้';
      state.hidden=false;state.innerHTML='<p class="line-login-status error">ยังไม่สามารถเตรียม LINE Login ได้ กรุณาลองใหม่หรือเข้าสู่ระบบปกติ</p>';
      return null;
    }finally{oauthPreparePromise=null}
  })();
  return oauthPreparePromise;
}

async function resumeOauth(){
  const u=new URL(location.href),flag=u.searchParams.get('line_oauth'),err=u.searchParams.get('line_oauth_error');
  if(!flag&&!err)return;
  const state=stateBox(),btn=$('#line-login-start');state.hidden=false;btn.disabled=true;busy=true;
  if(err){
    cleanOauthQuery();clearOauth();busy=false;btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';
    if(err==='line_not_registered'){
      state.innerHTML='<p class="line-login-status error">LINE นี้ยังไม่ได้เชื่อมกับบัญชี อสม. พลัส กรุณาเข้าสู่ระบบปกติก่อน แล้วเชื่อม LINE ครั้งแรก</p>';return;
    }
    if(err==='not_configured'){
      state.innerHTML='<p class="line-login-status error">LINE Login ยังตั้งค่าไม่ครบ ระบบจะเปิดวิธียืนยันผ่าน LINE OA สำรอง</p>';await startCodeLogin(true);return;
    }
    const msg=err==='cancelled'||err==='access_denied'?'ยกเลิกการเข้าสู่ระบบด้วย LINE แล้ว สามารถลองใหม่ได้':'LINE Auto login ไม่สำเร็จ อาจเกิดจาก browser, Private Browsing หรือการเปิดลิงก์จากแอปอื่น กรุณาลองใหม่หรือใช้ LINE ผ่านเว็บ';
    state.innerHTML=`<p class="line-login-status error">${msg}</p>`;
    await prepareDirectLineLogin();return;
  }
  const requestId=String(u.searchParams.get('request_id')||''),saved=readOauth();cleanOauthQuery();
  if(!saved||saved.request_id!==requestId||!saved.browser_secret){clearOauth();busy=false;btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';state.innerHTML='<p class="line-login-status error">ข้อมูลยืนยันในเบราว์เซอร์หมดอายุ กรุณาลอง LINE Login ใหม่</p>';await prepareDirectLineLogin();return;}
  state.innerHTML='<p class="line-login-status success">LINE ยืนยันแล้ว กำลังเข้าสู่ระบบ…</p>';
  try{
    const data=await callOauth('claim',{request_id:requestId,browser_secret:saved.browser_secret});
    if(data.status==='approved'&&data.session?.access_token&&data.session?.refresh_token){clearOauth();await applySession(data.session);return;}
    throw new Error(data.status||'OAUTH_CLAIM_FAILED');
  }catch(e){clearOauth();busy=false;btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';state.innerHTML='<p class="line-login-status error">ยืนยัน LINE แล้วแต่สร้าง session ไม่สำเร็จ กรุณาลองใหม่หรือเข้าสู่ระบบปกติ</p>';await prepareDirectLineLogin();}
}

function startCountdown(expiresAt){
  const render=()=>{const el=$('#line-login-countdown');if(!el)return;const sec=Math.max(0,Math.ceil((new Date(expiresAt).getTime()-Date.now())/1000));el.textContent=`${Math.floor(sec/60)}:${String(sec%60).padStart(2,'0')}`;if(sec<=0){statusText('รหัสหมดอายุ กรุณาสร้างรหัสใหม่',true);stopTimers();busy=false;current=null;const btn=$('#line-login-start');if(btn){btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';btn.onclick=prepareDirectLineLogin}}};
  render();countdownTimer=setInterval(render,1000);
}
async function poll(){
  if(!current)return;
  try{
    const data=await callCode('poll',{request_id:current.request_id,browser_secret:current.browser_secret});
    if(data.status==='approved'&&data.session?.access_token&&data.session?.refresh_token){stopTimers();statusText('ยืนยันจาก LINE แล้ว กำลังเข้าสู่ระบบ…');await applySession(data.session);return;}
    if(['expired','consumed','not_found'].includes(data.status)){statusText(data.status==='expired'?'รหัสหมดอายุ กรุณาสร้างใหม่':'คำขอนี้ไม่สามารถใช้งานต่อได้ กรุณาสร้างใหม่',true);stopTimers();busy=false;current=null;const btn=$('#line-login-start');if(btn){btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';btn.onclick=prepareDirectLineLogin}return;}
    pollTimer=setTimeout(poll,2000);
  }catch(e){statusText('ยังตรวจสอบ LINE ไม่สำเร็จ ระบบจะลองใหม่อัตโนมัติ');pollTimer=setTimeout(poll,3500);}
}
function ensureLineActionButton(){
  let btn=$('#line-login-start');
  const ready=btn?.closest?.('.line-login-ready');
  if(ready){
    const fresh=document.createElement('button');fresh.type='button';fresh.id='line-login-start';fresh.className='line-login-button';fresh.textContent='เข้าสู่ระบบด้วย LINE';fresh.onclick=prepareDirectLineLogin;ready.replaceWith(fresh);btn=fresh;
  }
  return btn;
}
async function startCodeLogin(fromFallback=false){
  if(busy)return;busy=true;stopTimers();clearOauth();const btn=ensureLineActionButton(),state=stateBox();if(!btn){busy=false;return;}btn.onclick=null;btn.disabled=true;btn.textContent='กำลังสร้างรหัส LINE แบบเดิม…';state.hidden=false;state.innerHTML='<p class="line-login-status">กำลังเตรียมระบบ LINE แบบเดิมผ่าน LINE OA…</p>';
  try{
    const data=await callCode('start');current=data;
    state.innerHTML=`<p class="line-login-status" id="line-login-status">${fromFallback?'โหมดสำรอง: ':'LINE แบบเดิม: '}เปิด LINE OA ของหน่วยงาน แล้วส่งข้อความนี้ภายใน <span class="line-login-count" id="line-login-countdown">3:00</span></p><div class="line-login-code" id="line-login-code">LOGIN ${String(data.code||'')}</div><div class="line-login-actions"><button type="button" class="secondary" id="line-login-copy">คัดลอกรหัส</button><button type="button" class="secondary" id="line-login-cancel">ยกเลิก</button></div><p class="line-login-status">เมื่อ LINE ตอบว่าอนุมัติแล้ว หน้านี้จะเข้าสู่ระบบอัตโนมัติ</p>`;
    $('#line-login-copy').onclick=async()=>{try{await navigator.clipboard.writeText(`LOGIN ${data.code}`);statusText('คัดลอกรหัสแล้ว นำไปส่งที่ LINE OA ของหน่วยงาน')}catch{statusText('คัดลอกอัตโนมัติไม่ได้ กรุณากดค้างที่รหัสเพื่อคัดลอก',true)}};
    $('#line-login-cancel').onclick=()=>{reset();prepareDirectLineLogin().catch(()=>{})};btn.textContent='กำลังรอการยืนยันจาก LINE';startCountdown(data.expires_at);pollTimer=setTimeout(poll,1200);
  }catch(e){state.innerHTML='<p class="line-login-status error">ยังไม่สามารถเริ่มระบบ LINE แบบเดิมได้ กรุณาลองใหม่หรือเข้าสู่ระบบปกติ</p>';btn.disabled=false;btn.textContent='เข้าสู่ระบบด้วย LINE';btn.onclick=prepareDirectLineLogin;busy=false;}
}
function init(){
  injectStyle();const form=$('#login-form');if(!form||$('#line-login-v201'))return;
  const box=document.createElement('section');box.id='line-login-v201';box.className='line-login-v201';box.innerHTML='<div class="line-login-or">หรือ</div><button type="button" class="line-login-button" id="line-login-start" disabled aria-disabled="true">กำลังเตรียม LINE…</button><p class="line-login-help">กำลังเตรียมการยืนยันตัวตนอย่างปลอดภัย…</p><div class="line-login-state" id="line-login-state" hidden></div>';
  form.insertAdjacentElement('afterend',box);$('#line-login-start').onclick=prepareDirectLineLogin;
  window.addEventListener('pagehide',stopTimers,{once:true});
  window.addEventListener('pageshow',()=>{if(!hasOauthReturn()){busy=false;const state=stateBox();if(state)state.hidden=true;refreshPreparedOauth().catch(()=>{})}});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden&&!hasOauthReturn()){busy=false;refreshPreparedOauth().catch(()=>{})}});
  if(hasOauthReturn())resumeOauth().catch(()=>{});else prepareDirectLineLogin().catch(()=>{});
}

if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
