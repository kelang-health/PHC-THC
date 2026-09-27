-- OSM-PHC Cloud v2.0.31
-- Fast, role-scoped dashboard snapshots with atomic generation switching.
-- JHCIS remains read-only. No Auth, population, or house data is duplicated here.
begin;

create extension if not exists pg_cron with schema pg_catalog;

create table if not exists public.report_snapshot_runs_v2031 (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('running','success','failed')),
  reason text not null default 'manual',
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  duration_ms bigint,
  cache_rows bigint not null default 0,
  error_message text not null default ''
);

create table if not exists public.report_snapshot_cache_v2031 (
  generation uuid not null references public.report_snapshot_runs_v2031(id) on delete cascade,
  report_key text not null check (report_key in ('care','field')),
  scope_type text not null check (scope_type in ('all','community','volunteer')),
  scope_key text not null,
  payload jsonb not null,
  generated_at timestamptz not null default now(),
  primary key (generation,report_key,scope_type,scope_key)
);

create index if not exists report_snapshot_lookup_v2031
  on public.report_snapshot_cache_v2031(report_key,scope_type,scope_key,generation);

create table if not exists public.report_snapshot_state_v2031 (
  singleton boolean primary key default true check(singleton),
  current_generation uuid references public.report_snapshot_runs_v2031(id),
  generated_at timestamptz,
  status text not null default 'empty' check(status in ('empty','running','ready','failed')),
  last_reason text not null default '',
  last_error text not null default ''
);

insert into public.report_snapshot_state_v2031(singleton)
values(true) on conflict(singleton) do nothing;

create table if not exists public.report_refresh_requests_v2031 (
  id bigint generated always as identity primary key,
  source text not null,
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  result_status text not null default 'pending' check(result_status in ('pending','success','failed'))
);
create index if not exists report_refresh_pending_v2031
  on public.report_refresh_requests_v2031(processed_at,requested_at);

alter table public.report_snapshot_runs_v2031 enable row level security;
alter table public.report_snapshot_cache_v2031 enable row level security;
alter table public.report_snapshot_state_v2031 enable row level security;
alter table public.report_refresh_requests_v2031 enable row level security;
revoke all on public.report_snapshot_runs_v2031 from public,anon,authenticated;
revoke all on public.report_snapshot_cache_v2031 from public,anon,authenticated;
revoke all on public.report_snapshot_state_v2031 from public,anon,authenticated;
revoke all on public.report_refresh_requests_v2031 from public,anon,authenticated;
grant all on public.report_snapshot_runs_v2031 to service_role;
grant all on public.report_snapshot_cache_v2031 to service_role;
grant all on public.report_snapshot_state_v2031 to service_role;
grant all on public.report_refresh_requests_v2031 to service_role;

