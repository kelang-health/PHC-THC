import { getSharedSupabase } from './shared-runtime-v2035.mjs?v=2.0.35';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js?v=2.0.45&p=2050';

const supabase = await getSharedSupabase(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);

const IDLE_TIMEOUT_MS = 10 * 60 * 1000;
const LAST_ACTIVITY_KEY = 'phc.auth.last-activity';
const IDLE_NOTICE_KEY = 'phc.auth.idle-notice';
const LOGIN_SUCCESS_KEY = 'phc.auth.login-success';
const ACTIVITY_WRITE_THROTTLE_MS = 2000;
let idleTimer = null;
let idleWatchActive = false;
let idleLogoutInProgress = false;
let lastActivityWrite = 0;
let lockCountdownTimer = null;
let loginBusyOverlay = null;
let mfaOverlay = null;

const $ = selector => document.querySelector(selector);

function loginButton(){ return $('#login-form .login-submit'); }
function loginError(){ return $('#login-error'); }

function ensureLoginBusyOverlay(){
  if(loginBusyOverlay && document.body.contains(loginBusyOverlay)) return loginBusyOverlay;
  if(!document.getElementById('phc-login-busy-style')){
    const style = document.createElement('style');
    style.id = 'phc-login-busy-style';
    style.textContent = `
      #phc-login-busy{position:fixed;inset:0;z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px;background:rgba(20,49,45,.38);backdrop-filter:blur(2px);-webkit-backdrop-filter:blur(2px)}
      #phc-login-busy[hidden]{display:none!important}
      .phc-login-busy-card{width:min(360px,92vw);background:#fff;border:1px solid #d3e4de;border-radius:22px;padding:26px 22px;text-align:center;box-shadow:0 24px 70px rgba(16,46,40,.28);color:#17312d}
      .phc-login-spinner{width:52px;height:52px;margin:0 auto 16px;border:6px solid #dcebe6;border-top-color:#0b6f60;border-radius:50%;animation:phc-login-spin .8s linear infinite}
      .phc-login-busy-card strong{display:block;font-size:1.34rem;line-height:1.35;margin-bottom:7px}
      .phc-login-busy-card p{margin:0;color:#5b716a;font-size:1.02rem;line-height:1.55}
      @keyframes phc-login-spin{to{transform:rotate(360deg)}}
      @media(max-width:640px){.phc-login-busy-card{padding:28px 20px;border-radius:20px}.phc-login-busy-card strong{font-size:1.42rem}.phc-login-busy-card p{font-size:1.08rem}.phc-login-spinner{width:58px;height:58px}}
      @media(prefers-reduced-motion:reduce){.phc-login-spinner{animation-duration:1.6s}}
    `;
    document.head.appendChild(style);
  }
  loginBusyOverlay = document.createElement('div');
  loginBusyOverlay.id = 'phc-login-busy';
  loginBusyOverlay.hidden = true;
  loginBusyOverlay.setAttribute('role','status');
  loginBusyOverlay.setAttribute('aria-live','polite');
  loginBusyOverlay.setAttribute('aria-label','กำลังเข้าสู่ระบบ');
  loginBusyOverlay.innerHTML = `
    <div class="phc-login-busy-card">
      <div class="phc-login-spinner" aria-hidden="true"></div>
      <strong>กำลังเข้าสู่ระบบ…</strong>
      <p>กรุณารอสักครู่ ระบบกำลังตรวจสอบบัญชีของคุณ</p>
    </div>`;
  document.body.appendChild(loginBusyOverlay);
  return loginBusyOverlay;
}

function showLoginBusy(){
  const overlay = ensureLoginBusyOverlay();
  overlay.hidden = false;
  document.body.setAttribute('aria-busy','true');
  const button = loginButton();
  if(button){
    button.disabled = true;
    button.textContent = 'กำลังเข้าสู่ระบบ…';
  }
}

function hideLoginBusy(){
  const overlay = loginBusyOverlay || document.getElementById('phc-login-busy');
  if(overlay) overlay.hidden = true;
  document.body.removeAttribute('aria-busy');
}

function formatRemaining(seconds){
  const value = Math.max(0, Number(seconds) || 0);
  const m = Math.floor(value / 60);
  const s = value % 60;
  return `${m}:${String(s).padStart(2,'0')}`;
}

function stopLockCountdown(){
  if(lockCountdownTimer){ clearInterval(lockCountdownTimer); lockCountdownTimer = null; }
  const button = loginButton();
  if(button){ button.disabled = false; button.textContent = 'เข้าสู่ระบบ'; }
}

