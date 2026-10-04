'use strict';
window.AppointmentNoticeFailover={
  async mount(){
    const host=document.getElementById('an-failover-panel');
    if(!host)return;
    const pct=x=>Number(x||0).toFixed(1)+'%';
    const qtext=o=>{
      if(!o)return '—';
      if(o.quota_type==='limited')return num(o.used||0)+' / '+num(o.limit||0)+' · เหลือ '+num(o.remaining||0);
      return o.quota_type==='unlimited'?'ไม่จำกัด':'—';
    };
    const stateLabel=s=>({
      primary:'ใช้ OA หลัก',
      warning:'เตือนโควตา OA หลัก',
      failover:'เริ่มใช้ OA สำรองสำหรับผู้ที่พร้อม',
      primary_exhausted:'OA หลักโควตาหมด',
      primary_unavailable:'OA หลักไม่พร้อม'
    }[s]||s||'—');
    const badge=(text,kind='')=>'<span class="badge '+kind+'">'+esc(text)+'</span>';

    const render=async()=>{
      host.innerHTML='<div class="empty">กำลังตรวจโควตา LINE OA…</div>';
      try{
        const d=await api('/appointment-notices/failover/status');
        const c=d.config||{},p=d.primary||{},b=d.backup||{},v=d.coverage||{};
        host.innerHTML=`
          <div class="panel-head notice-failover-head">
            <div>
              <h3>Multi-OA Failover</h3>
              <p class="muted">ตรวจโควตาก่อนส่งทุกครั้ง · OA สำรองใช้เฉพาะผู้รับที่ PID mapping ตรงและ verified</p>
            </div>
            <div>${badge(stateLabel(d.state),d.state==='primary'?'good':d.state==='warning'?'warn':'')}</div>
          </div>
          <div class="notice-oa-grid">
            <article>
              <div class="notice-oa-title"><strong>OA หลัก</strong>${p.ready?badge('พร้อม','good'):badge('ไม่พร้อม','warn')}</div>
              <div class="notice-oa-id">${esc(p.basic_id||'—')}</div>
              <div class="notice-oa-quota">${esc(qtext(p))}</div>
              <div class="notice-oa-meter"><span style="width:${Math.min(100,Number(p.usage_pct||0))}%"></span></div>
              <small>ใช้ ${esc(pct(p.usage_pct))}</small>
            </article>
            <article>
              <div class="notice-oa-title"><strong>OA สำรอง</strong>${b.ready?badge('พร้อม','good'):badge('ไม่พร้อม','warn')}</div>
              <div class="notice-oa-id">${esc(b.basic_id||'—')}</div>
              <div class="notice-oa-quota">${esc(qtext(b))}</div>
              <div class="notice-oa-meter"><span style="width:${Math.min(100,Number(b.usage_pct||0))}%"></span></div>
              <small>ใช้ ${esc(pct(b.usage_pct))}</small>
            </article>
            <article>
              <div class="notice-oa-title"><strong>Backup coverage</strong></div>
              <div class="notice-oa-coverage"><b>${num(v.dual_ready_volunteers||0)}</b> / ${num(v.volunteers_total||0)} อสม.</div>
              <div class="notice-oa-coverage"><b>${num(v.dual_ready_staff||0)}</b> / ${num(v.staff_total||0)} Staff</div>
              <small>${num(v.dual_not_ready_volunteers||0)} อสม. ยังไม่พร้อมทั้ง Primary + Backup</small>
            </article>
          </div>
          <div class="notice-failover-settings">
            <label class="notice-auto-toggle"><input type="checkbox" id="fo-enabled" ${d.enabled?'checked':''}><span>เปิด Multi-OA Failover</span></label>
            <label class="notice-auto-toggle"><input type="checkbox" id="fo-backup" ${d.backup_enabled?'checked':''}><span>อนุญาต OA สำรอง</span></label>
            <label>เตือนเมื่อใช้ถึง<input type="number" id="fo-warn" min="50" max="99" value="${Number(c.warn_usage_pct||90)}"><span>%</span></label>
            <label>เริ่ม failover<input type="number" id="fo-cut" min="60" max="100" value="${Number(c.failover_usage_pct||95)}"><span>%</span></label>
            <label>สำรองโควตา OA หลัก<input type="number" id="fo-reserve" min="0" max="1000" value="${Number(c.primary_reserve||15)}"><span>ข้อความ</span></label>
          </div>
          <div class="actions"><button type="button" class="primary" id="fo-save">บันทึกนโยบาย</button><button type="button" class="secondary" id="fo-refresh">รีเฟรชโควตา</button></div>
          <div class="notice-auto-note">
            ถ้า OA หลักถึงเกณฑ์หรือโควตาไม่พอ ระบบจะสลับเฉพาะผู้รับที่มี backup mapping ยืนยันแล้ว
            ส่วนผู้ที่ยังไม่มี mapping จะคงใช้ OA หลักเท่าที่โควตาเหลือ และจะไม่เดา LINE ID ข้าม OA
          </div>`;
        document.getElementById('fo-refresh').onclick=render;
        document.getElementById('fo-save').onclick=async()=>{
          const body={
            enabled:document.getElementById('fo-enabled').checked,
            backup_enabled:document.getElementById('fo-backup').checked,
            warn_usage_pct:Number(document.getElementById('fo-warn').value||90),
            failover_usage_pct:Number(document.getElementById('fo-cut').value||95),
            primary_reserve:Number(document.getElementById('fo-reserve').value||15)
          };
          try{
            await api('/appointment-notices/failover/settings',{method:'POST',body:JSON.stringify(body)});
            toast('บันทึก Multi-OA Failover แล้ว');
            await render();
          }catch(e){toast(e.message);}
        };
      }catch(e){
        host.innerHTML='<div class="empty">'+esc(e.message)+'</div>';
      }
    };
    await render();
  }
};