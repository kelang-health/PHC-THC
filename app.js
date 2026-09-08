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

function show(el, visible=true){ el.hidden = !visible; }
function roleLabel(role){ return ({admin:'ผู้ดูแลระบบ',staff:'เจ้าหน้าที่',user:'อสม.'})[role] || role || 'ไม่ระบุ'; }

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
  $('#scope-label').textContent = ['admin','staff'].includes(profile.role) ? 'ทุก 16 ชุมชนในระบบ' : `บ้านในความรับผิดชอบของคุณ · PID ${profile.volunteer_pid??'—'}`;
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
