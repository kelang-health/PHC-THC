'use strict';
window.AppointmentNoticePhase33={
  async mount(){
    const host=document.getElementById('an-rollout-panel');
    if(!host)return;
    let data=null;
    let community='';
    const badge=(text,kind='')=>'<span class="badge '+kind+'">'+esc(text)+'</span>';
    const statusBadge=s=>({
      dual_ready:badge('พร้อม 2 OA','good'),
      assisted:badge('ช่วยเชื่อมแล้ว','warn'),
      invited:badge('เชิญแล้ว','warn'),
      pending:badge('รอดำเนินการ','')
    }[s]||badge(s||'—'));
    const pct=v=>Number(v||0).toFixed(1)+'%';

    const render=async()=>{
      host.innerHTML='<div class="empty">กำลังโหลด Operational Rollout…</div>';
      try{
        const q=community?'?community='+encodeURIComponent(community):'';
        data=await api('/appointment-notices/failover/rollout'+q);
        const s=data.summary||{},comms=data.communities||[],rows=data.rows||[],o=data.onboarding||{},hist=data.history||[];
        host.innerHTML=`
          <div class="panel-head">
            <div>
              <h3>Operational Onboarding Rollout</h3>
              <p class="muted">ติดตามการเชื่อม OA สำรองจริง · สถานะพร้อม 2 OA มาจาก mapping เท่านั้น</p>
            </div>
            <div>${Number(s.dual_pct||0)>=90?badge('Coverage ≥90%','good'):badge('Coverage '+pct(s.dual_pct),'warn')}</div>
          </div>

          <div class="notice-rollout-grid">
            <article><strong>${num(s.dual_ready||0)}</strong><span>พร้อม 2 OA</span><small>${pct(s.dual_pct)} ของ ${num(s.volunteers_total||0)} คน</small></article>
            <article><strong>${num(s.pending||0)}</strong><span>รอดำเนินการ</span><small>ยังไม่ได้เชิญ/ช่วยเชื่อม</small></article>
            <article><strong>${num(s.invited||0)}</strong><span>เชิญแล้ว</span><small>รอผู้ใช้เชื่อม Backup</small></article>
            <article><strong>${num(s.assisted||0)}</strong><span>ช่วยเชื่อมแล้ว</span><small>รอ mapping verified</small></article>
            <article><strong>${num(s.today_touched||0)}</strong><span>ดำเนินการวันนี้</span><small>มีการเปลี่ยนสถานะวันนี้</small></article>
          </div>

          <div class="notice-rollout-toolbar">
            <label>ชุมชน
              <select id="p33-community">
                <option value="">ทุกชุมชน</option>
                ${(comms||[]).map(c=>'<option value="'+esc(c.community)+'" '+(c.community===community?'selected':'')+'>'+esc(c.community)+' · พร้อม '+num(c.dual_ready)+'/'+num(c.total)+'</option>').join('')}
              </select>
            </label>
            <button type="button" class="secondary" id="p33-refresh">รีเฟรช</button>
            <button type="button" class="secondary" id="p33-snapshot">บันทึก Snapshot วันนี้</button>
            <button type="button" class="secondary" id="p33-print">พิมพ์ชุดลงพื้นที่</button>
          </div>

          <div class="notice-rollout-print-head">
            <img src="${esc(o.qr_asset||'')}" alt="QR OA สำรอง">
            <div>
              <h3>ชุดลงพื้นที่เชื่อม LINE OA สำรอง ${esc(o.backup_basic_id||'')}</h3>
              <p>${community?esc(community):'ทุกชุมชน'} · สแกน QR → เพิ่มเพื่อน → ส่ง “ลงทะเบียน” → ยืนยันตัวตน → กลับมาตรวจสถานะ</p>
            </div>
          </div>

          <div class="table-wrap notice-rollout-community">
            <table><thead><tr><th>ชุมชน</th><th>ทั้งหมด</th><th>พร้อม 2 OA</th><th>Coverage</th><th>คงเหลือ</th><th>เชิญแล้ว</th><th>ช่วยเชื่อมแล้ว</th></tr></thead>
            <tbody>${comms.length?comms.map(c=>`<tr><td><strong>${esc(c.community)}</strong></td><td>${num(c.total)}</td><td>${num(c.dual_ready)}</td><td>${pct(c.dual_pct)}</td><td>${num(c.remaining)}</td><td>${num(c.invited)}</td><td>${num(c.assisted)}</td></tr>`).join(''):'<tr><td colspan="7" class="empty">ไม่มีข้อมูล</td></tr>'}</tbody></table>
          </div>

          <div class="notice-rollout-actions">
            <button type="button" class="secondary" id="p33-select-drill">เลือก Drill 1 คน/ชุมชน</button>
            <button type="button" class="primary" id="p33-run-drill">Controlled Failover Drill (Dry-run)</button>
            <span class="muted">สูงสุด 2 คน/ชุมชน · ไม่มีการส่ง LINE จริง</span>
          </div>

          <div class="table-wrap notice-rollout-people">
            <table>
              <thead><tr><th>Drill</th><th>อสม.</th><th>ชุมชน</th><th>หมู่</th><th>Primary</th><th>Backup</th><th>สถานะ rollout</th><th>ดำเนินการ</th></tr></thead>
              <tbody id="p33-rows">${rows.length?rows.map(r=>`
                <tr>
                  <td>${r.dual_ready?'<input type="checkbox" class="p33-drill" value="'+num(r.volunteer_id)+'" aria-label="เลือก Drill">':'—'}</td>
                  <td><strong>${esc(r.name||'—')}</strong>${r.is_staff?'<br><small>Staff</small>':''}</td>
                  <td>${esc(r.community||'—')}</td>
                  <td>${esc(r.moo||'—')}</td>
                  <td>${r.primary_ready?badge('พร้อม','good'):badge('ไม่พร้อม','warn')}</td>
                  <td>${r.backup_ready?badge('พร้อม','good'):badge('ไม่พร้อม','warn')}</td>
                  <td>${statusBadge(r.rollout_status)}${r.last_action_at?'<br><small>'+esc(r.last_action_at)+'</small>':''}</td>
                  <td>${r.dual_ready?'mapping verified':`
                    <select class="p33-status" data-id="${num(r.volunteer_id)}">
                      <option value="pending" ${r.rollout_status==='pending'?'selected':''}>รอดำเนินการ</option>
                      <option value="invited" ${r.rollout_status==='invited'?'selected':''}>เชิญแล้ว</option>
                      <option value="assisted" ${r.rollout_status==='assisted'?'selected':''}>ช่วยเชื่อมแล้ว</option>
                    </select>`}
                  </td>
                </tr>`).join(''):'<tr><td colspan="8" class="empty">ไม่มีข้อมูล</td></tr>'}</tbody>
            </table>
          </div>

          <div class="notice-rollout-history">
            <h4>ความคืบหน้ารายวัน</h4>
            ${hist.length?'<div class="table-wrap"><table><thead><tr><th>วันที่</th><th>พร้อม 2 OA</th><th>Coverage</th><th>รอดำเนินการ</th><th>เชิญแล้ว</th><th>ช่วยเชื่อมแล้ว</th><th>Gap 90%</th></tr></thead><tbody>'+
              hist.slice(-10).reverse().map(h=>`<tr><td>${esc(h.date||'')}</td><td>${num(h.dual_ready||0)}</td><td>${pct(h.dual_pct)}</td><td>${num(h.pending||0)}</td><td>${num(h.invited||0)}</td><td>${num(h.assisted||0)}</td><td>${num(h.gap_to_90||0)}</td></tr>`).join('')+
              '</tbody></table></div>':'<p class="muted">ยังไม่มี snapshot รายวัน</p>'}
          </div>`;

        document.getElementById('p33-community').onchange=async e=>{community=e.target.value;await render();};
        document.getElementById('p33-refresh').onclick=render;
        document.getElementById('p33-snapshot').onclick=async()=>{
          try{await api('/appointment-notices/failover/rollout/snapshot',{method:'POST',body:'{}'});toast('บันทึก Snapshot วันนี้แล้ว');await render();}catch(e){toast(e.message);}
        };
        document.getElementById('p33-print').onclick=()=>{
          document.body.classList.add('print-rollout');
          const cleanup=()=>document.body.classList.remove('print-rollout');
          window.addEventListener('afterprint',cleanup,{once:true});
          window.print();
          setTimeout(cleanup,1500);
        };
        document.querySelectorAll('.p33-status').forEach(el=>{
          el.onchange=async()=>{
            const body={volunteer_id:Number(el.dataset.id),status:el.value};
            try{await api('/appointment-notices/failover/rollout/status',{method:'POST',body:JSON.stringify(body)});toast('บันทึกสถานะแล้ว');await render();}catch(e){toast(e.message);}
          };
        });
        document.getElementById('p33-select-drill').onclick=()=>{
          const picked=new Set();
          document.querySelectorAll('.p33-drill').forEach(cb=>{
            const row=rows.find(r=>Number(r.volunteer_id)===Number(cb.value));
            const key=(row&&row.community)||'';
            if(!picked.has(key)){cb.checked=true;picked.add(key);}else cb.checked=false;
          });
          toast('เลือกผู้พร้อม 1 คนต่อชุมชนแล้ว');
        };
        document.getElementById('p33-run-drill').onclick=async()=>{
          const ids=[...document.querySelectorAll('.p33-drill:checked')].map(x=>Number(x.value));
          if(!ids.length){toast('กรุณาเลือกผู้พร้อม 2 OA อย่างน้อย 1 คน');return;}
          if(!confirm('รัน Controlled Failover Drill แบบ Dry-run '+num(ids.length)+' คน\nไม่มีการส่ง LINE จริง'))return;
          try{
            const r=await api('/appointment-notices/failover/drill',{method:'POST',body:JSON.stringify({volunteer_ids:ids})});
            const lines=['Controlled Drill: '+(r.status||'—'),'ทดสอบ '+num(r.selected_count||0)+' คน','ผ่าน '+num(r.passed||0)+' · ไม่ผ่าน '+num(r.failed||0),'ส่ง LINE จริง: '+(r.live_message_sent?'ใช่':'ไม่')];
            (r.results||[]).forEach(x=>lines.push('• '+(x.name||'อสม.')+' · '+(x.community||'')+' · '+(x.status||'—')));
            alert(lines.join('\n'));
          }catch(e){toast(e.message);}
        };
      }catch(e){host.innerHTML='<div class="empty">'+esc(e.message)+'</div>';}
    };
    await render();
  }
};