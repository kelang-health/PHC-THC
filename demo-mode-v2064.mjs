import {getSharedSupabase,getSharedProfile,bindPortalActivation,isPortalViewActive} from './shared-runtime-v2035.mjs?v=2.0.35';
const $=(s,r=document)=>r.querySelector(s);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const groups=['เด็กปฐมวัย 0–5 ปี','เด็กวัยเรียน 6–14 ปี','วัยรุ่นและวัยผู้ใหญ่ 15–34 ปี','วัยทำงาน 35–59 ปี','ผู้สูงอายุ 60 ปีขึ้นไป'];
let client=null,profile=null,workspace=null,preview='admin',selected='',busy=false,initialized=false,epoch=0;
const host=()=>document.querySelector('[data-demo2064-host]');
const active=()=>isPortalViewActive('demo')&&profile?.role==='admin';
function style(){
  if($('#demo64-style'))return;
  const s=document.createElement('style');s.id='demo64-style';
  s.textContent='.demo64{display:grid;gap:12px;max-width:1200px;color:#1d4339}.demo64-banner{border:2px dashed #ca9a53;background:#fff6e7;padding:13px;border-radius:14px;color:#714911}.demo64-note{color:#597369}.demo64-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(110px,1fr));gap:8px}.demo64-stat,.demo64-item,.demo64-panel{border:1px solid #d3e3db;border-radius:12px;padding:11px;background:#fff}.demo64-stat{background:#f0f8f4}.demo64-stat strong{display:block;font-size:1.5rem}.demo64-two{display:grid;gap:10px}.demo64-list{display:grid;gap:8px}.demo64-item{display:grid;gap:6px}.demo64-item.selected{border:2px solid #18745f;background:#f5fbf7}.demo64-row{display:flex;align-items:center;gap:8px;flex-wrap:wrap}.demo64-btn{min-height:47px;border:2px solid #a1c7b4;border-radius:11px;background:#edf7f0;color:#195244;padding:8px 11px;font:inherit;font-weight:800;cursor:pointer}.demo64-btn.primary{background:#18745f;border-color:#18745f;color:#fff}.demo64-btn.danger{background:#fff0e9;border-color:#dba19a;color:#922f27}.demo64-btn:disabled{opacity:.5;cursor:not-allowed}.demo64 select{min-height:47px;border:1px solid #a9c0b4;border-radius:10px;padding:8px;font:inherit}.demo64-tag{font-size:.8rem;background:#fff0ce;color:#764a13;border-radius:99px;padding:4px 8px}.demo64-message{font-weight:750;min-height:1.2em}.demo64-panel{display:grid;gap:9px}.demo64-panel h3{margin:0}@media(min-width:770px){.demo64-two{grid-template-columns:minmax(0,1fr) minmax(0,1.5fr)}}';
  document.head.appendChild(s);
}
async function rpc(name,args){
  const r=await client.rpc(name,args);
  if(r.error)throw new Error(r.error.message||'Demo RPC failed');
  return r.data;
}
function status(message,bad=false){
  const out=$('[data-demo-message]',host());
  if(out){out.textContent=message||'';out.style.color=bad?'#a22e26':'#1b6650';}
}
function confirmDestructive(verb){
  return window.prompt('พิมพ์ DEMO เพื่อยืนยัน'+verb+'เฉพาะพื้นที่สาธิต ข้อมูลจริงจะไม่ถูกแก้ไข')==='DEMO';
}
async function load(){
  const current=++epoch,target=host();
  if(!target||!active())return;
  target.innerHTML='<p class="demo64-banner">กำลังเปิดพื้นที่สาธิตซึ่งแยกจากข้อมูลจริง…</p>';
  try{
    const result=await rpc('admin_demo_get_v2064');
    if(current!==epoch||!active())return;
    workspace=result;render();
  }catch(e){
    if(current!==epoch)return;
    target.innerHTML='<div class="demo64-banner">ไม่สามารถเปิดพื้นที่สาธิต: '+esc(e.message)+'</div>';
  }
}
async function apply(name,payload={},destructive=false){
  if(busy||!active())return;
  if(destructive&&!confirmDestructive(name.includes('delete')?'ลบ':'รีเซ็ต'))return;
  busy=true;
  const before=workspace;
  status('กำลังบันทึกเฉพาะข้อมูลจำลอง…');
  try{
    const result=name.startsWith('admin_demo_')
      ?await rpc(name)
      :await rpc('admin_demo_action_v2064',{p_action:name,p_payload:{...payload,preview_role:preview},p_revision:workspace.revision});
    workspace=result;render();
    status('บันทึกข้อมูลสาธิตสำเร็จ ไม่เปลี่ยนข้อมูลจริงหรือ JHCIS');
  }catch(e){
    workspace=before;render();status('ไม่สำเร็จ: '+e.message,true);
  }finally{busy=false;}
}
function render(){
  const target=host();
  if(!target||!active())return;
  if(!workspace?.exists||!workspace.scenario){
    target.innerHTML='<div class="demo64"><div class="demo64-banner"><strong>พื้นที่สาธิตถูกลบแล้ว</strong><p>ไม่มีข้อมูลสมมติในขณะนี้ ข้อมูลจริงไม่ถูกเปลี่ยน</p></div><button class="demo64-btn primary" data-reset>สร้างชุดตัวอย่าง 5 บ้าน 20 คน</button><div class="demo64-message" data-demo-message aria-live="polite"></div></div>';
    $('[data-reset]',target).onclick=()=>apply('admin_demo_reset_v2064',{},true);
    return;
  }
  const s=workspace.scenario,allHouses=s.houses||[],allPeople=s.people||[];
  const houses=allHouses.filter(h=>preview!=='user'||h.owner==='DEMO-V01');
  if(!houses.some(h=>h.id===selected))selected=houses[0]?.id||'';
  const h=houses.find(h=>h.id===selected);
  const visible=allPeople.filter(p=>houses.some(h=>h.id===p.house_id));
  const members=allPeople.filter(p=>p.house_id===selected);
  const pending=allHouses.filter(h=>h.status==='pending'&&
    (preview==='admin'||preview==='staff'||h.owner==='DEMO-V01')).length+
    visible.filter(p=>p.status==='pending').length;
  const counts=groups.map(g=>({name:g,count:visible.filter(p=>p.group===g&&p.status==='confirmed').length}));
  const stats=[
    ['บ้านที่มองเห็น',houses.length],['บุคคลสมมติ',visible.length],
    [preview==='admin'?'รอ Admin ตรวจ (ทั้งพื้นที่)':'คำขอสมมติที่รอตรวจ',pending],
    ['มีผลคัดกรองสาธิต',visible.filter(p=>Object.keys(p.screenings||{}).length>0).length]
  ];
  target.innerHTML='<div class="demo64">'+
    '<div class="demo64-banner"><strong>DEMO MODE · หมู่ 9 · ชุมชนทดสอบ · ข้อมูลสมมติ</strong>'+
    '<p>พื้นที่นี้ใช้ข้อมูลแยกต่างหาก ไม่มี CID/PID จริง ไม่ส่ง JHCIS ไม่เข้ารายงาน KPI แผนที่ Snapshot หรือการแจ้งเตือนปฏิบัติการ</p>'+
    '<small>การเลือกบทบาทด้านล่างเป็นภาพจำลอง ไม่ได้เปลี่ยนสิทธิ์ล็อกอินหรือเปิดข้อมูลจริงของ Staff/User</small></div>'+
    '<div class="demo64-row"><h2>คู่มือและพื้นที่ทดลอง</h2><label>มุมมองสาธิต <select data-role>'+
    ['admin','staff','user'].map(r=>'<option value="'+r+'" '+(r===preview?'selected':'')+'>'+esc(r==='user'?'User อสม. สาธิต 01':r==='staff'?'Staff ประธานชุมชน':'Admin')+'</option>').join('')+
    '</select></label></div>'+
    '<div class="demo64-grid">'+stats.map(v=>'<div class="demo64-stat"><small>'+esc(v[0])+'</small><strong>'+v[1]+'</strong></div>').join('')+'</div>'+
    '<section class="demo64-panel"><h3>กลุ่มวัยในมุมมองสาธิต</h3><div class="demo64-grid">'+counts.map(x=>'<div class="demo64-stat"><small>'+esc(x.name)+'</small><strong>'+x.count+'</strong></div>').join('')+'</div></section>'+
    '<div class="demo64-row"><button class="demo64-btn primary" data-add-house>+ เพิ่มบ้านสาธิต</button>'+
    '<button class="demo64-btn" data-add-person '+(h?.status!=='confirmed'?'disabled':'')+'>+ เพิ่มบุคคลสาธิต</button>'+
    '<button class="demo64-btn" data-reload>โหลดข้อมูลสาธิตใหม่</button></div>'+
    '<div class="demo64-two"><section class="demo64-panel"><h3>บ้านสาธิต</h3><div class="demo64-list">'+
    houses.map(item=>'<article class="demo64-item '+(item.id===selected?'selected':'')+'"><strong>'+esc(item.house_no)+'</strong>'+
      '<small>'+esc(item.owner==='DEMO-V01'?'อสม. สาธิต 01':'อสม. สาธิต 02')+
      ' · '+allPeople.filter(p=>p.house_id===item.id).length+' คน'+(item.status==='pending'?' · รอ Admin ตรวจ':'')+'</small>'+
      '<div class="demo64-row"><button class="demo64-btn" data-open-house="'+esc(item.id)+'">เปิดบ้าน</button>'+
      (item.status==='pending'&&preview==='admin'?'<button class="demo64-btn primary" data-approve-house="'+esc(item.id)+'">อนุมัติ (สาธิต)</button>':'')+
      '</div></article>').join('')+'</div></section>'+
    '<section class="demo64-panel"><h3>สมาชิกของ '+esc(h?.house_no||'บ้านสาธิต')+'</h3><p class="demo64-note">กลุ่มดูแลพิเศษเป็นตัวอย่างซ้อนในกลุ่มวัย ไม่มีประวัติสุขภาพจริง</p><div class="demo64-list">'+
    (members.map(p=>'<article class="demo64-item"><strong>'+esc(p.display_name)+'</strong>'+
      '<small>อายุสมมติ '+Number(p.age_years)+' ปี · '+esc(p.group)+(p.status==='pending'?' · รอ Admin ตรวจ':'')+'</small>'+
      (p.special?'<span class="demo64-tag">'+esc(p.special)+' (สมมติ)</span>':'')+
      '<small>'+Object.entries(p.screenings||{}).map(([k,v])=>esc(k)+': '+esc(v)).join(' · ')+'</small>'+
      '<div class="demo64-row">'+
      (p.status==='pending'&&preview==='admin'?'<button class="demo64-btn primary" data-approve-person="'+esc(p.id)+'">อนุมัติ (สาธิต)</button>':'')+
      (p.status==='confirmed'?'<button class="demo64-btn" data-screen="'+esc(p.id)+'">ทดลองคัดกรอง</button>':'')+
      '</div></article>').join('')||'<p>ยังไม่มีสมาชิกสาธิต</p>')+'</div></section></div>'+
    '<section class="demo64-panel"><h3>ประวัติการทดลองล่าสุด</h3>'+
    ((s.events||[]).slice(-6).reverse().map(e=>'<small>'+esc(e.at)+' · '+esc(e.preview_role)+' · '+esc(e.action)+' · '+esc(e.id)+'</small>').join('')||'<p class="demo64-note">ยังไม่มีการทดลองเพิ่มเติม</p>')+'</section>'+
    '<section class="demo64-panel"><h3>ลำดับฝึกใช้งานและทำคู่มือ</h3><p class="demo64-note">1. เลือกมุมมอง User แล้วเพิ่มบ้านหรือสมาชิกสมมติ · 2. เปลี่ยนเป็น Admin แล้วอนุมัติในบ้าน/สมาชิก · 3. เลือกคนให้ตรงกลุ่มวัยแล้วทดลองคัดกรอง · 4. จับภาพคู่มือ · 5. รีเซ็ตข้อมูลสาธิต</p></section>'+
    (preview==='admin'?'<section class="demo64-panel"><h3>จัดการพื้นที่สาธิต (Admin)</h3>'+
    '<p class="demo64-note">รีเซ็ตคืนตัวอย่าง 5 บ้าน/20 คน หรือลบพื้นที่สาธิตทั้งหมดได้โดยไม่กระทบฐานข้อมูลจริง</p>'+
    '<div class="demo64-row"><button class="demo64-btn" data-reset>รีเซ็ตข้อมูลสาธิต</button><button class="demo64-btn danger" data-delete>ลบพื้นที่สาธิต</button></div></section>':'')+
    '<div class="demo64-message" data-demo-message aria-live="polite"></div></div>';
  $('[data-role]',target).onchange=e=>{preview=e.target.value;render();};
  target.querySelectorAll('[data-open-house]').forEach(b=>b.onclick=()=>{selected=b.dataset.openHouse;render();});
  $('[data-add-house]',target).onclick=()=>apply('add_house');
  $('[data-add-person]',target).onclick=()=>{
    const raw=window.prompt('อายุบุคคลสมมติ 0–120 ปี (ไม่ใช้ข้อมูลบุคคลจริง)','38');
    if(raw===null)return;
    const age=Number(raw);
    if(!/^\d{1,3}$/.test(raw.trim())||!Number.isInteger(age)||age>120){status('กรอกอายุสมมติ 0–120 ปี',true);return;}
    apply('add_person',{house_id:selected,age_years:age});
  };
  $('[data-reload]',target).onclick=load;
  if(preview==='admin'){
    $('[data-reset]',target).onclick=()=>apply('admin_demo_reset_v2064',{},true);
    $('[data-delete]',target).onclick=()=>apply('admin_demo_delete_v2064',{},true);
  }
  target.querySelectorAll('[data-approve-house]').forEach(b=>b.onclick=()=>apply('approve_house',{house_id:b.dataset.approveHouse}));
  target.querySelectorAll('[data-approve-person]').forEach(b=>b.onclick=()=>apply('approve_person',{person_id:b.dataset.approvePerson}));
  target.querySelectorAll('[data-screen]').forEach(b=>b.onclick=()=>{
    const p=allPeople.find(p=>p.id===b.dataset.screen);if(!p)return;
    const age=p.age_years,allowed=[];
    if(age>=35)allowed.push('ncd');if(age<=5)allowed.push('dspm');
    if(age>=6&&age<=14)allowed.push('school');if(age>=60)allowed.push('older');
    const kind=window.prompt('ชนิดคัดกรองสาธิต: '+allowed.join(', ')+' (ncd / dspm / school / older)',allowed[0]||'');
    if(kind===null)return;
    if(!allowed.includes(kind)){status('ชนิดการคัดกรองไม่ตรงช่วงวัยสมมติ',true);return;}
    const choice=window.prompt('ผลการสาธิต: พิมพ์ 1 = ผ่านการสาธิต หรือ 2 = ต้องติดตาม (สาธิต) · กดยกเลิกเพื่อไม่บันทึก','1');
    if(choice===null)return;
    if(!['1','2'].includes(choice.trim())){status('กรุณาเลือกผลการสาธิต 1 หรือ 2',true);return;}
    const result=choice.trim()==='1'?'ผ่านการสาธิต':'ต้องติดตาม (สาธิต)';
    apply('screen',{person_id:p.id,kind,result});
  });
}
export async function initDemoModeV2064(url,key){
  if(initialized)return;initialized=true;style();
  client=await getSharedSupabase(url,key);
  bindPortalActivation('demo',async()=>{
    profile=await getSharedProfile(client,{force:true});
    if(profile?.role!=='admin'){if(host())host().textContent='เปิด Demo Mode ได้เฉพาะ Admin';workspace=null;return;}
    await load();
  });
  document.addEventListener('phc:portal-view-changed',e=>{if(e.detail?.previous==='demo'){workspace=null;epoch++;}});
}
