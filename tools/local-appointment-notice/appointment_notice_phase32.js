'use strict';
window.AppointmentNoticePhase32={
  async mount(){
    const coverageHost=document.getElementById('an-onboarding-panel');
    const forecastHost=document.getElementById('an-forecast-panel');
    if(!coverageHost||!forecastHost)return;

    const badge=(text,kind='')=>'<span class="badge '+kind+'">'+esc(text)+'</span>';
    const pct=v=>Number(v||0).toFixed(1)+'%';
    const fmtDT=s=>s?date(s):'—';

    let coverageData=null;
    const renderCoverage=async()=>{
      coverageHost.innerHTML='<div class="empty">กำลังตรวจ Backup coverage…</div>';
      try{
        coverageData=await api('/appointment-notices/failover/coverage');
        const s=coverageData.summary||{};
        const o=coverageData.onboarding||{};
        const comms=coverageData.communities||[];
        const rows=coverageData.rows||[];
        coverageHost.innerHTML=`
          <div class="panel-head">
            <div>
              <h3>Backup Coverage Onboarding</h3>
              <p class="muted">เป้าหมายคือให้อสม.มีทั้ง Primary และ Backup ที่ยืนยันตัวตนแล้ว ก่อนพึ่ง failover ในวงกว้าง</p>
            </div>
            <div>${s.dual_pct>=95?badge('พร้อม ≥95%','good'):s.dual_pct>=90?badge('ผ่านขั้นต่ำ ≥90%','good'):badge('ยังต่ำกว่า 90%','warn')}</div>
          </div>

          <div class="notice-coverage-grid">
            <article><strong>${num(s.dual_ready||0)}</strong><span>พร้อมทั้ง 2 OA</span><small>${pct(s.dual_pct)} ของ ${num(s.volunteers_total||0)} อสม.</small></article>
            <article><strong>${num(s.target_90||0)}</strong><span>เป้าขั้นต่ำ 90%</span><small>ขาดอีก ${num(s.gap_to_90||0)} คน</small></article>
            <article><strong>${num(s.target_95||0)}</strong><span>เป้าหมาย 95%</span><small>ขาดอีก ${num(s.gap_to_95||0)} คน</small></article>
            <article><strong>${num(s.staff_dual_ready||0)}</strong><span>Staff พร้อม 2 OA</span><small>จาก ${num(s.staff_total||0)} คน</small></article>
          </div>

          <div class="notice-coverage-progress">
            <div><span>Coverage ปัจจุบัน</span><b>${pct(s.dual_pct)}</b></div>
            <div class="notice-coverage-meter"><span style="width:${Math.min(100,Number(s.dual_pct||0))}%"></span><i class="goal90"></i><i class="goal95"></i></div>
            <small>เส้น 90% = พร้อมใช้งานขั้นต่ำ · 95% = เป้าหมายใช้งานจริง</small>
          </div>

          <div class="notice-onboarding-box">
            <div class="notice-onboarding-qr">
              <img src="${esc(o.qr_asset||'')}" alt="QR เพิ่มเพื่อน LINE OA สำรอง">
              <strong>${esc(o.backup_basic_id||'')}</strong>
            </div>
            <div>
              <h4>เชื่อม OA สำรองครั้งเดียว</h4>
              <ol>${(o.steps||[]).map(x=>'<li>'+esc(x)+'</li>').join('')}</ol>
              <div class="actions">
                <a class="button primary" href="${esc(o.add_friend_url||'#')}" target="_blank" rel="noopener">เพิ่มเพื่อน OA สำรอง</a>
                <a class="button secondary" href="${esc(o.register_chat_url||'#')}" target="_blank" rel="noopener">เปิดแชต “ลงทะเบียน”</a>
                <button type="button" class="secondary" id="fo-coverage-refresh">ตรวจสถานะใหม่</button>
              </div>
              <p class="muted">หน้า OSM แสดงเฉพาะสถานะพร้อม/ไม่พร้อม ไม่เปิด CID, PID หรือ raw LINE user ID</p>
            </div>
          </div>

          <div class="notice-coverage-tools">
            <label>ชุมชน<select id="fo-community-filter"><option value="">ทุกชุมชน</option>${comms.map(c=>`<option value="${esc(c.community)}">${esc(c.community)} · ${num(c.dual_ready)}/${num(c.total)}</option>`).join('')}</select></label>
            <label>ค้นหา<input id="fo-search" type="search" placeholder="ชื่อ อสม."></label>
            <span class="muted" id="fo-filter-count"></span>
          </div>

          <div class="table-wrap notice-community-coverage">
            <table>
              <thead><tr><th>ชุมชน</th><th>อสม.</th><th>Primary</th><th>Backup</th><th>พร้อม 2 OA</th><th>ขาด</th></tr></thead>
              <tbody>${comms.map(c=>`<tr>
                <td><strong>${esc(c.community)}</strong></td>
                <td>${num(c.total)}</td>
                <td>${num(c.primary_ready)}</td>
                <td>${num(c.backup_ready)}</td>
                <td>${num(c.dual_ready)} <small>(${pct(c.dual_pct)})</small></td>
                <td>${num(c.gap)}</td>
              </tr>`).join('')}</tbody>
            </table>
          </div>

          <div class="table-wrap">
            <table>
              <thead><tr><th>ชื่อ อสม.</th><th>ชุมชน</th><th>หมู่</th><th>สิทธิ์</th><th>Primary</th><th>Backup</th><th>สถานะ</th></tr></thead>
              <tbody id="fo-coverage-rows"></tbody>
            </table>
          </div>`;

        const tbody=document.getElementById('fo-coverage-rows');
        const comm=document.getElementById('fo-community-filter');
        const search=document.getElementById('fo-search');
        const count=document.getElementById('fo-filter-count');
        const drawRows=()=>{
          const q=(search.value||'').trim().toLocaleLowerCase('th');
          const c=comm.value||'';
          const visible=rows.filter(r=>(!c||r.community===c)&&(!q||(r.name||'').toLocaleLowerCase('th').includes(q)));
          count.textContent='แสดง '+num(visible.length)+' / '+num(rows.length)+' คน';
          tbody.innerHTML=visible.length?visible.map(r=>{
            const state=r.dual_ready?badge('พร้อม 2 OA','good'):r.backup_ready?badge('Backup only','warn'):r.primary_ready?badge('ต้องเชื่อม Backup','warn'):badge('ยังไม่พร้อม','');
            return `<tr>
              <td><strong>${esc(r.name||'—')}</strong></td>
              <td>${esc(r.community||'—')}</td>
              <td>${esc(r.moo||'—')}</td>
              <td>${r.is_staff?badge('Staff','good'):badge('อสม.')}</td>
              <td>${r.primary_ready?badge('พร้อม','good'):badge('ไม่มี','warn')}</td>
              <td>${r.backup_ready?badge('พร้อม','good'):badge('ไม่มี','warn')}</td>
              <td>${state}</td>
            </tr>`;
          }).join(''):'<tr><td colspan="7" class="empty">ไม่พบรายการ</td></tr>';
        };
        comm.onchange=drawRows;
        search.oninput=drawRows;
        document.getElementById('fo-coverage-refresh').onclick=renderCoverage;
        drawRows();
      }catch(e){
        coverageHost.innerHTML='<div class="empty">'+esc(e.message)+'</div>';
      }
    };

    const riskBadge=r=>r==='critical'?badge('เสี่ยง','warn'):r==='warning'?badge('เฝ้าระวัง','warn'):badge('เพียงพอ','good');

    const renderForecast=async()=>{
      forecastHost.innerHTML='<div class="empty">กำลังคำนวณโควตานัดพรุ่งนี่…</div>';
      try{
        const [f,p]=await Promise.all([
          api('/appointment-notices/failover/forecast'),
          api('/appointment-notices/failover/preflight')
        ]);
        forecastHost.innerHTML=`
          <div class="panel-head">
            <div><h3>Quota Forecast ก่อน Auto D-1</h3><p class="muted">คำนวณจากกลุ่มผู้รับจริงที่ยังไม่เคยส่ง สำหรับ ${esc(f.target_date||'—')}</p></div>
            <div>${riskBadge(f.risk)}</div>
          </div>
          <div class="notice-forecast-grid">
            <article><strong>${num(f.appointments||0)}</strong><span>นัดหมาย</span><small>${num(f.people||0)} คน / ${num(f.houses||0)} บ้าน</small></article>
            <article><strong>${num(f.projected_groups||0)}</strong><span>กลุ่มผู้รับคาดว่าจะส่ง</span><small>อสม. ${num(f.vhv_groups||0)} · ชุมชน ${num(f.community_groups||0)}</small></article>
            <article><strong>${num(f.primary_groups||0)}</strong><span>คาดใช้ OA หลัก</span><small>เหลือ ${num((f.primary||{}).remaining||0)}</small></article>
            <article><strong>${num(f.backup_groups||0)}</strong><span>คาดใช้ OA สำรอง</span><small>เหลือ ${num((f.backup||{}).remaining||0)}</small></article>
            <article class="${Number(f.blocked_groups||0)>0?'notice-risk-card':''}"><strong>${num(f.blocked_groups||0)}</strong><span>กลุ่มที่อาจส่งไม่ได้</span><small>${esc(f.routing_state||'')}</small></article>
          </div>
          <div class="notice-auto-note"><strong>${esc(f.message||'')}</strong><br>
            Backup dual coverage ${pct((f.coverage||{}).dual_pct)} · เป้า 90% ${num((f.coverage||{}).target_90||0)} คน · ขาด ${num((f.coverage||{}).gap_to_90||0)} คน
          </div>
          <div class="actions">
            <button type="button" class="secondary" id="fo-forecast-refresh">คำนวณใหม่</button>
            <button type="button" class="primary" id="fo-preflight-run">รัน Preflight ตอนนี้</button>
          </div>
          <div class="notice-preflight-last">
            <h4>Preflight ล่าสุด 16:30</h4>
            ${p.available?`<p>${riskBadge(p.risk)} เป้าหมาย ${esc(p.target_date||'—')} · ${num(p.projected_groups||0)} กลุ่ม · blocked ${num(p.blocked_groups||0)} · ${esc(fmtDT(p.generated_at))}</p>`:'<p class="muted">ยังไม่มี ��ล Preflight ที่บันทึกไว้</p>'}
          </div>`;
        document.getElementById('fo-forecast-refresh').onclick=renderForecast;
        document.getElementById('fo-preflight-run').onclick=async()=>{
          try{
            const r=await api('/appointment-notices/failover/preflight',{method:'POST',body:'{}'});
            toast('บันทึก Preflight แล้ว: '+String(r.risk||'ok'));
            await renderForecast();
          }catch(e){toast(e.message);}
        };
      }catch(e){
        forecastHost.innerHTML='<div class="empty">'+esc(e.message)+'</div>';
      }
    };

    await Promise.all([renderCoverage(),renderForecast()]);
  }
};