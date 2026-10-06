begin;
alter table public.health_screening_target_cache_v2030
  add column if not exists elderly9_status_current_fy text not null default 'not_required',
  add column if not exists elderly9_completed_current_fy boolean not null default false,
  add column if not exists elderly9_completed_domains_current_fy smallint not null default 0,
  add column if not exists latest_elderly9_screened_on date;

create index if not exists health_target_cache_elderly_due_v2194_idx
  on public.health_screening_target_cache_v2030
  (volunteer_pid,elderly9_completed_current_fy,community,hcode,source_pid)
  where screening_route='elderly_60_plus';

create or replace function private.sync_elderly9_target_cache_person_v2194()
returns trigger language plpgsql security definer set search_path to ''
as $function$
declare
  v_pcucode text; v_pid bigint; v_today date:=timezone('Asia/Bangkok',now())::date; v_fy_start date;
  v_complete boolean:=false; v_progress boolean:=false; v_complete_on date; v_progress_on date; v_domains smallint:=0;
begin
  if tg_op='DELETE' then v_pcucode:=old.source_pcucode;v_pid:=old.source_pid;
  else v_pcucode:=new.source_pcucode;v_pid:=new.source_pid; end if;
  if tg_op='UPDATE' and coalesce(new.route,'')<>'elderly_60_plus' and coalesce(old.route,'')<>'elderly_60_plus' then return null;
  elsif tg_op='INSERT' and coalesce(new.route,'')<>'elderly_60_plus' then return null;
  elsif tg_op='DELETE' and coalesce(old.route,'')<>'elderly_60_plus' then return null; end if;
  v_fy_start:=greatest(date '2026-10-01',case when extract(month from v_today)>=10 then make_date(extract(year from v_today)::int,10,1) else make_date(extract(year from v_today)::int-1,10,1) end);
  select coalesce(bool_or(s.elderly9_status='complete'),false),coalesce(bool_or(s.elderly9_status='in_progress'),false),
    max(s.screening_date) filter(where s.elderly9_status='complete'),max(s.screening_date) filter(where s.elderly9_status='in_progress'),
    greatest(coalesce(max(cardinality(coalesce(s.completed_domains,'{}'::text[]))),0),case when coalesce(bool_or(s.elderly9_status='complete'),false) then 9 else 0 end)::smallint
  into v_complete,v_progress,v_complete_on,v_progress_on,v_domains
  from public.screening_sessions s
  where s.source_pcucode=v_pcucode and s.source_pid=v_pid and s.route='elderly_60_plus'
    and s.screening_date between v_fy_start and v_today and s.elderly9_status in ('complete','in_progress');
  update public.health_screening_target_cache_v2030 c set
    elderly9_status_current_fy=case when coalesce(c.screening_route,'')<>'elderly_60_plus' then 'not_required' when v_complete then 'complete' when v_progress then 'in_progress' else 'not_started' end,
    elderly9_completed_current_fy=case when coalesce(c.screening_route,'')='elderly_60_plus' then v_complete else false end,
    elderly9_completed_domains_current_fy=case when coalesce(c.screening_route,'')='elderly_60_plus' then coalesce(v_domains,0) else 0 end,
    latest_elderly9_screened_on=case when coalesce(c.screening_route,'')<>'elderly_60_plus' then null when v_complete then v_complete_on when v_progress then v_progress_on else null end
  where c.source_pcucode=v_pcucode and c.source_pid=v_pid;
  return null;
