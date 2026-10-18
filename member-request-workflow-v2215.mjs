// Member request end-to-end worklist; no automatic closing or JHCIS writes.
export async function openAdminMemberWorklistV2215(ctx){
 const {supabase,openModal,esc,fmt,showPhcToast,friendlyError,reviewRequest,cancelMemberRequestV2070}=ctx;
 const body=openModal('ติดตามคำขอสมาชิกจนเห็นในบ้าน','เสร็จเมื่อเชื่อม JHCIS + สมาชิกอยู่ในบ้าน + อสม. ผู้รับผิดชอบยืนยันการมองเห็นเท่านั้น');
 let scope='open',offset=0,seq=0;
 const PAGE=30;
 const tabs=[['open','ค้างทั้งหมด'],['pending','รอตรวจ'],['jhcis','รอ JHCIS'],['correction','รอแก้ไข'],['exception','ข้อมูลผิดปกติ'],['field','รอ อสม. ยืนยัน'],['completed','เสร็จครบ'],['cancelled','ยกเลิก'],['all','ประวัติทั้งหมด']];
 const names={pending:'รอตรวจคำขอ',jhcis:'รอเชื่อม/ตรวจ JHCIS',correction:'ส่งกลับแก้ไข',exception:'เชื่อมแล้วแต่ข้อมูลบ้าน/ผู้รับผิดชอบผิดปกติ',field:'รอ อสม. ยืนยันเห็นสมาชิก',completed:'ปิดงานครบทุกขั้น',cancelled:'ยกเลิก'};
 body.innerHTML='<div class="phc190-note">ระบบไม่ลบคำขอเก่าและไม่เพิ่มประชากรซ้ำ · ตรวจเลข 13 หลักกับ JHCIS ก่อนเชื่อมทุกครั้ง</div>'+
 '<label style="display:block;margin:12px 0">ประเภทคิว <select data-work-scope style="min-height:48px;width:100%;padding:8px">'+tabs.map(x=>'<option value="'+x[0]+'">'+x[1]+'</option>').join('')+'</select></label>'+
 '<div data-work-count class="phc190-note">กำลังโหลด…</div><div data-work-rows class="phc190-request-list"></div>'+
 '<div class="phc190-actions"><button class="phc190-secondary" data-work-prev type="button">ก่อนหน้า</button><button class="phc190-secondary" data-work-next type="button">ถัดไป</button></div>';
 const select=body.querySelector('[data-work-scope]'),count=body.querySelector('[data-work-count]'),host=body.querySelector('[data-work-rows]');
 const prev=body.querySelector('[data-work-prev]'),next=body.querySelector('[data-work-next]');
 select.onchange=()=>{scope=select.value;offset=0;load();};
 prev.onclick=()=>{offset=Math.max(0,offset-PAGE);load();};
 next.onclick=()=>{offset+=PAGE;load();};
 async function load(){
   const current=++seq;host.textContent='กำลังโหลด…';prev.disabled=true;next.disabled=true;
   const {data,error}=await supabase.rpc('admin_member_worklist_v2215',{p_scope:scope,p_limit:PAGE,p_offset:offset});
   if(current!==seq||!body.isConnected)return;
   if(error){host.textContent='โหลดไม่สำเร็จ: '+friendlyError(error);count.textContent='ไม่สามารถตรวจคิวได้';return;}
   const rows=data||[],total=Number(rows[0]?.total_count||0);
   if(!rows.length&&offset>0){offset=Math.max(0,offset-PAGE);return load();}
   count.textContent='พบ '+total.toLocaleString('th-TH')+' คำขอ · แสดง '+(total?offset+1:0)+'–'+(offset+rows.length)+' · ไม่จำกัดคิว 100 รายการ';
   prev.disabled=offset===0;next.disabled=offset+rows.length>=total;
   host.innerHTML=rows.map(r=>{
     const state=r.workflow_state;
     const actions=state==='pending'
       ?'<button type="button" class="phc190-primary" data-verify>ตรวจผ่าน · รอเชื่อม JHCIS</button><button type="button" class="phc190-secondary" data-correct>ขอแก้ไข</button>'
       :(state==='jhcis'&&r.linked_person_id==null
         ?'<button type="button" class="phc190-secondary" data-return>ส่งกลับแก้ไขพร้อมเหตุผล</button>'
         :'');
     const canCancel=r.linked_person_id==null&&!['completed','cancelled','field','exception'].includes(state);
     const note=[r.jhcis_verification_note,r.review_note].filter(Boolean).filter((v,i,a)=>a.indexOf(v)===i).join(' · ');
     return '<article class="phc190-request" data-work-id="'+esc(r.id)+'">'+
       '<strong>'+esc(r.full_name)+'</strong><small>บ้าน '+esc(r.house_no||'—')+' หมู่ '+esc(r.moo||'—')+' · '+esc(r.community||'ยังไม่ระบุ')+
       ' · '+esc(r.masked_citizen_id)+' · เกิด '+esc(fmt(r.birth_date))+'</small>'+
       '<span class="phc190-status '+esc(state==='completed'?'verified':'pending')+'">'+esc(names[state]||state)+'</span>'+
       '<small>ผู้แจ้ง: '+esc(r.requester_name||'ไม่ระบุ')+' · '+esc(r.requester_community||'—')+'</small>'+
       '<small>PID: '+esc(r.linked_person_id??'ยังไม่เชื่อม')+' · สมาชิกอยู่ในบ้าน: '+(r.roster_found?'ใช่':'ยังไม่ยืนยัน')+
       ' · บัญชีผู้รับผิดชอบ: '+(r.owner_account_ready?'พร้อม':'ต้องตรวจ')+'</small>'+
       (note?'<div class="phc190-note phc190-warning" style="margin-top:8px">เหตุผล/ผลตรวจ: '+esc(note)+'</div>':'')+
       '<div class="phc190-actions"><button type="button" class="phc190-secondary" data-sensitive>ตรวจเลข 13 หลัก</button>'+
       '<button type="button" class="phc190-secondary" data-match>ค้นคนเดิม</button></div>'+
       (r.requester_line_connected&&r.requester_user_id?'<button type="button" class="phc190-secondary" data-contact>แจ้งผู้ส่งผ่าน LINE</button>':'<small>ติดต่อผู้แจ้งผ่านหน่วยบริการ หากยังไม่เชื่อม LINE</small>')+
       (actions?'<div class="phc190-actions">'+actions+'</div>':'')+
       (canCancel?'<button type="button" class="phc190-secondary phc190-danger" data-cancel>ยกเลิกคำขอ (มีเหตุผล)</button>':'')+
       '<div data-detail></div></article>';
   }).join('')||'<div class="phc190-note">ไม่มีรายการในกลุ่มนี้</div>';
   for(const card of host.querySelectorAll('[data-work-id]')){
     const id=card.dataset.workId,r=rows.find(x=>x.id===id),detail=card.querySelector('[data-detail]');
     card.querySelector('[data-verify]')?.addEventListener('click',()=>reviewRequest(id,'verify'));
     card.querySelector('[data-correct]')?.addEventListener('click',()=>reviewRequest(id,'needs_correction'));
     card.querySelector('[data-cancel]')?.addEventListener('click',()=>cancelMemberRequestV2070(id,r.full_name));
     card.querySelector('[data-return]')?.addEventListener('click',async()=>{
       const reason=prompt('ระบุสาเหตุที่ต้องแก้ไข (8–300 ตัวอักษร ห้ามใส่ CID/ข้อมูลสุขภาพ)');
       if(!reason)return;
       if(reason.trim().length<8){alert('กรุณาระบุสาเหตุให้ชัดเจนอย่างน้อย 8 ตัวอักษร');return;}
       if(!confirm('ส่งคำขอเดิมกลับให้แก้ไข และเก็บประวัติการตรวจไว้?'))return;
       const result=await supabase.rpc('admin_return_member_correction_v2215',{p_request_id:id,p_reason:reason.trim()});
       if(result.error){alert(friendlyError(result.error));return;}
       showPhcToast('ส่งกลับแก้ไขแล้ว ไม่สร้างคำขอใหม่');offset=0;load();
     });
     card.querySelector('[data-sensitive]').onclick=async()=>{
       detail.textContent='กำลังตรวจ…';
       const result=await supabase.rpc('admin_member_request_sensitive_v190',{p_request_id:id});
       detail.innerHTML=result.error?'<p class="phc190-error">'+esc(friendlyError(result.error))+'</p>':
         '<div class="phc190-note">เลขสำหรับตรวจ JHCIS: <strong>'+esc(result.data.citizen_id)+'</strong><small>บันทึก Audit การเปิดดูแล้ว</small></div>';
     };
     card.querySelector('[data-match]').onclick=async()=>{
       detail.textContent='กำลังเทียบทะเบียน…';
       const result=await supabase.rpc('admin_member_request_match_v190',{p_request_id:id});
       if(result.error){detail.textContent=friendlyError(result.error);return;}
       detail.innerHTML=(result.data||[]).map(m=>'<div class="phc190-note"><strong>'+esc(m.display_name)+'</strong><small>PID '+esc(m.source_pid)+' · '+esc(m.house_no)+' · '+esc(m.community)+' · '+esc(m.match_type==='citizen_id_hash'?'CID hash ตรง':'ชื่อและวันเกิดตรง ต้องยืนยัน CID')+'</small>'+
        (m.same_house&&m.match_type==='citizen_id_hash'&&['pending','correction'].includes(r.workflow_state)?'<button type="button" class="phc190-primary" data-link-pid="'+esc(m.source_pid)+'" data-link-pcucode="'+esc(m.source_pcucode)+'">เชื่อม PID หลังยืนยัน CID</button>':'')+'</div>').join('')||'<div class="phc190-note">ไม่พบข้อมูลที่ตรงกัน ต้องตรวจ JHCIS ต้นทาง ไม่เพิ่มซ้ำ</div>';
       detail.querySelectorAll('[data-link-pid]').forEach(b=>b.onclick=()=>reviewRequest(id,'verify','',b.dataset.linkPcucode,Number(b.dataset.linkPid)));
     };
     card.querySelector('[data-contact]')?.addEventListener('click',()=>{
       detail.innerHTML='<form data-contact-form class="phc190-form"><label>ข้อความทั่วไปถึงผู้แจ้ง<textarea name="message" required maxlength="500">คำขอเพิ่มสมาชิกยังอยู่ระหว่างตรวจสอบ กรุณาเปิดระบบพระบาท พลัส หรือติดต่อหน่วยบริการเพื่อรับรายละเอียด</textarea></label><small>ห้ามระบุเลขบัตรหรือข้อมูลสุขภาพ</small><button type="submit" class="phc190-primary">เข้าคิวส่ง LINE</button></form>';
       const form=detail.querySelector('[data-contact-form]');
       form.onsubmit=async e=>{
         e.preventDefault();const message=form.elements.message.value.trim();
         if(!message||/\d{13}/.test(message)){alert('ห้ามส่งเลขประจำตัวประชาชน');return;}
         const b=form.querySelector('button');b.disabled=true;
         const result=await supabase.rpc('admin_queue_line_message_v190',{p_recipient_user_id:r.requester_user_id,p_body:message,p_action_path:'?panel=overview',p_message_type:'notice'});
         if(result.error){alert(friendlyError(result.error));b.disabled=false;return;}
         showPhcToast('เข้าคิว LINE สำเร็จ');detail.replaceChildren();
       };
     });
   }
 }
 await load();
}

