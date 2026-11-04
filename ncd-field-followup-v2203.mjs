import {getSharedSupabase,getSharedProfile,sharedCall,invalidateShared,bindPortalActivation} from './shared-runtime-v2035.mjs?v=2.0.126-log-usage';
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export function bpProgress(ms=[]){const days=new Map();for(const m of ms){if(m.kind!=='bp')continue;if(!days.has(m.measured_on))days.set(m.measured_on,new Set());days.get(m.measured_on).add(`${m.period}:${m.sequence}`);}const complete=[...days].filter(([,v])=>['morning:1','morning:2','evening:1','evening:2'].every(k=>v.has(k))).map(([d])=>d).sort();let run=0,best=0,last=null;for(const d of complete){const n=Date.parse(d+'T00:00:00Z');run=last!==null&&n-last===86400000?run+1:1;best=Math.max(best,run);last=n;}return {days:complete.length,consecutive:best,complete:best>=7};}
const PAGE_SIZE=50;
const consecutive=r=>r.measurements?bpProgress(r.measurements).consecutive:Number(r.bp_days_consecutive||0);
const measurementCount=r=>r.measurements?.length??Number(r.measurement_count||0);
const complete=r=>r.kind==='bp'?consecutive(r)>=7:measurementCount(r)>0;
export function caseState(r){
  if(r.kind==='bp'){
    const days=consecutive(r);
    return days>=7?'ภาคสนามครบ · รอเจ้าหน้าที่ตรวจ':`Home BP ครบ ${days}/7 วันต่อเนื่อง`;
  }
  return measurementCount(r)?'DTX ภาคสนามเสร็จ · รอเจ้าหน้าที่/FPG':'รอ DTX ซ้ำในชุมชน';
}
let client,started=false;
function styles(){if(document.getElementById('ncd-field-style'))return;const s=document.createElement('style');s.id='ncd-field-style';s.textContent=`.nf-wrap{padding:12px;border:1px solid #bcd8cb;border-radius:16px;background:#f6fbf8;margin:12px 0}.nf-wrap button,.nf-dialog button{min-height:46px;padding:8px 12px;border:1px solid #a9c9ba;border-radius:10px;background:#e4f4ec;color:#15513f;font:inherit;cursor:pointer}.nf-row[hidden]{display:none}.nf-row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.nf-card{background:white;border:1px solid #d4e4dc;border-left:5px solid #dcad2e;border-radius:12px;padding:12px;margin:10px 0}.nf-card.done{border-left-color:#22866a}.nf-card small{display:block;color:#617d70;margin:5px 0}.nf-overlay{position:fixed;inset:0;z-index:15000;background:#0008;display:grid;place-items:center;padding:12px}.nf-dialog{background:white;padding:18px;border-radius:18px;width:min(500px,100%);box-sizing:border-box;max-height:92vh;overflow:auto}.nf-dialog input:not([type=checkbox]):not([type=radio]),.nf-wrap input{min-height:48px;font:inherit;padding:8px;border:1px solid #b7d0c2;border-radius:10px;box-sizing:border-box;width:100%}.nf-dialog label{display:block;margin:10px 0}.nf-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}.nf-dialog small{color:#617d70}.nf-warn{background:#fff3cd;padding:10px;border-radius:10px}.nf-error{color:#a02d2d}.nf-history{font-size:14px;border-top:1px solid #dae5de;padding-top:10px}.nf-actions{position:sticky;bottom:-18px;background:white;padding:10px 0}.nf-primary{background:#08745e!important;color:white!important}`;document.head.append(s);}
async function loadPage(client,kind,search,offset){
  const actor=await getSharedProfile(client);
  if(!actor?.active)throw new Error('AUTH_REQUIRED');
  const args={p_kind:kind,p_search:search,p_offset:offset};
  const key='ncd-field-page:'+JSON.stringify([actor.user_id,kind,search,offset]);
  const {data,error}=await sharedCall(key,()=>client.rpc('ncd_field_worklist_page_v2196',args),120000);
  if(error)throw error;
  return data;
}
function render(root,items){
  root.querySelector('[data-nf-list]').innerHTML=items.map(r=>`<article class="nf-card ${complete(r)?'done':''}"><strong>${esc(r.display_name)} · ${r.kind==='bp'?'Home BP':'DTX ซ้ำ'}</strong><small>บ้าน ${esc(r.house_no)} · ${esc(r.community)} · คัดกรอง ${esc(r.screened_on)}</small><small>ค่าเดิม ${r.kind==='bp'?esc(r.sbp)+'/'+esc(r.dbp):esc(r.glucose_mg_dl)+' mg/dL · '+(r.glucose_type==='fasting'?'อดอาหาร':'ไม่อดอาหาร')}</small><p>${esc(caseState(r))}</p><button data-nf-open="${esc(r.source_screen_id)}:${r.kind}">บันทึก / ดูประวัติ</button></article>`).join('')||'<p>ไม่มีรายการตามตัวกรองนี้</p>';
}
async function mount(parent,client){
  if(parent.querySelector('[data-nf-root]'))return;
  const root=document.createElement('section');
  root.className='nf-wrap';
  root.dataset.nfRoot='';
  root.innerHTML=`<h3>ติดตาม NCD ภาคสนาม</h3><div class="nf-row"><button data-nf-filter="all" aria-pressed="true">ทั้งหมด</button><button data-nf-filter="bp" aria-pressed="false">Home BP</button><button data-nf-filter="dtx" aria-pressed="false">DTX ซ้ำ</button><button data-nf-staff>ส่วนเจ้าหน้าที่/FPG</button><button data-nf-refresh>↻ อัปเดต</button></div><p data-nf-staff-note hidden>เจ้าหน้าที่ตรวจประวัติภาคสนามและดำเนินการยืนยันใน JHCIS · การบันทึก DTX หรือ Home BP ครบยังไม่ถือว่าจบผลงาน HDC</p><label>ค้นชื่อ / บ้าน / ชุมชน<input type="search" data-nf-search maxlength="160"></label><p data-nf-count role="status">กำลังอ่านข้อมูล…</p><p data-nf-detail-error role="alert" class="nf-error"></p><div data-nf-list></div><div class="nf-row" data-nf-pages hidden><button data-nf-prev>หน้าก่อน</button><button data-nf-next>หน้าถัดไป</button></div>`;
  parent.append(root);
  const get=selector=>root.querySelector(selector);
  const count=get('[data-nf-count]'),list=get('[data-nf-list]'),pages=get('[data-nf-pages]');
  const previous=get('[data-nf-prev]'),next=get('[data-nf-next]'),refresh=get('[data-nf-refresh]');
  const detailError=get('[data-nf-detail-error]');
  let filter='all',search='',offset=0,total=0,items=[],version=0,timer,opening=false;

  const draw=()=>{
    render(root,items);
    count.textContent=total?`แสดง ${offset+1}–${offset+items.length} จาก ${total} งาน`:'0 งาน';
    pages.hidden=total<=PAGE_SIZE;
    previous.disabled=offset===0;
    next.disabled=offset+PAGE_SIZE>=total;
  };
  const loading=()=>{
    count.textContent='กำลังอ่านข้อมูล…';
    list.replaceChildren();
    detailError.textContent='';
    pages.hidden=true;
    refresh.disabled=true;
  };
  const read=async token=>{
    try{
      const result=await loadPage(client,filter,search,offset);
      if(token!==version||!root.isConnected)return;
      total=Number(result.total);
      if(offset>0&&offset>=total){
        offset=Math.max(0,Math.floor((total-1)/PAGE_SIZE)*PAGE_SIZE);
        return await read(token);
      }
      items=result.items;
      draw();
    }catch{
      if(token===version&&root.isConnected)count.textContent='อ่านข้อมูลไม่สำเร็จ กรุณากดอัปเดตอีกครั้ง';
    }finally{
      if(token===version)refresh.disabled=false;
    }
  };
  const reload=(delay=0)=>{
    clearTimeout(timer);
    const token=++version;
    loading();
    if(delay)timer=setTimeout(()=>{if(root.isConnected)read(token);},delay);
    else return read(token);
  };
  root.querySelectorAll('[data-nf-filter]').forEach(button=>button.onclick=()=>{
    if(filter===button.dataset.nfFilter)return;
    filter=button.dataset.nfFilter;
    offset=0;
    root.querySelectorAll('[data-nf-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
    reload();
  });
  get('[data-nf-search]').oninput=event=>{
    search=event.target.value;
    offset=0;
    reload(300);
  };
  get('[data-nf-staff]').onclick=()=>{
    const note=get('[data-nf-staff-note]');
    note.hidden=!note.hidden;
  };
  refresh.onclick=()=>{invalidateShared('ncd-field-page:');reload();};
  previous.onclick=()=>{offset-=PAGE_SIZE;reload();};
  next.onclick=()=>{offset+=PAGE_SIZE;reload();};
  list.onclick=async event=>{
    const button=event.target.closest('[data-nf-open]');
    const row=items.find(r=>`${r.source_screen_id}:${r.kind}`===button?.dataset.nfOpen);
    if(!row||opening)return;
    const token=version;
    opening=true;
    button.disabled=true;
    detailError.textContent='';
    try{
      const {data,error}=await client.rpc('ncd_field_case_history_v2196',{
        p_source_screen_id:row.source_screen_id,p_kind:row.kind
      });
      if(error)throw error;
      if(token!==version||!root.isConnected)return;
      open({...row,measurements:data},client,measurements=>{
        invalidateShared('ncd-field-page:');
        if(token!==version||!root.isConnected)return;
        row.measurement_count=measurements.length;
        row.bp_days_consecutive=bpProgress(measurements).consecutive;
        const card=button.closest('.nf-card');
        card.classList.toggle('done',complete(row));
        card.querySelector('p').textContent=caseState(row);
        button.focus();
      });
    }catch{
      if(token===version&&root.isConnected)detailError.textContent='เปิดประวัติไม่สำเร็จ กรุณาลองใหม่หรือกดอัปเดตรายชื่อ';
    }finally{
      opening=false;
      button.disabled=false;
    }
  };
  return reload();
}
function open(r,client,onSaved){if(!r)return;document.querySelector('.nf-entry-overlay')?.remove();const overlay=document.createElement('div');overlay.className='nf-overlay nf-entry-overlay';const bp=r.kind==='bp';let requestId=crypto.randomUUID(),saving=false,warningKey='';
 overlay.innerHTML=`<section class="nf-dialog" role="dialog" aria-modal="true" aria-label="บันทึกติดตาม NCD"><button type="button" data-nf-close style="float:right">ปิด</button><h3>${esc(r.display_name)} · ${bp?'Home BP':'DTX ซ้ำ'}</h3><p>${esc(caseState(r))}</p><small>ค่าเดิม ${bp?esc(r.sbp)+'/'+esc(r.dbp):esc(r.glucose_mg_dl)+' mg/dL'} · ${esc(r.screened_on)} · ช่องใหม่ไม่เติมผลเดิม</small><form><label>วันที่วัดจริง<input name="day" type="date" value="${today()}" min="${new Date(Date.parse(r.screened_on+'T00:00:00Z')+86400000).toISOString().slice(0,10)}" max="${today()}" required></label>${bp?`<div class="nf-row"><label><input type="radio" name="period" value="morning" required> เช้า</label><label><input type="radio" name="period" value="evening"> เย็น</label></div><p data-nf-slot>เลือกช่วงวัด · ครั้งที่ 1 และ 2 กรอกทีละครั้ง</p><div class="nf-grid"><label>ความดันบน<input name="sbp" type="number" min="70" max="260" required inputmode="numeric"></label><label>ความดันล่าง<input name="dbp" type="number" min="40" max="180" required inputmode="numeric"></label></div><label>ชีพจร ครั้ง/นาที<input name="pulse" type="number" min="20" max="250" required inputmode="numeric"></label>`:`<label>DTX mg/dL<input name="dtx" type="number" min="20" max="700" required inputmode="numeric"></label><div class="nf-row"><label><input type="radio" name="fasting" value="yes" required> งดอาหารแล้วอย่างน้อย 8 ชม.</label><label><input type="radio" name="fasting" value="no"> ไม่ได้งดอาหาร</label></div><small>ผลนี้เป็น DTX ภาคสนาม · FPG ให้เจ้าหน้าที่ดำเนินการต่อ</small>`}<p class="nf-warn" data-nf-warning hidden></p><p class="nf-error" data-nf-error role="alert"></p><div class="nf-actions"><label><input type="checkbox" name="confirm" required> ตรวจสอบผลที่วัดจริงแล้ว</label><button type="submit" class="nf-primary">บันทึกและกลับรายชื่อ</button></div></form><details class="nf-history"><summary>ประวัติภาคสนาม (${r.measurements.length} ครั้ง)</summary>${r.measurements.map(m=>`<p>${esc(m.measured_on)} · ${bp?(m.period==='morning'?'เช้า':'เย็น')+' ครั้งที่ '+esc(m.sequence)+' · '+esc(m.sbp)+'/'+esc(m.dbp)+' · ชีพจร '+esc(m.pulse):'DTX '+esc(m.dtx)+' · '+(m.fasting?'งดอาหาร':'ไม่งดอาหาร')}</p>`).join('')||'<p>ยังไม่มีผลติดตาม</p>'}</details></section>`;document.body.append(overlay);const f=overlay.querySelector('form'),error=overlay.querySelector('[data-nf-error]'),warn=overlay.querySelector('[data-nf-warning]'),button=f.querySelector('[type=submit]');overlay.querySelector('[data-nf-close]').onclick=()=>{if(!saving)overlay.remove()};
 const sequence=()=>{const filled=new Set(r.measurements.filter(m=>m.measured_on===f.elements.day.value&&m.period===f.elements.period?.value).map(m=>m.sequence));return !filled.has(1)?1:!filled.has(2)?2:0;};
 f.oninput=()=>{if(!saving)requestId=crypto.randomUUID();warningKey='';warn.hidden=true;if(bp){const slot=sequence();overlay.querySelector('[data-nf-slot]').textContent=slot?'กำลังบันทึกครั้งที่ '+slot+' ของช่วงนี้':'ช่วงนี้ครบ 2 ครั้งแล้ว กรุณาตรวจประวัติ';}};
 f.onsubmit=async e=>{e.preventDefault();if(saving||!f.reportValidity())return;error.textContent='';const n=name=>Number(f.elements[name].value),seq=bp?sequence():null;if(bp&&(n('sbp')<=n('dbp')||!seq)){error.textContent=!seq?'ช่วงนี้บันทึกครบแล้ว':'ความดันบนต้องมากกว่าความดันล่าง';return;}
 const abnormal=bp?(n('sbp')>=180||n('dbp')>=110||n('sbp')<90||n('dbp')<60||n('pulse')<50||n('pulse')>120):(n('dtx')<70||n('dtx')>=200||(f.elements.fasting.value==='yes'&&n('dtx')>=126));const signature=JSON.stringify([...new FormData(f)]);if(abnormal&&warningKey!==signature){warn.hidden=false;warn.textContent='ค่าผิดปกติ กรุณาตรวจวัดซ้ำและประสานเจ้าหน้าที่ หากตรวจค่าถูกต้องแล้วให้กดบันทึกอีกครั้ง';warningKey=signature;return;}
 saving=true;button.disabled=true;button.textContent='กำลังบันทึก…';const payload={p_source_screen_id:r.source_screen_id,p_kind:r.kind,p_measured_on:f.elements.day.value,p_request_id:requestId,...(bp?{p_sbp:n('sbp'),p_dbp:n('dbp'),p_pulse:n('pulse'),p_period:f.elements.period.value,p_sequence:seq}:{p_dtx:n('dtx'),p_fasting:f.elements.fasting.value==='yes'})};
 const inputs=[...f.querySelectorAll('input')];
 inputs.forEach(input=>{input.disabled=true;});
 try{
   const result=await client.rpc('save_ncd_field_result_v2203',payload);
   if(result.error)throw result.error;
   const measurement={
     kind:payload.p_kind,measured_on:payload.p_measured_on,period:payload.p_period,
     sequence:payload.p_sequence,sbp:payload.p_sbp,dbp:payload.p_dbp,pulse:payload.p_pulse,
     dtx:payload.p_dtx,fasting:payload.p_fasting
   };
   overlay.remove();
   onSaved([...r.measurements,measurement]);
 }catch(err){
   error.textContent=String(err.code)==='23505'?'มีผลวัน/ช่วงนี้แล้ว กรุณาปิดแล้วเปิดรายการนี้ใหม่':String(err.message||'').includes('DATE_INVALID')?'ผลติดตามต้องเป็นวันถัดจากคัดกรอง และไม่เกินวันนี้':'บันทึกไม่สำเร็จ ข้อมูลที่กรอกยังอยู่ กดอีกครั้งเพื่อทดลองใหม่';
 }finally{
   saving=false;
   inputs.forEach(input=>{input.disabled=false;});
   button.disabled=false;
   button.textContent='บันทึกและกลับรายชื่อ';
 }};

}
export async function initNcdFieldFollowup2203(url,key){if(started)return;started=true;client=await getSharedSupabase(url,key);styles();const activate=()=>{const stats=document.querySelector('#stats');if(stats&&!stats.querySelector('[data-nf-launch]')){const b=document.createElement('button');b.dataset.nfLaunch='';b.className='nf-primary';b.textContent='ติดตาม Home BP / DTX ภาคสนาม';b.onclick=()=>{const modal=document.createElement('div');modal.className='nf-overlay';modal.innerHTML='<section class="nf-dialog"><button data-nf-list-close>ปิด / กลับหน้าหลัก</button><div data-nf-container></div></section>';document.body.append(modal);modal.querySelector('[data-nf-list-close]').onclick=()=>modal.remove();mount(modal.querySelector('[data-nf-container]'),client);};stats.prepend(b);}};bindPortalActivation('overview',activate);let pending=false;new MutationObserver(()=>{if(pending)return;pending=true;queueMicrotask(()=>{pending=false;activate();});}).observe(document.body,{childList:true,subtree:true});client.auth?.onAuthStateChange?.(e=>{if(e==='SIGNED_OUT'){invalidateShared('ncd-field-page:');document.querySelectorAll('.nf-overlay').forEach(n=>n.remove());}});}


export async function mountNcdFollowupList(parent,supabaseClient){styles();return mount(parent,supabaseClient);}