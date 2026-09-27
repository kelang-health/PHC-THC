-- OSM-PHC Cloud v2.0.8
-- Pre-go-live test mode and reset controls for every screening route.
-- Before 2026-10-01 all new OSM-PHC screening results are test data and are not production output.
-- Reset never deletes JHCIS/J-Report/3Doctor source history; reset rows are archived for audit.

begin;

create table if not exists public.screening_test_reset_archive_v208 (
  archive_id bigint generated always as identity primary key,
  entity_type text not null,
  original_id text not null,
  source_pcucode text not null default '',
  source_pid bigint,
  original_row jsonb not null,
  reset_at timestamptz not null default now(),
  reset_by uuid references auth.users(id),
  reason text not null default '',
  reset_batch uuid not null,
  unique(entity_type,original_id)
);

alter table public.screening_test_reset_archive_v208 enable row level security;

revoke all on public.screening_test_reset_archive_v208 from public,anon,authenticated;

grant select on public.screening_test_reset_archive_v208 to authenticated;

drop policy if exists screening_test_reset_archive_admin_v208 on public.screening_test_reset_archive_v208;

create policy screening_test_reset_archive_admin_v208 on public.screening_test_reset_archive_v208
for select to authenticated using(private.current_role()='admin');

create or replace function private.screening_record_mode_v208(p_day date)
returns text language sql immutable set search_path=''
as $$ select case when p_day < date '2026-10-01' then 'test' else 'production' end $$;

revoke all on function private.screening_record_mode_v208(date) from public,anon,authenticated;

-- During field testing, same-day NCD test records must unlock the elderly 9-domain route.
create or replace function public.start_age_screening_v190(p_source_pcucode text,p_source_pid bigint,p_screening_date date default current_date)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  p public.health_persons%rowtype;
  v_date date:=coalesce(p_screening_date,current_date);
  v_months integer;
  v_years integer;
  v_route text;
  s public.screening_sessions%rowtype;
  n public.health_ncd_screenings%rowtype;
  v_target integer;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  if v_date>current_date+1 then raise exception 'SCREENING_DATE_IN_FUTURE'; end if;
  select * into p from public.health_persons where source_pcucode=p_source_pcucode and source_pid=p_source_pid and active=true;
  if not found then raise exception 'PERSON_NOT_FOUND'; end if;
  if not private.health_can_access_person(p.source_pcucode,p.source_pid) then raise exception 'PERSON_OUT_OF_SCOPE'; end if;
  if p.birth_date is null or p.birth_date>v_date then raise exception 'BIRTH_DATE_REQUIRED'; end if;
  v_months:=(extract(year from age(v_date,p.birth_date))::integer*12)+extract(month from age(v_date,p.birth_date))::integer;
  v_years:=extract(year from age(v_date,p.birth_date))::integer;
  v_route:=private.screening_route_v190(v_months);

  select * into n from public.health_ncd_screenings x
  where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid and x.screened_on=v_date
    and coalesce(x.record_mode,'production')=private.screening_record_mode_v208(v_date)
  order by x.recorded_at desc limit 1;

  insert into public.screening_sessions(source_pcucode,source_pid,house_pcucode,hcode,screening_date,age_years,age_months,route,ncd_screening_id,ncd_status,elderly9_status,started_by)
  values(p.source_pcucode,p.source_pid,p.house_pcucode,p.hcode,v_date,v_years,v_months,v_route,
    case when v_route in ('ncd_35_59','elderly_60_plus') then n.id else null end,
    case when v_route in ('ncd_35_59','elderly_60_plus') then case when n.id is null then 'required' else 'complete' end else 'not_required' end,
    case when v_route='elderly_60_plus' then case when n.id is null then 'blocked_by_ncd' else 'in_progress' end else 'not_required' end,
    auth.uid())
  on conflict(source_pcucode,source_pid,screening_date,started_by) do update set
    age_years=excluded.age_years,age_months=excluded.age_months,route=excluded.route,
    ncd_screening_id=coalesce(excluded.ncd_screening_id,public.screening_sessions.ncd_screening_id),
    ncd_status=case when coalesce(excluded.ncd_screening_id,public.screening_sessions.ncd_screening_id) is null and excluded.route in ('ncd_35_59','elderly_60_plus') then 'required'
                    when excluded.route in ('ncd_35_59','elderly_60_plus') then 'complete' else 'not_required' end,
    elderly9_status=case when excluded.route='elderly_60_plus' and coalesce(excluded.ncd_screening_id,public.screening_sessions.ncd_screening_id) is null then 'blocked_by_ncd'
                         when excluded.route='elderly_60_plus' and public.screening_sessions.elderly9_status<>'complete' then 'in_progress'
                         when excluded.route<>'elderly_60_plus' then 'not_required' else public.screening_sessions.elderly9_status end,
    updated_at=now()
  returning * into s;
  v_target:=case when v_route='child_0_5' then private.closest_dspm_target_v190(v_months) else null end;
  return jsonb_build_object('session_id',s.id,'source_pcucode',p.source_pcucode,'source_pid',p.source_pid,'display_name',p.display_name,
    'age_years',v_years,'age_months',v_months,'route',v_route,'ncd_status',s.ncd_status,'ncd_screening_id',s.ncd_screening_id,
    'elderly9_status',s.elderly9_status,'completed_domains',s.completed_domains,'dspm_target_months',v_target,
    'record_mode',private.screening_record_mode_v208(v_date),'go_live_date','2026-10-01',
    'route_label',case v_route when 'child_0_5' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ + เธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธเธทเนเธญเธเธ•เนเธ' when 'school_6_14' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ'
      when 'youth_15_34' then 'เธเธฑเธ”เธเธฃเธญเธเน€เธชเธฃเธดเธกเธ•เธฒเธกเธเนเธงเธเธ—เธตเน Admin เน€เธเธดเธ”' when 'ncd_35_59' then 'NCD Screening' else 'NCD Screening เธเนเธญเธ เนเธฅเนเธงเธ—เธณเธเธนเนเธชเธนเธเธญเธฒเธขเธธ 9 เธ”เนเธฒเธ' end);