create or replace function private.refresh_report_snapshots_v2031(p_reason text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_generation uuid:=gen_random_uuid();
  v_started timestamptz:=clock_timestamp();
  v_rows bigint:=0;
  v_added bigint:=0;
  v_reason text:=left(coalesce(nullif(btrim(p_reason),''),'manual'),80);
begin
  if not pg_try_advisory_xact_lock(hashtext('osm_phc_report_snapshot_v2031')) then
    return jsonb_build_object('ok',false,'status','busy','version','2.0.31');
  end if;

  insert into public.report_snapshot_runs_v2031(id,status,reason,started_at)
  values(v_generation,'running',v_reason,v_started);
  update public.report_snapshot_state_v2031
  set status='running',last_reason=v_reason,last_error=''
  where singleton=true;

  begin
    -- Care dashboard: scan each base relation once and fan rows into all/community/volunteer scopes.
    with house_scoped as materialized (
      select s.scope_type,s.scope_key,h.latitude,h.longitude,h.review_required
      from public.houses h
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(h.community),'')),
        ('volunteer'::text,h.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), hagg as (
      select scope_type,scope_key,count(*)::bigint houses,
        count(*) filter(where latitude is not null and longitude is not null)::bigint mapped_houses,
        count(*) filter(where latitude is null or longitude is null)::bigint missing_coordinates,
        count(*) filter(where review_required=true)::bigint review_houses
      from house_scoped group by scope_type,scope_key
    ), person_base as materialized (
      select w.source_pcucode,w.source_pid,w.life_stage,w.ncd_target,w.screened_current_fy,w.known_ncd,w.latest_severity,
        p.is_student,p.is_disabled,p.service_population_eligible,p.adl_group_code,
        h.community,h.volunteer_pid
      from public.health_person_worklist_active_v1847 w
      join public.health_persons p on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
      join public.houses h on h.source_pcucode=w.house_pcucode and h.hcode=w.hcode
    ), person_scoped as materialized (
      select s.scope_type,s.scope_key,p.*
      from person_base p
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(p.community),'')),
        ('volunteer'::text,p.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), pagg as (
      select scope_type,scope_key,count(*)::bigint household_people,
        count(*) filter(where service_population_eligible)::bigint service_people,
        count(*) filter(where service_population_eligible and ncd_target)::bigint ncd_targets,
        count(*) filter(where service_population_eligible and ncd_target and coalesce(screened_current_fy,false))::bigint ncd_done,
        count(*) filter(where service_population_eligible and ncd_target and not coalesce(screened_current_fy,false))::bigint ncd_due,
        count(*) filter(where service_population_eligible and known_ncd)::bigint known_ncd,
        count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข')::bigint early_child,
        count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ')::bigint school_age,
        count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ')::bigint youth,
        count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ')::bigint working_age,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ')::bigint older_people,
        count(*) filter(where service_population_eligible and is_student)::bigint students,
        count(*) filter(where service_population_eligible and is_disabled)::bigint disabled_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code<>'')::bigint adl_assessed_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1280')::bigint social_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1281')::bigint homebound_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1282')::bigint bedridden_people,
        count(*) filter(where service_population_eligible and latest_severity in ('alert','urgent'))::bigint urgent_attention
      from person_scoped group by scope_type,scope_key
    ), latest_2q as materialized (
      select distinct on (s.source_pcucode,s.source_pid)
        s.source_pcucode,s.source_pid,s.mental_2q_status,s.mental_2q_result
      from public.health_ncd_screenings s
      join person_base p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
      where p.service_population_eligible=true and coalesce(s.record_mode,'production')='production'
      order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
    ), qagg as (
      select ps.scope_type,ps.scope_key,
        count(*) filter(where q.mental_2q_status='assessed')::bigint mental_2q_assessed,
        count(*) filter(where q.mental_2q_status='not_assessed')::bigint mental_2q_not_assessed,
        count(*) filter(where q.mental_2q_status='incomplete')::bigint mental_2q_incomplete,
        count(*) filter(where q.mental_2q_status='assessed' and q.mental_2q_result=true)::bigint mental_2q_positive
      from person_scoped ps join latest_2q q on q.source_pcucode=ps.source_pcucode and q.source_pid=ps.source_pid
      group by ps.scope_type,ps.scope_key
    ), scopes as (
      select scope_type,scope_key from hagg union select scope_type,scope_key from pagg union select scope_type,scope_key from qagg
    )
    insert into public.report_snapshot_cache_v2031(generation,report_key,scope_type,scope_key,payload,generated_at)
    select v_generation,'care',s.scope_type,s.scope_key,jsonb_build_object(
      'houses',coalesce(h.houses,0),'mapped_houses',coalesce(h.mapped_houses,0),
      'missing_coordinates',coalesce(h.missing_coordinates,0),'review_houses',coalesce(h.review_houses,0),
      'household_people',coalesce(p.household_people,0),'people',coalesce(p.service_people,0),'service_people',coalesce(p.service_people,0),
      'ncd_targets',coalesce(p.ncd_targets,0),'ncd_done',coalesce(p.ncd_done,0),'ncd_due',coalesce(p.ncd_due,0),'known_ncd',coalesce(p.known_ncd,0),
      'early_child',coalesce(p.early_child,0),'school_age',coalesce(p.school_age,0),'youth',coalesce(p.youth,0),
      'working_age',coalesce(p.working_age,0),'older_people',coalesce(p.older_people,0),'students',coalesce(p.students,0),
      'disabled_people',coalesce(p.disabled_people,0),'adl_assessed_people',coalesce(p.adl_assessed_people,0),
      'social_people',coalesce(p.social_people,0),'homebound_people',coalesce(p.homebound_people,0),'bedridden_people',coalesce(p.bedridden_people,0),
      'urgent_attention',coalesce(p.urgent_attention,0),'mental_2q_assessed',coalesce(q.mental_2q_assessed,0),
      'mental_2q_not_assessed',coalesce(q.mental_2q_not_assessed,0),'mental_2q_incomplete',coalesce(q.mental_2q_incomplete,0),
      'mental_2q_positive',coalesce(q.mental_2q_positive,0),
      'metric_sources',jsonb_build_object(
        'person_level','JHCIS read-only / J-Report operational definition',
        'service_population','typelive 1,3 + nation 99 + alive + non-00 village',
        'ncd','J-Report operational worklist; official HDC DM/HT denominators are separate',
        'adl','latest JHCIS f43specialpp 1B1280/1B1281/1B1282',
        'official_comparator','MoPH Open Data via hdc-app; aggregate only'
      )
    ),clock_timestamp()
    from scopes s
    left join hagg h using(scope_type,scope_key)
    left join pagg p using(scope_type,scope_key)
    left join qagg q using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;

    -- Field-work dashboard: materialize once, then aggregate the same rows for each permitted scope.
    with work_scoped as materialized (
      select s.scope_type,s.scope_key,w.*
      from public.field_work_items_v200 w
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(w.community),'')),
        ('volunteer'::text,w.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), base_summary as (
      select scope_type,scope_key,count(*)::bigint total,
        count(*) filter(where status='complete')::bigint complete,
        count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due,
        count(*) filter(where priority='red')::bigint red,
        count(*) filter(where priority='orange')::bigint orange
      from work_scoped group by scope_type,scope_key
    ), task_rows as (
      select scope_type,scope_key,task_type,max(task_label) task_label,count(*)::bigint target,
        count(*) filter(where status='complete')::bigint complete,
        count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due
      from work_scoped group by scope_type,scope_key,task_type
    ), task_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'task_type',task_type,'task_label',task_label,'target',target,'complete',complete,'partial',partial,'due',due,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by task_type) value from task_rows group by scope_type,scope_key
    ), person_keys as (
      select distinct scope_type,scope_key,source_pcucode,source_pid from work_scoped
    ), follow_stat as (
      select p.scope_type,p.scope_key,
        count(*) filter(where f.status in ('open','in_progress'))::bigint open_count,
        count(*) filter(where f.status='done')::bigint done_count,
        count(*) filter(where f.status in ('open','in_progress') and f.priority='red')::bigint red_count,
        count(*) filter(where f.status in ('open','in_progress') and f.priority='orange')::bigint orange_count
      from person_keys p join public.screening_followups f on f.source_pcucode=p.source_pcucode and f.source_pid=p.source_pid
      group by p.scope_type,p.scope_key
    ), volunteer_rows as (
      select s.scope_type,s.scope_key,s.volunteer_pid,max(v.display_name) display_name,max(s.community) community,
        count(*)::bigint target,count(*) filter(where s.status='complete')::bigint complete,
        count(*) filter(where s.status='partial')::bigint partial,count(*) filter(where s.status='due')::bigint due
      from work_scoped s left join public.volunteers v on v.source_pid=s.volunteer_pid
      where s.volunteer_pid is not null group by s.scope_type,s.scope_key,s.volunteer_pid
    ), volunteer_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'volunteer_pid',volunteer_pid,'display_name',coalesce(display_name,'เนเธกเนเธฃเธฐเธเธธ'),'community',community,
        'target',target,'complete',complete,'partial',partial,'due',due,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by (case when target>0 then complete*100.0/target else 0 end),display_name) value
      from volunteer_rows group by scope_type,scope_key
    ), community_rows as (
      select scope_type,scope_key,community,count(*)::bigint target,
        count(*) filter(where status='complete')::bigint complete,count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due,count(distinct volunteer_pid) filter(where volunteer_pid is not null)::bigint volunteers
      from work_scoped group by scope_type,scope_key,community
    ), community_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'community',community,'target',target,'complete',complete,'partial',partial,'due',due,'volunteers',volunteers,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by (case when target>0 then complete*100.0/target else 0 end),community) value
      from community_rows group by scope_type,scope_key
    )
    insert into public.report_snapshot_cache_v2031(generation,report_key,scope_type,scope_key,payload,generated_at)
    select v_generation,'field',b.scope_type,b.scope_key,jsonb_build_object(
      'period_start',private.field_period_start_v200(),'period_mode',private.field_period_mode_v200(),
      'target_tasks',coalesce(b.total,0),'complete_tasks',coalesce(b.complete,0),'partial_tasks',coalesce(b.partial,0),'due_tasks',coalesce(b.due,0),
      'coverage_percent',case when coalesce(b.total,0)>0 then round(b.complete*100.0/b.total,1) else 0 end,
      'red_tasks',coalesce(b.red,0),'orange_tasks',coalesce(b.orange,0),
      'followup_open',coalesce(f.open_count,0),'followup_done',coalesce(f.done_count,0),
      'followup_red',coalesce(f.red_count,0),'followup_orange',coalesce(f.orange_count,0),
      'tasks',coalesce(t.value,'[]'::jsonb),'volunteers',coalesce(v.value,'[]'::jsonb),'communities',coalesce(c.value,'[]'::jsonb),
      'metric_note','เน€เธเธญเธฃเนเน€เธเนเธเธ•เนเธฃเธงเธกเน€เธเนเธ Operational Task Completion; เนเธกเนเนเธเนเนเธ—เธ KPI HDC เธ—เธฒเธเธเธฒเธฃ เนเธฅเธฐเธฃเธฒเธขเธเธฒเธฃเธ•เธดเธ”เธ•เธฒเธกเนเธกเนเธ–เธนเธเธเธณเธกเธฒเธซเธฑเธ Coverage'
    ),clock_timestamp()
    from base_summary b
    left join task_json t using(scope_type,scope_key)
    left join follow_stat f using(scope_type,scope_key)
    left join volunteer_json v using(scope_type,scope_key)
    left join community_json c using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;

    update public.report_snapshot_runs_v2031 set status='success',finished_at=clock_timestamp(),
      duration_ms=round(extract(epoch from (clock_timestamp()-v_started))*1000),cache_rows=v_rows
    where id=v_generation;
    update public.report_snapshot_state_v2031 set current_generation=v_generation,generated_at=clock_timestamp(),
      status='ready',last_reason=v_reason,last_error='' where singleton=true;

    -- Keep four completed generations so readers always have a valid previous generation.
    delete from public.report_snapshot_runs_v2031 r
    where r.status<>'running' and r.id not in (
      select id from public.report_snapshot_runs_v2031 where status='success' order by finished_at desc nulls last limit 4
    ) and coalesce(r.finished_at,r.started_at)<now()-interval '7 days';

    return jsonb_build_object('ok',true,'status','ready','generation',v_generation,'cache_rows',v_rows,
      'duration_ms',round(extract(epoch from (clock_timestamp()-v_started))*1000),'generated_at',clock_timestamp(),'version','2.0.31');
  exception when others then
    update public.report_snapshot_runs_v2031 set status='failed',finished_at=clock_timestamp(),
      duration_ms=round(extract(epoch from (clock_timestamp()-v_started))*1000),error_message=left(sqlerrm,500)
    where id=v_generation;
    update public.report_snapshot_state_v2031 set status=case when current_generation is null then 'failed' else 'ready' end,
      last_reason=v_reason,last_error=left(sqlerrm,500) where singleton=true;
    return jsonb_build_object('ok',false,'status','failed','error',left(sqlerrm,500),'version','2.0.31');
  end;
