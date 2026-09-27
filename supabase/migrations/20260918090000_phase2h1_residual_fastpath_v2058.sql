-- Cloud v2.0.58 Phase 2H.1 Residual Fast Path.
-- Scope: assignment-summary cache only. Auth/Login/LINE/OAuth unchanged. JHCIS remains read-only.
begin;

create table if not exists public.assignment_summary_cache_v2058 (
  scope_type text not null check(scope_type in ('all','community','volunteer')),
  scope_key text not null,
  payload jsonb not null,
  generated_at timestamptz not null default now(),
  primary key(scope_type,scope_key)
);

create table if not exists public.assignment_summary_state_v2058 (
  singleton boolean primary key default true check(singleton),
  dirty boolean not null default true,
  dirty_at timestamptz,
  last_refreshed_at timestamptz,
  last_reason text not null default ''
);

insert into public.assignment_summary_state_v2058(singleton,dirty,dirty_at)
values(true,true,now())
on conflict(singleton) do nothing;

alter table public.assignment_summary_cache_v2058 enable row level security;

alter table public.assignment_summary_state_v2058 enable row level security;

revoke all on public.assignment_summary_cache_v2058 from public,anon,authenticated;

revoke all on public.assignment_summary_state_v2058 from public,anon,authenticated;

grant all on public.assignment_summary_cache_v2058 to service_role;

grant all on public.assignment_summary_state_v2058 to service_role;

create or replace function private.mark_assignment_summary_dirty_v2058()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  update public.assignment_summary_state_v2058
  set dirty=true,dirty_at=clock_timestamp()
  where singleton=true;
  return null;
end;
$$;

drop trigger if exists houses_assignment_summary_dirty_v2058 on public.houses;

create trigger houses_assignment_summary_dirty_v2058
after insert or update or delete on public.houses
for each statement execute function private.mark_assignment_summary_dirty_v2058();

drop trigger if exists profiles_assignment_summary_dirty_v2058 on public.profiles;

create trigger profiles_assignment_summary_dirty_v2058
after insert or update or delete on public.profiles
for each statement execute function private.mark_assignment_summary_dirty_v2058();

drop trigger if exists volunteers_assignment_summary_dirty_v2058 on public.volunteers;

create trigger volunteers_assignment_summary_dirty_v2058
after insert or update or delete on public.volunteers
for each statement execute function private.mark_assignment_summary_dirty_v2058();

drop trigger if exists health_persons_assignment_summary_dirty_v2058 on public.health_persons;

create trigger health_persons_assignment_summary_dirty_v2058
after insert or update or delete on public.health_persons
for each statement execute function private.mark_assignment_summary_dirty_v2058();