export async function renderFieldMemberVisibilityV2215(ctx){
 const {supabase,houseId,sec,esc,showPhcToast,friendlyError}=ctx;
 const result=await supabase.rpc('field_member_visibility_candidates_v2215',{p_house_id:houseId});
 if(result.error||!sec.isConnected)return;
 const rows=(result.data||[]).filter(r=>!r.confirmed);
 if(!rows.length)return;
 const section=document.createElement('div');section.className='phc190-note';
 section.innerHTML='<strong>ยืนยันการมองเห็นสมาชิกที่เชื่อม JHCIS แล้ว</strong><small>ตรวจว่าชื่อบุคคลปรากฏในหัวข้อสมาชิกในบ้านด้านบน ก่อนกดยืนยัน เพื่อปิดงานให้ครบจริง</small>'+
 rows.map(r=>'<div class="phc190-request" style="margin-top:8px"><strong>'+esc(r.full_name)+'</strong><small>PID '+esc(r.linked_person_id)+'</small><button type="button" class="phc190-secondary" data-visibility-id="'+esc(r.id)+'">เห็นสมาชิกในบ้านแล้ว</button></div>').join('');
 sec.appendChild(section);
 section.querySelectorAll('[data-visibility-id]').forEach(b=>b.onclick=async()=>{
   const item=rows.find(x=>x.id===b.dataset.visibilityId);
   if(!item||!confirm('ยืนยันว่าท่านเห็น '+item.full_name+' อยู่ในรายชื่อสมาชิกของบ้านนี้จริง?'))return;
   b.disabled=true;
   const resp=await supabase.rpc('field_confirm_member_visibility_v2215',{p_request_id:item.id});
   if(resp.error){alert(friendlyError(resp.error));b.disabled=false;return;}
   showPhcToast('ยืนยันมองเห็นสมาชิกในบ้านแล้ว');b.closest('.phc190-request')?.remove();
   if(!section.querySelector('[data-visibility-id]'))section.remove();
 });
}
