
begin;

alter table public.health_screening_target_cache_v2030
  add column if not exists dm_target boolean not null default false,
  add column if not exists ht_target boolean not null default false,
  add column if not exists dm_screened_current_fy boolean not null default false,
  add column if not exists ht_screened_current_fy boolean not null default false;

create index if not exists health_target_cache_dm_due_v2117_idx
  on public.health_screening_target_cache_v2030(volunteer_pid,dm_target,dm_screened_current_fy,community,hcode,source_pid);
create index if not exists health_target_cache_ht_due_v2117_idx
  on public.health_screening_target_cache_v2030(volunteer_pid,ht_target,ht_screened_current_fy,community,hcode,source_pid);

create or replace function public.refresh_screening_target_cache_v2030()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_count bigint;
  v_production_merged bigint:=0;
  v_fy_start date;
begin
  if auth.role()<>'service_role' and (auth.uid() is null or private.current_role()<>'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;

  v_fy_start:=greatest(
    date '2026-10-01',
    case when extract(month from current_date)>=10
      then make_date(extract(year from current_date)::int,10,1)
      else make_date(extract(year from current_date)::int-1,10,1)
    end
  );

  truncate table public.health_screening_target_cache_v2030;

  insert into public.health_screening_target_cache_v2030
  select w.*,
    (coalesce(w.age_years,0)>=35 and not coalesce(w.has_dm,false)) as dm_target,
    (coalesce(w.age_years,0)>=35 and not coalesce(w.has_ht,false)) as ht_target,
    (
      coalesce(w.age_years,0)>=35
      and not coalesce(w.has_dm,false)
      and w.previous_screened_on between v_fy_start and current_date
      and coalesce(w.previous_glucose_mg_dl,0)>0
    ) as dm_screened_current_fy,
    (
      coalesce(w.age_years,0)>=35
      and not coalesce(w.has_ht,false)
      and w.previous_screened_on between v_fy_start and current_date
      and coalesce(w.previous_sbp,0)>0
      and coalesce(w.previous_dbp,0)>0
    ) as ht_screened_current_fy
  from public.health_screening_target_worklist_v2026 w;

  update public.health_screening_target_cache_v2030
     set ncd_target=(dm_target or ht_target);

  get diagnostics v_count=row_count;

  with latest_production as (
    select distinct on (s.source_pcucode,s.source_pid)
      s.source_pcucode,s.source_pid,s.screened_on,s.ncd_status,s.severity,
      s.weight_kg,s.height_cm,s.waist_cm,s.sbp,s.dbp,s.glucose_mg_dl,s.bmi,
      s.smoking_frequency,s.alcohol_frequency,s.exercise_frequency
    from public.health_ncd_screenings s
    where coalesce(s.record_mode,'production')='production'
    order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
  )
  update public.health_screening_target_cache_v2030 c set
    latest_screened_on=s.screened_on,
    latest_ncd_status=s.ncd_status,
    latest_severity=s.severity,
    screened_current_fy=s.screened_on>=v_fy_start and s.screened_on<=current_date,
    dm_screened_current_fy=(
      c.dm_screened_current_fy
      or (c.dm_target and s.screened_on between v_fy_start and current_date and coalesce(s.glucose_mg_dl,0)>0)
    ),
    ht_screened_current_fy=(
      c.ht_screened_current_fy
      or (c.ht_target and s.screened_on between v_fy_start and current_date and coalesce(s.sbp,0)>0 and coalesce(s.dbp,0)>0)
    ),
    previous_screened_on=s.screened_on,
    previous_weight_kg=s.weight_kg,
    previous_height_cm=s.height_cm,
    previous_waist_cm=s.waist_cm,
    previous_sbp=s.sbp,
    previous_dbp=s.dbp,
    previous_glucose_mg_dl=s.glucose_mg_dl,
    previous_bmi=s.bmi,
    previous_source='เธญเธชเธก. เธเธฅเธฑเธช',
    previous_smoking=coalesce(s.smoking_frequency,''),
    previous_alcohol=coalesce(s.alcohol_frequency,''),
    previous_exercise=coalesce(s.exercise_frequency,'')
  from latest_production s
  where c.source_pcucode=s.source_pcucode and c.source_pid=s.source_pid
    and (c.previous_screened_on is null or s.screened_on>=c.previous_screened_on);

  get diagnostics v_production_merged=row_count;

  return jsonb_build_object(
    'ok',true,
    'cached_rows',(select count(*) from public.health_screening_target_cache_v2030),
    'dm_targets',(select count(*) from public.health_screening_target_cache_v2030 where dm_target),
    'ht_targets',(select count(*) from public.health_screening_target_cache_v2030 where ht_target),
    'production_screenings_restored',v_production_merged,
    'version','2.0.117'
  );
end;
$function$;

create or replace function public.screening_plan_for_person_v2023(
  p_source_pcucode text,
  p_source_pid bigint,
  p_screening_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  p public.health_persons%rowtype;
  pl public.health_screening_plan_v2023%rowtype;
  s public.screening_sessions%rowtype;
  n public.health_ncd_screenings%rowtype;
  v_day date:=coalesce(p_screening_date,current_date);
  v_years integer;v_months integer;v_route text;v_label text;v_target integer;v_source text:='precomputed';
  v_mode text;
  v_dm_target boolean:=false;
  v_ht_target boolean:=false;
  v_ncd_required boolean:=false;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  if v_day>current_date+1 then raise exception 'SCREENING_DATE_IN_FUTURE'; end if;

  select * into p from public.health_persons
  where source_pcucode=btrim(p_source_pcucode) and source_pid=p_source_pid and active=true;
  if not found then raise exception 'PERSON_NOT_FOUND'; end if;
  if p.jhcis_typelive not in (1,3) then raise exception 'PERSON_NOT_TYPE13_TARGET'; end if;
  if not private.health_can_access_person(p.source_pcucode,p.source_pid) then raise exception 'PERSON_OUT_OF_SCOPE'; end if;
  if p.birth_date is null or p.birth_date>v_day then raise exception 'BIRTH_DATE_REQUIRED'; end if;

  select * into pl from public.health_screening_plan_v2023
  where source_pcucode=p.source_pcucode and source_pid=p.source_pid and plan_date=v_day;
  if found then
    v_years:=pl.age_years;v_months:=pl.age_months;v_route:=pl.route;v_label:=pl.route_label;v_target:=pl.dspm_target_months;
  else
    v_source:='live_fallback';
    v_years:=extract(year from age(v_day,p.birth_date))::integer;
    v_months:=(v_years*12)+extract(month from age(v_day,p.birth_date))::integer;
    v_route:=private.screening_route_v190(v_months);
    v_target:=case when v_route='child_0_5' then private.closest_dspm_target_v190(v_months) else null end;
    v_label:=case v_route
      when 'child_0_5' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ + เธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธเธทเนเธญเธเธ•เนเธ'
      when 'school_6_14' then 'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ'
      when 'youth_15_34' then 'เธเธฑเธ”เธเธฃเธญเธเน€เธชเธฃเธดเธกเธ•เธฒเธกเธเนเธงเธเธ—เธตเน Admin เน€เธเธดเธ”'
      when 'ncd_35_59' then 'NCD Screening'
      else 'NCD Screening เธเนเธญเธ เนเธฅเนเธงเธ—เธณเธเธนเนเธชเธนเธเธญเธฒเธขเธธ 9 เธ”เนเธฒเธ'
    end;
  end if;

  v_dm_target:=v_years>=35 and not coalesce(p.has_dm,false);
  v_ht_target:=v_years>=35 and not coalesce(p.has_ht,false);
  v_ncd_required:=v_route in ('ncd_35_59','elderly_60_plus') and (v_dm_target or v_ht_target);

  v_mode:=private.screening_record_mode_v208(v_day);
  if v_ncd_required then
    select * into n from public.health_ncd_screenings x
    where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid
      and x.screened_on=v_day and coalesce(x.record_mode,'production')=v_mode
    order by x.recorded_at desc limit 1;
  end if;

  select * into s from public.screening_sessions x
  where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid
    and x.screening_date=v_day and x.started_by=auth.uid()
  limit 1;

  return jsonb_build_object(
    'session_id',case when s.id is null then null else s.id end,
    'source_pcucode',p.source_pcucode,'source_pid',p.source_pid,'display_name',p.display_name,
    'age_years',v_years,'age_months',v_months,'route',v_route,'route_label',v_label,
    'dspm_target_months',v_target,'plan_date',v_day,'plan_source',v_source,
    'population_definition','jhcis_typelive_1_3',
    'record_mode',v_mode,'go_live_date','2026-10-01',
    'has_dm',coalesce(p.has_dm,false),'has_ht',coalesce(p.has_ht,false),
    'dm_target',v_dm_target,'ht_target',v_ht_target,
    'ncd_required',v_ncd_required,
    'ncd_screening_id',case when n.id is null then s.ncd_screening_id else n.id end,
    'ncd_status',case
      when v_route not in ('ncd_35_59','elderly_60_plus') then 'not_required'
      when not v_ncd_required then 'not_required'
      when n.id is not null or s.ncd_status='complete' then 'complete'
      else 'required'
    end,
    'elderly9_status',case
      when v_route<>'elderly_60_plus' then 'not_required'
      when not v_ncd_required then coalesce(nullif(s.elderly9_status,'not_required'),'in_progress')
      when n.id is null and coalesce(s.ncd_status,'required')<>'complete' then 'blocked_by_ncd'
      else coalesce(nullif(s.elderly9_status,'not_required'),'in_progress')
    end,
    'completed_domains',coalesce(s.completed_domains,'{}'::text[])
  );
end;
$function$;

create or replace function public.start_age_screening_v190(
  p_source_pcucode text,
  p_source_pid bigint,
  p_screening_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_plan jsonb;
  p public.health_persons%rowtype;
  s public.screening_sessions%rowtype;
  n_id uuid;
  v_day date:=coalesce(p_screening_date,current_date);
  v_route text;v_ncd_status text;v_elderly text;
begin
  v_plan:=public.screening_plan_for_person_v2023(p_source_pcucode,p_source_pid,v_day);
  v_route:=v_plan->>'route';
  v_ncd_status:=v_plan->>'ncd_status';
  v_elderly:=v_plan->>'elderly9_status';
  n_id:=nullif(v_plan->>'ncd_screening_id','')::uuid;

  select * into s from public.screening_sessions x
  where x.source_pcucode=btrim(p_source_pcucode) and x.source_pid=p_source_pid
    and x.screening_date=v_day and x.started_by=auth.uid()
  limit 1;

  if found then
    if v_route in ('ncd_35_59','elderly_60_plus') then
      update public.screening_sessions set
        ncd_screening_id=case when v_ncd_status='complete' then coalesce(n_id,ncd_screening_id) else null end,
        ncd_status=v_ncd_status,
        elderly9_status=case
          when route<>'elderly_60_plus' then 'not_required'
          when elderly9_status='complete' then 'complete'
          when v_elderly='in_progress' then 'in_progress'
          else v_elderly
        end,
        updated_at=now()
      where id=s.id returning * into s;
    end if;
  else
    select * into p from public.health_persons
    where source_pcucode=btrim(p_source_pcucode) and source_pid=p_source_pid and active=true;

    insert into public.screening_sessions(
      source_pcucode,source_pid,house_pcucode,hcode,screening_date,age_years,age_months,route,
      ncd_screening_id,ncd_status,elderly9_status,started_by
    ) values(
      p.source_pcucode,p.source_pid,p.house_pcucode,p.hcode,v_day,
      (v_plan->>'age_years')::integer,(v_plan->>'age_months')::integer,v_route,
      case when v_ncd_status='complete' then n_id else null end,
      case when v_route in ('ncd_35_59','elderly_60_plus') then v_ncd_status else 'not_required' end,
      case when v_route='elderly_60_plus' then v_elderly else 'not_required' end,
      auth.uid()
    ) returning * into s;
  end if;

  return v_plan || jsonb_build_object(
    'session_id',s.id,
    'ncd_screening_id',s.ncd_screening_id,
    'ncd_status',s.ncd_status,'elderly9_status',s.elderly9_status,
    'completed_domains',s.completed_domains
  );
end;
$function$;

do $patch$
declare
  ddl text;
  old_filter text;
  new_filter text;
begin
  select pg_get_functiondef(p.oid) into ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='health_worklist_assignment_json_v2054'
  order by p.oid desc limit 1;

  old_filter:=E'        and coalesce(c.screened_current_fy,false)=false\n        and (c.latest_screened_on is null or c.latest_screened_on::date<>current_date)';
  new_filter:=E'        and (\n          (coalesce(c.screening_route,'''')=''ncd_35_59'' and (\n            (coalesce(c.dm_target,false) and not coalesce(c.dm_screened_current_fy,false))\n            or (coalesce(c.ht_target,false) and not coalesce(c.ht_screened_current_fy,false))\n          ))\n          or (coalesce(c.screening_route,'''')<>''ncd_35_59''\n              and coalesce(c.screened_current_fy,false)=false\n              and (c.latest_screened_on is null or c.latest_screened_on::date<>current_date))\n        )';

  if ddl is null or position(old_filter in ddl)=0 then
    raise exception 'V2054_FILTER_PATCH_NOT_FOUND';
  end if;
  ddl:=replace(ddl,old_filter,new_filter);
  ddl:=replace(ddl,'''version'',''2.0.54''','''version'',''2.0.117''');
  execute ddl;

  select pg_get_functiondef(p.oid) into ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='health_worklist_assignment_json_v2033'
  order by p.oid desc limit 1;

  if ddl is null or position(old_filter in ddl)=0 then
    raise exception 'V2033_FIELD_FILTER_PATCH_NOT_FOUND';
  end if;
  ddl:=replace(ddl,old_filter,new_filter);
  ddl:=replace(
    ddl,
    E'(v_filter=''due'' and coalesce(w.ncd_target,false) and not coalesce(w.screened_current_fy,false))\n        or (v_filter=''targets'' and coalesce(w.ncd_target,false))',
    E'(v_filter=''due'' and coalesce(w.age_years,0)>=35 and (not coalesce(w.has_dm,false) or not coalesce(w.has_ht,false)) and not coalesce(w.screened_current_fy,false))\n        or (v_filter=''targets'' and coalesce(w.age_years,0)>=35 and (not coalesce(w.has_dm,false) or not coalesce(w.has_ht,false)))'
  );
  ddl:=replace(ddl,'''version'',''2.0.33''','''version'',''2.0.117''');
  execute ddl;
end
$patch$;

do $patch$
declare
  ddl text;
  old_guard text:=E'if s.ncd_status<>''complete'' or s.ncd_screening_id is null then raise exception ''NCD_SCREENING_REQUIRED_FIRST''; end if;';
  new_guard text:=E'if s.ncd_status not in (''complete'',''not_required'') then raise exception ''NCD_SCREENING_REQUIRED_FIRST''; end if;\n  if s.ncd_status=''complete'' and s.ncd_screening_id is null then raise exception ''NCD_SCREENING_REQUIRED_FIRST''; end if;';
begin
  select pg_get_functiondef(p.oid) into ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='save_elderly9_domain_v190'
  order by p.oid desc limit 1;
  if ddl is null or position(old_guard in ddl)=0 then raise exception 'ELDERLY_V190_GUARD_PATCH_NOT_FOUND'; end if;
  execute replace(ddl,old_guard,new_guard);

  select pg_get_functiondef(p.oid) into ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='save_elderly9_community_v207'
  order by p.oid desc limit 1;
  if ddl is null or position(old_guard in ddl)=0 then raise exception 'ELDERLY_V207_GUARD_PATCH_NOT_FOUND'; end if;
  execute replace(ddl,old_guard,new_guard);
end
$patch$;

insert into public.app_settings(key,value)
values(
  'ncd_disease_specific_targets_v2117',
  jsonb_build_object(
    'version','2.0.117',
    'population_scope','jhcis_typelive_1_3',
    'dm_target','age>=35 AND NOT has_dm',
    'ht_target','age>=35 AND NOT has_ht',
    'known_both_ncd_screening_required',false,
    'elderly_known_both_go_direct_elderly9',true,
    'jhcis_write_back',false
  )
)
on conflict(key) do update set value=excluded.value,updated_at=now();

select public.refresh_screening_target_cache_v2030();

notify pgrst,'reload schema';
commit;