create or replace function private.refresh_assignment_summary_cache_v2058(p_reason text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_now timestamptz:=clock_timestamp();
  v_rows integer:=0;
begin
  if not pg_try_advisory_xact_lock(hashtext('osm_phc_assignment_summary_v2058')) then
    return jsonb_build_object('ok',false,'status','busy','version','2.0.58');
  end if;

  create temporary table if not exists pg_temp.assignment_summary_build_v2058(
    scope_type text,
    scope_key text,
    payload jsonb
  ) on commit drop;
  truncate pg_temp.assignment_summary_build_v2058;

  with active_vhv as materialized (
    select distinct v.source_pid
    from public.volunteers v
    where v.active=true
  ),
  active_ops as materialized (
    select distinct v.source_pid
    from public.volunteers v
    join public.profiles p on p.volunteer_pid=v.source_pid
    where v.active=true and p.active=true and p.role in ('user','staff')
  ),
  house_base as materialized (
    select
      h.source_pcucode,h.hcode,h.volunteer_pid,
      nullif(private.community_key(h.community),'') as community_key,
      case
        when nullif(private.community_key(h.community),'') is null then 'unresolved'
        when h.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback'
        else 'assigned'
      end as assignment_status,
      case
        when nullif(private.community_key(h.community),'') is null then 'missing_community'
        when h.volunteer_pid is null then 'no_volunteer'
        when av.source_pid is null then 'inactive_volunteer'
        when ao.source_pid is null then 'no_active_user'
        else 'assigned'
      end as assignment_reason
    from public.houses h
    left join active_vhv av on av.source_pid=h.volunteer_pid
    left join active_ops ao on ao.source_pid=h.volunteer_pid
    where h.superseded_by is null
      and h.verification_status='verified_jhcis'
  ),
  house_scoped as materialized (
    select s.scope_type,s.scope_key,h.assignment_status,h.assignment_reason
    from house_base h
    cross join lateral (
      values
        ('all'::text,'*'::text),
        ('community'::text,h.community_key),
        ('volunteer'::text,h.volunteer_pid::text)
    ) s(scope_type,scope_key)
    where s.scope_key is not null
  ),
  people_base as materialized (
    select h.community_key,h.volunteer_pid,h.assignment_status,h.assignment_reason
    from public.health_persons p
    join house_base h
      on h.source_pcucode=p.house_pcucode
     and h.hcode=p.hcode
    where p.active=true
      and coalesce(p.service_population_eligible,false)=true
  ),
  people_scoped as materialized (
    select s.scope_type,s.scope_key,p.assignment_status,p.assignment_reason
    from people_base p
    cross join lateral (
      values
        ('all'::text,'*'::text),
        ('community'::text,p.community_key),
        ('volunteer'::text,p.volunteer_pid::text)
    ) s(scope_type,scope_key)
    where s.scope_key is not null
  ),
  hagg as (
    select scope_type,scope_key,
      count(*)::bigint houses,
      count(*) filter(where assignment_status='assigned')::bigint assigned_houses,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_houses,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_houses,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_houses,
      count(*) filter(where assignment_reason='inactive_volunteer')::bigint inactive_volunteer_houses,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_houses
    from house_scoped
    group by scope_type,scope_key
  ),
  pagg as (
    select scope_type,scope_key,
      count(*)::bigint people,
      count(*) filter(where assignment_status='assigned')::bigint assigned_people,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_people,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_people,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_people,
      count(*) filter(where assignment_reason='inactive_volunteer')::bigint inactive_volunteer_people,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_people
    from people_scoped
    group by scope_type,scope_key
  ),
  scopes as (
    select scope_type,scope_key from hagg
    union
    select scope_type,scope_key from pagg
  )
  insert into pg_temp.assignment_summary_build_v2058(scope_type,scope_key,payload)
  select
    s.scope_type,s.scope_key,
    jsonb_build_object(
      'houses',coalesce(h.houses,0),
      'assigned_houses',coalesce(h.assigned_houses,0),
      'fallback_houses',coalesce(h.fallback_houses,0),
      'unresolved_houses',coalesce(h.unresolved_houses,0),
      'no_volunteer_houses',coalesce(h.no_volunteer_houses,0),
      'inactive_volunteer_houses',coalesce(h.inactive_volunteer_houses,0),
      'no_active_user_houses',coalesce(h.no_active_user_houses,0),
      'people',coalesce(p.people,0),
      'assigned_people',coalesce(p.assigned_people,0),
      'fallback_people',coalesce(p.fallback_people,0),
      'unresolved_people',coalesce(p.unresolved_people,0),
      'no_volunteer_people',coalesce(p.no_volunteer_people,0),
      'inactive_volunteer_people',coalesce(p.inactive_volunteer_people,0),
      'no_active_user_people',coalesce(p.no_active_user_people,0)
    )
  from scopes s
  left join hagg h using(scope_type,scope_key)
  left join pagg p using(scope_type,scope_key);

  delete from public.assignment_summary_cache_v2058;
  insert into public.assignment_summary_cache_v2058(scope_type,scope_key,payload,generated_at)
  select scope_type,scope_key,payload,v_now
  from pg_temp.assignment_summary_build_v2058;
  get diagnostics v_rows=row_count;

  update public.assignment_summary_state_v2058
  set dirty=false,last_refreshed_at=v_now,last_reason=left(coalesce(p_reason,'manual'),80)
  where singleton=true;

  return jsonb_build_object(
    'ok',true,'version','2.0.58','rows',v_rows,'generated_at',v_now
  );
end;
$$;

create or replace function public.assignment_summary_fast_v2058(
  p_scope text default 'self',
  p_owner_pid bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_owner bigint:=p_owner_pid;
  v_key text;
  v_payload jsonb;
  v_dirty boolean:=true;
  v_generated timestamptz;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select role,community,volunteer_pid
  into v_role,v_community,v_pid
  from public.profiles
  where user_id=v_uid and active=true
  limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then
    v_scope:='all';v_owner:=null;v_key:='*';
  elsif v_role='user' then
    v_scope:='self';v_owner:=v_pid;v_key:=v_pid::text;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(
        select 1
        from public.profiles p
        join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner
          and private.community_key(p.community)=private.community_key(v_community)
      ) then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
      v_key:=v_owner::text;
    elsif v_scope='community' then
      v_owner:=null;v_key:=private.community_key(v_community);
    else
      v_scope:='self';v_owner:=v_pid;v_key:=v_pid::text;
    end if;
  else
    raise exception 'ROLE_NOT_ALLOWED';
  end if;

  select dirty into v_dirty
  from public.assignment_summary_state_v2058
  where singleton=true;

  if coalesce(v_dirty,true) then
    perform private.refresh_assignment_summary_cache_v2058('lazy_read');
  end if;

  select payload,generated_at
  into v_payload,v_generated
  from public.assignment_summary_cache_v2058
  where scope_type=case when v_scope='self' then 'volunteer' else v_scope end
    and scope_key=v_key
  limit 1;

  if v_payload is null then
    return public.assignment_summary_v2033(v_scope,v_owner);
  end if;

  return jsonb_build_object(
    'version','2.0.58',
    'cache','assignment_summary_cache_v2058',
    'generated_at',v_generated,
    'role',v_role,
    'scope',v_scope,
    'community',coalesce(v_community,''),
    'owner_pid',v_owner,
    'fallback_policy','staff_community',
    'auto_reassign_volunteer_pid',false,
    'scope_label',case
      when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเน'
      when v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      when v_scope='volunteer' then 'เธเธฒเธเธเธญเธ เธญเธชเธก. เธ—เธตเนเน€เธฅเธทเธญเธ'
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเนเธเธเธงเธฒเธกเธฃเธฑเธเธเธดเธ”เธเธญเธ'
    end
  ) || v_payload;
end;
$$;

revoke all on function public.assignment_summary_fast_v2058(text,bigint) from public,anon;

grant execute on function public.assignment_summary_fast_v2058(text,bigint) to authenticated;

create or replace function private.refresh_assignment_summary_after_report_v2058()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.status='ready'
     and (old.current_generation is distinct from new.current_generation
          or old.status is distinct from new.status) then
    perform private.refresh_assignment_summary_cache_v2058('report_snapshot_ready');
  end if;
  return new;
end;
$$;

drop trigger if exists report_snapshot_assignment_refresh_v2058
on public.report_snapshot_state_v2031;

create trigger report_snapshot_assignment_refresh_v2058
after update on public.report_snapshot_state_v2031
for each row execute function private.refresh_assignment_summary_after_report_v2058();

select private.refresh_assignment_summary_cache_v2058('migration_seed');

insert into public.app_settings(key,value)
values('phase2h1_residual_fastpath_v2058',jsonb_build_object(
  'version','2.0.58',
  'health_initial_navigation','single_intent_request',
  'assignment_summary','cached_fast_rpc_with_dirty_refresh',
  'volunteer_photo_concurrency',3,
  'volunteer_photo_root_margin_px',80,
  'auth_login_unchanged',true,
  'line_login_unchanged',true,
  'jhcis_write_back',false
))
on conflict(key) do update
set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
