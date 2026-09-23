/* H6.5: scoped real-household test data; isolated TEST bookings only. */
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export async function openHcvDemoRealV2094({client,event,body,back}){
 if(!client||!body?.isConnected||event?.is_demo!==true||event.demo_real_data_enabled!==true||
    event.booking_enabled!==false||event.event_subtype!=='hcv_hbsag')return;
 let step=1,person=null,hcv=!!event.hcv_enabled,hb=!!event.hbsag_enabled,slot='',slots=[],saving=false,searchSeq=0,timer=null,receipt=null;
 const get=q=>body.querySelector(q),alive=()=>body.isConnected;
 const label='🧪 ทดสอบด้วยข้อมูลบ้านจริง · ไม่มีนัดตรวจจริง';
 const warning='ใช้รายชื่อจริงเฉพาะบ้านในความรับผิดชอบ แต่รายการจองและสถานะเป็นข้อมูลทดสอบแยกจากงานบริการจริง ไม่ส่งข้อมูลไป JHCIS ไม่มีการเก็บเบอร์โทร และ Admin รีเซ็ตข้อมูลทดสอบทั้งหมดได้';
 const rpc=async(name,args)=>{const {data,error}=await client.rpc(name,args);if(error)throw error;return data;};
 const status=t=>{const el=get('[data-h94-status]');if(el)el.textContent=t||'';};
 const begin=()=>'<section class="h94"><h3>'+label+'</h3><p class="cn83-demo-label">'+warning+'</p><p>ขั้นตอน '+step+'/3</p><p role="status" data-h94-status></p><div data-h94-content></div><button type="button" class="h94-exit" data-h94-exit>กลับรายละเอียดกิจกรรม</button></section>';
 function shell(){body.innerHTML=begin();get('[data-h94-exit]').onclick=()=>{++searchSeq;clearTimeout(timer);back();};}
 function draw(){
  if(!alive())return;shell();const host=get('[data-h94-content]');
  if(receipt){host.innerHTML='<div class="h94-panel"><h4>✅ บันทึกการจองทดสอบแล้ว</h4><p>รายการนี้ไม่ใช่นัดตรวจจริงและไม่ถือว่าได้รับบริการ</p><p>'+esc(receipt.person)+' · '+esc(receipt.slot)+' · '+esc(receipt.tests)+'</p><p>เจ้าหน้าที่สามารถตรวจสอบรายการนี้ในรายงานทดสอบของ Local ก่อนกดรีเซ็ตได้</p></div><button type="button" data-h94-mine>ดูรายการทดสอบของฉัน</button>';get('[data-h94-mine]').onclick=()=>{receipt=null;step=1;draw();mine();};return;}
  if(step===1){
   host.innerHTML='<div class="h94-panel"><h4>1. เลือกบุคคลจริงในบ้านที่รับผิดชอบ</h4><label>ค้นหาชื่ออย่างน้อย 2 ตัวอักษร<input type="search" maxlength="70" autocomplete="off" data-h94-search placeholder="ค้นหารายชื่อในบ้านของฉัน"></label><div data-h94-results></div><div data-h94-picked></div><button type="button" data-h94-next disabled>ถัดไป: เลือกรายการตรวจ</button><button type="button" data-h94-mine>ดูรายการทดสอบของฉัน</button></div>';
   get('[data-h94-mine]').onclick=mine;
   get('[data-h94-next]').onclick=()=>{if(person){step=2;draw();}};
   get('[data-h94-search]').oninput=e=>{
    person=null;get('[data-h94-next]').disabled=true;get('[data-h94-picked]').textContent='';
    const q=e.target.value.trim(),seq=++searchSeq;clearTimeout(timer);const results=get('[data-h94-results]');
    results.textContent=q.length<2?'กรุณาพิมพ์อย่างน้อย 2 ตัวอักษร':'กำลังค้นหาบ้านที่รับผิดชอบ…';
    if(q.length<2)return;
    timer=setTimeout(async()=>{try{
      const rows=await rpc('search_hcv_event_people_v2087',{p_event:event.id,p_query:q,p_limit:20});
      if(!alive()||step!==1||seq!==searchSeq)return;
      results.replaceChildren();
      if(!Array.isArray(rows)||!rows.length){results.textContent='ไม่พบรายชื่อในขอบเขตที่รับผิดชอบ';return;}
      rows.forEach(p=>{const btn=document.createElement('button');btn.type='button';btn.className='h94-person';
        btn.textContent=p.display_name+' · บ้าน '+(p.house_no||'—');
        btn.onclick=async()=>{const selected=++searchSeq;clearTimeout(timer);person=null;
          get('[data-h94-next]').disabled=true;results.replaceChildren();
          get('[data-h94-picked]').textContent='กำลังตรวจรายการทดสอบเดิม…';
          try{const mineRows=await rpc('list_my_hcv_demo_v2094',{p_event:event.id});
            if(!alive()||step!==1||selected!==searchSeq)return;
            const previous=(mineRows||[]).find(x=>x.source_pcucode===p.source_pcucode&&Number(x.source_pid)===Number(p.source_pid));
            if(previous){get('[data-h94-picked]').textContent='บุคคลนี้มีการจองทดสอบแล้ว กรุณาดูรายการของฉัน';return;}
            person=p;get('[data-h94-picked]').textContent='เลือก: '+p.display_name+' · บ้าน '+(p.house_no||'—');
            get('[data-h94-next]').disabled=false;
          }catch{if(alive())get('[data-h94-picked]').textContent='ตรวจรายการเดิมไม่สำเร็จ กรุณาลองอีกครั้ง';}
        };results.appendChild(btn);});
    }catch{if(alive()&&seq===searchSeq)results.textContent='ค้นหาไม่สำเร็จ กรุณาลองใหม่';}},350);
   };return;
  }
  if(step===2){
   host.innerHTML='<div class="h94-panel"><h4>2. เลือกรายการตรวจสำหรับทดสอบ</h4><p>'+esc(person?.display_name||'')+'</p>'+
    (event.hcv_enabled?'<label><input type="checkbox" data-h94-hcv '+(hcv?'checked':'')+'> Anti-HCV</label>':'')+
    (event.hbsag_enabled?'<label><input type="checkbox" data-h94-hb '+(hb?'checked':'')+'> HBsAg</label>':'')+
    '<p>ไม่มีการเก็บเบอร์โทรหรือผลตรวจจริง</p><button type="button" data-h94-prev>ย้อนกลับ</button><button type="button" data-h94-next>ถัดไป: เลือกรอบทดสอบ</button></div>';
   get('[data-h94-prev]').onclick=()=>{step=1;person=null;draw();};
   const changed=()=>{hcv=!!get('[data-h94-hcv]')?.checked;hb=!!get('[data-h94-hb]')?.checked;get('[data-h94-next]').disabled=!(hcv||hb);};
   host.querySelectorAll('input').forEach(x=>x.onchange=changed);changed();
   get('[data-h94-next]').onclick=async()=>{changed();if(get('[data-h94-next]').disabled)return;step=3;draw();await loadSlots();};return;
  }
  host.innerHTML='<div class="h94-panel"><h4>3. เลือกรอบและยืนยันรายการทดสอบ</h4><p>'+esc(person?.display_name||'')+' · '+(hcv?'Anti-HCV ':'')+(hb?'HBsAg':'')+'</p><label>รอบทดสอบ<select data-h94-slot><option value="">กำลังโหลดรอบทดสอบ…</option></select></label><p>รอบ A รับ 1 รายการทดสอบ รอบ B รับ 5 รายการทดสอบ ใช้ตรวจเงื่อนไขจำนวนรับ</p><button type="button" data-h94-prev>ย้อนกลับ</button><button type="button" data-h94-submit disabled>ยืนยันรายการทดสอบ (ไม่ใช่นัดจริง)</button></div>';
  get('[data-h94-prev]').onclick=()=>{if(!saving){step=2;draw();}};
  get('[data-h94-slot]').onchange=()=>{slot=get('[data-h94-slot]').value;const s=slots.find(x=>x.slot_key===slot);get('[data-h94-submit]').disabled=saving||!s||Number(s.remaining)<1;};
  get('[data-h94-submit]').onclick=submit;if(slots.length)renderSlots();
 }
 async function mine(){
  if(!alive()||step!==1)return;
  const results=get('[data-h94-results]');results.textContent='กำลังโหลดรายการทดสอบของฉัน…';
  person=null;get('[data-h94-next]').disabled=true;
  try{const rows=await rpc('list_my_hcv_demo_v2094',{p_event:event.id});if(!alive()||step!==1)return;
    results.replaceChildren();if(!rows?.length){results.textContent='ยังไม่มีรายการจองทดสอบ';return;}
    rows.forEach(row=>{const item=document.createElement('div');item.className='h94-record';
      const p=document.createElement('p');
      p.textContent=row.display_name+' · รอบ '+row.slot_key+' · '+[row.hcv_selected?'Anti-HCV':'',row.hbsag_selected?'HBsAg':''].filter(Boolean).join(' + ')+' · สถานะทดลอง '+row.verification_status;
      item.appendChild(p);
      const cancel=document.createElement('button');cancel.type='button';cancel.textContent='ยกเลิกรายการทดสอบ';
      cancel.onclick=async()=>{if(!confirm('ยกเลิกเฉพาะรายการทดสอบนี้? ไม่มีผลต่อการจองจริง'))return;
        cancel.disabled=true;try{await rpc('cancel_hcv_demo_v2094',{p_booking:row.booking_id});await mine();status('ยกเลิกรายการทดสอบแล้ว');}
        catch{cancel.disabled=false;status('ยกเลิกไม่สำเร็จ กรุณาติดต่อเจ้าหน้าที่หากบันทึกบริการจำลองแล้ว');}};
      item.appendChild(cancel);results.appendChild(item);
    });
  }catch{results.textContent='ไม่สามารถอ่านรายการทดสอบ กรุณาลองใหม่';}
 }
 function renderSlots(){
  const el=get('[data-h94-slot]');if(!el)return;
  el.innerHTML='<option value="">เลือกรอบทดสอบ</option>'+slots.map(s=>'<option value="'+esc(s.slot_key)+'" '+(Number(s.remaining)>0?'':'disabled')+'>'+esc(s.slot_label)+' · ว่าง '+Number(s.remaining)+' / '+Number(s.capacity)+'</option>').join('');
  slot='';get('[data-h94-submit]').disabled=true;
 }
 async function loadSlots(){try{const data=await rpc('hcv_demo_slots_v2094',{p_event:event.id});
  if(!alive()||step!==3)return;slots=Array.isArray(data)?data:[];renderSlots();status('เลือกรอบทดสอบที่ว่าง แล้วกดยืนยันเฉพาะรายการทดสอบ');}
  catch{if(alive()&&step===3)status('โหลดรอบทดสอบไม่สำเร็จ กรุณาลองใหม่');}}
 async function submit(){
  if(saving||!person||!(hcv||hb)||!['A','B'].includes(slot))return;
  if(!confirm('ยืนยันบันทึกรายการทดสอบสำหรับบุคคลที่เลือก? ไม่ใช่นัดตรวจจริง'))return;
  saving=true;get('[data-h94-submit]').disabled=true;status('กำลังตรวจจำนวนรับและบันทึกเฉพาะรายการทดสอบ…');
  try{const x=await rpc('book_hcv_demo_real_v2094',{p_event:event.id,p_pcucode:person.source_pcucode,p_pid:person.source_pid,p_slot:slot,p_hcv:hcv,p_hbsag:hb});
   if(!alive()||step!==3)return;
   if(x?.status==='already_booked'){status('บุคคลนี้มีรายการทดสอบแล้ว กรุณาดูรายการของฉัน');await loadSlots();return;}
   if(x?.status!=='booked'||x?.is_demo!==true)throw Error('ไม่ได้รับการยืนยันรายการทดสอบ');
   receipt={person:person.display_name,slot:slot,tests:[hcv?'Anti-HCV':'',hb?'HBsAg':''].filter(Boolean).join(' + ')};
   draw();status('บันทึกรายการทดสอบในฐานแยกแล้ว เจ้าหน้าที่ตรวจรายงานและรีเซ็ตได้');
  }catch(e){if(alive()&&step===3){await loadSlots();status(/เต็ม|สิทธิ์|ไม่อยู่/.test(String(e?.message||''))?String(e.message).slice(0,130):'บันทึกทดสอบไม่สำเร็จ กรุณาลองใหม่');}}
  finally{saving=false;const btn=get('[data-h94-submit]');if(btn)btn.disabled=!slot;}
 }
 draw();status('ค้นหาบุคคลจริงเฉพาะในบ้านที่ท่านรับผิดชอบ');
}
