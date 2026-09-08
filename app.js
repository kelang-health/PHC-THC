import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js';

const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});
const $ = s => document.querySelector(s);
const esc = v => String(v ?? '').replace(/[&<>"']/g, x => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[x]));
const num = v => Number(v || 0).toLocaleString('th-TH');

function show(el, visible=true){ el.hidden = !visible; }
function roleLabel(role){ return ({admin:'ผู้ดูแลระบบ',coordinator:'ผู้ประสานงาน',viewer:'ผู้ดูรายงาน',volunteer:'อสม.'})[role] || role || 'ไม่ระบุ'; }
function anchorLabel(status){ return ({confirmed:'ยืนยัน',community_review:'ตรวจชุมชน',outside_tambon:'นอกตำบล',missing:'ไม่มีพิกัด'})[status] || status || '—'; }

async function getProfile(userId){
  const { data, error } = await supabase.from('profiles').select('user_id,display_name,role,community,volunteer_pid,active').eq('user_id', userId).maybeSingle();
  if(error) throw error;
  return data;
}

async function loadPortal(session){
  const profile = await getProfile(session.user.id);
  if(!profile || !profile.active){
    show($('#login-card'), false); show($('#portal'), false); show($('#blocked'), true); show($('#logout'), true); return;
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
  $('#scope-label').textContent = profile.role === 'admin' ? 'ทุกชุมชนที่อยู่ในระบบ' : (profile.community ? `ขอบเขตสิทธิ์: ${profile.community}` : 'ตามสิทธิ์ที่กำหนด');
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

  show($('#login-card'), false); show($('#blocked'), false); show($('#portal'), true); show($('#logout'), true);
}

async function refreshAuth(){
  const { data: { session } } = await supabase.auth.getSession();
  if(!session){ show($('#login-card'), true); show($('#portal'), false); show($('#blocked'), false); show($('#logout'), false); return; }
  try{ await loadPortal(session); }
  catch(error){ show($('#portal'), false); show($('#blocked'), true); $('#blocked').innerHTML = `<p class="eyebrow">ACCESS ERROR</p><h2>ไม่สามารถอ่านข้อมูลได้</h2><p>${esc(error.message)}</p>`; show($('#logout'), true); }
}

$('#login-form').addEventListener('submit', async e => {
  e.preventDefault();
  $('#login-error').textContent = '';
  const f = new FormData(e.target);
  const { error } = await supabase.auth.signInWithPassword({ email:f.get('email'), password:f.get('password') });
  if(error){ $('#login-error').textContent = error.message; return; }
  e.target.reset(); await refreshAuth();
});
$('#logout').addEventListener('click', async ()=>{ await supabase.auth.signOut(); await refreshAuth(); });
supabase.auth.onAuthStateChange(()=>refreshAuth());
refreshAuth();
