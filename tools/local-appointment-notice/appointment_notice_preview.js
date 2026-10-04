'use strict';
window.AppointmentNoticePreview={
  async render(renderId){
    const host=$('#content');
    const iso=d=>new Date(d).toISOString().slice(0,10);
    const today=new Date();
    const plus=n=>{const d=new Date(today);d.setDate(d.getDate()+n);return iso(d);};
    const newNonce=()=>crypto.randomUUID();
    let state={
      from:iso(today),to:plus(6),community:'',volunteerId:0,
      data:null,selected:new Set(),sending:false
    };

    const shell=()=>{
      host.innerHTML=`
      <div class="welcome"><div><span class="eyebrow">PHASE 3.2 · BACKUP COVERAGE ONBOARDING</span><h2>แจ้งเตือนนัดหมาย อสม.</h2><p>Auto D-1 + Multi-OA พร้อมติดตาม coverage รายชุมชน, QR ลงทะเบียน และ quota forecast ก่อนส่ง</p></div><span class="badge good">Coverage + Forecast</span></div>
      <section class="panel" id="an-failover-panel"><div class="empty">กำลังตรวจโควตา LINE OA…</div></section>
      <section class="panel" id="an-onboarding-panel"><div class="empty">กำลังตรวจ Backup coverage…</div></section>
      <section class="panel" id="an-forecast-panel"><div class="empty">กำลังคำนวณ Quota Forecast…</div></section>
      <section class="panel" id="an-auto-panel"><div class="empty">กำลังโหลด Auto D-1…</div></section>
      <section class="notice-filter">
        <div class="quick-range">
          <button type="button" class="secondary" data-days="0">วันนี้</button>
          <button type="button" class="secondary" data-days="1">พรุ่งนี้</button>
          <button type="button" class="secondary" data-days="3">3 วัน</button>
          <button type="button" class="secondary" data-days="7">7 วัน</button>
        </div>
        <label>จาก<input type="date" id="an-from" value="${state.from}"></label>
        <label>ถึง<input type="date" id="an-to" value="${state.to}"></label>
        <label>ชุมชน<select id="an-community"><option value="">ทุกชุมชน</option></select></label>
        <label>อสม.<select id="an-volunteer"><option value="0">ทุกคน</option></select></label>
        <button type="button" class="primary" id="an-load">แสดงนัดหมาย</button>
      </section>
      <div id="an-metrics" class="notice-metrics"></div>

      <section class="panel">
        <div class="panel-head"><div><h3>ภาพรวมชุมชน</h3><p class="muted">ส่งสรุปทั้งหมดของชุมชนให้ประธาน อสม. / Staff / ทั้งสองได้แบบกดเอง</p></div></div>
        <div id="an-community-cards" class="notice-community-grid"></div>
      </section>

      <section class="panel">
        <div class="panel-head notice-case-head"><div><h3>รายการนัดหมาย</h3><p class="muted" id="an-row-status"></p></div><div class="actions">
          <button type="button" class="secondary" id="an-select-all">เลือกทั้งหมด</button>
          <button type="button" class="secondary" id="an-select-ready">เลือกเฉพาะ LINE พร้อม</button>
          <button type="button" class="secondary" id="an-clear">ล้าง</button>
          <button type="button" class="secondary" id="an-preview-vhv">ดูตัวอย่างแจ้ง อสม.</button>
          <button type="button" class="primary" id="an-send-vhv" disabled>ส่ง LINE ที่เลือก</button>
        </div></div>
        <div class="table-wrap"><table><thead><tr><th>เลือก</th><th>ผู้มีนัด</th><th>บ้าน</th><th>วัน/เวลา</th><th>บริการ</th><th>อสม.</th><th>LINE</th><th>ประวัติ</th></tr></thead><tbody id="an-rows"></tbody></table></div>
      </section>

      <section class="panel" id="an-preview-panel" hidden>
        <div class="panel-head"><h3>ตัวอย่าง / ผลการส่ง</h3><button type="button" class="secondary" id="an-close-preview">ปิด</button></div>
        <div id="an-message-preview" class="notice-message-preview"></div>
      </section>

      <section class="panel">
        <div class="panel-head"><div><h3>ประวัติส่งล่าสุด</h3><p class="muted">เก็บเฉพาะ metadata การส่ง ไม่เก็บ CID/PID หรือเนื้อหาข้อความ</p></div><button type="button" class="secondary" id="an-history-refresh">รีเฟรช</button></div>
        <div class="table-wrap"><table><thead><tr><th>เวลา</th><th>ผู้รับ</th><th>ประเภท</th><th>ชุมชน</th><th>OA</th><th>เคส</th><th>สถานะ</th></tr></thead><tbody id="an-history"></tbody></table></div>
      </section>`;
    };

    const fmtDate=s=>s?new Date(s+'T00:00:00').toLocaleDateString('th-TH',{dateStyle:'medium'}):'—';
    const fmtDateTime=s=>s?date(s):'—';
    const lineBadge=ready=>ready?'<span class="badge good">LINE พร้อม</span>':'<span class="badge warn">ยังไม่พร้อม</span>';
    const statusBadge=status=>{
      const good=status==='sent',warn=status==='pending';
      return '<span class="badge '+(good?'good':warn?'warn':'')+'">'+esc(status||'—')+'</span>';
    };
    const updateSendButton=()=>{
      const b=$('#an-send-vhv');
      if(b)b.disabled=state.sending||state.selected.size===0;
    };

    const renderMetrics=()=>{
      const s=state.data?.summary||{};
      $('#an-metrics').innerHTML=[
        ['นัดหมาย',s.appointments],['ผู้มีนัด',s.people],['บ้าน',s.houses],['อสม.เกี่ยวข้อง',s.volunteers],
        ['เคส LINE พร้อม',s.line_ready_cases],['อสม.ไม่มี LINE',s.no_line_cases],['บ้านไม่มี อสม.',s.unassigned_cases],
        ['เคยส่งแล้ว',s.sent_before_cases]
      ].map(([k,v])=>`<article><strong>${num(v||0)}</strong><span>${esc(k)}</span></article>`).join('');
    };

    const populateFilters=()=>{
      const currentCommunity=state.community;
      const communities=[...new Set((state.data?.rows||[]).map(x=>x.community).filter(Boolean))].sort();
      $('#an-community').innerHTML='<option value="">ทุกชุมชน</option>'+communities.map(x=>`<option value="${esc(x)}" ${x===currentCommunity?'selected':''}>${esc(x)}</option>`).join('');
      const vols=new Map();
      (state.data?.rows||[]).forEach(x=>{if(x.volunteer_id)vols.set(x.volunteer_id,x.volunteer_name||('อสม. '+x.volunteer_id));});
      $('#an-volunteer').innerHTML='<option value="0">ทุกคน</option>'+[...vols.entries()].sort((a,b)=>a[1].localeCompare(b[1],'th')).map(([id,name])=>`<option value="${id}" ${Number(id)===Number(state.volunteerId)?'selected':''}>${esc(name)}</option>`).join('');
    };

    const renderRows=()=>{
      const rows=state.data?.rows||[];
      $('#an-row-status').textContent='ช่วง '+fmtDate(state.data?.from_date)+' – '+fmtDate(state.data?.to_date)+' · เลือกแล้ว '+num(state.selected.size)+' รายการ';
      $('#an-rows').innerHTML=rows.length?rows.map(x=>`
        <tr data-case="${esc(x.case_id)}">
          <td><input type="checkbox" class="an-case" data-case="${esc(x.case_id)}" ${state.selected.has(x.case_id)?'checked':''}></td>
          <td><strong>${esc(x.patient_name)}</strong><br><small>${esc(x.community||'ไม่ระบุชุมชน')}</small></td>
          <td>${esc(x.house_no||'—')}<br><small>HCODE ${esc(x.hcode||'—')}</small></td>
          <td>${esc(fmtDate(x.appointment_date))}<br><small>${esc(x.appointment_time||'ไม่ระบุเวลา')}</small></td>
          <td>${esc(x.service_label)}</td>
          <td>${esc(x.volunteer_name||'ยังไม่มี อสม.')}</td>
          <td>${x.assignment_status==='unassigned'?'<span class="badge warn">ไม่มีผู้รับผิดชอบ</span>':lineBadge(x.volunteer_line_ready)}</td>
          <td>${Number(x.sent_count||0)>0?'<span class="badge good">ส่งแล้ว '+num(x.sent_count)+' ครั้ง</span><br><small>'+esc(fmtDateTime(x.last_sent_at))+'</small>':'<span class="badge">ยังไม่ส่ง</span>'}</td>
        </tr>`).join(''):'<tr><td colspan="8" class="empty">ไม่พบนัดหมายในช่วงที่เลือก</td></tr>';
      document.querySelectorAll('.an-case').forEach(cb=>cb.onchange=()=>{
        cb.checked?state.selected.add(cb.dataset.case):state.selected.delete(cb.dataset.case);
        renderRows();
      });
      updateSendButton();
    };

    const communityMessage=(c,target='both')=>{
      const rows=(state.data?.rows||[]).filter(x=>x.community===c.community);
      const chairText=c.chair?(c.chair.name+(c.chair.line_ready?' · LINE พร้อม':' · LINE ยังไม่พร้อม')):'ยังไม่ได้กำหนดประธาน';
      const staffText=(c.staff||[]).length?(c.staff||[]).map(s=>s.name+(s.line_ready?' · LINE พร้อม':' · LINE ยังไม่พร้อม')).join(', '):'ไม่พบ Staff';
      const recipientText=target==='chair'?'ประธาน อสม.: '+chairText:target==='staff'?'Staff: '+staffText:'ประธาน อสม.: '+chairText+' | Staff: '+staffText;
      const lines=rows.slice(0,40).map(x=>`${x.appointment_time||'—'} น. ${x.patient_name} บ้าน ${x.house_no||'—'} · ${x.service_label}`);
      const extra=rows.length>40?'\n… และอีก '+(rows.length-40)+' ราย':'';
      return `📅 สรุปนัดหมาย${c.community}\nผู้รับ: ${recipientText}\nช่วง ${fmtDate(state.data.from_date)} – ${fmtDate(state.data.to_date)}\n\nผู้มีนัด ${c.people} คน / ${c.houses} บ้าน / ${c.appointments} นัด\n\n${lines.join('\n')}${extra}\n\nกรุณาช่วยย้ำเตือนประชาชนในพื้นที่`;
    };

    const showMessage=text=>{
      const panel=$('#an-preview-panel');
      $('#an-message-preview').textContent=text;
      panel.hidden=false;
      panel.scrollIntoView({behavior:'smooth',block:'start'});
    };

    const buildSendBody=({data,channel,caseIds,community='',target='both',policy='new_only',validateOnly=true,nonce})=>({
      from_date:data.from_date,
      to_date:data.to_date,
      case_ids:caseIds,
      channel,
      community,
      filter_community:channel==='vhv'?state.community:'',
      filter_volunteer_id:channel==='vhv'?Number(state.volunteerId||0):0,
      recipient_target:target,
      policy,
      preview_token:data.preview_token,
      send_nonce:nonce,
      validate_only:validateOnly
    });

    const validateAndSend=async({data,channel,caseIds,community='',target='both'})=>{
      if(state.sending)return;
      if(!caseIds.length){toast('ไม่มีรายการสำหรับส่ง');return;}
      if(caseIds.length>200){toast('รายการเกิน 200 เคส กรุณาแบ่งช่วงก่อนส่ง');return;}
      state.sending=true;updateSendButton();
      try{
        const nonce=newNonce();
        let policy='new_only';
        let check=await api('/appointment-notices/send',{
          method:'POST',
          body:JSON.stringify(buildSendBody({data,channel,caseIds,community,target,policy,validateOnly:true,nonce}))
        });
        if(!check.oa_ready){
          showMessage('LINE OA พระบาท พลัสยังไม่พร้อมส่ง\n\nตรวจ Channel access token / สถานะเปิดใช้ / Basic ID ของ OA ก่อน ระบบยังไม่ส่งข้อความใด ๆ');
          return;
        }
        const readyGroups=(check.recipients||[]).filter(x=>x.status==='ready').length;
        if(readyGroups===0){
          showMessage('ไม่มีผู้รับที่พร้อมส่งในขณะนี้\n\nPrimary/Backup quota หรือ mapping ของผู้รับยังไม่พร้อม ระบบยังไม่ส่ง LINE');
          return;
        }
        if(Number(check.duplicate_deliveries||0)>0){
          const resend=confirm(
            'พบ '+num(check.duplicate_deliveries)+' รายการที่เคยส่งแล้ว\n\n'+
            'ตกลง = ส่งย้ำทั้งหมดอีกครั้ง\n'+
            'ยกเลิก = ส่งเฉพาะรายการที่ยังไม่เคยส่ง'
          );
          policy=resend?'resend_all':'new_only';
          if(resend){
            check=await api('/appointment-notices/send',{
              method:'POST',
              body:JSON.stringify(buildSendBody({data,channel,caseIds,community,target,policy,validateOnly:true,nonce}))
            });
            const resendReady=(check.recipients||[]).filter(x=>x.status==='ready').length;
            if(resendReady===0){
              showMessage('ไม่มีผู้รับที่พร้อมสำหรับการส่งย้ำ ระบบยังไม่ส่ง LINE');
              return;
            }
          }
        }
        if(Number(check.eligible_deliveries||0)===0){
          showMessage('ไม่มีรายการใหม่ที่ต้องส่ง\nรายการที่เลือกเคยส่งแล้วทั้งหมด หากต้องการส่งย้ำให้กดส่งอีกครั้งและเลือก “ส่งย้ำทั้งหมด”');
          return;
        }
        const missing=(check.missing||[]);
        const blocked=Number(check.blocked_groups||0);
        const warning=(missing.length||blocked)
          ?'\n\nข้าม/บล็อก '+num(missing.length+blocked)+' รายการหรือกลุ่มที่ยังไม่มี provider พร้อม':'';
        const routing='\nOA หลัก '+num(check.primary_groups||0)+' กลุ่ม · OA สำรอง '+num(check.backup_groups||0)+' กลุ่ม';
        const ok=confirm(
          'ยืนยันส่ง LINE จริง\n'+
          'ผู้รับพร้อม '+num((check.recipients||[]).filter(x=>x.status==='ready').length)+' กลุ่ม\n'+
          'รายการที่จะส่ง '+num(check.eligible_deliveries)+' รายการ'+
          routing+warning
        );
        if(!ok)return;

        const result=await api('/appointment-notices/send',{
          method:'POST',
          body:JSON.stringify(buildSendBody({data,channel,caseIds,community,target,policy,validateOnly:false,nonce}))
        });
        const lines=[
          'ผลการส่ง LINE',
          'สถานะ: '+String(result.status||'—'),
          'ส่งสำเร็จ: '+num(result.sent_groups||0)+' กลุ่มผู้รับ',
          'ล้มเหลว: '+num(result.failed_groups||0)+' กลุ่ม',
          'รายการที่เคยส่ง: '+num(result.duplicate_deliveries||0),
          'OA หลัก: '+num(result.primary_sent_groups||0)+' กลุ่ม',
          'OA สำรอง: '+num(result.backup_sent_groups||0)+' กลุ่ม',
          'ถูกบล็อก: '+num(result.blocked_groups||0)+' กลุ่ม',
        ];
        if((result.missing||[]).length)lines.push('ข้าม/ต้องตรวจ: '+num(result.missing.length)+' รายการ');
        for(const r of (result.recipients||[])){
          lines.push('• '+(r.name||'ผู้รับ')+' · '+(r.target_kind||'')+' · '+(r.status||'—')+' · '+num(r.case_count||0)+' เคส · '+(r.provider==='backup'?'OA สำรอง':r.provider==='primary'?'OA หลัก':'ไม่มี provider'));
        }
        showMessage(lines.join('\n'));
        toast(result.failed_groups?'ส่งบางส่วนสำเร็จ กรุณาตรวจผลการส่ง':'ส่ง LINE สำเร็จ');
        await load();
        await loadHistory();
      }catch(e){
        showMessage('ยังไม่ส่ง/ส่งไม่สำเร็จ\n'+e.message);
      }finally{
        state.sending=false;updateSendButton();
      }
    };

    const renderCommunities=()=>{
      const cards=state.data?.communities||[];
      $('#an-community-cards').innerHTML=cards.length?cards.map(c=>{
        const chair=c.chair;
        const staff=c.staff||[];
        return `<article class="notice-community-card" data-community="${esc(c.community)}">
          <div class="notice-community-title"><h4>${esc(c.community)}</h4><span class="badge">${num(c.appointments)} นัด</span></div>
          <div class="notice-community-stats"><span>${num(c.people)} คน</span><span>${num(c.houses)} บ้าน</span><span>${num(c.volunteers)} อสม.</span></div>
          <div class="notice-recipient"><strong>ประธาน อสม.</strong><span>${chair?esc(chair.name):'ยังไม่ได้กำหนด'} ${chair?lineBadge(chair.line_ready):'<span class="badge warn">ต้องกำหนด</span>'}</span></div>
          <div class="notice-recipient"><strong>Staff</strong><span>${staff.length?staff.map(s=>esc(s.name)+' '+(s.line_ready?'✓':'✕')).join(' · '):'ไม่พบ Staff ในชุมชน'}</span></div>
          <div class="notice-warning">${c.cases_no_line?num(c.cases_no_line)+' นัด: อสม.ยังไม่เชื่อม LINE':''}${c.cases_unassigned?' · '+num(c.cases_unassigned)+' นัด: ไม่มี อสม.':''}</div>
          <div class="actions notice-target-actions">
            <button type="button" class="secondary an-filter-community">ดูรายชื่อ</button>
            <button type="button" class="secondary an-set-chair">ตั้งประธาน</button>
            <select class="an-recipient-target" aria-label="เลือกผู้รับสรุป"><option value="chair">ประธาน อสม.</option><option value="staff">Staff</option><option value="both" selected>ประธาน + Staff</option></select>
            <button type="button" class="secondary an-preview-community">ดูตัวอย่าง</button>
            <button type="button" class="primary an-send-community">ส่งสรุปชุมชน</button>
          </div>
        </article>`;
      }).join(''):'<p class="empty">ไม่มีชุมชนที่มีนัดในช่วงนี้</p>';

      document.querySelectorAll('.notice-community-card').forEach(card=>{
        const name=card.dataset.community;
        card.querySelector('.an-filter-community').onclick=()=>{state.community=name;$('#an-community').value=name;load();};
        card.querySelector('.an-preview-community').onclick=()=>{
          const c=(state.data.communities||[]).find(x=>x.community===name);
          const target=card.querySelector('.an-recipient-target').value;
          if(c)showMessage(communityMessage(c,target));
        };
        card.querySelector('.an-set-chair').onclick=()=>configureChair(name);
        card.querySelector('.an-send-community').onclick=async()=>{
          const target=card.querySelector('.an-recipient-target').value;
          try{
            const q=new URLSearchParams({from_date:state.from,to_date:state.to,community:name});
            const full=await api('/appointment-notices/preview?'+q);
            await validateAndSend({
              data:full,
              channel:'community',
              caseIds:(full.rows||[]).map(x=>x.case_id),
              community:name,
              target
            });
          }catch(e){showMessage(e.message);}
        };
      });
    };

    const configureChair=async community=>{
      try{
        const d=await api('/appointment-notices/chair-options?'+new URLSearchParams({community}));
        const optionsHtml='<option value="">— ยังไม่กำหนด —</option>'+d.candidates.map(x=>`<option value="${x.volunteer_id}" ${Number(x.volunteer_id)===Number(d.selected_volunteer_id)?'selected':''}>${esc(x.name)} ${x.line_ready?'· LINE พร้อม':'· ยังไม่เชื่อม LINE'}</option>`).join('');
        const panel=$('#an-preview-panel');panel.hidden=false;
        $('#an-message-preview').innerHTML=`<div class="notice-chair-config"><h4>กำหนดประธาน อสม. · ${esc(community)}</h4><select id="an-chair-select">${optionsHtml}</select><div class="actions"><button type="button" class="primary" id="an-save-chair">บันทึกผู้รับสรุป</button></div><p class="muted">บันทึกผู้รับใน Local เท่านั้น การส่ง LINE ต้องกด “ส่งสรุปชุมชน” แยกอีกครั้ง</p></div>`;
        $('#an-save-chair').onclick=async()=>{
          const value=$('#an-chair-select').value;
          await api('/appointment-notices/chair',{method:'POST',body:JSON.stringify({community,volunteer_id:value?Number(value):null})});
          toast('บันทึกประธาน อสม.แล้ว');
          await load();
        };
      }catch(e){toast(e.message);}
    };

    const previewVhv=()=>{
      const rows=(state.data?.rows||[]).filter(x=>state.selected.has(x.case_id));
      if(!rows.length){toast('กรุณาเลือกอย่างน้อย 1 รายการ');return;}
      const groups=new Map();
      rows.forEach(x=>{const key=x.volunteer_id||'unassigned';if(!groups.has(key))groups.set(key,[]);groups.get(key).push(x);});
      const messages=[];
      for(const items of groups.values()){
        const v=items[0].volunteer_name||'ยังไม่มี อสม.ผู้รับผิดชอบ';
        messages.push(`📅 แจ้งเตือนนัดหมายในพื้นที่รับผิดชอบ\nอสม. ${v}\nมี ${items.length} นัด\n\n`+items.map(x=>`${fmtDate(x.appointment_date)} ${x.appointment_time||'ไม่ระบุเวลา'} · ${x.patient_name} · บ้าน ${x.house_no||'—'}`).join('\n'));
      }
      showMessage(messages.join('\n\n----------------\n\n'));
    };

    const loadHistory=async()=>{
      try{
        const h=await api('/appointment-notices/history?limit=50');
        const rows=h.items||[];
        $('#an-history').innerHTML=rows.length?rows.map(x=>`
          <tr>
            <td>${esc(fmtDateTime(x.sent_at||x.created_at))}</td>
            <td><strong>${esc(x.recipient_name||'—')}</strong><br><small>${esc(x.target_kind||'')}</small></td>
            <td>${esc(x.channel==='community'?'สรุปชุมชน':'แจ้ง อสม.')}${x.is_resend?'<br><span class="badge warn">ส่งย้ำ</span>':''}</td>
            <td>${esc(x.community||'—')}</td>
            <td>${esc(x.provider_slot==='backup'?'สำรอง':x.provider_slot==='primary'?'หลัก':'—')}<br><small>${esc(x.oa_basic_id||'')}</small></td>
            <td>${num(x.case_count||0)}</td>
            <td>${statusBadge(x.status)}${x.error_code?'<br><small>'+esc(x.error_code)+'</small>':''}</td>
          </tr>`).join(''):'<tr><td colspan="7" class="empty">ยังไม่มีประวัติการส่ง</td></tr>';
      }catch(e){
        $('#an-history').innerHTML='<tr><td colspan="7" class="empty">'+esc(e.message)+'</td></tr>';
      }
    };

    const bind=()=>{
      document.querySelectorAll('[data-days]').forEach(b=>b.onclick=()=>{
        const n=Number(b.dataset.days);
        if(n===0){state.from=iso(today);state.to=iso(today);}
        else if(n===1){state.from=plus(1);state.to=plus(1);}
        else{state.from=iso(today);state.to=plus(n-1);}
        $('#an-from').value=state.from;$('#an-to').value=state.to;load();
      });
      $('#an-load').onclick=()=>{
        state.from=$('#an-from').value;state.to=$('#an-to').value;
        state.community=$('#an-community').value;
        state.volunteerId=Number($('#an-volunteer').value||0);
        load();
      };
      $('#an-select-all').onclick=()=>{(state.data?.rows||[]).forEach(x=>state.selected.add(x.case_id));renderRows();};
      $('#an-select-ready').onclick=()=>{
        state.selected.clear();
        (state.data?.rows||[]).filter(x=>x.assignment_status==='ready').forEach(x=>state.selected.add(x.case_id));
        renderRows();
      };
      $('#an-clear').onclick=()=>{state.selected.clear();renderRows();};
      $('#an-preview-vhv').onclick=previewVhv;
      $('#an-send-vhv').onclick=()=>validateAndSend({
        data:state.data,
        channel:'vhv',
        caseIds:[...state.selected]
      });
      $('#an-close-preview').onclick=()=>$('#an-preview-panel').hidden=true;
      $('#an-history-refresh').onclick=loadHistory;
    };

    const load=async()=>{
      $('#an-row-status').textContent='กำลังอ่านนัดหมายจาก JHCIS…';
      try{
        const q=new URLSearchParams({from_date:state.from,to_date:state.to});
        if(state.community)q.set('community',state.community);
        if(state.volunteerId)q.set('volunteer_id',String(state.volunteerId));
        state.data=await api('/appointment-notices/preview?'+q);
        state.selected.clear();
        renderMetrics();populateFilters();renderCommunities();renderRows();bind();
      }catch(e){
        $('#an-row-status').textContent=e.message;
        $('#an-rows').innerHTML='<tr><td colspan="8" class="empty">'+esc(e.message)+'</td></tr>';
      }
    };

    shell();bind();await load();await loadHistory();if(window.AppointmentNoticeFailover)await AppointmentNoticeFailover.mount();if(window.AppointmentNoticePhase32)await AppointmentNoticePhase32.mount();if(window.AppointmentNoticePhase3)await AppointmentNoticePhase3.mount();
  }
};