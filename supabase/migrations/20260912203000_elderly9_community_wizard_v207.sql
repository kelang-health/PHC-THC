-- OSM-PHC Cloud v2.0.7
-- Elderly 9-domain community screening for VHV/Staff/Admin.
-- Inputs follow the Ministry of Public Health community-screening pattern.
-- The system derives normal/risk; VHV never selects the clinical status directly.

begin;

create or replace function public.save_elderly9_community_v207(
  p_session_id uuid,
  p_domain_code text,
  p_answers jsonb,
  p_note text default ''
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  s public.screening_sessions%rowtype;
  d text:=lower(btrim(coalesce(p_domain_code,'')));
  a jsonb:=coalesce(p_answers,'{}'::jsonb);
  st text:='normal';
  priority text:='orange';
  summary text:='';
  details jsonb:='{}'::jsonb;
  score integer;
  v_done integer:=0;
  v_obs integer:=0;
  v_followup_id uuid;
  v_had_followup boolean:=false;
  v_urgent boolean:=false;
  v_seconds numeric;
  v_result text;
  v_bool1 boolean;
  v_bool2 boolean;
  v_bool3 boolean;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route<>'elderly_60_plus' or s.age_years<60 then raise exception 'ELDERLY9_NOT_APPLICABLE'; end if;
  if s.ncd_status<>'complete' or s.ncd_screening_id is null then raise exception 'NCD_SCREENING_REQUIRED_FIRST'; end if;
  if d not in ('cognition','mobility','nutrition','vision','hearing','depression','urinary','adl','oral') then raise exception 'INVALID_ELDERLY_DOMAIN'; end if;
  if jsonb_typeof(a)<>'object' then raise exception 'INVALID_ANSWERS'; end if;

  if d='cognition' then
    if jsonb_typeof(a->'clock_numbers_correct')<>'boolean'
       or jsonb_typeof(a->'clock_hands_correct')<>'boolean'
       or jsonb_typeof(a->'recall_count')<>'number' then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    if (a->>'recall_count')::integer not between 0 and 3 then raise exception 'INVALID_RECALL_COUNT'; end if;
    score:=((a->>'clock_numbers_correct')::boolean)::integer
           +((a->>'clock_hands_correct')::boolean)::integer
           +(a->>'recall_count')::integer;
    st:=case when score<=3 then 'observation' else 'normal' end;
    summary:=case when st='observation' then 'Mini-Cog เธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธ เธเธงเธฃเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธเธเธงเธฒเธกเธเธดเธ”เธเธงเธฒเธกเธเธณเน€เธเธดเนเธกเน€เธ•เธดเธก' else 'Mini-Cog เธเธเธ•เธดเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','Mini-Cog','score',score,'max_score',5,'risk_cutoff','<=3');
  elsif d='mobility' then
    if jsonb_typeof(a->'unable')<>'boolean' or jsonb_typeof(a->'fall_6m')<>'boolean' then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    v_bool1:=(a->>'unable')::boolean;
    v_bool2:=(a->>'fall_6m')::boolean;
    if not v_bool1 then
      if jsonb_typeof(a->'tug_seconds')<>'number' then raise exception 'TUG_SECONDS_REQUIRED'; end if;
      v_seconds:=(a->>'tug_seconds')::numeric;
      if v_seconds<=0 or v_seconds>300 then raise exception 'INVALID_TUG_SECONDS'; end if;
    else v_seconds:=null; end if;
    st:=case when v_bool1 or coalesce(v_seconds,999)>=12 or v_bool2 then 'observation' else 'normal' end;
    summary:=case when st='observation' then 'เธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเธซเธเธฅเนเธกเธเธฒเธ TUG/เธเธฃเธฐเธงเธฑเธ•เธดเธซเธเธฅเนเธก เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเน€เธเธดเนเธกเน€เธ•เธดเธก' else 'เนเธกเนเธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเธซเธเธฅเนเธกเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','Timed Up and Go + fall history','threshold_seconds',12,'tug_seconds',v_seconds);
  elsif d='nutrition' then
    if jsonb_typeof(a->'weight_loss_3kg_3m')<>'boolean' or jsonb_typeof(a->'appetite_loss')<>'boolean' then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    v_bool1:=(a->>'weight_loss_3kg_3m')::boolean; v_bool2:=(a->>'appetite_loss')::boolean;
    st:=case when v_bool1 or v_bool2 then 'observation' else 'normal' end;
    summary:=case when st='observation' then 'เธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเธ เธฒเธงเธฐเธเธฒเธ”เธชเธฒเธฃเธญเธฒเธซเธฒเธฃ เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเนเธ เธเธเธฒเธเธฒเธฃเน€เธเธดเนเธกเน€เธ•เธดเธก' else 'เนเธกเนเธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเธ เธฒเธงเธฐเธเธฒเธ”เธชเธฒเธฃเธญเธฒเธซเธฒเธฃเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','Community nutrition 2 questions');
  elsif d='vision' then
    if jsonb_typeof(a->'vision_problem')<>'boolean' then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    v_bool1:=(a->>'vision_problem')::boolean;
    st:=case when v_bool1 then 'observation' else 'normal' end;
    summary:=case when st='observation' then 'เธเธเธเธฑเธเธซเธฒเธเธฒเธฃเธกเธญเธเน€เธซเนเธ เธเธงเธฃเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธเน€เธเธดเนเธกเน€เธ•เธดเธก' else 'เนเธกเนเธเธเธเธฑเธเธซเธฒเธเธฒเธฃเธกเธญเธเน€เธซเนเธเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','Vision community question');
  elsif d='hearing' then
    v_result:=coalesce(a->>'hearing_result','');
    if v_result not in ('both','left_only','right_only','none') then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    st:=case when v_result='both' then 'normal' else 'observation' end;
    summary:=case when st='observation' then 'Finger rub test เธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเธ”เนเธฒเธเธเธฒเธฃเนเธ”เนเธขเธดเธ เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเน€เธเธดเนเธกเน€เธ•เธดเธก' else 'Finger rub test เธเธเธ•เธดเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','Finger rub test');
  elsif d='depression' then
    if jsonb_typeof(a->'q1')<>'boolean' or jsonb_typeof(a->'q2')<>'boolean' or jsonb_typeof(a->'q3')<>'boolean' then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    v_bool1:=(a->>'q1')::boolean; v_bool2:=(a->>'q2')::boolean; v_bool3:=(a->>'q3')::boolean;
    st:=case when v_bool1 or v_bool2 or v_bool3 then 'observation' else 'normal' end;
    v_urgent:=v_bool3;
    priority:=case when v_urgent then 'red' else 'orange' end;
    summary:=case when v_urgent then '2Q plus เธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเธ•เนเธญเธเธฒเธฃเธเนเธฒเธ•เธฑเธงเธ•เธฒเธข เธ•เนเธญเธเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธเธ•เนเธญเนเธ”เธขเน€เธฃเนเธง'
                  when st='observation' then '2Q plus เธเธเธเธงเธฒเธกเน€เธชเธตเนเธขเธเธเธถเธกเน€เธจเธฃเนเธฒ เธเธงเธฃเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธ 9Q เธ•เนเธญ'
                  else '2Q plus เธเธเธ•เธดเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','2Q plus','urgent',v_urgent);
  elsif d='urinary' then
    if jsonb_typeof(a->'urinary_problem')<>'boolean' then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    v_bool1:=(a->>'urinary_problem')::boolean;
    st:=case when v_bool1 then 'observation' else 'normal' end;
    summary:=case when st='observation' then 'เธเธเธเธฑเธเธซเธฒเธเธฑเธชเธชเธฒเธงเธฐเน€เธฅเนเธ”/เธฃเธฒเธ”เธ—เธตเนเธเธฃเธฐเธ—เธเธเธตเธงเธดเธ•เธเธฃเธฐเธเธณเธงเธฑเธ เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธเน€เธเธดเนเธกเน€เธ•เธดเธก' else 'เนเธกเนเธเธเธเธฑเธเธซเธฒเธเธฒเธฃเธเธฅเธฑเนเธเธเธฑเธชเธชเธฒเธงเธฐเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','Urinary incontinence community question');
  elsif d='adl' then
    if jsonb_typeof(a->'adl_decline')<>'boolean' then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    v_bool1:=(a->>'adl_decline')::boolean;
    st:=case when v_bool1 then 'observation' else 'normal' end;
    summary:=case when st='observation' then 'เธเธงเธฒเธกเธชเธฒเธกเธฒเธฃเธ–เธเนเธงเธขเน€เธซเธฅเธทเธญเธ•เธเน€เธญเธเนเธเธเธดเธเธงเธฑเธ•เธฃเธเธฃเธฐเธเธณเธงเธฑเธเธฅเธ”เธฅเธ เธเธงเธฃเธเธฃเธฐเน€เธกเธดเธ ADL เน€เธเธดเนเธกเน€เธ•เธดเธก' else 'เธเธดเธเธงเธฑเธ•เธฃเธเธฃเธฐเธเธณเธงเธฑเธเธเธเธ•เธดเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','ADL decline community question');
  elsif d='oral' then
    if jsonb_typeof(a->'chewing_hard_problem')<>'boolean' or jsonb_typeof(a->'oral_pain')<>'boolean' then raise exception 'ELDERLY9_ANSWER_REQUIRED'; end if;
    v_bool1:=(a->>'chewing_hard_problem')::boolean; v_bool2:=(a->>'oral_pain')::boolean;
    st:=case when v_bool1 or v_bool2 then 'observation' else 'normal' end;
    summary:=case when st='observation' then 'เธเธเธเธฑเธเธซเธฒเธชเธธเธเธ เธฒเธเธเนเธญเธเธเธฒเธเน€เธเธทเนเธญเธเธ•เนเธ เธเธงเธฃเนเธซเนเธ—เธฑเธเธ•เธเธธเธเธฅเธฒเธเธฃ/เน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธเธ•เนเธญ' else 'เนเธกเนเธเธเธเธฑเธเธซเธฒเธชเธธเธเธ เธฒเธเธเนเธญเธเธเธฒเธเน€เธเธทเนเธญเธเธ•เนเธ' end;
    details:=a||jsonb_build_object('tool','Oral health community 2 questions');
  end if;

  details:=details||jsonb_build_object('derived_status',st,'priority',case when st='observation' then priority else 'normal' end,'reference_version','MOPH-community-elderly9-v207');

  select exists(select 1 from public.screening_followups f where f.session_id=s.id and f.followup_type='elderly9' and f.domain_code=d)
  into v_had_followup;

  insert into public.elderly9_domain_results(session_id,source_pcucode,source_pid,domain_code,status,checklist,note,assessed_by)
  values(s.id,s.source_pcucode,s.source_pid,d,st,details,left(coalesce(p_note,''),500),auth.uid())
  on conflict(session_id,domain_code) do update set
    status=excluded.status,checklist=excluded.checklist,note=excluded.note,assessed_by=auth.uid(),assessed_at=now(),updated_at=now();

  if st='observation' then
    insert into public.screening_followups(session_id,source_pcucode,source_pid,followup_type,domain_code,priority,summary,created_by)
    values(s.id,s.source_pcucode,s.source_pid,'elderly9',d,priority,summary,auth.uid())
    on conflict(session_id,followup_type,domain_code) do update set
      priority=excluded.priority,status='open',summary=excluded.summary,completed_at=null,updated_at=now()
    returning id into v_followup_id;
    if not v_had_followup or v_urgent then
      perform private.emit_admin_notification_v190(
        case when v_urgent then 'elderly9.urgent' else 'elderly9.followup' end,
        case when v_urgent then 'critical' else 'warning' end,
        case when v_urgent then 'OSM-PHC: เธกเธตเธเธฒเธเธ•เธดเธ”เธ•เธฒเธกเธเธนเนเธชเธนเธเธญเธฒเธขเธธเน€เธฃเนเธเธ”เนเธงเธ' else 'OSM-PHC: เธกเธตเธเธฅเธเธฑเธ”เธเธฃเธญเธเธเธนเนเธชเธนเธเธญเธฒเธขเธธเธ•เนเธญเธเธ•เธดเธ”เธ•เธฒเธก' end,
        case when v_urgent then 'เธเธเธเธฅเธเธฑเธ”เธเธฃเธญเธเธชเธธเธเธ เธฒเธเธเธดเธ•เธ—เธตเนเธ•เนเธญเธเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธเธฃเธฐเน€เธกเธดเธเนเธ”เธขเน€เธฃเนเธง เธเธฃเธธเธ“เธฒเน€เธเธดเธ”เธฃเธฐเธเธ' else 'เธเธเธเธฅเธเธฑเธ”เธเธฃเธญเธเธเธนเนเธชเธนเธเธญเธฒเธขเธธเธ—เธตเนเธ•เนเธญเธเธ•เธดเธ”เธ•เธฒเธก เธเธฃเธธเธ“เธฒเน€เธเธดเธ”เธฃเธฐเธเธ' end,
        '?panel=field-work',
        jsonb_build_object('session_id',s.id,'domain_code',d,'priority',priority),
        false
      );
    end if;
  else
    update public.screening_followups
       set status='cancelled',completed_at=now(),updated_at=now(),
           resolution_note=case when coalesce(resolution_note,'')='' then 'เนเธเนเนเธ/เธเธฃเธฐเน€เธกเธดเธเธเนเธณเนเธ session เน€เธ”เธดเธกเน€เธเนเธเธเธเธ•เธด' else resolution_note end
     where session_id=s.id and followup_type='elderly9' and domain_code=d and status in ('open','in_progress');
  end if;

  select count(*) filter(where status in ('normal','observation')),
         count(*) filter(where status='observation')
    into v_done,v_obs
    from public.elderly9_domain_results where session_id=s.id;

  update public.screening_sessions set
    completed_domains=(select coalesce(array_agg(domain_code order by domain_code),'{}'::text[]) from public.elderly9_domain_results where session_id=s.id and status in ('normal','observation')),
    elderly9_status=case when v_done>=9 then 'complete' else 'in_progress' end,
    completed_at=case when v_done>=9 then now() else null end,
    updated_at=now()
  where id=s.id;

  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,source_pid,severity,details)
  values(auth.uid(),'UPSERT','elderly9_community_screening',s.id::text,s.source_pcucode,s.source_pid,
         case when v_urgent then 'red' when st='observation' then 'orange' else 'normal' end,
         jsonb_build_object('domain_code',d,'status',st,'priority',case when st='observation' then priority else 'normal' end,'completed',v_done));

  return jsonb_build_object(
    'ok',true,'domain_code',d,'status',st,
    'status_label',case when st='normal' then 'เธเธเธ•เธด' else 'เน€เธชเธตเนเธขเธ' end,
    'priority',case when st='observation' then priority else 'normal' end,
    'summary',summary,'score',score,'urgent',v_urgent,
    'followup_created',st='observation','followup_id',v_followup_id,
    'completed',v_done,'remaining',greatest(9-v_done,0),'observations',v_obs
  );