end;
$$;
revoke all on function private.refresh_report_snapshots_v2031(text) from public,anon,authenticated,service_role;

create or replace function public.report_snapshot_v2031(p_report_key text,p_scope text default 'self')
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare
  v_uid uuid:=auth.uid(); v_role text; v_community text; v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self'))); v_scope_type text; v_scope_key text;
  v_payload jsonb; v_generated timestamptz; v_hdc jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid
  from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all'; v_scope_type:='all'; v_scope_key:='*';
  elsif v_role='user' then v_scope:='self'; v_scope_type:='volunteer'; v_scope_key:=v_pid::text;
  elsif v_role='staff' and v_scope='community' then v_scope_type:='community'; v_scope_key:=private.community_key(v_community);
  elsif v_role='staff' then v_scope:='self'; v_scope_type:='volunteer'; v_scope_key:=v_pid::text;
  else raise exception 'ROLE_NOT_ALLOWED';
  end if;
  if nullif(v_scope_key,'') is null then raise exception 'PROFILE_SCOPE_NOT_READY'; end if;
  if p_report_key not in ('care','field') then raise exception 'UNKNOWN_REPORT'; end if;

  select c.payload,s.generated_at into v_payload,v_generated
  from public.report_snapshot_state_v2031 s
  join public.report_snapshot_cache_v2031 c on c.generation=s.current_generation
  where s.singleton=true and c.report_key=p_report_key and c.scope_type=v_scope_type and c.scope_key=v_scope_key;
  if not found then return null; end if;

  v_payload:=v_payload||jsonb_build_object(
    'version','2.0.31','role',v_role,'scope',v_scope,'community',coalesce(v_community,''),
    'has_personal_scope',(v_pid is not null),'snapshot_generated_at',v_generated,'snapshot_source','scheduled_cache',
    'scope_label',case when v_role='admin' then case when p_report_key='field' then 'เธ—เธธเธเธเธธเธกเธเธ' else 'เธ—เธธเธเธเธทเนเธเธ—เธตเนเธ•เธฒเธกเธชเธดเธ—เธเธดเนเธเธนเนเธ”เธนเนเธฅเธฃเธฐเธเธ' end
      when v_role='staff' and v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      when p_report_key='field' then 'เธเธฒเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' end
  );
  if p_report_key='care' then
    v_payload:=v_payload-'hdc_reference';
    if v_role='admin' then select value into v_hdc from public.app_settings where key='care_reference_hdc' limit 1;
      v_payload:=v_payload||jsonb_build_object('hdc_reference',v_hdc); end if;
  else
    if v_role='user' then v_payload:=v_payload||jsonb_build_object('volunteers','[]'::jsonb,'communities','[]'::jsonb);
    elsif v_role='staff' then v_payload:=v_payload||jsonb_build_object('communities','[]'::jsonb); end if;
  end if;
  return v_payload;
