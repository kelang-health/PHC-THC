import {getSharedSupabase,getSharedProfile,invalidateShared} from './shared-runtime-v2035.mjs?v=2.0.35';
// Pending field-house corrections only. All authorization is rechecked by Supabase RPC.
const $=(s,r=document)=>r.querySelector(s);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let db=null,profile=null,staffBusy=false,staffTimer=null;
async function session(){
  if(!window.__PHC_SHARED_RUNTIME_V2035__?.client)throw Error('กรุณาเข้าสู่ระบบใหม่');
  db=db||await getSharedSupabase();profile=await getSharedProfile(db,{force:true});
  if(!profile?.active)throw Error('บัญชีไม่พร้อมใช้งาน');
  return profile;
}
function css(){
  if($('#field-correction-css'))return;
  const el=document.createElement('style');el.id='field-correction-css';
  el.textContent='.fc22{border:1px solid #bcd8cc;background:#f4faf7;border-radius:18px;padding:15px;margin:16px 0;display:grid;gap:12px}.fc22 h3{margin:0}.fc22 article{border:1px solid #d1e2d9;border-radius:13px;background:#fff;padding:12px;display:grid;gap:8px}.fc22 button,.fc22-dialog button{min-height:54px;border-radius:12px;border:2px solid #a5c6b9;background:#fff;color:#15594b;font:inherit;font-weight:800;padding:9px 13px;cursor:pointer}.fc22 button:disabled,.fc22-dialog button:disabled{opacity:.5}.fc22-dialog{border:0;border-radius:20px;max-height:92dvh;width:min(650px,96vw);padding:18px;background:#fff;overflow:auto;color:#173c34}.fc22-dialog::backdrop{background:#15372f99}.fc22-dialog form,.fc22-dialog label{display:grid;gap:9px}.fc22-dialog form{gap:14px}.fc22-dialog input{width:100%;min-height:50px;box-sizing:border-box;padding:10px;border:2px solid #bad2c7;border-radius:12px;font:inherit}.fc22-dialog .fc22-actions{display:grid;grid-template-columns:1fr 1fr;gap:10px}.fc22-dialog .fc22-save{background:#087563;color:#fff}.fc22-dialog .fc22-status{background:#f1f8f4;border-radius:12px;padding:12px}.fc22-dialog .fc22-map{height:260px;border-radius:12px;background:#e8f1ec}.fc22-dialog .fc22-coords{display:grid;grid-template-columns:1fr 1fr;gap:8px}.fc22-dialog [hidden]{display:none!important}@media(max-width:550px){.fc22-dialog{width:100vw;max-height:100dvh;min-height:100dvh;box-sizing:border-box;border-radius:0}.fc22-dialog .fc22-actions{grid-template-columns:1fr}}';
  document.head.appendChild(el);
}
async function leaflet(){
  if(window.L)return window.L;
  if(!$('#fc22-leaflet-css')){const link=document.createElement('link');link.id='fc22-leaflet-css';link.rel='stylesheet';link.href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';document.head.appendChild(link);}
  if(!window.__FC22_LEAFLET__)window.__FC22_LEAFLET__=new Promise((resolve,reject)=>{
    const script=document.createElement('script');script.src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';script.onload=()=>resolve(window.L);script.onerror=()=>reject(Error('โหลดแผนที่ไม่สำเร็จ'));document.head.appendChild(script);
  });
  return window.__FC22_LEAFLET__;
}
function errorText(err){
  const code=String(err?.message||err||'');
  if(code.includes('REQUEST_CHANGED_RELOAD'))return'รายการนี้ถูกแก้ไขหรือเข้าสู่การตรวจสอบแล้ว กรุณาโหลดใหม่';
  if(code.includes('REQUEST_ALREADY_IN_REVIEW_OR_VERIFIED'))return'รายการนี้กำลังตรวจสอบหรือยืนยันกับ JHCIS แล้ว';
  if(code.includes('HOUSE_OUT_OF_SCOPE'))return'บัญชีนี้ไม่มีสิทธิ์แก้ไขบ้านหลังนี้';
  if(code.includes('DUPLICATE_HOUSE_ID_11'))return'รหัสบ้าน 11 หลักซ้ำกับบ้านอื่น';
  if(code.includes('DUPLICATE_HOUSE_NO_MOO'))return'บ้านเลขที่ซ้ำในหมู่เดียวกัน';
  if(code.includes('OUTSIDE_TAMBON_OR_COMMUNITY'))return'พิกัดอยู่นอกเขตที่กำหนด กรุณาตรวจแผนที่';
  return'บันทึกไม่สำเร็จ กรุณาตรวจข้อมูลและลองใหม่';
}
async function openHouse(id,onSaved){
  css();await session();
  const {data,error}=await db.rpc('field_editable_house_requests_v2122');
  if(error)throw Error('อ่านรายการแก้ไขไม่สำเร็จ');
  const record=(data||[]).find(h=>String(h.id)===String(id));
  if(!record)throw Error('บ้านนี้ไม่มีสิทธิ์แก้ไขหรือเข้าสู่ขั้นตอนตรวจสอบแล้ว');
  const dialog=document.createElement('dialog');dialog.className='fc22-dialog';
  dialog.innerHTML=[
    '<form method="dialog" data-fc22-form><h2>แก้ไขบ้านที่แจ้งเพิ่ม</h2>',
    '<p class="fc22-status">บ้านยังรอตรวจ JHCIS · ใช้ระเบียนเดิม ไม่เพิ่มบ้านซ้ำ</p>',
    '<p>หมู่ '+esc(record.moo)+' · '+esc(record.community)+' (ไม่เปลี่ยนเขตในแบบฟอร์มนี้)</p>',
    '<label>บ้านเลขที่<input name="houseNo" maxlength="50" value="'+esc(record.house_no)+'" required></label>',
    '<label>รหัสประจำบ้าน 11 หลัก<input name="houseId11" maxlength="11" inputmode="numeric" pattern="[0-9]{11}" value="'+esc(record.house_id_11)+'" required></label>',
    '<label><input type="checkbox" name="changeLocation" style="width:auto;min-height:22px"> แก้พิกัดที่แจ้งผิด</label>',
    '<section data-fc22-location hidden><p>ใช้ GPS หรือแตะแผนที่เพื่อย้ายหมุด หากไม่แก้พิกัดให้เว้นช่องนี้ไว้</p>',
    '<button type="button" data-fc22-gps>ใช้ GPS ตอนนี้</button>',
    '<div class="fc22-map" data-fc22-map></div>',
    '<div class="fc22-coords"><label>ละติจูด<input name="lat" inputmode="decimal" type="number" step="any" value="'+esc(record.latitude)+'"></label>',
    '<label>ลองจิจูด<input name="lng" inputmode="decimal" type="number" step="any" value="'+esc(record.longitude)+'"></label></div>',
    '<small data-fc22-geo-status>ต้องตรวจพิกัดในเขตตำบลและชุมชนก่อนบันทึก</small></section>',
    '<p data-fc22-error role="alert" style="color:#a12a27"></p>',
    '<div class="fc22-actions"><button type="button" data-fc22-cancel>ยกเลิก</button>',
    '<button type="submit" class="fc22-save" data-fc22-save>บันทึกและส่งตรวจใหม่</button></div></form>'
  ].join('');
  document.body.appendChild(dialog);dialog.showModal();
  const form=$('[data-fc22-form]',dialog),location=$('[data-fc22-location]',dialog);
  const msg=$('[data-fc22-error]',dialog),geoMsg=$('[data-fc22-geo-status]',dialog);
  const close=()=>{try{map?.remove();}catch{}if(dialog.open)dialog.close();dialog.remove();};
  let map=null,marker=null,source='map';
  const setPoint=(lat,lng,kind='map')=>{
    form.elements.lat.value=Number(lat).toFixed(6);form.elements.lng.value=Number(lng).toFixed(6);source=kind;
    if(map&&Number.isFinite(Number(lat))&&Number.isFinite(Number(lng))){
      if(marker)marker.setLatLng([lat,lng]);else marker=window.L.marker([lat,lng],{draggable:true}).addTo(map);
      marker.on('dragend',()=>{const pt=marker.getLatLng();setPoint(pt.lat,pt.lng,'map');});
      map.setView([lat,lng],17);
    }
  };
  async function showMap(){
    try{
      const L=await leaflet();if(!dialog.open||location.hidden)return;
      map=L.map($('[data-fc22-map]',dialog)).setView([18.2696,99.5071],13);
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:20,attribution:'© OpenStreetMap'}).addTo(map);
      map.on('click',e=>setPoint(e.latlng.lat,e.latlng.lng,'map'));
      const lat=Number(form.elements.lat.value),lng=Number(form.elements.lng.value);
      if(Number.isFinite(lat)&&Number.isFinite(lng)&&lat>5&&lng>97)setPoint(lat,lng);
      setTimeout(()=>{if(dialog.open)map?.invalidateSize();},120);
    }catch{geoMsg.textContent='แผนที่ไม่พร้อม กรุณาใช้ GPS หรือกรอกพิกัดที่ตรวจสอบแล้ว';}
  }
  form.elements.changeLocation.onchange=()=>{
    location.hidden=!form.elements.changeLocation.checked;
    if(!location.hidden&&!map)showMap();
  };
  $('[data-fc22-gps]',dialog).onclick=()=>{
    if(!navigator.geolocation){geoMsg.textContent='อุปกรณ์ไม่รองรับ GPS';return;}
    geoMsg.textContent='กำลังอ่านตำแหน่ง…';
    navigator.geolocation.getCurrentPosition(p=>{setPoint(p.coords.latitude,p.coords.longitude,'gps');geoMsg.textContent='ได้ตำแหน่งแล้ว · ตรวจเขตก่อนบันทึก';},
      ()=>{geoMsg.textContent='อ่าน GPS ไม่สำเร็จ กรุณาเลือกตำแหน่งบนแผนที่';},
      {enableHighAccuracy:true,timeout:15000,maximumAge:0});
  };
  $('[data-fc22-cancel]',dialog).onclick=close;
  dialog.oncancel=()=>{try{map?.remove();}catch{}dialog.remove();};
  form.onsubmit=async event=>{
    event.preventDefault();msg.textContent='';
    const changed=form.elements.changeLocation.checked;
    const lat=Number(form.elements.lat.value),lng=Number(form.elements.lng.value);
    if(changed&&(!Number.isFinite(lat)||!Number.isFinite(lng))){msg.textContent='กรุณาเลือกพิกัดใหม่';return;}
    const save=$('[data-fc22-save]',dialog);save.disabled=true;
    try{
      if(changed){
        geoMsg.textContent='กำลังตรวจเขตพิกัด…';
        const check=await db.rpc('check_house_location',{p_latitude:lat,p_longitude:lng,p_community:record.community});
        if(check.error||!check.data?.allowed)throw Error('OUTSIDE_TAMBON_OR_COMMUNITY');
      }
      const {error:writeError}=await db.rpc('edit_pending_house_request_v2122',{
        p_house_id:record.id,p_expected_updated_at:record.updated_at,
        p_house_no:form.elements.houseNo.value.trim(),p_house_id_11:form.elements.houseId11.value.trim(),
        p_change_location:changed,p_latitude:changed?lat:null,p_longitude:changed?lng:null,
        p_coordinate_source:source
      });
      if(writeError)throw writeError;
      close();
      invalidateShared('my-pending-houses-v2055:');invalidateShared('staff-community-bundle-v2055:');
      document.dispatchEvent(new CustomEvent('phc:spatial-data-changed',{detail:{source:'field-correction-v2122'}}));
      try{await onSaved?.();}catch{}
    }catch(e){msg.textContent=errorText(e);}
    finally{save.disabled=false;}
  };
}
async function renderStaffPending(root,community){
  if(staffBusy)return;staffBusy=true;
  try{
    const p=await session();
    if(p.role!=='staff'||p.community?.trim()!==community?.trim()||root.hidden)return;
    const {data,error}=await db.rpc('field_editable_house_requests_v2122');
    if(error)throw error;
    if(root.hidden||root.dataset.community!==community||root.querySelector('[data-fc22-staff]'))return;
    const section=document.createElement('section');section.className='fc22';section.dataset.fc22Staff='1';
    const rows=(data||[]).filter(h=>h.community?.trim()===community.trim());
    section.innerHTML='<h3>บ้านที่รอตรวจ JHCIS · แก้ข้อมูลที่แจ้งผิด</h3>'+
      '<p>Staff แก้ได้เฉพาะคำขอบ้านในชุมชนที่รับผิดชอบ · บ้านยืนยันแล้วให้แก้ที่ JHCIS</p>'+
      (rows.length?rows.map(h=>'<article><strong>บ้านเลขที่ '+esc(h.house_no)+'</strong>'+
        '<small>หมู่ '+esc(h.moo)+' · '+esc(h.verification_status)+'</small>'+
        '<button type="button" data-fc22-edit="'+esc(h.id)+'">แก้ไขข้อมูลที่แจ้ง</button></article>').join(''):
        '<p>ไม่มีบ้านที่อยู่ในสถานะแก้ไขได้</p>');
    const head=root.querySelector('.community-workspace-head');
    if(head)head.insertAdjacentElement('afterend',section);else root.appendChild(section);
    section.querySelectorAll('[data-fc22-edit]').forEach(b=>b.onclick=async()=>{
      b.disabled=true;try{await openHouse(b.dataset.fc22Edit,()=>{
        section.remove();renderStaffPending(root,community);
      });}catch(e){alert(errorText(e));}finally{b.disabled=false;}
    });
  }catch{}finally{staffBusy=false;}
}
function init(){
  css();window.PHCFieldRequestEdits2122={openHouse};
  const root=$('#community-workspace');if(!root)return;
  new MutationObserver(()=>{
    if(root.hidden||root.querySelector('[data-fc22-staff]'))return;
    const community=root.dataset.community;
    if(!community||!root.querySelector('.community-workspace-head'))return;
    clearTimeout(staffTimer);staffTimer=setTimeout(()=>renderStaffPending(root,community),180);
  }).observe(root,{childList:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
