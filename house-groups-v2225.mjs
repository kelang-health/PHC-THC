import {getSharedSupabase,getSharedProfile,sharedCall,invalidateShared,bindPortalActivation} from './shared-runtime-v2035.mjs?v=2.0.126-log-usage';
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const num=v=>Number(v||0).toLocaleString('th-TH');
const labels={care:'บ้านดูแล',review:'รอตรวจสอบ',empty:'บ้านว่าง'};
const PAGE=30;
let client,profile,rows=[],group='care',term='',limit=PAGE,root,overlay,epoch=0,started=false;
export function visibleHouseRows(rows,group,term=''){
 const q=term.trim().toLowerCase();
 return rows.filter(r=>r.house_group===group&&(!q||[r.house_no,r.community,r.moo,r.hcode].some(v=>String(v??'').toLowerCase().includes(q))));
}
function style(){if(document.getElementById('house-groups-style'))return;const s=document.createElement('style');s.id='house-groups-style';s.textContent=`
.house-groups-ready>[data-house-review-section],.house-groups-ready>.section-head,.house-groups-ready>.table-wrap,.house-groups-ready>#staff-house-note,
.house-groups-ready>.myh>.myh-search,.house-groups-ready>.myh>.myh-msg,.house-groups-ready .myh-title,.house-groups-ready .myh-kpis{display:none!important}
.house-groups-ready:not([data-house-group="review"]) [data-myh-pending]{display:none!important}
.house-groups-ready>.myh{margin-top:14px}.house-groups-ready>.myh>.myh-top{order:10}.hg25{display:grid;gap:12px}.hg25-head{display:flex;align-items:center;justify-content:space-between;gap:12px}.hg25-head h2{margin:0;font-size:1.25rem}.hg25 button{font:inherit;cursor:pointer}.hg25-refresh{min-width:44px;min-height:44px;border:1px solid #bbd2ca;background:white;border-radius:12px}.hg25-tabs{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:7px}.hg25-tab{min-width:0;min-height:76px;border:2px solid #cbded5;border-radius:14px;background:#f7faf8;color:#234e43;padding:9px 3px;line-height:1.5;font-weight:800}.hg25-tab strong{display:block;font-size:1.05rem}.hg25-tab[aria-pressed="true"]{background:#087563;color:white;border-color:#087563}.hg25-tab[data-group="review"][aria-pressed="true"]{background:#855d15;border-color:#855d15}.hg25-tab[data-group="empty"][aria-pressed="true"]{background:#516679;border-color:#516679}.hg25-search{display:grid;gap:6px;font-weight:700}.hg25-search input{width:100%;box-sizing:border-box;min-height:54px;border:2px solid #c4d9cf;border-radius:12px;font:inherit;padding:10px}.hg25-list{display:grid;gap:9px}.hg25-card{width:100%;box-sizing:border-box;min-height:74px;padding:12px;border:1px solid #d1e2d9;border-radius:14px;background:white;color:#21483d;text-align:left}.hg25-card strong,.hg25-card small{display:block}.hg25-card strong{font-size:1.08rem}.hg25-card small{margin-top:5px;line-height:1.5;color:#51675f}.hg25-card.review{border-color:#d5b879;background:#fff9e9}.hg25-card.empty{background:#f4f7fa;border-color:#c7d2dd}.hg25-note{background:#f0f5f3;border-radius:12px;padding:11px;line-height:1.6;color:#4e675e}.hg25-more{min-height:48px;border:1px solid #a8c8bb;border-radius:12px;background:white;color:#175c48}.hg25-special summary{cursor:pointer;min-height:44px;line-height:44px}.hg25-overlay{position:fixed;inset:0;z-index:17000;background:#12352d88;display:grid;place-items:center;padding:12px}.hg25-dialog{box-sizing:border-box;width:min(100%,560px);max-height:90vh;overflow:auto;background:white;border-radius:18px;padding:18px;color:#234e43}.hg25-dialog button{min-height:48px;font:inherit;border:1px solid #b4cdc2;border-radius:12px;padding:10px 14px;background:#edf5f1;color:#234e43;cursor:pointer}.hg25-dialog h2{margin-top:0;padding-right:50px;font-size:1.3rem}.hg25-close{float:right}.hg25-names{margin-top:12px;display:grid;gap:8px}.hg25-name{border:1px solid #d1e2d9;border-radius:10px;padding:10px;overflow-wrap:anywhere}.hg25-error{color:#a32929}.hg25 [hidden],.hg25-overlay [hidden]{display:none!important}
@media(max-width:420px){.hg25-tabs{gap:5px}.hg25-tab{font-size:.87rem}.hg25-tab strong{font-size:1rem}.hg25-dialog{padding:15px}}
`;document.head.append(s);}
function renderList(){if(!root)return;const filtered=visibleHouseRows(rows,group,term),shown=filtered.slice(0,limit);root.querySelector('[data-hg-result]').textContent=`${labels[group]} ${num(filtered.length)} หลัง · แสดง ${num(shown.length)} หลัง`;
 root.querySelector('[data-hg-list]').innerHTML=shown.map(card).join('')||'<div class="hg25-note">ไม่มีบ้านในกลุ่มนี้ตามคำค้นหา</div>';
 root.querySelector('[data-hg-more]').hidden=shown.length>=filtered.length;
 root.querySelectorAll('[data-hg-open]').forEach(b=>b.onclick=()=>openHouse(rows.find(r=>String(r.id)===b.dataset.hgOpen),b));
 root.closest('[data-portal-panel]').dataset.houseGroup=group;
 root.querySelectorAll('[data-group]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.group===group)));
}
function card(r){const reviewClass=r.review?.unassigned_village?'house-review-yellow':r.review?.needs_id11?'house-review-red':'';return `<button type="button" class="hg25-card ${esc(r.house_group)} ${reviewClass}" data-hg-open="${esc(r.id)}"${r.review?` data-house-review-id="${esc(r.id)}"`:''}><strong>บ้าน ${esc(r.house_no||'ไม่ระบุ')} · หมู่ ${esc(r.moo||'—')}</strong><small>${esc(r.community||'ยังไม่ระบุชุมชน')}</small><small>${esc(r.reason)}</small>${r.house_group!=='special'?`<small>เป้าหมายสุขภาพ ${num(r.target_count)} คน${Number(r.type2_count)>0?` · ชื่อทะเบียน type 2 ${num(r.type2_count)} คน (ไม่นับเป็นเป้าหมาย)`:''}</small>`:''}</button>`;}
function create(){const panel=document.querySelector('[data-portal-panel="houses"]');if(!panel)return;root=panel.querySelector('[data-house-groups]');if(root)return;root=document.createElement('section');root.className='hg25';root.dataset.houseGroups='';panel.prepend(root);
 root.innerHTML=`<div class="hg25-head"><h2>บ้านในพื้นที่ของคุณ</h2><button type="button" class="hg25-refresh" data-hg-refresh aria-label="โหลดข้อมูลบ้านล่าสุด">↻</button></div><div class="hg25-tabs" role="group" aria-label="เลือกกลุ่มบ้าน">${Object.entries(labels).map(([key,label])=>`<button type="button" class="hg25-tab" data-group="${key}" aria-pressed="${key==='care'}">${label}<strong data-hg-count="${key}">— หลัง</strong></button>`).join('')}</div><label class="hg25-search">ค้นหาบ้านเลขที่ / ชุมชน<input type="search" data-hg-search placeholder="เช่น 12 หรือ 12/1"></label><div data-hg-result role="status" aria-live="polite"></div><div class="hg25-list" data-hg-list></div><button type="button" class="hg25-more" data-hg-more hidden>แสดงเพิ่ม</button><div data-hg-special></div><div data-hg-error role="alert" class="hg25-error"></div>`;
 root.querySelectorAll('[data-group]').forEach(b=>b.onclick=()=>{group=b.dataset.group;limit=PAGE;renderList();});
 root.querySelector('[data-hg-search]').value=term;root.querySelector('[data-hg-search]').oninput=e=>{term=e.target.value;limit=PAGE;renderList();};
 root.querySelector('[data-hg-more]').onclick=()=>{limit+=PAGE;renderList();};
 root.querySelector('[data-hg-refresh]').onclick=()=>{document.querySelector('[data-myh-refresh]')?.click();return load(true);};
}
async function load(force=false){const before=epoch,current=await getSharedProfile(client);if(before!==epoch||!current?.active)return;const ticket=++epoch;
 if(profile?.user_id!==current.user_id){rows=[];group='care';term='';limit=PAGE;root?.remove();root=null;}profile=current;create();if(!root)return;
 const button=root.querySelector('[data-hg-refresh]');button.disabled=true;root.querySelector('[data-hg-error]').textContent='';
 if(force)invalidateShared(`house-groups:${profile.user_id}`);
 try{const result=await sharedCall(`house-groups:${profile.user_id}`,()=>client.rpc('house_groups_v2225'),60000);if(ticket!==epoch)return;if(result.error)throw result.error;
  if(!Array.isArray(result.data))throw Error('INVALID_RESPONSE');rows=result.data;
  root.closest('[data-portal-panel]').classList.add('house-groups-ready');
  for(const key of Object.keys(labels))root.querySelector(`[data-hg-count="${key}"]`).textContent=`${num(rows.filter(r=>r.house_group===key).length)} หลัง`;
  const special=rows.filter(r=>r.house_group==='special');root.querySelector('[data-hg-special]').innerHTML=special.length?`<details class="hg25-special"><summary>ทะเบียนบ้านพิเศษ ${num(special.length)} หลัง · ไม่นับเป็นบ้านเป้าหมาย</summary>${special.map(card).join('')}</details>`:'';
  renderList();
 }catch{if(ticket===epoch)root.querySelector('[data-hg-error]').textContent='โหลดกลุ่มบ้านไม่สำเร็จ กรุณากด ↻ เพื่อลองใหม่';}
 finally{if(ticket===epoch)button.disabled=false;}
}
function close(){if(!overlay)return;const focus=overlay.returnFocus;document.body.style.overflow=overlay.previousOverflow;overlay.remove();overlay=null;document.removeEventListener('keydown',escapeDialog);if(focus?.isConnected)focus.focus();}
function escapeDialog(e){if(e.key==='Escape')close();else if(e.key==='Tab'&&overlay){const buttons=[...overlay.querySelectorAll('button:not(:disabled)')],first=buttons[0],last=buttons.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus();}}}
async function openHouse(row,button){if(!row)return;
 if(row.house_group==='review'){if(row.review)document.dispatchEvent(new CustomEvent('phc:open-house-registration-review',{detail:{houseId:row.id}}));else document.dispatchEvent(new CustomEvent('phc:open-house-detail',{detail:{houseId:row.id}}));return;}
 if(row.house_group==='care'){document.dispatchEvent(new CustomEvent('phc:open-field-house',{detail:{houseId:row.id}}));return;}
 await openNotice(row,button);
}
async function openNotice(row,button){close();const o=document.createElement('div');overlay=o;o.returnFocus=button;o.previousOverflow=document.body.style.overflow;document.body.style.overflow='hidden';o.className='hg25-overlay';o.innerHTML='<section class="hg25-dialog" role="dialog" aria-modal="true" aria-labelledby="hg25-title"><button type="button" class="hg25-close" data-hg-close>ปิด</button><h2 id="hg25-title">รายละเอียดบ้าน</h2><div data-hg-notice role="status">กำลังโหลดข้อมูลทะเบียน…</div></section>';document.body.append(o);o.querySelector('[data-hg-close]').onclick=close;o.onclick=e=>{if(e.target===o)close();};document.addEventListener('keydown',escapeDialog);o.querySelector('[data-hg-close]').focus();
 // No names or person identifiers are fetched until an authorized operator clicks.
 try{const {data:d,error}=await client.rpc('house_type2_notice_v2225',{p_house_id:row.id});if(overlay!==o)return;if(error)throw error;
  o.querySelector('#hg25-title').textContent=`บ้าน ${d.house_no||'ไม่ระบุ'} · หมู่ ${d.moo||'—'}`;
  o.querySelector('[data-hg-notice]').innerHTML=`<p>${esc(d.community||'ยังไม่ระบุชุมชน')}</p><div class="hg25-note">${d.school_house_only?'โรงเรียน · เก็บเฉพาะทะเบียนบ้าน ไม่รวมประชากรเป็นเป้าหมาย':Number(d.type2_count)>0?`มีชื่อในทะเบียนบ้าน แต่ไม่อยู่ในพื้นที่ (type 2) จำนวน <strong>${num(d.type2_count)} คน</strong><br>ไม่นับรวมเป็นเป้าหมายของระบบ`:'ไม่พบรายชื่อ type 2 ในทะเบียน Cloud<br>บ้านนี้ไม่มีเป้าหมายสุขภาพตามข้อมูลปัจจุบัน จำนวนคนเป็นศูนย์ยังไม่ยืนยันว่าสภาพบ้านไม่มีผู้พักอาศัย'}</div>${d.can_view_names&&['admin','staff'].includes(profile?.role)?`<p><button type="button" data-hg-names aria-expanded="false">ดูรายชื่อที่ไม่นับเป็นเป้าหมาย ${num(d.type2_count)} คน</button></p><div class="hg25-names" data-hg-name-list hidden></div>`:''}`;
  if(profile?.role==='user'&&!d.school_house_only&&Number(d.type2_count)>0)o.querySelector('[data-hg-notice]').insertAdjacentHTML('beforeend','<p class="hg25-note" data-hg-contact-chair>ต้องการดูรายชื่อ โปรดติดต่อประธาน อสม.</p>');
  const b=o.querySelector('[data-hg-names]');if(b)b.onclick=async()=>{const list=o.querySelector('[data-hg-name-list]');if(!list.hidden){list.replaceChildren();list.hidden=true;b.setAttribute('aria-expanded','false');return;}b.disabled=true;
   try{const result=await client.rpc('house_type2_names_v2225',{p_house_id:row.id});if(overlay!==o)return;if(result.error)throw result.error;
    list.innerHTML=(result.data||[]).map(p=>`<div class="hg25-name">${esc(p.display_name)}<br><small>type 2 · ไม่นับเป็นเป้าหมาย</small></div>`).join('')||'ไม่มีรายชื่อ type 2';list.hidden=false;b.setAttribute('aria-expanded','true');
   }catch{if(overlay===o){list.textContent='เปิดรายชื่อไม่สำเร็จ หรือสิทธิ์ของคุณเปลี่ยน กรุณาปิดแล้วลองใหม่';list.hidden=false;}}
   finally{b.disabled=false;}
  };
 }catch{if(overlay===o)o.querySelector('[data-hg-notice]').textContent='เปิดบ้านไม่สำเร็จ หรือบ้านอยู่นอกขอบเขตสิทธิ์ กรุณาปิดแล้วลองใหม่';}
}
export async function initHouseGroupsV2225(url,key){if(started)return;started=true;client=await getSharedSupabase(url,key);style();
 client.auth?.onAuthStateChange?.(event=>{if(['SIGNED_OUT','SIGNED_IN','USER_UPDATED'].includes(event)){epoch++;close();rows=[];profile=null;group='care';term='';limit=PAGE;root?.remove();root=null;document.querySelector('[data-portal-panel="houses"]')?.classList.remove('house-groups-ready');invalidateShared('house-groups:');}});
 bindPortalActivation('houses',()=>load());
 document.addEventListener('phc:house-registration-corrected',()=>load(true));
 document.addEventListener('phc:house-requests-updated',()=>load(true));
}
