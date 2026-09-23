/* Loaded only after a logged-in user opens a published, booking-enabled event. */
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;','\'':'&#39;'}[c]));
const fmt=v=>{try{return new Date(v).toLocaleString('th-TH',{timeZone:'Asia/Bangkok',dateStyle:'medium',timeStyle:'short'});}catch{return String(v||'');}};
const validId=v=>/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(String(v||''));
export async function openEventBookingV2085({client,event,body,back}){
 if(!client||!event||!validId(event.id)||!body)return;
 let rounds=[],chosen=null,currentBooking=null,request=0,searchTimer=null;
 const alive=()=>body.isConnected;
 const note='การจองไม่ใช่การได้รับวัคซีน หากต้องการตรวจสอบสิทธิ์ทางคลินิกให้เจ้าหน้าที่ตรวจสอบตามเกณฑ์กิจกรรม';
 body.innerHTML=`<div class="cb85"><button type="button" class="cb85-back">← กลับรายละเอียด</button>
 <h3>${esc(event.title)} · จองกิจกรรม</h3><p class="cb85-muted">${note}</p>
 <div class="cb85-warning" data-cb85-status role="status">กำลังตรวจรอบบริการ…</div>
 <label class="cb85-field">ค้นหาชื่อบุคคลในบ้านหรือชุมชนที่ท่านมีสิทธิ์ดูแล
 <input type="search" data-cb85-query minlength="2" maxlength="70" placeholder="พิมพ์ชื่ออย่างน้อย 2 ตัวอักษร" autocomplete="off"></label>
 <div data-cb85-people class="cb85-people" aria-live="polite"></div>
 <div class="cb85-picked" data-cb85-picked hidden></div>
 <div data-cb85-existing role="status"></div>
 <label class="cb85-field">เลือกรอบบริการ<select data-cb85-slot><option value="">กำลังโหลด…</option></select></label>
 <button type="button" data-cb85-book class="cb85-submit" disabled>ยืนยันการจอง</button>
 <p class="cb85-muted">ระบบตรวจจำนวนที่ว่างและป้องกันการจองซ้ำที่ฝั่งเซิร์ฟเวอร์ทุกครั้งก่อนยืนยัน</p></div>`;
 const $=s=>body.querySelector(s);
 $('.cb85-back').onclick=back;
 const status=$('[data-cb85-status]'),people=$('[data-cb85-people]'),select=$('[data-cb85-slot]'),book=$('[data-cb85-book]');
 const bookingOpen=()=>event.booking_enabled&&(!event.booking_opens_at||Date.parse(event.booking_opens_at)<=Date.now())&&(!event.booking_closes_at||Date.parse(event.booking_closes_at)>Date.now());
 const setStatus=s=>{if(alive())status.textContent=s;};
 async function loadRounds(){
   try{
     const {data,error}=await client.rpc('health_event_slots_v2085',{p_event:event.id});if(error)throw error;if(!alive())return;
     rounds=Array.isArray(data)?data:[];
     select.innerHTML='<option value="">เลือกรอบบริการ</option>'+rounds.map(s=>{
       const open=s.status==='open'&&Date.parse(s.starts_at)>Date.now()&&s.remaining>0&&bookingOpen();
       return `<option value="${esc(s.id)}" ${open?'':'disabled'}>${esc(fmt(s.starts_at))} · ${esc(s.location)} · ว่าง ${Number(s.remaining)||0} / ${Number(s.capacity)||0}${open?'':' (ปิด/เต็ม)'}</option>`;
     }).join('');
     setStatus(bookingOpen()?'เลือกบุคคลและรอบบริการเพื่อจอง':'กิจกรรมยังไม่เปิดรับจอง หรือปิดรับจองแล้ว');
     refreshBook();
   }catch{setStatus('ไม่สามารถโหลดรอบบริการได้ กรุณาเปิดกิจกรรมใหม่อีกครั้ง');select.innerHTML='<option value="">ไม่มีข้อมูลรอบบริการ</option>';}
 }
 const refreshBook=()=>{book.disabled=!chosen||!select.value||!!currentBooking||!bookingOpen();};
 select.onchange=refreshBook;
 async function showPerson(p){
   chosen=p;currentBooking=null;
   $('[data-cb85-picked]').hidden=false;
   $('[data-cb85-picked]').textContent=`เลือก: ${p.display_name} · บ้าน ${p.house_no||'ไม่ระบุ'} · ${p.community||''}`;
   people.replaceChildren();$('[data-cb85-existing]').textContent='กำลังตรวจประวัติการจอง…';refreshBook();
   try{
     const {data,error}=await client.from('cloud_event_bookings_v2085')
       .select('id,status,slot_id,created_at').eq('announcement_id',event.id)
       .eq('source_pcucode',p.source_pcucode).eq('source_pid',p.source_pid)
       .eq('status','booked').maybeSingle();
     if(error)throw error;if(!alive()||chosen!==p)return;
     currentBooking=data||null;const host=$('[data-cb85-existing]');host.replaceChildren();
     if(data){
       const box=document.createElement('div');box.className='cb85-confirmed';
       const slot=rounds.find(r=>r.id===data.slot_id);
       box.textContent=`จองแล้ว · ${slot?fmt(slot.starts_at)+' · '+slot.location:''} · เลขอ้างอิง ${data.id.slice(0,8).toUpperCase()}`;
       const cancel=document.createElement('button');cancel.type='button';cancel.textContent='ยกเลิกการจอง';cancel.className='cb85-cancel';
       cancel.onclick=async()=>{
         if(!confirm('ยืนยันยกเลิกการจองนี้?'))return;cancel.disabled=true;
         const {data:out,error:err}=await client.rpc('cancel_health_event_booking_v2085',{p_booking:data.id});
         if(err||!['cancelled','already_cancelled'].includes(out?.status)){cancel.disabled=false;setStatus('ยกเลิกไม่สำเร็จ กรุณาลองอีกครั้ง');return;}
         if(!alive())return;currentBooking=null;host.replaceChildren();await loadRounds();setStatus('ยกเลิกการจองแล้ว');
       };
       box.appendChild(cancel);host.appendChild(box);
     }else host.textContent='ยังไม่มีการจองกิจกรรมนี้สำหรับบุคคลที่เลือก';
     refreshBook();
   }catch{if(alive()){$('[data-cb85-existing]').textContent='ตรวจประวัติการจองไม่สำเร็จ';book.disabled=true;}}
 }
 $('[data-cb85-query]').oninput=e=>{
   clearTimeout(searchTimer);const q=e.target.value.trim();chosen=null;currentBooking=null;
   $('[data-cb85-picked]').hidden=true;$('[data-cb85-existing]').textContent='';refreshBook();
   const serial=++request;people.textContent=q.length<2?'พิมพ์ชื่ออย่างน้อย 2 ตัวอักษร':'กำลังค้นหารายชื่อ…';
   if(q.length<2)return;
   searchTimer=setTimeout(async()=>{
     try{
       const {data,error}=await client.rpc('search_event_people_v2085',{p_query:q,p_limit:20});if(error)throw error;
       if(serial!==request||!alive())return;people.replaceChildren();
       if(!data?.length){people.textContent='ไม่พบชื่อบุคคลในขอบเขตสิทธิ์ที่ดูแล';return;}
       for(const p of data){
         const button=document.createElement('button');button.type='button';button.className='cb85-person';
         button.textContent=`${p.display_name} · บ้าน ${p.house_no||'—'} · ${p.community||''}`;
         button.onclick=()=>showPerson(p);people.appendChild(button);
       }
     }catch{if(serial===request&&alive())people.textContent='ค้นหารายชื่อไม่สำเร็จ กรุณาลองใหม่';}
   },300);
 };
 book.onclick=async()=>{
   if(!chosen||!validId(select.value)||!bookingOpen()||currentBooking)return;
   if(!confirm(`ยืนยันจอง ${chosen.display_name} ในรอบที่เลือก? การจองนี้ยังไม่ใช่การได้รับบริการ`))return;
   book.disabled=true;setStatus('กำลังตรวจสิทธิ์ จำนวนที่ว่าง และบันทึกการจอง…');
   try{
     const {data,error}=await client.rpc('book_health_event_v2085',
       {p_slot:select.value,p_pcucode:chosen.source_pcucode,p_pid:chosen.source_pid});
     if(error)throw error;if(!alive())return;
     if(!['booked','already_booked'].includes(data?.status)){setStatus('Cloud ยังไม่ยืนยันการจอง กรุณาตรวจสอบอีกครั้ง');return;}
     currentBooking={id:data.booking_id,slot_id:select.value};
     await loadRounds();await showPerson(chosen);
     setStatus(data.status==='booked'?'จองสำเร็จแล้ว':'บุคคลนี้จองกิจกรรมนี้ไว้แล้ว');
   }catch(e){if(alive()){await loadRounds();setStatus('จองไม่สำเร็จ: '+String(e?.message||'กรุณาลองใหม่').slice(0,180));}}
 };
 await loadRounds();
}
