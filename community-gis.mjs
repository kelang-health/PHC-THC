const VERSION = '1.8.17';
const DEFAULT_CENTER = [18.2696, 99.5071];
const DEFAULT_ZOOM = 14;
let supabase = null;
let map = null;
let markerLayer = null;
let draftMarker = null;
let activeWorkspace = null;
let houses = [];
let selectedHouse = null;
let draftCoordinate = null;
let leafletPromise = null;
let observer = null;
let enhanceTimer = null;

const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const hasCoordinate = h => Number.isFinite(Number(h?.latitude)) && Number.isFinite(Number(h?.longitude));
const coordText = (lat,lng) => `${Number(lat).toFixed(6)}, ${Number(lng).toFixed(6)}`;

function injectStyles(){
  if(document.getElementById('community-gis-style')) return;
  const style = document.createElement('style');
  style.id = 'community-gis-style';
  style.textContent = `
  .community-gis-action{background:#0b6f60!important;color:#fff!important;border-color:#0b6f60!important}
  .community-gis-view{display:grid;gap:16px;margin-top:14px}
  .community-gis-head{display:flex;justify-content:space-between;align-items:flex-start;gap:14px;flex-wrap:wrap}
  .community-gis-head h4{margin:0 0 4px;font-size:1.2rem}.community-gis-head p{margin:0;color:#5d716c;line-height:1.55}
  .community-gis-filter{display:grid;grid-template-columns:minmax(220px,1.4fr) minmax(180px,.8fr);gap:12px;align-items:end;background:#f5faf7;border:1px solid #d5e6df;border-radius:16px;padding:14px}
  .community-gis-filter label{margin:0;font-size:1rem}.community-gis-filter select{width:100%;min-height:54px;padding:11px 13px;border:2px solid #bfd6cd;border-radius:13px;background:#fff;font:inherit;font-size:1.05rem;font-weight:750;color:#17312d}
  .community-gis-status{display:flex;align-items:center;min-height:54px;padding:10px 13px;border-radius:13px;background:#fff;border:1px solid #d6e5df;font-weight:800;line-height:1.35}
  .community-gis-map-wrap{position:relative}.community-gis-map{height:430px;min-height:330px;border:2px solid #c9ddd5;border-radius:18px;overflow:hidden;background:#e9f0ed;z-index:1}
  .community-gis-help{padding:12px 14px;border-radius:14px;background:#fff8df;border:1px solid #eadca9;color:#604f1e;font-size:.92rem;line-height:1.55}
  .community-house-card{display:grid;gap:10px;padding:15px;border-radius:16px;background:#fff;border:1px solid #d8e6e0;box-shadow:0 8px 22px #17312d0d}
  .community-house-card[hidden]{display:none!important}.community-house-title{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap}.community-house-title strong{font-size:1.22rem}.community-house-meta{color:#5e716b;line-height:1.55}.community-house-coordinate{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.95rem;background:#eef5f2;padding:10px 12px;border-radius:11px;word-break:break-word}
  .community-gis-actions{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.community-gis-btn,.community-gis-link{display:flex;align-items:center;justify-content:center;text-align:center;gap:8px;min-height:58px;padding:12px 14px;border-radius:14px;border:2px solid #bcd2c9;background:#fff;color:#194f46;font:inherit;font-size:1.02rem;font-weight:850;line-height:1.25;cursor:pointer;text-decoration:none}.community-gis-btn:hover,.community-gis-link:hover{background:#f1f8f5}.community-gis-btn.primary{background:#0b6f60;color:#fff;border-color:#0b6f60}.community-gis-btn.gps{background:#eaf5ff;color:#164b78;border-color:#b9d8ef}.community-gis-btn:disabled,.community-gis-link.disabled{opacity:.45;cursor:not-allowed;pointer-events:none}
  .community-gis-message{min-height:1.5em;font-weight:750;line-height:1.45}.community-gis-message.good{color:#116450}.community-gis-message.bad{color:#a23e31}.community-gis-message.info{color:#315c72}
  .community-gis-legend{display:flex;gap:12px;flex-wrap:wrap;font-size:.82rem;color:#50645e}.community-gis-legend span{display:inline-flex;align-items:center;gap:5px}.community-gis-dot{width:12px;height:12px;border-radius:50%;display:inline-block;border:2px solid #fff;box-shadow:0 0 0 1px #98aaa4}.community-gis-dot.ok{background:#17745f}.community-gis-dot.review{background:#b75a42}.community-gis-dot.other{background:#3979a8}
  .community-gis-confirm{position:fixed;inset:0;z-index:3000;background:#102e287d;display:flex;align-items:center;justify-content:center;padding:18px}.community-gis-confirm[hidden]{display:none!important}.community-gis-confirm-card{width:min(520px,100%);background:#fff;border-radius:20px;padding:22px;box-shadow:0 20px 60px #0004}.community-gis-confirm-card h3{margin:0 0 8px;font-size:1.35rem}.community-gis-confirm-card p{line-height:1.6;color:#536a64}.community-gis-confirm-actions{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:16px}.community-gis-confirm-actions button{min-height:58px;border-radius:14px;font:inherit;font-size:1.03rem;font-weight:850;border:0;cursor:pointer}.community-gis-confirm-cancel{background:#e9f0ed;color:#294b44}.community-gis-confirm-save{background:#0b6f60;color:#fff}
  .leaflet-popup-content{font-family:inherit;font-size:15px;line-height:1.5}.leaflet-control-layers{font-size:14px}
  @media(max-width:700px){.community-gis-filter{grid-template-columns:1fr}.community-gis-map{height:52vh;min-height:350px}.community-gis-actions{grid-template-columns:1fr}.community-gis-btn,.community-gis-link{min-height:62px;font-size:1.08rem}.community-gis-filter select{min-height:58px;font-size:1.08rem}.community-gis-confirm-actions{grid-template-columns:1fr}.community-gis-confirm-actions button{min-height:62px;font-size:1.08rem}}
  `;
  document.head.appendChild(style);
}

