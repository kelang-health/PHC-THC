/* H6.5 demonstration only: no network, real people, authentication, or persistent bookings. */
const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function openHcvDemoV2093({event,body,back}){
 if(!body||!body.isConnected||event?.is_demo!==true||event.booking_enabled!==false||event.event_subtype!=='hcv_hbsag')return;
 let step=1,person='',hcv=!!event.hcv_enabled,hb=!!event.hbsag_enabled,slot='',completed=false;
 const find=q=>body.querySelector(q);
 const name='บุคคลจำลอง A (ไม่ใช่ข้อมูลประชาชนจริง)';
 const when=new Date(Date.now()+86400000).toLocaleString('th-TH',{timeZone:'Asia/Bangkok',dateStyle:'medium',timeStyle:'short'});
 const title='🧪 ทดลองจอง HCV / HBsAg — ไม่มีการจองจริง';
 const header=()=>'<h3>'+title+'</h3><p class="cn83-demo-label">โหมดทดสอบ: ใช้บุคคลและเบอร์โทรจำลองเท่านั้น ไม่มีการเชื่อมต่อฐานจอง ไม่มีการบันทึกใด ๆ หลังออกจากหน้านี้</p>';
 const actions=(next,backLabel='ย้อนกลับ')=>'<div class="h93-actions"><button type="button" data-h93-back>'+backLabel+'</button>'+(next?'<button type="button" data-h93-next>'+next+'</button>':'')+'</div>';
 function paint(){
  if(!body.isConnected)return;
  if(completed){body.innerHTML='<section class="h93-demo">'+header()+'<div class="h93-stage"><h4>✅ จำลองการจองสำเร็จ</h4><p>นี่เป็นเพียงผลทดสอบหน้าจอ ไม่ได้จองรอบจริง ไม่ลดจำนวนที่ว่าง และไม่มีรายการส่งถึงเจ้าหน้าที่</p><p>'+name+' · '+(hcv?'Anti-HCV ':'')+(hb?'HBsAg':'')+' · '+when+'</p></div>'+actions('','กลับรายละเอียดกิจกรรม')+'</section>';find('[data-h93-back]').onclick=back;return;}
  let inner='';
  if(step===1)inner='<p>ขั้นที่ 1/3 · เลือกคนจำลอง</p><button type="button" data-h93-pick class="cn83-book">'+name+'</button><p>ไม่ใช้ข้อมูลรายชื่อหรือบ้านจริงของ อสม.</p>'+actions('ถัดไป');
  else if(step===2)inner='<p>ขั้นที่ 2/3 · เลือกรายการตรวจ</p>'+(event.hcv_enabled?'<label><input type="checkbox" data-h93-hcv '+(hcv?'checked':'')+'> Anti-HCV</label>':'')+(event.hbsag_enabled?'<label><input type="checkbox" data-h93-hb '+(hb?'checked':'')+'> HBsAg</label>':'')+'<p>เบอร์ติดต่อจำลอง: 0800000000 (ไม่มีการรับหรือส่งเบอร์โทรจริง)</p>'+actions('ถัดไป');
  else inner='<p>ขั้นที่ 3/3 · ตรวจสอบนัดจำลอง</p><p>'+name+'</p><p>รายการตรวจ: '+(hcv?'Anti-HCV ':'')+(hb?'HBsAg':'')+'</p><label>รอบทดสอบ<select data-h93-slot><option value="">เลือกรอบจำลอง</option><option value="fake">'+safe(when)+' · สถานที่จำลอง · ว่าง 1 ที่</option></select></label><p class="h93-caption">ปุ่มยืนยันนี้จำลองผลในเบราว์เซอร์เท่านั้น ไม่ส่งคำสั่งจองจริง</p>'+actions('จำลองการยืนยัน');
  body.innerHTML='<section class="h93-demo">'+header()+'<div class="h93-stage">'+inner+'</div></section>';
  const prev=find('[data-h93-back]'),next=find('[data-h93-next]');
  prev.onclick=()=>{if(step===1)back();else{step--;paint();}};
  if(step===1){const pick=find('[data-h93-pick]');pick.onclick=()=>{person='fake';next.disabled=false;pick.setAttribute('aria-pressed','true');};next.disabled=!person;next.onclick=()=>{if(person){step=2;paint();}};}
  if(step===2){const update=()=>{hcv=!!find('[data-h93-hcv]')?.checked;hb=!!find('[data-h93-hb]')?.checked;next.disabled=!(hcv||hb);};body.querySelectorAll('input[type=checkbox]').forEach(x=>x.onchange=update);update();next.onclick=()=>{update();if(!next.disabled){step=3;paint();}};}
  if(step===3){const select=find('[data-h93-slot]');select.onchange=()=>{slot=select.value;next.disabled=slot!=='fake';};next.disabled=slot!=='fake';if(slot)select.value=slot;next.onclick=()=>{if(slot==='fake'&&(hcv||hb)){completed=true;paint();}};}
 }
 paint();
}