end;
$function$;
drop trigger if exists trg_sync_elderly9_target_cache_v2194 on public.screening_sessions;
create trigger trg_sync_elderly9_target_cache_v2194 after insert or update or delete on public.screening_sessions
for each row execute function private.sync_elderly9_target_cache_person_v2194();
revoke all on function private.sync_elderly9_target_cache_person_v2194() from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.refresh_screening_target_cache_v2030()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    ) as ht_screened_current_fy,
    case when coalesce(w.screening_route,'')='elderly_60_plus' then 'not_started' else 'not_required' end as elderly9_status_current_fy,
    false as elderly9_completed_current_fy,
    0::smallint as elderly9_completed_domains_current_fy,
    null::date as latest_elderly9_screened_on
  from public.health_screening_target_worklist_v2026 w;

  update public.health_screening_target_cache_v2030
     set ncd_target=(birth_date is not null and extract(year from age(v_fy_start,birth_date))::int>=35 and not coalesce(has_dm,false) and not coalesce(has_ht,false)) where source_pcucode is not null and source_pid is not null;

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
    previous_source='อสม. พลัส',
    previous_smoking=coalesce(s.smoking_frequency,''),
    previous_alcohol=coalesce(s.alcohol_frequency,''),
    previous_exercise=coalesce(s.exercise_frequency,'')
  from latest_production s
  where c.source_pcucode=s.source_pcucode and c.source_pid=s.source_pid
    and (c.previous_screened_on is null or s.screened_on>=c.previous_screened_on);

  get diagnostics v_production_merged=row_count;

  with e as (
    select s.source_pcucode,s.source_pid,
      coalesce(bool_or(s.elderly9_status='complete'),false) as is_complete,
      coalesce(bool_or(s.elderly9_status='in_progress'),false) as is_progress,
      max(s.screening_date) filter(where s.elderly9_status='complete') as complete_on,
      max(s.screening_date) filter(where s.elderly9_status='in_progress') as progress_on,
      greatest(coalesce(max(cardinality(coalesce(s.completed_domains,'{}'::text[]))),0),
        case when coalesce(bool_or(s.elderly9_status='complete'),false) then 9 else 0 end)::smallint as completed_domains
    from public.screening_sessions s
    where s.route='elderly_60_plus'
      and s.screening_date between v_fy_start and current_date
      and s.elderly9_status in ('complete','in_progress')
    group by s.source_pcucode,s.source_pid
  )
  update public.health_screening_target_cache_v2030 c set
    elderly9_status_current_fy=case when coalesce(c.screening_route,'')<>'elderly_60_plus' then 'not_required'
      when coalesce(e.is_complete,false) then 'complete'
      when coalesce(e.is_progress,false) then 'in_progress' else 'not_started' end,
    elderly9_completed_current_fy=case when coalesce(c.screening_route,'')='elderly_60_plus' then coalesce(e.is_complete,false) else false end,
    elderly9_completed_domains_current_fy=case when coalesce(c.screening_route,'')='elderly_60_plus' then coalesce(e.completed_domains,0) else 0 end,
    latest_elderly9_screened_on=case when coalesce(c.screening_route,'')<>'elderly_60_plus' then null
      when coalesce(e.is_complete,false) then e.complete_on
      when coalesce(e.is_progress,false) then e.progress_on else null end
  from e
  where c.source_pcucode=e.source_pcucode and c.source_pid=e.source_pid;

  return jsonb_build_object(
    'ok',true,
    'cached_rows',(select count(*) from public.health_screening_target_cache_v2030),
    'dm_targets',(select count(*) from public.health_screening_target_cache_v2030 where dm_target),
    'ht_targets',(select count(*) from public.health_screening_target_cache_v2030 where ht_target),
    'production_screenings_restored',v_production_merged,
    'version','2.0.151'
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.health_worklist_assignment_json_v2033(p_scope text DEFAULT 'self'::text, p_filter text DEFAULT 'field_targets'::text, p_stage text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_community text DEFAULT NULL::text, p_assignment text DEFAULT 'all'::text, p_owner_pid bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;v_owner bigint:=p_owner_pid;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));v_filter text:=lower(btrim(coalesce(p_filter,'field_targets')));
  v_assignment text:=lower(btrim(coalesce(p_assignment,'all')));v_stage text:=nullif(btrim(coalesce(p_stage,'')),'');
  v_search text:=left(regexp_replace(btrim(coalesce(p_search,'')),'[%_(),]','','g'),60);
  v_filter_community text:=nullif(btrim(coalesce(p_community,'')),'');
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);v_offset integer:=greatest(coalesce(p_offset,0),0);v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_role='admin' then v_scope:='all';v_owner:=null;
  elsif v_role='user' then v_scope:='self';v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(select 1 from public.profiles p join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner and private.community_key(p.community)=private.community_key(v_community))
      then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    elsif v_scope not in ('self','community') then v_scope:='self';v_owner:=v_pid;
    else v_owner:=case when v_scope='self' then v_pid else null end; end if;
  else raise exception 'ROLE_NOT_ALLOWED'; end if;
  if v_filter not in ('field_targets','due','targets','known','all') then v_filter:='field_targets'; end if;
  if v_assignment not in ('all','assigned','fallback','unresolved') then v_assignment:='all'; end if;
  if v_scope<>'community' and v_role<>'admin' then v_assignment:='all'; end if;

  if v_filter='field_targets' then
    with active_vhv as materialized(select distinct v.source_pid from public.volunteers v where v.active=true),
    active_ops as materialized(select distinct v.source_pid from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid where v.active=true and p.active=true and p.role in ('user','staff')),
    base as(
      select c.*,
        case when nullif(private.community_key(c.community),'') is null then 'unresolved'
          when c.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback' else 'assigned' end assignment_status,
        case when nullif(private.community_key(c.community),'') is null then 'missing_community'
          when c.volunteer_pid is null then 'no_volunteer' when av.source_pid is null then 'inactive_volunteer'
          when ao.source_pid is null then 'no_active_user' else 'assigned' end assignment_reason
      from public.health_screening_target_cache_v2030 c
      left join active_vhv av on av.source_pid=c.volunteer_pid left join active_ops ao on ao.source_pid=c.volunteer_pid
      where (v_role='admin' or (v_scope in ('self','volunteer') and v_owner is not null and c.volunteer_pid=v_owner)
        or (v_role='staff' and v_scope='community' and private.community_key(c.community)=private.community_key(v_community)))
        and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
        and (v_stage is null or c.life_stage=v_stage) and (v_search='' or c.display_name ilike('%'||v_search||'%'))
        and (
          (coalesce(c.screening_route,'')='ncd_35_59' and (
            (coalesce(c.dm_target,false) and not coalesce(c.dm_screened_current_fy,false))
            or (coalesce(c.ht_target,false) and not coalesce(c.ht_screened_current_fy,false))
          ))
          or (coalesce(c.screening_route,'')='elderly_60_plus' and (
            (coalesce(c.dm_target,false) and not coalesce(c.dm_screened_current_fy,false))
            or (coalesce(c.ht_target,false) and not coalesce(c.ht_screened_current_fy,false))
            or not coalesce(c.elderly9_completed_current_fy,false)
          ))
          or (coalesce(c.screening_route,'') not in ('ncd_35_59','elderly_60_plus')
              and coalesce(c.screened_current_fy,false)=false
              and (c.latest_screened_on is null or c.latest_screened_on::date<>current_date))
        )
    ), filtered as(
      select b.*,case when b.assignment_reason='missing_community' then 'ไม่ระบุชุมชน · ส่งให้ Admin ตรวจสอบ'
        when b.assignment_reason='no_volunteer' then 'ยังไม่มี อสม.รับผิดชอบ · Staff ดูแลชั่วคราว'
        when b.assignment_reason='inactive_volunteer' then 'อสม.เดิมไม่ปฏิบัติงานแล้ว · Staff ดูแลชั่วคราว'
        when b.assignment_reason='no_active_user' then 'มี อสม.แต่ยังไม่มีบัญชีใช้งาน · Staff ดูแลชั่วคราว'
        else 'มีผู้รับผิดชอบ' end assignment_label
      from base b where v_assignment='all' or b.assignment_status=v_assignment
    ), page as materialized(
      select * from filtered order by community,hcode,display_name,source_pid limit v_limit+1 offset v_offset
    ), visible as(select * from page order by community,hcode,display_name,source_pid limit v_limit)
    select jsonb_build_object('version','2.0.151','rows',coalesce((select jsonb_agg(to_jsonb(v) order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
      'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from page)) into v_result;
    return v_result;
  end if;

  with active_vhv as materialized(select distinct v.source_pid from public.volunteers v where v.active=true),
  active_ops as materialized(select distinct v.source_pid from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid where v.active=true and p.active=true and p.role in ('user','staff')),
  base as(
    select w.*,
      c.elderly9_status_current_fy,c.elderly9_completed_current_fy,
      c.elderly9_completed_domains_current_fy,c.latest_elderly9_screened_on,
      case when nullif(private.community_key(w.community),'') is null then 'unresolved'
        when w.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback' else 'assigned' end assignment_status,
      case when nullif(private.community_key(w.community),'') is null then 'missing_community'
        when w.volunteer_pid is null then 'no_volunteer' when av.source_pid is null then 'inactive_volunteer'
        when ao.source_pid is null then 'no_active_user' else 'assigned' end assignment_reason
    from public.health_person_worklist_active_v1847 w
    left join public.health_screening_target_cache_v2030 c
      on c.source_pcucode=w.source_pcucode and c.source_pid=w.source_pid
    left join active_vhv av on av.source_pid=w.volunteer_pid left join active_ops ao on ao.source_pid=w.volunteer_pid
    where (v_role='admin' or (v_scope in ('self','volunteer') and v_owner is not null and w.volunteer_pid=v_owner)
      or (v_role='staff' and v_scope='community' and private.community_key(w.community)=private.community_key(v_community)))
      and (v_filter_community is null or private.community_key(w.community)=private.community_key(v_filter_community))
      and (v_stage is null or w.life_stage=v_stage) and (v_search='' or w.display_name ilike('%'||v_search||'%'))
      and (v_filter='all' or (v_filter='due' and coalesce(w.age_years,0)>=35 and (not coalesce(w.has_dm,false) or not coalesce(w.has_ht,false)) and not coalesce(w.screened_current_fy,false))
        or (v_filter='targets' and coalesce(w.age_years,0)>=35 and (not coalesce(w.has_dm,false) or not coalesce(w.has_ht,false))) or (v_filter='known' and coalesce(w.known_ncd,false)))
  ), filtered as(
    select b.*,case when b.assignment_reason='missing_community' then 'ไม่ระบุชุมชน · ส่งให้ Admin ตรวจสอบ'
      when b.assignment_reason='no_volunteer' then 'ยังไม่มี อสม.รับผิดชอบ · Staff ดูแลชั่วคราว'
      when b.assignment_reason='inactive_volunteer' then 'อสม.เดิมไม่ปฏิบัติงานแล้ว · Staff ดูแลชั่วคราว'
      when b.assignment_reason='no_active_user' then 'มี อสม.แต่ยังไม่มีบัญชีใช้งาน · Staff ดูแลชั่วคราว'
      else 'มีผู้รับผิดชอบ' end assignment_label
    from base b where v_assignment='all' or b.assignment_status=v_assignment
  ), page as materialized(
    select * from filtered order by community,hcode,display_name,source_pid limit v_limit+1 offset v_offset
  ), visible as(select * from page order by community,hcode,display_name,source_pid limit v_limit)
  select jsonb_build_object('version','2.0.151','rows',coalesce((select jsonb_agg(to_jsonb(v) order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
    'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from page)) into v_result;
  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.health_worklist_assignment_json_v2054(p_scope text DEFAULT 'self'::text, p_filter text DEFAULT 'field_targets'::text, p_stage text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_community text DEFAULT NULL::text, p_assignment text DEFAULT 'all'::text, p_owner_pid bigint DEFAULT NULL::bigint, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_owner bigint:=p_owner_pid;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_filter text:=lower(btrim(coalesce(p_filter,'field_targets')));
  v_assignment text:=lower(btrim(coalesce(p_assignment,'all')));
  v_stage text:=nullif(btrim(coalesce(p_stage,'')),'');
  v_search text:=left(regexp_replace(btrim(coalesce(p_search,'')),'[%_(),]','','g'),60);
  v_filter_community text:=nullif(btrim(coalesce(p_community,'')),'');
  v_limit integer:=least(greatest(coalesce(p_limit,50),1),100);
  v_offset integer:=greatest(coalesce(p_offset,0),0);
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select role,community,volunteer_pid
    into v_role,v_community,v_pid
  from public.profiles
  where user_id=v_uid and active=true
  limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then
    v_scope:='all'; v_owner:=null;
  elsif v_role='user' then
    v_scope:='self'; v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(
        select 1
        from public.profiles p
        join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner
          and private.community_key(p.community)=private.community_key(v_community)
      ) then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    elsif v_scope not in ('self','community') then
      v_scope:='self'; v_owner:=v_pid;
    else
      v_owner:=case when v_scope='self' then v_pid else null end;
    end if;
  else
    raise exception 'ROLE_NOT_ALLOWED';
  end if;

  if v_filter<>'field_targets' then
    return public.health_worklist_assignment_json_v2033(
      v_scope,v_filter,v_stage,v_search,v_filter_community,v_assignment,
      v_owner,v_limit,v_offset
    );
  end if;

  if v_assignment not in ('all','assigned','fallback','unresolved') then v_assignment:='all'; end if;
  if v_scope<>'community' and v_role<>'admin' then v_assignment:='all'; end if;

  -- Common mobile path: current user or one selected volunteer.
  -- No runtime joins are needed; the active authenticated profile already proves
  -- the operator is allowed to see this owner scope.
  if v_scope in ('self','volunteer') and v_owner is not null then
    with page as materialized (
      select c.*
      from public.health_screening_target_cache_v2030 c
      where c.volunteer_pid=v_owner
        and (
          (coalesce(c.screening_route,'')='ncd_35_59' and (
            (coalesce(c.dm_target,false) and not coalesce(c.dm_screened_current_fy,false))
            or (coalesce(c.ht_target,false) and not coalesce(c.ht_screened_current_fy,false))
          ))
          or (coalesce(c.screening_route,'')='elderly_60_plus' and (
            (coalesce(c.dm_target,false) and not coalesce(c.dm_screened_current_fy,false))
            or (coalesce(c.ht_target,false) and not coalesce(c.ht_screened_current_fy,false))
            or not coalesce(c.elderly9_completed_current_fy,false)
          ))
          or (coalesce(c.screening_route,'') not in ('ncd_35_59','elderly_60_plus')
              and coalesce(c.screened_current_fy,false)=false
              and (c.latest_screened_on is null or c.latest_screened_on::date<>current_date))
        )
        and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
        and (v_stage is null or c.life_stage=v_stage)
        and (v_search='' or c.display_name ilike('%'||v_search||'%'))
      order by c.community,c.hcode,c.display_name,c.source_pid
      limit v_limit+1 offset v_offset
    ), visible as (
      select p.*,'assigned'::text assignment_status,'assigned'::text assignment_reason,
             'มีผู้รับผิดชอบ'::text assignment_label
      from page p
      order by community,hcode,display_name,source_pid
      limit v_limit
    )
    select jsonb_build_object(
      'version','2.0.151','source','health_screening_target_cache_v2030',
      'rows',coalesce((select jsonb_agg(to_jsonb(v) order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
      'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from page)
    ) into v_result;
    return v_result;
  end if;

  -- Staff community/admin default path: page the denormalized cache first,
  -- then classify assignment only for the <= 51 visible candidates.
  if v_assignment='all' then
    with candidates as materialized (
      select c.*
      from public.health_screening_target_cache_v2030 c
      where
        (v_role='admin'
          or (v_role='staff' and v_scope='community'
              and private.community_key(c.community)=private.community_key(v_community)))
        and (v_filter_community is null or private.community_key(c.community)=private.community_key(v_filter_community))
        and (v_stage is null or c.life_stage=v_stage)
        and (v_search='' or c.display_name ilike('%'||v_search||'%'))
        and (
          (coalesce(c.screening_route,'')='ncd_35_59' and (
            (coalesce(c.dm_target,false) and not coalesce(c.dm_screened_current_fy,false))
            or (coalesce(c.ht_target,false) and not coalesce(c.ht_screened_current_fy,false))
          ))
          or (coalesce(c.screening_route,'')='elderly_60_plus' and (
            (coalesce(c.dm_target,false) and not coalesce(c.dm_screened_current_fy,false))
            or (coalesce(c.ht_target,false) and not coalesce(c.ht_screened_current_fy,false))
            or not coalesce(c.elderly9_completed_current_fy,false)
          ))
          or (coalesce(c.screening_route,'') not in ('ncd_35_59','elderly_60_plus')
              and coalesce(c.screened_current_fy,false)=false
              and (c.latest_screened_on is null or c.latest_screened_on::date<>current_date))
        )
      order by c.community,c.hcode,c.display_name,c.source_pid
      limit v_limit+1 offset v_offset
    ), classified as (
      select c.*,
        case
          when nullif(private.community_key(c.community),'') is null then 'unresolved'
          when c.volunteer_pid is null then 'staff_fallback'
          when not exists(select 1 from public.volunteers v where v.source_pid=c.volunteer_pid and v.active=true) then 'staff_fallback'
          when not exists(select 1 from public.profiles p where p.volunteer_pid=c.volunteer_pid and p.active=true and p.role in ('user','staff')) then 'staff_fallback'
          else 'assigned'
        end::text assignment_status,
        case
          when nullif(private.community_key(c.community),'') is null then 'missing_community'
          when c.volunteer_pid is null then 'no_volunteer'
          when not exists(select 1 from public.volunteers v where v.source_pid=c.volunteer_pid and v.active=true) then 'inactive_volunteer'
          when not exists(select 1 from public.profiles p where p.volunteer_pid=c.volunteer_pid and p.active=true and p.role in ('user','staff')) then 'no_active_user'
          else 'assigned'
        end::text assignment_reason
      from candidates c
    ), visible as (
      select x.*,
        case x.assignment_reason
          when 'missing_community' then 'ไม่ระบุชุมชน · ส่งให้ Admin ตรวจสอบ'
          when 'no_volunteer' then 'ยังไม่มี อสม.รับผิดชอบ · Staff ดูแลชั่วคราว'
          when 'inactive_volunteer' then 'อสม.เดิมไม่ปฏิบัติงานแล้ว · Staff ดูแลชั่วคราว'
          when 'no_active_user' then 'มี อสม.แต่ยังไม่มีบัญชีใช้งาน · Staff ดูแลชั่วคราว'
          else 'มีผู้รับผิดชอบ'
        end::text assignment_label
      from classified x
      order by community,hcode,display_name,source_pid
      limit v_limit
    )
    select jsonb_build_object(
      'version','2.0.151','source','health_screening_target_cache_v2030',
      'rows',coalesce((select jsonb_agg(to_jsonb(v) order by community,hcode,display_name,source_pid) from visible v),'[]'::jsonb),
      'offset',v_offset,'limit',v_limit,'has_more',(select count(*)>v_limit from candidates)
    ) into v_result;
    return v_result;
  end if;

  -- Less common staff/admin assignment filters keep the validated v2033 path.
  return public.health_worklist_assignment_json_v2033(
    v_scope,v_filter,v_stage,v_search,v_filter_community,v_assignment,
    v_owner,v_limit,v_offset
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.screening_plan_for_person_v2023(p_source_pcucode text, p_source_pid bigint, p_screening_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  p public.health_persons%rowtype;
  pl public.health_screening_plan_v2023%rowtype;
  s public.screening_sessions%rowtype;
  n public.health_ncd_screenings%rowtype;
  v_day date:=coalesce(p_screening_date,current_date);
  v_years integer;v_months integer;v_route text;v_label text;v_target integer;v_source text:='precomputed';
  v_mode text;
  v_fy_start date;
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
      when 'child_0_5' then 'น้ำหนัก/ส่วนสูง + พัฒนาการเบื้องต้น'
      when 'school_6_14' then 'น้ำหนัก/ส่วนสูง'
      when 'youth_15_34' then 'คัดกรองเสริมตามช่วงที่ Admin เปิด'
      when 'ncd_35_59' then 'NCD Screening'
      else 'NCD Screening ก่อน แล้วทำผู้สูงอายุ 9 ด้าน'
    end;
  end if;

  v_dm_target:=v_years>=35 and not coalesce(p.has_dm,false);
  v_ht_target:=v_years>=35 and not coalesce(p.has_ht,false);
  v_ncd_required:=v_route in ('ncd_35_59','elderly_60_plus') and (v_dm_target or v_ht_target);
  v_fy_start:=greatest(date '2026-10-01',
    case when extract(month from v_day)>=10
      then make_date(extract(year from v_day)::int,10,1)
      else make_date(extract(year from v_day)::int-1,10,1) end);

  v_mode:=private.screening_record_mode_v208(v_day);
  if v_ncd_required then
    select * into n from public.health_ncd_screenings x
    where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid
      and x.screened_on between v_fy_start and v_day and coalesce(x.record_mode,'production')=v_mode
    order by x.recorded_at desc limit 1;
  end if;

  if v_route='elderly_60_plus' then
    select * into s from public.screening_sessions x
    where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid
      and x.route='elderly_60_plus'
      and x.screening_date between v_fy_start and v_day
      and x.elderly9_status in ('complete','in_progress')
    order by case when x.elderly9_status='complete' then 0 else 1 end,
             x.screening_date desc,x.updated_at desc
    limit 1;
    if not found then
      select * into s from public.screening_sessions x
      where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid
        and x.screening_date=v_day and x.started_by=auth.uid()
      limit 1;
    end if;
  else
    select * into s from public.screening_sessions x
    where x.source_pcucode=p.source_pcucode and x.source_pid=p.source_pid
      and x.screening_date=v_day and x.started_by=auth.uid()
    limit 1;
  end if;

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
      when s.elderly9_status='complete' then 'complete'
      when not v_ncd_required then coalesce(nullif(s.elderly9_status,'not_required'),'in_progress')
      when n.id is null and coalesce(s.ncd_status,'required')<>'complete' then 'blocked_by_ncd'
      else coalesce(nullif(s.elderly9_status,'not_required'),'in_progress')
    end,
    'elderly9_completed_current_fy',(v_route='elderly_60_plus' and s.elderly9_status='complete'),
    'elderly9_completed_domains_current_fy',case
      when v_route='elderly_60_plus' then greatest(coalesce(cardinality(s.completed_domains),0),case when s.elderly9_status='complete' then 9 else 0 end)
      else 0 end,
    'latest_elderly9_screened_on',case
      when v_route='elderly_60_plus' and s.elderly9_status in ('complete','in_progress') then s.screening_date
      else null end,
    'completed_domains',coalesce(s.completed_domains,'{}'::text[])
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.start_age_screening_v190(p_source_pcucode text, p_source_pid bigint, p_screening_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  if nullif(v_plan->>'session_id','') is not null then
    select * into s from public.screening_sessions x
    where x.id=(v_plan->>'session_id')::uuid
      and x.source_pcucode=btrim(p_source_pcucode)
      and x.source_pid=p_source_pid;
  end if;

  if not found then
    select * into s from public.screening_sessions x
    where x.source_pcucode=btrim(p_source_pcucode) and x.source_pid=p_source_pid
      and x.screening_date=v_day and x.started_by=auth.uid()
    limit 1;
  end if;

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
$function$
;

with e as (
 select s.source_pcucode,s.source_pid,coalesce(bool_or(s.elderly9_status='complete'),false) is_complete,
 coalesce(bool_or(s.elderly9_status='in_progress'),false) is_progress,
 max(s.screening_date) filter(where s.elderly9_status='complete') complete_on,
 max(s.screening_date) filter(where s.elderly9_status='in_progress') progress_on,
 greatest(coalesce(max(cardinality(coalesce(s.completed_domains,'{}'::text[]))),0),case when coalesce(bool_or(s.elderly9_status='complete'),false) then 9 else 0 end)::smallint completed_domains
 from public.screening_sessions s
 where s.route='elderly_60_plus' and s.screening_date between date '2026-10-01' and timezone('Asia/Bangkok',now())::date
 and s.elderly9_status in ('complete','in_progress') group by s.source_pcucode,s.source_pid
)
update public.health_screening_target_cache_v2030 c set
 elderly9_status_current_fy=case when coalesce(c.screening_route,'')<>'elderly_60_plus' then 'not_required' when coalesce(e.is_complete,false) then 'complete' when coalesce(e.is_progress,false) then 'in_progress' else 'not_started' end,
 elderly9_completed_current_fy=case when coalesce(c.screening_route,'')='elderly_60_plus' then coalesce(e.is_complete,false) else false end,
 elderly9_completed_domains_current_fy=case when coalesce(c.screening_route,'')='elderly_60_plus' then coalesce(e.completed_domains,0) else 0 end,
 latest_elderly9_screened_on=case when coalesce(c.screening_route,'')<>'elderly_60_plus' then null when coalesce(e.is_complete,false) then e.complete_on when coalesce(e.is_progress,false) then e.progress_on else null end
from e where c.source_pcucode=e.source_pcucode and c.source_pid=e.source_pid;

update public.health_screening_target_cache_v2030 c set elderly9_status_current_fy='not_started',
 elderly9_completed_current_fy=false,elderly9_completed_domains_current_fy=0,latest_elderly9_screened_on=null
where c.screening_route='elderly_60_plus' and not exists(
 select 1 from public.screening_sessions s where s.source_pcucode=c.source_pcucode and s.source_pid=c.source_pid
 and s.route='elderly_60_plus' and s.screening_date between date '2026-10-01' and timezone('Asia/Bangkok',now())::date
 and s.elderly9_status in ('complete','in_progress'));
commit;