function setVersion(){
  const footer = document.querySelector('.login-version');
  if(footer) footer.textContent = `Cloud v${VERSION}`;
}

async function ensureLeaflet(){
  if(window.L) return window.L;
  if(leafletPromise) return leafletPromise;
  leafletPromise = new Promise((resolve,reject)=>{
    if(!document.querySelector('link[data-phc-leaflet]')){
      const link=document.createElement('link');
      link.rel='stylesheet';link.href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';link.dataset.phcLeaflet='1';
      document.head.appendChild(link);
    }
    const existing=document.querySelector('script[data-phc-leaflet]');
    if(existing){existing.addEventListener('load',()=>resolve(window.L),{once:true});existing.addEventListener('error',reject,{once:true});return;}
    const script=document.createElement('script');
    script.src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';script.dataset.phcLeaflet='1';script.async=true;
    script.onload=()=>resolve(window.L);script.onerror=()=>reject(new Error('ไม่สามารถโหลดแผนที่ได้'));
    document.head.appendChild(script);
  });
  return leafletPromise;
}

async function fetchCommunityHouses(community){
  const rows=[];
  for(let from=0;;from+=1000){
    const {data,error}=await supabase.from('houses')
      .select('id,hcode,house_no,moo,community,latitude,longitude,coordinate_source,coordinate_status,record_status,review_required,review_reason,volunteer_pid')
      .eq('community',community).order('house_no').range(from,from+999);
    if(error) throw error;
    rows.push(...(data||[]));
    if(!data || data.length<1000) break;
  }
  return rows;
}

function houseStatusText(h){
  if(!hasCoordinate(h)) return 'ยังไม่มีพิกัด';
  if(h.review_required) return 'มีพิกัด · ควรตรวจสอบข้อมูล';
  if(String(h.coordinate_status||'').startsWith('resolved_')) return 'ยืนยันพิกัดจากพื้นที่แล้ว';
  return 'มีพิกัด';
}