end;
$$;
revoke all on function public.report_snapshot_v2031(text,text) from public,anon;
grant execute on function public.report_snapshot_v2031(text,text) to authenticated;

create or replace function public.admin_refresh_report_snapshots_v2031()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_result jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  v_result:=private.refresh_report_snapshots_v2031('admin_manual');
  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'REFRESH','report_snapshots','current','',v_result);
  return v_result;
end;
$$;
revoke all on function public.admin_refresh_report_snapshots_v2031() from public,anon;
grant execute on function public.admin_refresh_report_snapshots_v2031() to authenticated;

create or replace function public.service_refresh_report_snapshots_v2031(p_reason text default 'local_sync')
returns jsonb language plpgsql security definer set search_path=''
as $$
begin
  if current_user<>'service_role' and coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  return private.refresh_report_snapshots_v2031(p_reason);
end;
$$;
revoke all on function public.service_refresh_report_snapshots_v2031(text) from public,anon,authenticated;
grant execute on function public.service_refresh_report_snapshots_v2031(text) to service_role;

create or replace function private.queue_report_snapshot_refresh_v2031()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  insert into public.report_refresh_requests_v2031(source)
  select tg_table_schema||'.'||tg_table_name
  where not exists(select 1 from public.report_refresh_requests_v2031 where processed_at is null);
  return null;