end;
$$;

revoke all on function public.save_elderly9_community_v207(uuid,text,jsonb,text) from public,anon;

grant execute on function public.save_elderly9_community_v207(uuid,text,jsonb,text) to authenticated;

insert into public.app_settings(key,value)
values('elderly9_community_v207',jsonb_build_object(
  'version','2.0.7',
  'mode','community_screening_by_vhv_then_staff_followup',
  'domain_order',jsonb_build_array('cognition','mobility','nutrition','vision','hearing','depression','urinary','adl','oral'),
  'tools',jsonb_build_object(
    'cognition','Mini-Cog; risk if total score <=3/5',
    'mobility','Timed Up and Go 3 m out + 3 m back; risk if >=12 sec, unable, or fall in 6 months',
    'nutrition','2 questions; risk if weight loss >3 kg/3 months or appetite loss',
    'vision','1 community question',
    'hearing','Finger rub test',
    'depression','2Q plus; q3 positive = red priority',
    'urinary','1 community question',
    'adl','1 community decline question',
    'oral','2 questions matching 3Doctor community screen'
  ),
  'references',jsonb_build_array(
    'https://hpc4.anamai.moph.go.th/th/general-downloads/download?did=30352&id=86298&lang=th&mid=22147&mkey=m_document',
    'https://eh.anamai.moph.go.th/',
    'https://3doctor.hss.moph.go.th/main/rp_screen',
    'https://mhso.dmh.go.th/fileupload/202301161330193317.pdf'
  ),
  'vhv_selects_risk_status',false,
  'staff_admin_owns_followup',true,
  'telegram_for_elderly_screening',false,
  'screening_is_diagnosis',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