function startLockCountdown(seconds){
  hideLoginBusy();
  stopLockCountdown();
  let remaining = Math.max(1, Math.ceil(Number(seconds) || 600));
  const button = loginButton();
  const error = loginError();
  const render = () => {
    if(button){ button.disabled = true; button.textContent = `ลองใหม่ ${formatRemaining(remaining)}`; }
    if(error) error.textContent = `กรอกรหัสผ่านไม่ถูกต้องครบ 5 ครั้ง บัญชีถูกระงับชั่วคราว กรุณาลองใหม่ใน ${formatRemaining(remaining)}`;
    if(remaining <= 0){
      stopLockCountdown();
      if(error) error.textContent = 'ครบเวลาระงับแล้ว สามารถลองเข้าสู่ระบบใหม่ได้';
      return;
    }
    remaining -= 1;
  };
  render();
  lockCountdownTimer = setInterval(render,1000);
}

async function secureLogin(login,password){
  const response = await fetch(`${SUPABASE_URL}/functions/v1/secure-login`, {
    method: 'POST',
    cache: 'no-store',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SUPABASE_PUBLISHABLE_KEY,
      'Authorization': `Bearer ${SUPABASE_PUBLISHABLE_KEY}`,
      'x-client-info': 'osm-phc-auth-security/2.0.46-hotfix1'
    },
    body: JSON.stringify({ login, password })
  });
  let payload = {};
  try{ payload = await response.json(); }catch{}
  return { response, payload };
}

function ensureMfaOverlay(){
  if(mfaOverlay && document.body.contains(mfaOverlay)) return mfaOverlay;
  if(!document.getElementById('phc-mfa-style')){
    const style=document.createElement('style');
    style.id='phc-mfa-style';
    style.textContent=`
      #phc-mfa{position:fixed;inset:0;z-index:10000;display:flex;align-items:center;justify-content:center;padding:18px;background:rgba(18,43,39,.72);backdrop-filter:blur(5px)}
      #phc-mfa[hidden]{display:none!important}.phc-mfa-card{width:min(440px,96vw);max-height:94vh;overflow:auto;background:#fff;border-radius:22px;padding:24px;box-shadow:0 28px 90px rgba(0,0,0,.34);color:#17312d}
      .phc-mfa-card h2{margin:.15rem 0 .5rem}.phc-mfa-card p{color:#526b65;line-height:1.55}.phc-mfa-qr{display:block;width:min(260px,78vw);height:auto;margin:14px auto;border:1px solid #d8e5e1;border-radius:14px}
      .phc-mfa-card label{display:grid;gap:7px;font-weight:700}.phc-mfa-card input{font-size:1.35rem;letter-spacing:.28em;text-align:center}.phc-mfa-actions{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:16px}.phc-mfa-error{min-height:1.4em;color:#a53f32}
    `;
    document.head.appendChild(style);
  }
  mfaOverlay=document.createElement('div');
  mfaOverlay.id='phc-mfa';
  mfaOverlay.hidden=true;
  mfaOverlay.innerHTML=`<section class="phc-mfa-card" role="dialog" aria-modal="true" aria-labelledby="phc-mfa-title"><p class="eyebrow">SECURE ACCESS</p><h2 id="phc-mfa-title">ยืนยันตัวตน 2 ชั้น</h2><p data-mfa-message></p><img class="phc-mfa-qr" data-mfa-qr alt="QR Code สำหรับตั้งค่า Authenticator" hidden><form data-mfa-form><label>รหัส 6 หลักจาก Authenticator<input data-mfa-code inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" required></label><p class="phc-mfa-error" data-mfa-error role="alert"></p><div class="phc-mfa-actions"><button type="button" class="secondary" data-mfa-cancel>ออกจากระบบ</button><button class="primary">ยืนยัน</button></div></form></section>`;
  document.body.appendChild(mfaOverlay);
  return mfaOverlay;
}

