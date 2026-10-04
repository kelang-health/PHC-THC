'use strict';
window.AppointmentNoticePhase36={
  async mount(){
    const host=document.getElementById('an-osm-bridge-panel');
    if(!host)return;
    let data=null;
    let role='staff',conversion='all',community='',search='';
    const badge=(text,kind)=>'<span class="badge '+(kind||'')+'">'+esc(text)+'</span>';
    const pct=v=>Number(v||0).toFixed(1)+'%';
    const roleLabel=r=>({staff:'Staff',chair:'ประธาน อสม.',vhv:'อสม.ทั่วไป',all:'ทั้งหมด'}[r]||r||'—');
    const convLabel=s=>({
      ready_to_invite:'พร้อมส่งคำเชิญ',
      invited_active:'คำเชิญยังใช้ได้',
      expired_wait:'ลิงก์หมดอายุ รอครบ 12 ชม.',
      resend_ready:'พร้อมส่งใหม่',
      dual_ready:'เชื่อมสำเร็จ',
      fallback_registration:'Fallback registration',
      primary_link_unusable:'OSM link ใช้ไม่ได้'
    }[s]||s||'—');
    const convKind=s=>s==='dual_ready'?'good':(s==='fallback_registration'||s==='primary_link_unusable'||s==='expired_wait'?'warn':'');
    const roleMatch=r=>{
      if(role==='all')return true;
      if(role==='staff')return !!r.is_staff;
      if(role==='chair')return !!r.is_chair;
      return !r.is_staff&&!r.is_chair;
    };
    const visibleRows=()=>{
      const q=search.trim().toLocaleLowerCase('th');
      return (data.rows||[]).filter(r=>{
        if(!roleMatch(r))return false;
        if(conversion!=='all'&&r.conversion_state!==conversion)return false;
        if(community&&r.community!==community)return false;
        if(q&&!String(r.name||'').toLocaleLowerCase('th').includes(q))return false;
        return true;
      });
    };
    const selectable=r=>r.bridge_sendable&&['ready_to_invite','resend_ready'].includes(r.conversion_state);

    const render=()=>{
      const summaries=data.role_summary||{},totals=data.conversion_totals||{},policy=data.policy||{},sf=data.staff_first||{},p=data.primary_quota||{},rows=visibleRows();
      const staff=summaries.staff||{},chair=summaries.chair||{},vhv=summaries.vhv||{},all=summaries.all||{};
      let html='';
      html+='<div class="panel-head"><div><h3>Staff-first Controlled Rollout</h3><p class="muted">ให้ Staff พร้อม OA สำรองก่อน แล้วค่อยขยายประธาน อสม.และ อสม.ทั่วไป · ไม่มี Auto Send</p></div><div>'+badge('Staff-first','good')+' '+badge('Admin Confirm','')+'</div></div>';
      html+='<div class="notice-role-grid">';
      [
        ['Staff',staff,'100%'],
        ['ประธาน อสม.',chair,'100%'],
        ['อสม.ทั่วไป',vhv,'90%'],
        ['ทั้งหมด',all,'90%']
      ].forEach(x=>{
        const a=x[1];
        html+='<article><strong>'+num(a.dual_ready||0)+'/'+num(a.total||0)+'</strong><span>'+esc(x[0])+'</span><small>Coverage '+pct(a.dual_pct)+' · เป้า '+x[2]+' · ขาด '+num(a.gap_to_target||0)+'</small></article>';
      });
      html+='</div>';

      html+='<div class="notice-conversion-grid">';
      [
        ['พร้อมส่ง',totals.ready_to_invite||0,''],
        ['คำเชิญยังใช้ได้',totals.invited_active||0,''],
        ['หมดอายุรอ',totals.expired_wait||0,'warn'],
        ['พร้อมส่งใหม่',totals.resend_ready||0,''],
        ['เชื่อมสำเร็จ',totals.dual_ready||0,'good'],
        ['Fallback',totals.fallback_registration||0,'warn']
      ].forEach(x=>{html+='<article class="'+(x[2]==='warn'?'notice-risk-card':'')+'"><strong>'+num(x[1])+'</strong><span>'+esc(x[0])+'</span></article>';});
      html+='</div>';

      html+='<div class="notice-staff-summary">';
      html+='<strong>Staff ปัจจุบัน:</strong> พร้อม 2 OA '+num(staff.dual_ready||0)+'/'+num(staff.total||0)+' · พร้อมส่งคำเชิญ '+num(staff.ready_to_invite||0)+' · Fallback '+num(staff.fallback_registration||0)+' · เป้าหมาย 100%';
      html+='<span>'+badge('OA หลักเหลือ '+num(p.remaining||0),'good')+'</span></div>';

      if(Number(sf.chair_count||0)===0){
        html+='<div class="notice-alert warning"><strong>ประธาน อสม.</strong><span>ยังไม่มีการกำหนดประธานแบบ explicit ในระบบ จึงแสดง 0 และไม่เดารายชื่อแทน</span></div>';
      }

      html+='<div class="notice-role-toolbar">';
      html+='<label>กลุ่มผู้รับ<select id="p36-role">';
      ['staff','chair','vhv','all'].forEach(v=>{html+='<option value="'+v+'" '+(role===v?'selected':'')+'>'+roleLabel(v)+'</option>';});
      html+='</select></label>';
      html+='<label>Conversion<select id="p36-conv"><option value="all">ทุกสถานะ</option>';
      ['ready_to_invite','invited_active','expired_wait','resend_ready','dual_ready','fallback_registration','primary_link_unusable'].forEach(v=>{html+='<option value="'+v+'" '+(conversion===v?'selected':'')+'>'+convLabel(v)+'</option>';});
      html+='</select></label>';
      html+='<label>ชุมชน<select id="p36-community"><option value="">ทุกชุมชน</option>';
      (data.communities||[]).forEach(c=>{html+='<option value="'+esc(c)+'" '+(community===c?'selected':'')+'>'+esc(c)+'</option>';});
      html+='</select></label>';
      html+='<label>ค้นหา<input id="p36-search" type="search" value="'+esc(search)+'" placeholder="ชื่อ อสม./Staff"></label>';
      html+='</div>';

      html+='<div class="notice-role-actions">';
      html+='<button type="button" class="secondary" id="p36-select-staff">เลือก Staff พร้อมเชื่อมทั้งหมด ('+num(sf.staff_priority_count||0)+')</button>';
      html+='<button type="button" class="secondary" id="p36-select-visible">เลือกที่พร้อมในมุมมอง</button>';
      html+='<button type="button" class="secondary" id="p36-clear">ล้างการเลือก</button>';
      html+='<button type="button" class="secondary" id="p36-dry">ตรวจสอบ Dry-run</button>';
      html+='<button type="button" class="primary" id="p36-send">ส่งคำเชิญที่เลือก</button>';
      html+='<span class="muted" id="p36-selected">เลือก 0 คน</span></div>';

      html+='<div class="table-wrap notice-role-table"><table><thead><tr><th>เลือก</th><th>บทบาท</th><th>ชื่อ</th><th>ชุมชน</th><th>OSM OA</th><th>Backup</th><th>Conversion</th><th>เชิญล่าสุด</th></tr></thead><tbody>';
      if(rows.length){
        rows.forEach(r=>{
          html+='<tr><td>'+(selectable(r)?'<input type="checkbox" class="p36-pick" value="'+num(r.volunteer_id)+'">':'—')+'</td>';
          html+='<td>'+(r.is_staff?badge('Staff','good'):'')+(r.is_chair?' '+badge('ประธาน',''):(r.is_staff?'':badge('อสม.','')))+'</td>';
          html+='<td><strong>'+esc(r.name||'—')+'</strong></td><td>'+esc(r.community||'—')+'</td>';
          html+='<td>'+(r.primary_ready?badge('พร้อม','good'):badge('ไม่พร้อม','warn'))+'</td>';
          html+='<td>'+(r.backup_ready?badge('พร้อม','good'):badge('ยัง',''))+'</td>';
          html+='<td>'+badge(convLabel(r.conversion_state),convKind(r.conversion_state))+'</td>';
          html+='<td>'+(r.last_invited_at?esc(r.last_invited_at):'—')+'</td></tr>';
        });
      }else html+='<tr><td colspan="8" class="empty">ไม่มีข้อมูลตามตัวกรอง</td></tr>';
      html+='</tbody></table></div>';
      host.innerHTML=html;

      const updateSelected=()=>{document.getElementById('p36-selected').textContent='เลือก '+num(document.querySelectorAll('.p36-pick:checked').length)+' คน';};
      document.querySelectorAll('.p36-pick').forEach(x=>x.onchange=updateSelected);
      document.getElementById('p36-role').onchange=e=>{role=e.target.value;render();};
      document.getElementById('p36-conv').onchange=e=>{conversion=e.target.value;render();};
      document.getElementById('p36-community').onchange=e=>{community=e.target.value;render();};
      document.getElementById('p36-search').onchange=e=>{search=e.target.value.trim();render();};
      document.getElementById('p36-select-staff').onclick=()=>{
        role='staff';conversion='all';community='';search='';render();
        const wanted=new Set((sf.staff_priority_ids||[]).map(Number));
        document.querySelectorAll('.p36-pick').forEach(cb=>{cb.checked=wanted.has(Number(cb.value));});
        updateSelected();
      };
      document.getElementById('p36-select-visible').onclick=()=>{
        let n=0;
        document.querySelectorAll('.p36-pick').forEach(cb=>{if(n<Number(policy.max_batch||50)){cb.checked=true;n++;}});
        updateSelected();
      };
      document.getElementById('p36-clear').onclick=()=>{document.querySelectorAll('.p36-pick').forEach(cb=>cb.checked=false);updateSelected();};
      const picked=()=>Array.from(document.querySelectorAll('.p36-pick:checked')).map(x=>Number(x.value));
      const run=async dry=>{
        const ids=picked();
        if(!ids.length){toast('กรุณาเลือกผู้รับอย่างน้อย 1 คน');return;}
        if(!dry&&!confirm('ส่งคำเชิญจริงผ่าน OSM OA '+num(ids.length)+' คน\nเน้น Staff-first · ต้องกดเชื่อม OA สำรองภายใน 30 นาที\n\nยืนยันส่งหรือไม่?'))return;
        try{
          const r=await api('/appointment-notices/failover/osm-bridge/invite',{method:'POST',body:JSON.stringify({volunteer_ids:ids,dry_run:dry,allow_resend:false})});
          const lines=[dry?'Staff-first Dry-run':'ส่งคำเชิญ Staff-first','เลือก '+num(r.selected||0)+' คน','พร้อม '+num(r.ready||0),'บล็อก '+num(r.blocked||0),'ส่งจริง '+num(r.sent||0)];
          (r.results||[]).slice(0,20).forEach(x=>lines.push('• '+(x.name||('ID '+x.volunteer_id))+' · '+(x.community||'')+' · '+(x.status||'—')+(x.reason?' · '+x.reason:'')));
          alert(lines.join('\n'));
          if(!dry)await load();
        }catch(e){toast(e.message);}
      };
      document.getElementById('p36-dry').onclick=()=>run(true);
      document.getElementById('p36-send').onclick=()=>run(false);
    };
    const load=async()=>{
      host.innerHTML='<div class="empty">กำลังโหลด Staff-first Conversion Dashboard…</div>';
      try{data=await api('/appointment-notices/failover/staff-first');render();}
      catch(e){host.innerHTML='<div class="empty">'+esc(e.message)+'</div>';}
    };
    await load();
  }
};