function markerColor(h){
  if(h.review_required) return '#b75a42';
  if(String(h.coordinate_status||'').startsWith('resolved_')) return '#17745f';
  return '#3979a8';
}

function naturalHouseSort(a,b){
  return String(a.house_no||'').localeCompare(String(b.house_no||''),'th',{numeric:true,sensitivity:'base'});
}

function addBaseLayers(L,targetMap){
  const street=L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:20,attribution:'&copy; OpenStreetMap contributors'}).addTo(targetMap);
  const satellite=L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',{maxZoom:20,attribution:'Tiles &copy; Esri'});
  const labels=L.tileLayer('https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',{maxZoom:20,attribution:'Labels &copy; Esri'});
  const satelliteGroup=L.layerGroup([satellite,labels]);
  L.control.layers({'แผนที่ถนน':street,'ภาพถ่ายดาวเทียม':satelliteGroup},null,{position:'topright',collapsed:true}).addTo(targetMap);
}

function renderMarkers(){
  if(!map || !markerLayer || !window.L) return;
  markerLayer.clearLayers();
  const bounds=[];
  houses.forEach(h=>{
    if(!hasCoordinate(h)) return;
    const lat=Number(h.latitude),lng=Number(h.longitude);
    const marker=window.L.circleMarker([lat,lng],{radius:8,color:'#fff',weight:2,fillColor:markerColor(h),fillOpacity:.92});
    marker.bindPopup(`<strong>บ้าน ${esc(h.house_no||'ไม่ระบุ')}</strong><br>หมู่ ${esc(h.moo||'—')} · ${esc(h.community||'—')}<br>${esc(houseStatusText(h))}`);
    marker.on('click',()=>selectHouse(h.id,true));
    marker.addTo(markerLayer);bounds.push([lat,lng]);
  });
  if(bounds.length && !selectedHouse){
    try{map.fitBounds(bounds,{padding:[25,25],maxZoom:17});}catch{}
  }
}

function updateMapMetric(){
  if(!activeWorkspace) return;
  const mapped=houses.filter(hasCoordinate).length;
  const el=activeWorkspace.querySelector('[data-community-gis-metric]');
  if(el) el.textContent=`${mapped.toLocaleString('th-TH')} / ${houses.length.toLocaleString('th-TH')} หลังมีพิกัด`;
}