function requestMfaCode({enrollment=false,qrCode=''}){
  const overlay=ensureMfaOverlay();
  overlay.hidden=false;
  overlay.querySelector('[data-mfa-message]').textContent=enrollment
    ? 'บัญชีเจ้าหน้าที่/ผู้ดูแลต้องใช้ MFA กรุณาสแกน QR ด้วย Google Authenticator, Microsoft Authenticator หรือแอป TOTP แล้วกรอกรหัส'
    : 'กรอกรหัสจากแอป Authenticator เพื่อเข้าถึงข้อมูลสิทธิ์สูง';
  const image=overlay.querySelector('[data-mfa-qr]');
  image.hidden=!qrCode;
  if(qrCode) image.src=qrCode; else image.removeAttribute('src');
  const form=overlay.querySelector('[data-mfa-form]');
  const input=overlay.querySelector('[data-mfa-code]');
  const error=overlay.querySelector('[data-mfa-error]');
  input.value='';error.textContent='';
  setTimeout(()=>input.focus(),50);
  return new Promise(resolve=>{
    const finish=value=>{form.onsubmit=null;overlay.querySelector('[data-mfa-cancel]').onclick=null;overlay.hidden=true;resolve(value);};
    form.onsubmit=event=>{event.preventDefault();const code=input.value.replace(/\D/g,'');if(code.length!==6){error.textContent='กรุณากรอกรหัส 6 หลัก';return;}finish(code);};
    overlay.querySelector('[data-mfa-cancel]').onclick=()=>finish(null);
  });
}

async function requirePrivilegedMfa(session){
  const {data:profile,error:profileError}=await supabase.from('profiles').select('role,active').eq('user_id',session.user.id).maybeSingle();
  if(profileError) throw profileError;
  if(!profile?.active || !['admin','staff'].includes(profile.role)) return true;
  const {data:assurance,error:assuranceError}=await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if(assuranceError) throw assuranceError;
  if(assurance?.currentLevel==='aal2') return true;
  const {data:listed,error:listError}=await supabase.auth.mfa.listFactors();
  if(listError) throw listError;
  let factor=(listed?.totp||[]).find(item=>item.status==='verified');
  let enrollment=null;
  if(!factor){
    for(const stale of (listed?.all||[]).filter(item=>item.factor_type==='totp'&&item.status!=='verified')){
      try{await supabase.auth.mfa.unenroll({factorId:stale.id});}catch{}
    }
    const {data,error}=await supabase.auth.mfa.enroll({factorType:'totp',friendlyName:`OSM-PHC ${profile.role}`});
    if(error) throw error;
    enrollment=data;
    factor={id:data.id};
  }
  const code=await requestMfaCode({enrollment:Boolean(enrollment),qrCode:enrollment?.totp?.qr_code||''});
  if(!code){await supabase.auth.signOut({scope:'local'});return false;}
  const {error:verifyError}=await supabase.auth.mfa.challengeAndVerify({factorId:factor.id,code});
  if(verifyError){await supabase.auth.signOut({scope:'local'});throw new Error('รหัส MFA ไม่ถูกต้อง กรุณาเข้าระบบใหม่');}
  return true;
}

function readLastActivity(){
  try{ return Number(localStorage.getItem(LAST_ACTIVITY_KEY) || 0); }catch{ return 0; }
}

function writeLastActivity(value=Date.now(),force=false){
  if(!idleWatchActive && !force) return;
  const now = Date.now();
  if(!force && now - lastActivityWrite < ACTIVITY_WRITE_THROTTLE_MS) return;
  lastActivityWrite = now;
  try{ localStorage.setItem(LAST_ACTIVITY_KEY,String(value)); }catch{}
}

function clearIdleTimer(){
  if(idleTimer){ clearTimeout(idleTimer); idleTimer = null; }
}

function stopIdleWatch(clearStored=false){
  idleWatchActive = false;
  clearIdleTimer();
  if(clearStored){ try{ localStorage.removeItem(LAST_ACTIVITY_KEY); }catch{} }
}

async function autoLogoutForIdle(){
  if(idleLogoutInProgress) return;
  idleLogoutInProgress = true;
  stopIdleWatch(true);
  try{ sessionStorage.setItem(IDLE_NOTICE_KEY,'1'); }catch{}
  try{ await supabase.auth.signOut({ scope:'local' }); }catch{}
  window.location.reload();
}

function scheduleIdleCheck(){
  if(!idleWatchActive) return;
  clearIdleTimer();
  const last = readLastActivity() || Date.now();
  const remaining = IDLE_TIMEOUT_MS - (Date.now() - last);
  if(remaining <= 0){ autoLogoutForIdle(); return; }
  idleTimer = setTimeout(checkIdleTimeout,Math.min(remaining,IDLE_TIMEOUT_MS));
}

function checkIdleTimeout(){
  if(!idleWatchActive || idleLogoutInProgress) return;
  const last = readLastActivity();
  if(last && Date.now() - last >= IDLE_TIMEOUT_MS){ autoLogoutForIdle(); return; }
  scheduleIdleCheck();
}

