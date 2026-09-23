/* H4: lazily loaded HCV/HBsAg three-step mobile booking; no public phone exposure. */
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const uuid=v=>/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(v||''));
const phone=v=>/^0[0-9]{8,9}$/.test(v);
const fmt=v=>{try{return new Date(v).toLocaleString('th-TH',{timeZone:'Asia/Bangkok',dateStyle:'medium',timeStyle:'short'});}catch{return 'ไม่ระบุ';}};
const born=v=>{try{return v?new Date(v+'T00:00:00Z').toLocaleDateString('th-TH',{timeZone:'UTC',dateStyle:'medium'}):'ไม่ระบุวันเกิด';}catch{return 'ไม่ระบุวันเกิด';}};
export async function openHcvBookingV2088({client,event,body,back}){
 if(!client||!body||!uuid(event?.id)||event?.kind!=='event'||event?.event_subtype!=='hcv_hbsag')return;
 let step=1,person=null,prior=null,checked=false,slots=[],slotId='',hcv=!!event.hcv_enabled,hb=!!event.hbsag_enabled,contact='',saving=false,receipt=null,searchTimer=null,searchSeq=0,personSeq=0;
 const $=q=>body.querySelector(q),alive=()=>body.isConnected;
 const open=()=>!!event.booking_enabled&&(!event.booking_opens_at||Date.parse(event.booking_opens_at)<=Date.now())&&(!event.booking_closes_at||Date.parse(event.booking_closes_at)>Date.now());
 const tests=()=>[hcv?'Anti-HCV':'',hb?'HBsAg':''].filter(Boolean).join(' + ');
 const announce=s=>{if(alive()&&$('[data-h88-status]'))$('[data-h88-status]').textContent=s;};
 const rpc=async(name,args)=>{const {data,error}=await client.rpc(name,args);if(error)throw error;return data;};
 const activeSlot=()=>slots.find(s=>s.id===slotId);
 const slotAvailable=()=>{const s=activeSlot();return !!s&&s.status==='open'&&Number(s.remaining)>0&&Date.parse(s.starts_at)>Date.now();};
 const bookingButton=()=>{const b=$('[data-h88-book]');if(b)b.disabled=saving||!slotAvailable()||!!prior||!open();};
 body.innerHTML=`<section class="h88"><button type="button" data-h88-back class="h88-back">← กลับรายละเอียดกิจกรรม</button>
 <h3>${esc(event.title)} · จองตรวจไวรัสตับอักเสบ</h3>
 <div class="h88-steps"><span data-h88-step="1">1 เลือกคน</span><span data-h88-step="2">2 รายการตรวจ</span><span data-h88-step="3">3 ยืนยันนัด</span></div>
 <p class="h88-muted">อสม. เป็นผู้จองให้บุคคลที่รับผิดชอบ · การจองยังไม่ใช่การได้รับบริการหรือยืนยันสิทธิ์ตรวจฟรี</p>
 <div role="status" aria-live="polite" data-h88-status></div><div data-h88-content></div></section>`;
 $('[data-h88-back]').onclick=()=>{++searchSeq;clearTimeout(searchTimer);back();};
 function render(){
  if(!alive())return;
  body.querySelectorAll('[data-h88-step]').forEach(e=>e.classList.toggle('current',+e.dataset.h88Step===step));
  const host=$('[data-h88-content]');
  if(receipt){showReceipt();return;}
  if(step===1){
    host.innerHTML=`<h4>ขั้นตอน 1 · เลือกผู้รับบริการ</h4><p class="h88-muted">ค้นหาเฉพาะบุคคลในบ้านที่รับผิดชอบ ไม่ต้องกรอกชื่อ วันเกิด หรือบ้านซ้ำ</p>
     <label class="h88-field">ค้นหาชื่อ<input data-h88-search type="search" maxlength="70" autocomplete="off" placeholder="พิมพ์ชื่ออย่างน้อย 2 ตัวอักษร"></label>
     <div data-h88-list class="h88-people" aria-live="polite"></div><div data-h88-person></div>
     <button type="button" data-h88-next disabled>ถัดไป: เลือกรายการตรวจ</button>`;
    $('[data-h88-next]').onclick=()=>{if(person&&checked&&!prior&&open()){step=2;announce('');render();}};
    $('[data-h88-search]').oninput=e=>{
      const q=e.target.value.trim(),seq=++searchSeq;++personSeq;clearTimeout(searchTimer);
      person=null;prior=null;checked=false;slotId='';$('[data-h88-person]').replaceChildren();$('[data-h88-next]').disabled=true;
      const list=$('[data-h88-list]');list.textContent=q.length<2?'พิมพ์ชื่ออย่างน้อย 2 ตัวอักษร':'กำลังค้นหา…';
      if(q.length<2)return;
      searchTimer=setTimeout(async()=>{try{
       const rows=await rpc('search_hcv_event_people_v2087',{p_event:event.id,p_query:q,p_limit:20});
       if(!alive()||step!==1||seq!==searchSeq)return;list.replaceChildren();
       if(!rows?.length){list.textContent='ไม่พบชื่อในขอบเขตที่รับผิดชอบ';return;}
       rows.forEach(p=>{const b=document.createElement('button');b.type='button';b.className='h88-person';
         b.textContent=`${p.display_name} · ${born(p.birth_date)} · บ้าน ${p.house_no||'—'}`;b.onclick=()=>choose(p);list.appendChild(b);});
      }catch{if(alive()&&seq===searchSeq)list.textContent='ค้นหารายชื่อไม่สำเร็จ กรุณาลองใหม่';}},300);
    };return;
  }
  if(step===2){
    host.innerHTML=`<h4>ขั้นตอน 2 · รายการตรวจและเบอร์ติดต่อ</h4>
    <div class="h88-selected">${esc(person.display_name)} · ${esc(born(person.birth_date))} · บ้าน ${esc(person.house_no||'—')}</div>
    <label class="h88-check"><input data-h88-hcv type="checkbox" ${hcv?'checked':''} ${event.hcv_enabled?'':'disabled'}> Anti-HCV — คัดกรองไวรัสตับอักเสบซี</label>
    <label class="h88-check"><input data-h88-hb type="checkbox" ${hb?'checked':''} ${event.hbsag_enabled?'':'disabled'}> HBsAg — คัดกรองไวรัสตับอักเสบบี</label>
    <p class="h88-muted">เลือกทั้งสองรายการได้ในการจองเดียว ใช้จำนวนที่ว่าง 1 ที่</p>
    <label class="h88-field">เบอร์โทรสำหรับติดต่อเรื่องนัดหมาย<input data-h88-phone type="tel" inputmode="numeric" autocomplete="off" maxlength="10" placeholder="0XXXXXXXXX" value="${esc(contact)}"></label>
    <p class="h88-muted">ใช้เบอร์ผู้รับบริการหรือผู้ประสานงานได้ ไม่ใช้ OTP และไม่แก้ทะเบียนประชากร</p>
    <div class="h88-actions"><button type="button" class="h88-light" data-h88-prev>ย้อนกลับ</button><button type="button" data-h88-next>ถัดไป: เลือกรอบนัด</button></div>`;
    $('[data-h88-prev]').onclick=()=>{step=1;render();announce('กรุณาเลือกบุคคลอีกครั้งเพื่อตรวจการจองเดิม');};
    const update=()=>{hcv=$('[data-h88-hcv]').checked;hb=$('[data-h88-hb]').checked;contact=$('[data-h88-phone]').value.trim();$('[data-h88-next]').disabled=!(hcv||hb)||!phone(contact)||!open();};
    ['[data-h88-hcv]','[data-h88-hb]','[data-h88-phone]'].forEach(s=>$(s).addEventListener('input',update));
    $('[data-h88-next]').onclick=async()=>{update();if($('[data-h88-next]').disabled)return;step=3;render();announce('กำลังโหลดรอบบริการ…');await loadSlots();};update();return;
  }
  host.innerHTML=`<h4>ขั้นตอน 3 · ตรวจสอบและยืนยันนัด</h4>
    <div class="h88-selected"><strong>${esc(person.display_name)}</strong><br>${esc(born(person.birth_date))} · บ้าน ${esc(person.house_no||'—')}<br>
    รายการตรวจ: ${esc(tests())}<br>เบอร์ติดต่อ: ${esc(contact)}<br>ผู้จอง: บัญชี อสม. ที่เข้าสู่ระบบ</div>
    <label class="h88-field">เลือกรอบบริการ<select data-h88-slot><option value="">กำลังโหลดรอบ…</option></select></label>
    <p class="h88-muted">เจ้าหน้าที่ต้องตรวจสอบประวัติและสิทธิ์อีกครั้งก่อนให้บริการจริง</p>
    <div class="h88-actions"><button class="h88-light" data-h88-prev type="button">ย้อนกลับ</button><button data-h88-book type="button" disabled>ยืนยันการจอง</button></div>`;
  $('[data-h88-prev]').onclick=()=>{if(!saving){step=2;render();announce('');}};
  $('[data-h88-slot]').onchange=()=>{slotId=$('[data-h88-slot]').value;bookingButton();};
  $('[data-h88-book]').onclick=submit;if(slots.length)renderSlots();
 }
 async function choose(p){
   const seq=++personSeq;person=p;prior=null;checked=false;slotId='';
   $('[data-h88-list]').replaceChildren();const info=$('[data-h88-person]');
   info.textContent=`เลือก: ${p.display_name} · ${born(p.birth_date)} · บ้าน ${p.house_no||'—'}`;
   announce('กำลังตรวจรายการจองเดิม…');
   try{const x=await rpc('get_hcv_hbsag_booking_v2087',{p_event:event.id,p_pcucode:p.source_pcucode,p_pid:p.source_pid});
     if(!alive()||step!==1||seq!==personSeq||person!==p)return;checked=true;
     prior=['booked','already_booked'].includes(x?.status)?x:null;
     if(prior){announce(x.status==='already_booked'?'บุคคลนี้มีการจองแล้วโดยผู้ทำรายการอื่น':'บุคคลนี้จองกิจกรรมนี้แล้ว');
       if(x.status==='booked'&&uuid(x.booking_id))showExisting(info,x);
     }else{announce('ยังไม่มีการจองที่ใช้งานอยู่');$('[data-h88-next]').disabled=!open();}
   }catch{if(alive()&&seq===personSeq)announce('ตรวจรายการจองไม่สำเร็จ กรุณาเลือกบุคคลอีกครั้ง');}
 }
 function showExisting(info,x){
   const el=document.createElement('div');el.className='h88-existing';
   el.textContent=`จองแล้ว · ${[x.hcv_selected?'Anti-HCV':'',x.hbsag_selected?'HBsAg':''].filter(Boolean).join(' + ')} · เลขอ้างอิง ${x.booking_id.slice(0,8).toUpperCase()}`;
   const button=document.createElement('button');button.className='h88-light';button.type='button';button.textContent='ยกเลิกการจอง';
   button.onclick=async()=>{if(!confirm('ยืนยันยกเลิกการจองนี้?'))return;button.disabled=true;announce('กำลังยกเลิก…');
     try{const result=await rpc('cancel_hcv_hbsag_booking_v2087',{p_booking:x.booking_id});
       if(!['cancelled','already_cancelled'].includes(result?.status))throw Error('not confirmed');
       if(!alive())return;step=1;person=null;prior=null;checked=false;slotId='';render();announce('ยกเลิกการจองแล้ว');
     }catch{if(alive()){button.disabled=false;announce('ยกเลิกไม่สำเร็จ กรุณาลองใหม่');}}
   };el.appendChild(button);info.appendChild(el);
 }
 function renderSlots(){
   const el=$('[data-h88-slot]');if(!el)return;
   el.innerHTML='<option value="">เลือกรอบบริการ</option>'+slots.map(s=>{
     const ok=s.status==='open'&&Number(s.remaining)>0&&Date.parse(s.starts_at)>Date.now()&&open();
     return `<option value="${esc(s.id)}" ${ok?'':'disabled'}>${esc(fmt(s.starts_at))} · ${esc(s.location)} · ว่าง ${Number(s.remaining)||0} / ${Number(s.capacity)||0}${ok?'':' (ปิด/เต็ม)'}</option>`;
   }).join('');
   const active=slots.find(s=>s.id===slotId);if(!active||active.status!=='open'||Number(active.remaining)<1||Date.parse(active.starts_at)<=Date.now())slotId='';
   if(slotId)el.value=slotId;bookingButton();
 }
 async function loadSlots(){
  try{const data=await rpc('health_event_slots_v2085',{p_event:event.id});if(!alive()||step!==3)return;
    slots=Array.isArray(data)?data:[];renderSlots();announce(open()?'เลือกรอบบริการที่ยังมีที่ว่าง':'กิจกรรมยังไม่เปิดรับจองหรือปิดรับจองแล้ว');
  }catch{if(alive()&&step===3){announce('โหลดรอบบริการไม่สำเร็จ กรุณาย้อนกลับและลองใหม่');$('[data-h88-slot]').innerHTML='<option value="">ไม่พบรอบบริการ</option>';bookingButton();}}
 }
 async function submit(){
   if(saving||!person||!checked||prior||!slotId||!(hcv||hb)||!phone(contact)||!open())return;
   const s=slots.find(s=>s.id===slotId);if(!s||s.status!=='open'||Number(s.remaining)<1||Date.parse(s.starts_at)<=Date.now())return;
   if(!confirm(`ยืนยันจอง ${person.display_name} · ${tests()} · ${fmt(s.starts_at)}? การจองยังไม่ใช่การได้รับบริการ`))return;
   saving=true;bookingButton();announce('กำลังตรวจสิทธิ์ การจองซ้ำ และจำนวนที่ว่าง…');
   try{const x=await rpc('book_hcv_hbsag_event_v2087',{p_slot:slotId,p_pcucode:person.source_pcucode,p_pid:person.source_pid,p_hcv:hcv,p_hbsag:hb,p_contact_phone:contact});
     if(!alive()||step!==3)return;
     if(x?.status==='already_booked'){prior={status:'already_booked'};announce('บุคคลนี้มีการจองแล้ว โปรดตรวจสอบรายการจอง');return;}
     if(x?.status!=='booked'||!uuid(x.booking_id))throw Error('not confirmed');
     receipt={id:x.booking_id,name:person.display_name,tests:tests(),time:s.starts_at,location:s.location};
     contact='';showReceipt();announce('Cloud ยืนยันการจองแล้ว · รอเจ้าหน้าที่ตรวจสอบสิทธิ์');
   }catch(e){if(alive()&&step===3){const msg=String(e?.message||'');await loadSlots();announce(/เต็ม|ซ้ำ|สิทธิ์|ปิดรับจอง|รอบนี้/.test(msg)?msg.slice(0,120):'จองไม่สำเร็จ กรุณาลองใหม่');}}
   finally{saving=false;bookingButton();}
 }
 function showReceipt(){
   if(!receipt||!alive())return;
   $('[data-h88-content]').innerHTML=`<div class="h88-success"><h4>จองสำเร็จ · รอตรวจสอบสิทธิ์</h4>
    <p>เลขอ้างอิง ${esc(receipt.id.slice(0,8).toUpperCase())}</p>
    <p>${esc(receipt.name)} · ${esc(receipt.tests)}</p>
    <p>${esc(fmt(receipt.time))} · ${esc(receipt.location)}</p>
    <p>เจ้าหน้าที่จะติดต่อเพื่อยืนยันนัดเมื่อจำเป็น · การจองไม่ใช่การได้รับบริการจริง</p></div>
    <button type="button" data-h88-done>กลับไปยังรายละเอียดกิจกรรม</button>`;
   $('[data-h88-done]').onclick=back;
 }
 if(!open()){announce('กิจกรรมยังไม่เปิดรับจองหรือปิดรับจองแล้ว');return;}
 render();announce('ค้นหาและเลือกบุคคลในบ้านที่รับผิดชอบ');
}