function updateHouseCard(){
  if(!activeWorkspace) return;
  const card=activeWorkspace.querySelector('[data-community-house-card]');
  const save=activeWorkspace.querySelector('[data-community-save-coordinate]');
  const reset=activeWorkspace.querySelector('[data-community-reset-coordinate]');
  const maps=activeWorkspace.querySelector('[data-community-open-maps]');
  const dirs=activeWorkspace.querySelector('[data-community-directions]');
  if(!selectedHouse){if(card)card.hidden=true;if(save)save.disabled=true;return;}
  card.hidden=false;
  const title=card.querySelector('[data-house-title]');
  const meta=card.querySelector('[data-house-meta]');
  const coordinate=card.querySelector('[data-house-coordinate]');
  const status=card.querySelector('[data-house-status]');
  if(title) title.textContent=`บ้าน ${selectedHouse.house_no||'ไม่ระบุ'}`;
  if(meta) meta.textContent=`หมู่ ${selectedHouse.moo||'—'} · ${selectedHouse.community||'—'} · HCODE ${selectedHouse.hcode||'—'}`;
  if(status) status.textContent=houseStatusText(selectedHouse);
  const current=draftCoordinate || (hasCoordinate(selectedHouse)?{lat:Number(selectedHouse.latitude),lng:Number(selectedHouse.longitude),source:selectedHouse.coordinate_source||'เดิม'}:null);
  if(coordinate) coordinate.textContent=current ? `${draftCoordinate?'พิกัดที่เลือกใหม่':'พิกัดปัจจุบัน'}: ${coordText(current.lat,current.lng)}` : 'บ้านหลังนี้ยังไม่มีพิกัด — ใช้ GPS หรือแตะแผนที่เพื่อกำหนดตำแหน่ง';
  if(save) save.disabled=!draftCoordinate;
  if(reset) reset.disabled=!draftCoordinate;
  if(current){
    const query=`${current.lat},${current.lng}`;
    maps.href=`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
    dirs.href=`https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(query)}`;
    maps.classList.remove('disabled');dirs.classList.remove('disabled');
  }else{
    maps.removeAttribute('href');dirs.removeAttribute('href');maps.classList.add('disabled');dirs.classList.add('disabled');
  }
}

function setMessage(text,type='info'){
  const el=activeWorkspace?.querySelector('[data-community-gis-message]');
  if(!el) return;
  el.textContent=text||'';el.className=`community-gis-message ${type}`;
}

function setDraft(lat,lng,source){
  if(!selectedHouse){setMessage('กรุณาเลือกบ้านก่อนกำหนดพิกัด','bad');return;}
  draftCoordinate={lat:Number(lat),lng:Number(lng),source};
  if(draftMarker){map.removeLayer(draftMarker);draftMarker=null;}
  draftMarker=window.L.marker([draftCoordinate.lat,draftCoordinate.lng],{draggable:true}).addTo(map);
  draftMarker.bindPopup('พิกัดใหม่ที่กำลังจะบันทึก').openPopup();
  draftMarker.on('dragend',e=>{const p=e.target.getLatLng();draftCoordinate.lat=p.lat;draftCoordinate.lng=p.lng;updateHouseCard();setMessage('เลื่อนหมุดแล้ว กรุณาตรวจตำแหน่งก่อนกดบันทึก','info');});
  map.setView([draftCoordinate.lat,draftCoordinate.lng],18);
  updateHouseCard();
  setMessage(source==='gps'?'ได้ตำแหน่ง GPS แล้ว กรุณาตรวจบนแผนที่ก่อนกดบันทึก':'เลือกจุดบนแผนที่แล้ว กรุณาตรวจตำแหน่งก่อนกดบันทึก','info');
}

function resetDraft(){
  draftCoordinate=null;
  if(draftMarker && map){map.removeLayer(draftMarker);draftMarker=null;}
  updateHouseCard();
  if(selectedHouse && hasCoordinate(selectedHouse)) map.setView([Number(selectedHouse.latitude),Number(selectedHouse.longitude)],18);
  setMessage('ยกเลิกพิกัดที่เลือกใหม่แล้ว','info');
}

function selectHouse(id,fromMarker=false){
  const house=houses.find(h=>String(h.id)===String(id));
  if(!house) return;
  selectedHouse=house;draftCoordinate=null;
  if(draftMarker && map){map.removeLayer(draftMarker);draftMarker=null;}
  const selector=activeWorkspace?.querySelector('[data-community-house-select]');
  if(selector && selector.value!==String(id)) selector.value=String(id);
  updateHouseCard();
  if(hasCoordinate(house)){
    map.setView([Number(house.latitude),Number(house.longitude)],18);
    setMessage(fromMarker?`เลือกบ้าน ${house.house_no} จากแผนที่แล้ว`:`แสดงพิกัดบ้าน ${house.house_no} แล้ว สามารถนำทางหรือกำหนดพิกัดใหม่ได้`,'good');
  }else{
    setMessage(`บ้าน ${house.house_no} ยังไม่มีพิกัด ใช้ปุ่ม GPS หรือแตะตำแหน่งบนแผนที่`,'info');
  }
}

function captureGps(){
  if(!selectedHouse){setMessage('กรุณาเลือกบ้านก่อนกดจับ GPS','bad');return;}
  if(!navigator.geolocation){setMessage('อุปกรณ์นี้ไม่รองรับการระบุตำแหน่ง GPS','bad');return;}
  const btn=activeWorkspace.querySelector('[data-community-gps]');
  const old=btn.textContent;btn.disabled=true;btn.textContent='กำลังจับตำแหน่ง…';
  navigator.geolocation.getCurrentPosition(
    pos=>{btn.disabled=false;btn.textContent=old;setDraft(pos.coords.latitude,pos.coords.longitude,'gps');},
    err=>{btn.disabled=false;btn.textContent=old;const msg=err.code===1?'ไม่ได้รับอนุญาตให้ใช้ตำแหน่ง กรุณาอนุญาต Location แล้วลองใหม่':err.code===2?'ไม่พบตำแหน่ง GPS ในขณะนี้ กรุณาออกพื้นที่โล่งแล้วลองใหม่':'จับตำแหน่งไม่ทันเวลา กรุณาลองใหม่';setMessage(msg,'bad');},
    {enableHighAccuracy:true,timeout:15000,maximumAge:0}
  );
}

function openConfirm(){
  if(!selectedHouse || !draftCoordinate) return;
  const dialog=activeWorkspace.querySelector('[data-community-gis-confirm]');
  dialog.querySelector('[data-confirm-house]').textContent=`บ้าน ${selectedHouse.house_no||'ไม่ระบุ'} หมู่ ${selectedHouse.moo||'—'}`;
  dialog.querySelector('[data-confirm-coordinate]').textContent=coordText(draftCoordinate.lat,draftCoordinate.lng);
  dialog.hidden=false;
  dialog.querySelector('[data-confirm-save]').focus();
}

function closeConfirm(){
  const dialog=activeWorkspace?.querySelector('[data-community-gis-confirm]');
  if(dialog) dialog.hidden=true;
}

async function saveDraft(){
  if(!selectedHouse || !draftCoordinate) return;
  const button=activeWorkspace.querySelector('[data-confirm-save]');
  const old=button.textContent;button.disabled=true;button.textContent='กำลังบันทึก…';
  try{
    const {data,error}=await supabase.rpc('update_house_coordinates',{
      p_house_id:selectedHouse.id,
      p_latitude:draftCoordinate.lat,
      p_longitude:draftCoordinate.lng,
      p_source:draftCoordinate.source
    });
    if(error) throw error;
    selectedHouse.latitude=Number(data?.latitude ?? draftCoordinate.lat);
    selectedHouse.longitude=Number(data?.longitude ?? draftCoordinate.lng);
    selectedHouse.coordinate_source=data?.coordinate_source || draftCoordinate.source;
    selectedHouse.coordinate_status=data?.coordinate_status || selectedHouse.coordinate_status;
    selectedHouse.review_required=false;
    draftCoordinate=null;
    if(draftMarker && map){map.removeLayer(draftMarker);draftMarker=null;}
    closeConfirm();renderMarkers();updateMapMetric();updateHouseCard();
    map.setView([Number(selectedHouse.latitude),Number(selectedHouse.longitude)],18);
    setMessage(`บันทึกพิกัดบ้าน ${selectedHouse.house_no} เรียบร้อยแล้ว`,'good');
  }catch(error){
    const mapError=String(error?.message||error);
    const friendly=mapError.includes('HOUSE_OUT_OF_SCOPE')?'บัญชีนี้ไม่มีสิทธิ์แก้ไขพิกัดบ้านหลังนี้':mapError.includes('INVALID_COORDINATES')?'พิกัดอยู่นอกช่วงประเทศไทย กรุณาตรวจสอบตำแหน่ง':mapError.includes('PROFILE_NOT_ACTIVE')?'บัญชีนี้ยังไม่พร้อมใช้งาน':'บันทึกพิกัดไม่สำเร็จ กรุณาลองใหม่';
    closeConfirm();setMessage(friendly,'bad');
  }finally{button.disabled=false;button.textContent=old;}
}

async function loadMapSection(community){
  const section=activeWorkspace.querySelector('[data-community-gis-section]');
  if(!section || section.dataset.loaded==='1'){setTimeout(()=>map?.invalidateSize(),80);return;}
  setMessage('กำลังโหลดบ้านและแผนที่…','info');
  try{
    houses=(await fetchCommunityHouses(community)).sort(naturalHouseSort);
    const select=section.querySelector('[data-community-house-select]');
    select.innerHTML='<option value="">— แตะเพื่อเลือกบ้าน —</option>'+houses.map(h=>`<option value="${esc(h.id)}">บ้าน ${esc(h.house_no||'ไม่ระบุ')} · หมู่ ${esc(h.moo||'—')}${hasCoordinate(h)?' · มีพิกัด':' · ไม่มีพิกัด'}</option>`).join('');
    select.onchange=()=>select.value?selectHouse(select.value):(()=>{selectedHouse=null;resetDraft();updateHouseCard();})();
    const L=await ensureLeaflet();
    if(map){try{map.remove();}catch{}map=null;}
    map=L.map(section.querySelector('[data-community-gis-map]'),{zoomControl:true}).setView(DEFAULT_CENTER,DEFAULT_ZOOM);
    addBaseLayers(L,map);markerLayer=L.layerGroup().addTo(map);
    map.on('click',e=>{
      if(!selectedHouse){setMessage('กรุณาเลือกบ้านก่อนแตะตำแหน่งบนแผนที่','bad');return;}
      setDraft(e.latlng.lat,e.latlng.lng,'map');
    });
    renderMarkers();updateMapMetric();section.dataset.loaded='1';
    setMessage(houses.length?`พบ ${houses.length.toLocaleString('th-TH')} หลังในสิทธิ์ของคุณ เลือกบ้านเพื่อดูหรือบันทึกพิกัด`:'ไม่พบบ้านในขอบเขตสิทธิ์','info');
    setTimeout(()=>map.invalidateSize(),100);
  }catch(error){setMessage(`เปิดแผนที่ไม่สำเร็จ: ${error?.message||error}`,'bad');}
}

function buildMapSection(community){
  const section=document.createElement('section');
  section.className='community-view community-gis-view';section.dataset.communityView='map';section.dataset.communityGisSection='1';section.hidden=true;
  section.innerHTML=`
    <div class="community-gis-head"><div><h4>แผนที่บ้านในชุมชน</h4><p>เลือกบ้านก่อน แล้วดูพิกัดเดิม ใช้ GPS หรือแตะบนแผนที่เพื่อกำหนดพิกัดใหม่</p></div><strong class="community-gis-status" data-community-gis-metric>กำลังโหลด…</strong></div>
    <div class="community-gis-filter"><label>บ้านที่ต้องการดู<select data-community-house-select aria-label="เลือกบ้าน"><option>กำลังโหลดบ้าน…</option></select></label><div class="community-gis-status">ชุมชน ${esc(community)}</div></div>
    <div class="community-gis-help"><strong>วิธีใช้:</strong> 1) เลือกบ้าน 2) ตรวจจุดบนแผนที่ 3) ถ้าต้องแก้ให้กด “ใช้ตำแหน่งปัจจุบัน” หรือแตะแผนที่ 4) กด “บันทึกพิกัดนี้” และยืนยันอีกครั้ง</div>
    <div class="community-gis-map-wrap"><div class="community-gis-map" data-community-gis-map aria-label="แผนที่บ้านในชุมชน"></div></div>
    <div class="community-gis-legend"><span><i class="community-gis-dot ok"></i>ยืนยันจากพื้นที่</span><span><i class="community-gis-dot review"></i>ควรตรวจสอบ</span><span><i class="community-gis-dot other"></i>พิกัดเดิม</span></div>
    <div class="community-house-card" data-community-house-card hidden><div class="community-house-title"><strong data-house-title></strong><span class="badge" data-house-status></span></div><div class="community-house-meta" data-house-meta></div><div class="community-house-coordinate" data-house-coordinate></div><div class="community-gis-actions"><button type="button" class="community-gis-btn gps" data-community-gps>ใช้ตำแหน่งปัจจุบัน (GPS)</button><button type="button" class="community-gis-btn" data-community-reset-coordinate disabled>ยกเลิกพิกัดที่เลือกใหม่</button><a class="community-gis-link disabled" data-community-open-maps target="_blank" rel="noopener noreferrer">เปิดใน Google Maps</a><a class="community-gis-link disabled" data-community-directions target="_blank" rel="noopener noreferrer">นำทางไปบ้านหลังนี้</a><button type="button" class="community-gis-btn primary" data-community-save-coordinate disabled>บันทึกพิกัดนี้</button></div></div>
    <div class="community-gis-message info" data-community-gis-message aria-live="polite"></div>
    <div class="community-gis-confirm" data-community-gis-confirm hidden role="dialog" aria-modal="true" aria-labelledby="community-gis-confirm-title"><div class="community-gis-confirm-card"><h3 id="community-gis-confirm-title">ยืนยันบันทึกพิกัด</h3><p>กำลังบันทึก <strong data-confirm-house></strong><br>พิกัด <strong data-confirm-coordinate></strong><br>กรุณาตรวจว่าคุณอยู่ที่บ้านหลังที่เลือก หรือแตะจุดบนแผนที่ถูกต้องแล้ว</p><div class="community-gis-confirm-actions"><button type="button" class="community-gis-confirm-cancel" data-confirm-cancel>กลับไปตรวจสอบ</button><button type="button" class="community-gis-confirm-save" data-confirm-save>ยืนยันบันทึก</button></div></div></div>`;
  section.querySelector('[data-community-gps]').onclick=captureGps;
  section.querySelector('[data-community-reset-coordinate]').onclick=resetDraft;
  section.querySelector('[data-community-save-coordinate]').onclick=openConfirm;
  section.querySelector('[data-confirm-cancel]').onclick=closeConfirm;
  section.querySelector('[data-confirm-save]').onclick=saveDraft;
  section.querySelector('[data-community-gis-confirm]').onclick=e=>{if(e.target===e.currentTarget)closeConfirm();};
  return section;
}

function enhanceWorkspace(){
  const workspace=document.querySelector('#community-workspace');
  if(!workspace || workspace.hidden || workspace.dataset.communityGisReady==='1') return;
  const actions=workspace.querySelector('.community-actions');
  const heading=workspace.querySelector('.community-workspace-head h3');
  if(!actions || !heading) return;
  const community=heading.textContent.trim();
  if(!community) return;
  workspace.dataset.communityGisReady='1';activeWorkspace=workspace;houses=[];selectedHouse=null;draftCoordinate=null;
  const button=document.createElement('button');
  button.type='button';button.className='community-gis-action';button.dataset.communityGisAction='map';
  button.innerHTML='<span>⌖</span><strong>แผนที่บ้าน</strong><small>เลือกบ้าน · GPS · นำทาง</small>';
  actions.appendChild(button);
  const section=buildMapSection(community);actions.insertAdjacentElement('afterend',section);
  button.onclick=async()=>{
    activeWorkspace=workspace;
    workspace.querySelectorAll('.community-actions button').forEach(x=>x.classList.toggle('active',x===button));
    workspace.querySelectorAll('[data-community-view]').forEach(x=>x.hidden=x!==section);
    await loadMapSection(community);
    section.scrollIntoView({behavior:'smooth',block:'start'});
  };
}

function startObserver(){
  if(observer) return;
  const workspace=document.querySelector('#community-workspace');
  if(!workspace) return;
  observer=new MutationObserver(()=>{clearTimeout(enhanceTimer);enhanceTimer=setTimeout(enhanceWorkspace,20);});
  observer.observe(workspace,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});
  enhanceWorkspace();
}

export async function initCommunityGIS(supabaseUrl,publishableKey){
  if(window.__PHC_COMMUNITY_GIS_1817__) return;
  window.__PHC_COMMUNITY_GIS_1817__=true;
  injectStyles();setVersion();
  const {createClient}=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');
  supabase=createClient(supabaseUrl,publishableKey,{auth:{persistSession:true,autoRefreshToken:false,detectSessionInUrl:false}});
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',startObserver,{once:true}); else startObserver();
}
