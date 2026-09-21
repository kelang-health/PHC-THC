// Pure presentation helpers. Counts and permissions are supplied by existing scoped APIs.
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num = value => Number(value).toLocaleString('th-TH');
export const POPULATION_NOTE = 'จำนวนสมาชิกแสดงเฉพาะประชากรในงานบริการตามเกณฑ์เดียวกับเมนูบ้าน ไม่ใช่จำนวนทั้งหมดในทะเบียนบ้าน · 0 คนไม่ได้หมายความว่าไม่มีคนในทะเบียน';

export function mergeHouseholdCards(houses, cards) {
  // UUID is the validated house reference. Never join on a house number.
  const byId = new Map(cards.map(card => [String(card.id), card]));
  return houses.map(h => {
    const card = byId.get(String(h.id));
    return {...h, health_access: card?.health_access === true,
      member_count: card?.health_access === true && card.member_count != null ? Number(card.member_count) : null};
  });
}

export function houseCards(rows, {assignmentBadge, emptyText = 'ไม่พบรายการบ้านตามสิทธิ์'} = {}) {
  if (!rows.length) return `<p class="community-empty">${esc(emptyText)}</p>`;
  return `<div class="community-record-list">${rows.map((h, index) => {
    const hasMap = h.latitude != null && h.longitude != null && Number.isFinite(Number(h.latitude)) && Number.isFinite(Number(h.longitude));
    const population = h.member_count == null ? 'จำนวนสมาชิก: ยังไม่มีข้อมูลในขอบเขตสิทธิ์' : h.member_count === 0 ? 'สมาชิกในงานบริการ 0 คน · ไม่ได้หมายความว่าบ้านไม่มีผู้อยู่อาศัย' : `สมาชิกในงานบริการ ${num(h.member_count)} คน`;
    const map = hasMap ? `<a class="community-map-link" href="https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${h.latitude},${h.longitude}`)}" target="_blank" rel="noopener noreferrer">ดูพิกัด</a>` : '<span class="muted">ไม่มีพิกัด</span>';
    return `<article class="community-record-card" data-community-house="${esc(h.id)}">
      <header><span class="community-record-index">${index + 1}</span><div><h5>บ้าน ${esc(h.house_no || 'ไม่ระบุ')}</h5><p>หมู่ ${esc(h.moo || '—')} · ${esc(h.community || '—')} · HCODE ${esc(h.hcode || '—')}</p></div></header>
      ${assignmentBadge ? assignmentBadge(h) : ''}
      <p class="community-population">${population}</p>
      <p>สถานะข้อมูล: ${esc(h.record_status || '—')}</p>
      <p class="${h.review_required ? 'warn' : 'good'}">${h.review_required ? `ต้องตรวจ · ${esc(h.review_reason || 'ทะเบียนระบุให้ตรวจสอบ แต่ยังไม่ระบุสาเหตุ')}` : 'ข้อมูลปกติ'}</p>
      <footer>${map}${h.id ? `<button type="button" class="secondary" data-community-house-open="${esc(h.id)}">${h.health_access ? 'เปิดบ้านและสมาชิก' : 'เปิดรายละเอียดบ้าน'}</button>` : '<span>ยังไม่มีรหัสบ้านสำหรับเปิดรายละเอียด</span>'}</footer>
    </article>`;
  }).join('')}</div>`;
}

export function volunteerCards(volunteers, houses) {
  if (!volunteers.length) return '<p class="community-empty">ไม่พบรายชื่อ อสม. ตามสิทธิ์</p>';
  return `<div class="community-record-list">${volunteers.map(v => {
    const pid = v.source_pid ?? v.volunteer_pid;
    const owned = pid == null ? [] : houses.filter(h => h.volunteer_pid != null && String(h.volunteer_pid) === String(pid));
    const count = Number(v.house_count || 0);
    const known = pid != null && count === owned.length && owned.every(h => h.health_access && h.member_count != null);
    const population = known ? `${num(owned.reduce((sum, h) => sum + h.member_count, 0))} คน` : 'ยังไม่มีข้อมูลครบตามสิทธิ์';
    return `<article class="community-record-card" data-community-volunteer><h5>${esc(v.display_name || 'ไม่ระบุชื่อ')}</h5><p>${esc(v.community || '—')}</p>
      <dl class="community-volunteer-metrics"><div><dt>บ้านรับผิดชอบทั้งหมด</dt><dd>${num(count)} หลัง</dd></div><div><dt>บ้านในชุมชนนี้</dt><dd>${num(owned.length)} หลัง</dd></div><div><dt>สมาชิกในงานบริการในชุมชนนี้</dt><dd>${population}</dd></div><div><dt>บ้านต้องตรวจในชุมชนนี้</dt><dd>${num(owned.filter(h => h.review_required).length)} หลัง</dd></div></dl>
      ${count === 0 ? '<p class="staff-workspace-note">อยู่ในทะเบียน อสม. · ยังไม่มีบ้านรับผิดชอบ</p>' : ''}
      ${count !== owned.length ? '<p class="muted">ยอดบ้านทั้งหมดรวมภาระงานนอกชุมชนนี้ตามสิทธิ์ ส่วนประชากรและรายการตรวจนับเฉพาะบ้านในชุมชนที่เปิด</p>' : ''}
    </article>`;
  }).join('')}</div>`;
}

export function selectCommunityView(workspace, action, {scroll = true} = {}) {
  workspace.querySelectorAll('[data-community-action]').forEach(button => {
    const active = button.dataset.communityAction === action;
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  });
  let selected;
  workspace.querySelectorAll('[data-community-view]').forEach(section => {
    section.hidden = section.dataset.communityView !== action;
    if (!section.hidden) selected = section;
  });
  if (scroll && selected) selected.scrollIntoView({behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth', block: 'nearest'});
}