end;
$$;

revoke all on function public.start_age_screening_v190(text,bigint,date) from public,anon;

grant execute on function public.start_age_screening_v190(text,bigint,date) to authenticated;

create or replace function public.attach_ncd_to_screening_session_v190(p_session_id uuid,p_ncd_screening_id uuid default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare s public.screening_sessions%rowtype; n public.health_ncd_screenings%rowtype; v_mode text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route not in ('ncd_35_59','elderly_60_plus') then raise exception 'NCD_NOT_REQUIRED_FOR_ROUTE'; end if;
  v_mode:=private.screening_record_mode_v208(s.screening_date);
  if p_ncd_screening_id is null then
    select * into n from public.health_ncd_screenings x
    where x.source_pcucode=s.source_pcucode and x.source_pid=s.source_pid and x.screened_on=s.screening_date
      and coalesce(x.record_mode,'production')=v_mode
    order by x.recorded_at desc limit 1;
  else
    select * into n from public.health_ncd_screenings x
    where x.id=p_ncd_screening_id and x.source_pcucode=s.source_pcucode and x.source_pid=s.source_pid and x.screened_on=s.screening_date
      and coalesce(x.record_mode,'production')=v_mode;
  end if;
  if not found then raise exception 'NCD_SCREENING_REQUIRED_SAME_DAY'; end if;
  update public.screening_sessions set ncd_screening_id=n.id,ncd_status='complete',elderly9_status=case when route='elderly_60_plus' and elderly9_status='blocked_by_ncd' then 'in_progress' else elderly9_status end,updated_at=now() where id=s.id returning * into s;
  return jsonb_build_object('ok',true,'ncd_status',s.ncd_status,'elderly9_status',s.elderly9_status,'ncd_screening_id',s.ncd_screening_id,'record_mode',v_mode);
end;
$$;

revoke all on function public.attach_ncd_to_screening_session_v190(uuid,uuid) from public,anon;

grant execute on function public.attach_ncd_to_screening_session_v190(uuid,uuid) to authenticated;

create or replace function public.reset_person_test_screening_v208(
  p_source_pcucode text,p_source_pid bigint,p_route text default 'all',p_reason text default 'เธฃเธตเน€เธเธ—เธเนเธญเธกเธนเธฅเธ—เธ”เธชเธญเธเธเนเธญเธเน€เธเธดเธ”เนเธเนเธเธฃเธดเธ'
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_route text:=lower(btrim(coalesce(p_route,'all')));
  v_reason text:=left(btrim(coalesce(p_reason,'')),500);
  v_batch uuid:=extensions.gen_random_uuid();
  v_archived integer:=0;v_n integer:=0;v_sessions integer:=0;v_ncd integer:=0;
begin
  if current_date>=date '2026-10-01' then raise exception 'TEST_RESET_CLOSED'; end if;
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  if not private.health_can_access_person(btrim(p_source_pcucode),p_source_pid) then raise exception 'PERSON_OUT_OF_SCOPE'; end if;
  if v_route not in ('all','child_0_5','school_6_14','youth_15_34','ncd_35_59','elderly_60_plus') then raise exception 'INVALID_RESET_ROUTE'; end if;
  if length(v_reason)<5 then raise exception 'RESET_REASON_REQUIRED'; end if;

  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'screening_followup',f.id::text,f.source_pcucode,f.source_pid,to_jsonb(f),auth.uid(),v_reason,v_batch
  from public.screening_followups f join public.screening_sessions s on s.id=f.session_id
  where s.source_pcucode=btrim(p_source_pcucode) and s.source_pid=p_source_pid and s.screening_date<date '2026-10-01'
    and (v_route='all' or s.route=v_route) on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;

  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'elderly9_domain',r.id::text,r.source_pcucode,r.source_pid,to_jsonb(r),auth.uid(),v_reason,v_batch
  from public.elderly9_domain_results r join public.screening_sessions s on s.id=r.session_id
  where s.source_pcucode=btrim(p_source_pcucode) and s.source_pid=p_source_pid and s.screening_date<date '2026-10-01'
    and (v_route='all' or s.route=v_route) on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;

  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'mental_2q',m.id::text,m.source_pcucode,m.source_pid,to_jsonb(m),auth.uid(),v_reason,v_batch
  from public.mental_health_2q_screenings_v206 m join public.screening_sessions s on s.id=m.session_id
  where s.source_pcucode=btrim(p_source_pcucode) and s.source_pid=p_source_pid and s.screening_date<date '2026-10-01'
    and (v_route='all' or s.route=v_route) on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;

  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'child_development',d.id::text,d.source_pcucode,d.source_pid,to_jsonb(d),auth.uid(),v_reason,v_batch
  from public.child_development_screenings d join public.screening_sessions s on s.id=d.session_id
  where s.source_pcucode=btrim(p_source_pcucode) and s.source_pid=p_source_pid and s.screening_date<date '2026-10-01'
    and (v_route='all' or s.route=v_route) on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;

  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'growth',g.id::text,g.source_pcucode,g.source_pid,to_jsonb(g),auth.uid(),v_reason,v_batch
  from public.health_growth_screenings g join public.screening_sessions s on s.id=g.session_id
  where s.source_pcucode=btrim(p_source_pcucode) and s.source_pid=p_source_pid and s.screening_date<date '2026-10-01'
    and (v_route='all' or s.route=v_route) on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;

  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'screening_session',s.id::text,s.source_pcucode,s.source_pid,to_jsonb(s),auth.uid(),v_reason,v_batch
  from public.screening_sessions s
  where s.source_pcucode=btrim(p_source_pcucode) and s.source_pid=p_source_pid and s.screening_date<date '2026-10-01'
    and (v_route='all' or s.route=v_route) on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;

  if v_route in ('all','youth_15_34','ncd_35_59','elderly_60_plus') then
    insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
    select 'ncd',n.id::text,n.source_pcucode,n.source_pid,to_jsonb(n),auth.uid(),v_reason,v_batch
    from public.health_ncd_screenings n
    where n.source_pcucode=btrim(p_source_pcucode) and n.source_pid=p_source_pid and n.record_mode='test'
    on conflict(entity_type,original_id) do nothing;
    get diagnostics v_n=row_count;v_archived:=v_archived+v_n;
  end if;

  delete from public.screening_sessions s
  where s.source_pcucode=btrim(p_source_pcucode) and s.source_pid=p_source_pid and s.screening_date<date '2026-10-01'
    and (v_route='all' or s.route=v_route);
  get diagnostics v_sessions=row_count;

  if v_route in ('all','youth_15_34','ncd_35_59','elderly_60_plus') then
    delete from public.health_ncd_screenings n
    where n.source_pcucode=btrim(p_source_pcucode) and n.source_pid=p_source_pid and n.record_mode='test';
    get diagnostics v_ncd=row_count;
  end if;

  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,source_pid,severity,details)
  values(auth.uid(),'RESET_TEST','age_screening',v_batch::text,btrim(p_source_pcucode),p_source_pid,'test',
    jsonb_build_object('route',v_route,'archived_rows',v_archived,'deleted_sessions',v_sessions,'deleted_ncd',v_ncd,'reason',v_reason,'go_live_date','2026-10-01'));

  return jsonb_build_object('ok',true,'route',v_route,'archived_rows',v_archived,'deleted_sessions',v_sessions,'deleted_ncd',v_ncd,'reset_batch',v_batch,'go_live_date','2026-10-01');
end;
$$;

revoke all on function public.reset_person_test_screening_v208(text,bigint,text,text) from public,anon;

grant execute on function public.reset_person_test_screening_v208(text,bigint,text,text) to authenticated;

create or replace function public.test_reset_preview_v208()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  return jsonb_build_object(
    'go_live_date','2026-10-01','reset_open',current_date<date '2026-10-01',
    'sessions',(select count(*) from public.screening_sessions where screening_date<date '2026-10-01'),
    'ncd',(select count(*) from public.health_ncd_screenings where record_mode='test'),
    'growth',(select count(*) from public.health_growth_screenings g join public.screening_sessions s on s.id=g.session_id where s.screening_date<date '2026-10-01'),
    'child_development',(select count(*) from public.child_development_screenings d join public.screening_sessions s on s.id=d.session_id where s.screening_date<date '2026-10-01'),
    'mental_2q',(select count(*) from public.mental_health_2q_screenings_v206 m join public.screening_sessions s on s.id=m.session_id where s.screening_date<date '2026-10-01'),
    'elderly_domains',(select count(*) from public.elderly9_domain_results r join public.screening_sessions s on s.id=r.session_id where s.screening_date<date '2026-10-01'),
    'followups',(select count(*) from public.screening_followups f join public.screening_sessions s on s.id=f.session_id where s.screening_date<date '2026-10-01'),
    'archive_rows',(select count(*) from public.screening_test_reset_archive_v208)
  );
end;
$$;

revoke all on function public.test_reset_preview_v208() from public,anon;

grant execute on function public.test_reset_preview_v208() to authenticated;

create or replace function public.admin_reset_all_test_screenings_v208(p_reason text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_reason text:=left(btrim(coalesce(p_reason,'')),500);v_batch uuid:=extensions.gen_random_uuid();
  v_archived integer:=0;v_n integer:=0;v_sessions integer:=0;v_ncd integer:=0;
begin
  if current_date>=date '2026-10-01' then raise exception 'TEST_RESET_CLOSED'; end if;
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  if length(v_reason)<5 then raise exception 'RESET_REASON_REQUIRED'; end if;

  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'screening_followup',f.id::text,f.source_pcucode,f.source_pid,to_jsonb(f),auth.uid(),v_reason,v_batch from public.screening_followups f join public.screening_sessions s on s.id=f.session_id where s.screening_date<date '2026-10-01' on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;
  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'elderly9_domain',r.id::text,r.source_pcucode,r.source_pid,to_jsonb(r),auth.uid(),v_reason,v_batch from public.elderly9_domain_results r join public.screening_sessions s on s.id=r.session_id where s.screening_date<date '2026-10-01' on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;
  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'mental_2q',m.id::text,m.source_pcucode,m.source_pid,to_jsonb(m),auth.uid(),v_reason,v_batch from public.mental_health_2q_screenings_v206 m join public.screening_sessions s on s.id=m.session_id where s.screening_date<date '2026-10-01' on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;
  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'child_development',d.id::text,d.source_pcucode,d.source_pid,to_jsonb(d),auth.uid(),v_reason,v_batch from public.child_development_screenings d join public.screening_sessions s on s.id=d.session_id where s.screening_date<date '2026-10-01' on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;
  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'growth',g.id::text,g.source_pcucode,g.source_pid,to_jsonb(g),auth.uid(),v_reason,v_batch from public.health_growth_screenings g join public.screening_sessions s on s.id=g.session_id where s.screening_date<date '2026-10-01' on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;
  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'screening_session',s.id::text,s.source_pcucode,s.source_pid,to_jsonb(s),auth.uid(),v_reason,v_batch from public.screening_sessions s where s.screening_date<date '2026-10-01' on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;
  insert into public.screening_test_reset_archive_v208(entity_type,original_id,source_pcucode,source_pid,original_row,reset_by,reason,reset_batch)
  select 'ncd',n.id::text,n.source_pcucode,n.source_pid,to_jsonb(n),auth.uid(),v_reason,v_batch from public.health_ncd_screenings n where n.record_mode='test' on conflict(entity_type,original_id) do nothing;
  get diagnostics v_n=row_count;v_archived:=v_archived+v_n;

  delete from public.screening_sessions where screening_date<date '2026-10-01';get diagnostics v_sessions=row_count;
  delete from public.health_ncd_screenings where record_mode='test';get diagnostics v_ncd=row_count;

  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'RESET_TEST_ALL','age_screening',v_batch::text,'test',jsonb_build_object('archived_rows',v_archived,'deleted_sessions',v_sessions,'deleted_ncd',v_ncd,'reason',v_reason,'go_live_date','2026-10-01'));
  return jsonb_build_object('ok',true,'archived_rows',v_archived,'deleted_sessions',v_sessions,'deleted_ncd',v_ncd,'reset_batch',v_batch,'go_live_date','2026-10-01');
end;
$$;

revoke all on function public.admin_reset_all_test_screenings_v208(text) from public,anon;

grant execute on function public.admin_reset_all_test_screenings_v208(text) to authenticated;

insert into public.app_settings(key,value)
values('test_reset_v208',jsonb_build_object(
  'version','2.0.8','go_live_date','2026-10-01','pre_go_live_mode','test','production_counting_before_go_live',false,
  'reset_visible_before_go_live',true,'person_reset_roles',jsonb_build_array('user','staff','admin'),'admin_bulk_reset',true,
  'archive_before_delete',true,'preserve_source_history',jsonb_build_array('JHCIS','J-Report','3Doctor'),'jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