end;
$$;
revoke all on function private.queue_report_snapshot_refresh_v2031() from public,anon,authenticated,service_role;

create or replace function private.process_report_refresh_queue_v2031()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_result jsonb;
begin
  if not exists(select 1 from public.report_refresh_requests_v2031 where processed_at is null) then
    return jsonb_build_object('ok',true,'status','idle','version','2.0.31');
  end if;
  v_result:=private.refresh_report_snapshots_v2031('change_queue');
  if coalesce((v_result->>'ok')::boolean,false) then
    update public.report_refresh_requests_v2031 set processed_at=now(),result_status='success' where processed_at is null;
  elsif v_result->>'status'='failed' then
    update public.report_refresh_requests_v2031 set processed_at=now(),result_status='failed' where processed_at is null;
  end if;
  return v_result;
end;
$$;
revoke all on function private.process_report_refresh_queue_v2031() from public,anon,authenticated,service_role;

do $$
declare t text;
begin
  foreach t in array array['houses','health_persons','volunteers','health_ncd_screenings','health_growth_screenings','child_development_screenings','screening_sessions','elderly9_domain_results','screening_followups']
  loop
    execute format('drop trigger if exists report_snapshot_dirty_v2031 on public.%I',t);
    execute format('create trigger report_snapshot_dirty_v2031 after insert or update or delete on public.%I for each statement execute function private.queue_report_snapshot_refresh_v2031()',t);
  end loop;
end;
$$;

do $$
declare j record;
begin
  for j in select jobid from cron.job where jobname in ('osm-phc-report-snapshot-queue-v2031','osm-phc-report-snapshot-nightly-v2031') loop
    perform cron.unschedule(j.jobid);
  end loop;
end;
$$;
select cron.schedule('osm-phc-report-snapshot-queue-v2031','*/5 * * * *',$cron$select private.process_report_refresh_queue_v2031();$cron$);
-- pg_cron uses UTC here: 17:05 UTC = 00:05 Asia/Bangkok.
select cron.schedule('osm-phc-report-snapshot-nightly-v2031','5 17 * * *',$cron$select private.refresh_report_snapshots_v2031('nightly_00_05_bangkok');$cron$);

insert into public.app_settings(key,value)
values('report_snapshot_v2031',jsonb_build_object(
  'version','2.0.31','strategy','atomic_generation_snapshot','nightly_bangkok','00:05',
  'change_queue_minutes',5,'manual_admin_refresh',true,'role_scope_server_side',true,
  'jhcis_write_back',false,'duplicate_auth',false,'duplicate_population',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

-- Build the first generation before clients switch to the cached RPC.
select private.refresh_report_snapshots_v2031('migration_initial');

notify pgrst,'reload schema';
commit;
