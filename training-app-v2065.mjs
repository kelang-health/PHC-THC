// Separate training-only auth and RPC transport. No production login or session.
const URL='https://tgeezbwbrovfyjbeykrj.supabase.co';
const KEY='sb_publishable_'+'bw0sKPthqc6S'+'l9xU8fdVpA_p2sZ4-N2';
const $=(s,r=document)=>r.querySelector(s);
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let token='',role='',data=null,view='overview',selected='',busy=false;
async function rpc(name,args={}){
  if(!name.startsWith('demo_training_'))throw Error('TRAINING_RPC_ONLY');
  const response=await fetch(URL+'/rest/v1/rpc/'+name,{method:'POST',
    headers:{'apikey':KEY,'Authorization':'Bearer '+KEY,'content-type':'application/json','accept':'application/json'},
    body:JSON.stringify(args),cache:'no-store'});
  const value=await response.json().catch(()=>null);
  if(!response.ok)throw Error(value?.message||'ไม่สามารถเชื่อมต่อข้อมูลฝึกอบรมได้');
  return value;
}
function status(message,error=false){
  const el=$('#training-status');
  if(el){el.textContent=message;el.classList.toggle('training-error',error);}
}
function clearSession(){
  token='';role='';data=null;selected='';busy=false;
  $('#training-login').hidden=false;$('#training-portal').hidden=true;
  $('#training-login-form').reset();
}
async function refresh(){
  if(!token)return;
  try{data=await rpc('demo_training_get_v2065',{p_token:token});render();}
  catch(e){if(/TRAINING_SESSION/.test(e.message)){clearSession();$('#training-login-error').textContent='หมดเวลาการฝึกอบรม กรุณาเข้าสู่ระบบอีกครั้ง';}
    else status(e.message,true);}
}
async function action(name,params={}){
  if(busy||!token)return;busy=true;status('กำลังบันทึกข้อมูลสาธิต…');
  try{
    data=await rpc('demo_training_action_v2065',{p_token:token,p_action:name,
      p_house_id:params.house||null,p_person_id:params.person||null,
      p_age:params.age??null,p_kind:params.kind||null,p_result:params.result||null});
    render();status('บันทึกข้อมูลสาธิตแล้ว ข้อมูลจริงไม่ถูกแก้ไข');
  }catch(e){status('ไม่สำเร็จ: '+e.message,true);}
  finally{busy=false;}
}
function button(label,handler,{primary=false,disabled=false}={}){
  const b=document.createElement('button');b.type='button';
  b.className='training-btn'+(primary?' primary':'');b.textContent=label;b.disabled=disabled;
  b.onclick=handler;return b;
}
function selectedHouse(){
  const h=data.houses||[];
  if(!h.some(x=>x.id===selected))selected=h[0]?.id||'';
  return h.find(x=>x.id===selected);
}
function render(){
  if(!data||!token)return;
  $('#training-role-label').textContent=role==='staff'?'Staff ทดสอบ · ประธานชุมชน':'User ทดสอบ · อสม. สาธิต 01';
  const nav=$('#training-nav');
  nav.querySelectorAll('[data-training-view]').forEach(b=>{
    b.hidden=false;
    if(b.dataset.trainingView==='communities')
      b.textContent=role==='staff'?'ชุมชนที่ดูแล':'ชุมชนของฉัน';
    b.classList.toggle('active',b.dataset.trainingView===view);
    b.onclick=()=>{view=b.dataset.trainingView;render();};
  });
  const root=$('#training-content');root.replaceChildren();
  const houses=data.houses||[],people=data.people||[],house=selectedHouse();
  const title=document.createElement('h3');
  const names={overview:'ภาพรวม',communities:'ชุมชนของฉัน',houses:'บ้านของฉัน',
    health:'งานสุขภาพ',work:'ผลงาน/ติดตาม'};
  title.textContent=names[view]||'ภาพรวม';root.appendChild(title);
  const hint=document.createElement('p');hint.className='training-notice';
  hint.textContent='พื้นที่ฝึกอบรม หมู่ 9 · ใช้ข้อมูลสมมติ ไม่มีเลขบัตรประชาชนหรือ PID จริง';root.appendChild(hint);
  const el=document.createElement('div');el.className='training-house';
  const stat=(label,n)=>'<div class="training-stat"><small>'+esc(label)+'</small><strong>'+n+'</strong></div>';
  const summary='<div class="training-grid">'+stat('บ้านที่เห็นตามสิทธิ์',houses.length)+
    stat('บุคคลสมมติ',people.length)+stat('รอตรวจ',houses.filter(x=>x.status==='pending').length+
      people.filter(x=>x.status==='pending').length)+
    stat('คัดกรองสาธิต',people.filter(x=>Object.keys(x.screenings||{}).length>0).length)+'</div>';
  if(view==='overview'){
    el.innerHTML=summary+'<p>เจ้าหน้าที่สาธิตสามารถใช้เมนูด้านบนเพื่อเรียนรู้ขั้นตอนตามบทบาท</p>'+
      '<div class="training-item"><strong>หมู่ 9 · ชุมชนทดสอบ</strong><small>ข้อมูลสมมติทั้งหมด ไม่รวมในผลงานจริง</small></div>';
  }else if(view==='communities'){
    el.innerHTML=summary+'<article class="training-item"><h3>ชุมชนทดสอบ · หมู่ 9</h3>'+
      '<p>บ้านในขอบเขต '+houses.length+' หลัง · บุคคลสมมติ '+people.length+' คน</p>'+
      '<button type="button" class="training-btn" data-open-houses>เปิดบ้านในชุมชน</button></article>';
  }else if(view==='houses'){
    el.innerHTML='<div class="training-row">'+(role==='user'?'<button type="button" class="training-btn primary" data-add-house>+ เพิ่มบ้าน</button>':'')+
      '<button type="button" class="training-btn" data-reload>ตรวจข้อมูลบ้านและสถานะคำขอล่าสุด</button></div>'+
      '<div class="training-layout"><div class="training-section"><h3>รายชื่อบ้าน</h3>'+
      houses.map(h=>'<div class="training-item"><strong>'+esc(h.house_no)+'</strong>'+
        '<small>'+esc(h.owner||'ยังไม่มอบหมาย')+' · '+(h.status==='pending'?'รอตรวจ':'ยืนยันสาธิต')+'</small>'+
        '<button type="button" class="training-btn" data-house="'+esc(h.id)+'">เปิดบ้าน</button></div>').join('')+
      '</div><div class="training-section"><h3>สมาชิกบ้าน '+esc(house?.house_no||'')+'</h3>'+
      (role==='user'?'<button type="button" class="training-btn primary" data-add-person '+(house?.status!=='confirmed'?'disabled':'')+'>+ แจ้งเพิ่มสมาชิก</button>':'')+
      people.filter(p=>p.house_id===house?.id).map(p=>'<div class="training-item"><strong>'+esc(p.display_name)+'</strong>'+
        '<small>อายุสมมติ '+Number(p.age_years)+' ปี · '+esc(p.group)+'</small>'+
        (p.special?'<span class="training-pending">'+esc(p.special)+'</span>':'')+
        (p.status==='pending'?'<span class="training-pending">รอตรวจคำขอ</span>':'')+
        '</div>').join('')+'</div></div>';
  }else if(view==='health'){
    el.innerHTML='<p>ตัวอย่างการคัดกรองตามกลุ่มวัย (เป็นเพียงผลสาธิต ไม่ใช่แบบประเมินทางคลินิก)</p>'+
      people.filter(p=>p.status==='confirmed').map(p=>'<article class="training-item"><strong>'+esc(p.display_name)+'</strong>'+
      '<small>อายุสมมติ '+Number(p.age_years)+' ปี · '+esc(p.group)+'</small>'+
      '<small>'+Object.entries(p.screenings||{}).map(([k,v])=>esc(k)+': '+esc(v)).join(' · ')+'</small>'+
      (role==='user'?'<button type="button" class="training-btn" data-screen="'+esc(p.id)+'">ทดลองบันทึกผล</button>':'')+'</article>').join('');
  }else if(view==='work'){
    el.innerHTML=summary+'<h3>สถานะคำขอสาธิต</h3>'+
      (role==='staff'?'<p>จำลองการตรวจติดตามคำขอในชุมชน ไม่มีการอนุมัติรายการจริงใน JHCIS</p>':'<p>รายการที่ส่งจากบัญชี User สาธิต</p>')+
      houses.filter(h=>h.status==='pending').map(h=>'<div class="training-item"><strong>'+esc(h.house_no)+'</strong>'+
        '<span class="training-pending">บ้านรอตรวจ</span>'+(role==='staff'?'<button class="training-btn primary" data-review-house="'+esc(h.id)+'">ยืนยันบ้านสาธิต</button>':'')+'</div>').join('')+
      people.filter(p=>p.status==='pending').map(p=>'<div class="training-item"><strong>'+esc(p.display_name)+'</strong>'+
        '<span class="training-pending">สมาชิกบ้านรอตรวจ</span>'+(role==='staff'?'<button class="training-btn primary" data-review-person="'+esc(p.id)+'">ยืนยันสมาชิกสาธิต</button>':'')+'</div>').join('');
  }
  root.appendChild(el);
  $('[data-open-houses]',root)?.addEventListener('click',()=>{view='houses';render();});
  $('[data-reload]',root)?.addEventListener('click',refresh);
  root.querySelectorAll('[data-house]').forEach(b=>b.onclick=()=>{selected=b.dataset.house;render();});
  $('[data-add-house]',root)?.addEventListener('click',()=>action('add_house'));
  $('[data-add-person]',root)?.addEventListener('click',()=>{
    const raw=window.prompt('อายุสมาชิกสมมติ 0–120 ปี (ไม่ใช้ข้อมูลประชาชนจริง)','38');
    if(raw===null)return;
    if(!/^\d{1,3}$/.test(raw.trim())||Number(raw)>120){status('กรอกอายุสมมติ 0–120 ปี',true);return;}
    action('add_person',{house:house.id,age:Number(raw)});
  });
  root.querySelectorAll('[data-review-house]').forEach(b=>b.onclick=()=>action('review_house',{house:b.dataset.reviewHouse}));
  root.querySelectorAll('[data-review-person]').forEach(b=>b.onclick=()=>action('review_person',{person:b.dataset.reviewPerson}));
  root.querySelectorAll('[data-screen]').forEach(b=>b.onclick=()=>{
    const p=people.find(x=>x.id===b.dataset.screen),a=Number(p?.age_years);if(!p)return;
    const kinds=[...(a>=35?['ncd']:[]),...(a<=5?['dspm']:[]),
      ...(a>=6&&a<=14?['school']:[]),...(a>=60?['older']:[])];
    const kind=window.prompt('เลือกรายการสาธิต '+kinds.join(', '),kinds[0]||'');
    if(kind===null)return;
    if(!kinds.includes(kind)){status('กรุณาเลือกการคัดกรองให้ตรงกลุ่มวัยสมมติ',true);return;}
    const result=window.prompt('ผลสาธิต: 1 = ผ่าน / 2 = ต้องติดตาม · ยกเลิก = ไม่บันทึก','1');
    if(result===null)return;
    if(!['1','2'].includes(result.trim())){status('เลือกผล 1 หรือ 2',true);return;}
    action('screen',{person:p.id,kind,result:result.trim()==='1'?'ผ่านการสาธิต':'ต้องติดตาม (สาธิต)'});
  });
}
$('#training-login-form').addEventListener('submit',async e=>{
  e.preventDefault();const f=e.currentTarget,submit=f.querySelector('[type=submit]');
  submit.disabled=true;$('#training-login-error').textContent='';
  const fields=new FormData(f),username=String(fields.get('username')||'').trim().toLowerCase();
  const password=String(fields.get('password')||'');
  f.querySelector('[name=password]').value='';
  try{
    const login=await rpc('demo_training_login_v2065',{p_username:username,p_password:password});
    if(!login?.token)throw Error('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
    token=login.token;role=login.role;data=null;view='overview';
    $('#training-login').hidden=true;$('#training-portal').hidden=false;
    await refresh();
  }catch(err){$('#training-login-error').textContent='เข้าสู่การฝึกอบรมไม่ได้: '+err.message;}
  finally{submit.disabled=false;}
});
$('#training-logout').addEventListener('click',async()=>{
  const old=token;clearSession();if(old)await rpc('demo_training_logout_v2065',{p_token:old}).catch(()=>{});
});
