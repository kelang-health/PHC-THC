-- Cloud v2.0.58 Phase 2H.1 corrective: safe-update compatible cache replacement.
-- No Auth/Login/LINE/OAuth changes. JHCIS remains read-only.
begin;

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

  delete from public.assignment_summary_cache_v2058
  where scope_type in ('all','community','volunteer');
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

select private.refresh_assignment_summary_cache_v2058('safe_update_corrective');

insert into public.app_settings(key,value)
values('phase2h1_assignment_cache_corrective_v2058',jsonb_build_object(
  'version','2.0.58',
  'safe_update_compatible',true,
  'auth_login_unchanged',true,
  'line_login_unchanged',true,
  'jhcis_write_back',false
))
on conflict(key) do update
set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