function markActivity(){
  if(!idleWatchActive || document.visibilityState === 'hidden') return;
  writeLastActivity(Date.now());
  scheduleIdleCheck();
}

function startIdleWatch({reset=false}={}){
  idleWatchActive = true;
  idleLogoutInProgress = false;
  let last = readLastActivity();
  if(reset || !last){ last = Date.now(); writeLastActivity(last,true); }
  if(Date.now() - last >= IDLE_TIMEOUT_MS){ autoLogoutForIdle(); return; }
  scheduleIdleCheck();
}

async function initializeSessionSecurity(){
  const { data:{ session } } = await supabase.auth.getSession();
  if(session){
    startIdleWatch();
  }else{
    stopIdleWatch(true);
    try{
      if(sessionStorage.getItem(IDLE_NOTICE_KEY)==='1'){
        sessionStorage.removeItem(IDLE_NOTICE_KEY);
        const error = loginError();
        if(error) error.textContent = 'ออกจากระบบอัตโนมัติ เนื่องจากไม่มีการใช้งานเกิน 10 นาที';
      }
    }catch{}
  }
}

const loginForm = $('#login-form');
if(loginForm){
  loginForm.addEventListener('submit', async event => {
    event.preventDefault();
    event.stopImmediatePropagation();
    const error = loginError();
    const button = loginButton();
    if(error) error.textContent = '';
    const formData = new FormData(loginForm);
    const login = String(formData.get('login') || '').trim();
    const password = String(formData.get('password') || '');
    if(!login || !password){ if(error) error.textContent = 'กรุณากรอกชื่อผู้ใช้และรหัสผ่าน'; return; }

    let loginSucceeded = false;
    showLoginBusy();
    await new Promise(resolve => requestAnimationFrame(() => resolve()));

    try{
      const {response,payload} = await secureLogin(login,password);
      if(response.status === 423 || payload.error === 'LOGIN_LOCKED'){
        startLockCountdown(payload.retry_after_seconds || 600);
        return;
      }
      if(!response.ok){
        const remaining = Number(payload.attempts_remaining);
        if(error){
          error.textContent = Number.isFinite(remaining)
            ? `ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง · เหลือลองได้อีก ${remaining} ครั้งก่อนระงับ 10 นาที`
            : payload.error === 'INVALID_LOGIN'
              ? 'อสม. กรุณากรอกเบอร์โทรศัพท์ 10 หลัก หรือใช้อีเมลสำหรับเจ้าหน้าที่'
              : 'ไม่สามารถเข้าสู่ระบบได้ กรุณาลองใหม่';
        }
        return;
      }
      if(!payload.session?.access_token || !payload.session?.refresh_token) throw new Error('SESSION_MISSING');
      stopLockCountdown();
      const { data, error:setError } = await supabase.auth.setSession({
        access_token: payload.session.access_token,
        refresh_token: payload.session.refresh_token
      });
      if(setError || !data.session) throw setError || new Error('SESSION_SETUP_FAILED');
      if(!await requirePrivilegedMfa(data.session)) return;
      writeLastActivity(Date.now(),true);
      try{ sessionStorage.setItem(LOGIN_SUCCESS_KEY,'1'); }catch{}
      loginSucceeded = true;
      window.location.reload();
    }catch(loginErrorValue){
      if(error) error.textContent = String(loginErrorValue?.message||'').startsWith('รหัส MFA')
        ? loginErrorValue.message
        : 'ไม่สามารถเชื่อมต่อระบบเข้าสู่ระบบได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่';
    }finally{
      if(!loginSucceeded) hideLoginBusy();
      if(button && !lockCountdownTimer && !loginSucceeded){
        button.disabled = false;
        button.textContent = 'เข้าสู่ระบบ';
      }
    }
  }, true);
}

const logoutButton = $('#logout');
if(logoutButton){
  logoutButton.addEventListener('click',()=>stopIdleWatch(true),true);
}

['pointerdown','touchstart','keydown','scroll','click'].forEach(type => {
  window.addEventListener(type,markActivity,{passive:true,capture:true});
});
document.addEventListener('visibilitychange',()=>{ if(document.visibilityState==='visible') checkIdleTimeout(); });
window.addEventListener('pageshow',()=>checkIdleTimeout());

supabase.auth.onAuthStateChange((event,session)=>{
  if(event==='SIGNED_OUT'){
    stopIdleWatch(true);
    return;
  }
  if((event==='INITIAL_SESSION' || event==='SIGNED_IN') && session && !idleWatchActive){
    startIdleWatch();
  }
});

ensureLoginBusyOverlay();
initializeSessionSecurity();