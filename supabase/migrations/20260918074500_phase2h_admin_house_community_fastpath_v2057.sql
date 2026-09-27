-- Cloud v2.0.57 Phase 2H โ€” Admin & House/Community Fast Path.
-- Scope is intentionally limited to:
-- 1) shared Admin community bundle
-- 2) coalesced target-config refresh
-- Auth/PIN/LINE Login/OAuth and JHCIS write paths are unchanged.
begin;

create or replace function public.admin_community_fast_bundle_v2057()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  with stats as materialized (
    select
      c.name::text as community,
      c.moo::text as moo,
      count(h.id)::bigint as houses,
      count(h.id) filter (where h.volunteer_pid is not null)::bigint as assigned_houses,
      count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint as pinned_houses,
      count(h.id) filter (where h.coordinate_status like 'resolved_%')::bigint as field_confirmed,
      count(h.id) filter (where h.review_required=true)::bigint as review_houses,
      count(h.id) filter (where h.inside_tambon=false)::bigint as outside_tambon,
      count(h.id) filter (
        where h.inside_community=false
          and h.inside_tambon is distinct from false
      )::bigint as outside_community,
      count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint as missing_coordinates,
      count(h.id) filter (where h.house_id_11 is null or h.house_id_11 !~ '^[0-9]{11}$')::bigint as missing_house_id_11,
      count(distinct h.volunteer_pid) filter (where h.volunteer_pid is not null)::bigint as volunteers
    from public.communities c
    left join public.houses h
      on btrim(h.community)=btrim(c.name)
     and h.superseded_by is null
     and h.verification_status='verified_jhcis'
    where c.active=true
    group by c.name,c.moo
  ),
  totals as (
    select
      coalesce(sum(houses),0)::bigint as total_houses,
      coalesce(sum(assigned_houses),0)::bigint as assigned_houses,
      coalesce(sum(pinned_houses),0)::bigint as pinned_houses,
      coalesce(sum(field_confirmed),0)::bigint as field_confirmed,
      coalesce(sum(review_houses),0)::bigint as review_houses,
      coalesce(sum(outside_tambon),0)::bigint as outside_tambon,
      coalesce(sum(outside_community),0)::bigint as outside_community,
      coalesce(sum(missing_coordinates),0)::bigint as missing_coordinates,
      coalesce(sum(missing_house_id_11),0)::bigint as missing_house_id_11
    from stats
  ),
  cards as (
    select
      community,moo,houses,assigned_houses,pinned_houses,field_confirmed,
      review_houses,outside_tambon,outside_community,missing_coordinates,
      volunteers,'manage'::text as access_mode,false::boolean as is_assigned
    from stats
    order by nullif(moo,'')::int nulls last,community
  )
  select jsonb_build_object(
    'version','2.0.57',
    'scope','admin_all',
    'dashboard',jsonb_build_object(
      'role','admin',
      'community','',
      'moo',null,
      'total_houses',t.total_houses,
      'assigned_houses',t.assigned_houses,
      'pinned_houses',t.pinned_houses,
      'field_confirmed',t.field_confirmed,
      'review_houses',t.review_houses,
      'outside_tambon',t.outside_tambon,
      'outside_community',t.outside_community,
      'outside_any',t.outside_tambon+t.outside_community,
      'missing_coordinates',t.missing_coordinates,
      'missing_house_id_11',t.missing_house_id_11,
      'field_progress_pct',
        case when t.total_houses>0
          then round((t.field_confirmed::numeric*100.0)/t.total_houses,1)
          else 0 end
    ),
    'cards',
      coalesce((select jsonb_agg(to_jsonb(c) order by nullif(c.moo,'')::int nulls last,c.community) from cards c),'[]'::jsonb)
  )
  into v_result
  from totals t;

  return coalesce(v_result,jsonb_build_object(
    'version','2.0.57','scope','admin_all',
    'dashboard',jsonb_build_object('role','admin','total_houses',0),
    'cards','[]'::jsonb
  ));
end;
$$;

revoke all on function public.admin_community_fast_bundle_v2057() from public,anon;

grant execute on function public.admin_community_fast_bundle_v2057() to authenticated;

create or replace function public.admin_set_screening_target_groups_v2057(p_changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_change jsonb;
  v_route text;
  v_enabled boolean;
  v_row public.health_screening_target_groups_v2026%rowtype;
  v_changed integer:=0;
  v_one integer:=0;
  v_refresh jsonb:=null;
  v_cache jsonb:=null;
  v_settings jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;
  if jsonb_typeof(coalesce(p_changes,'[]'::jsonb))<>'array' then
    raise exception 'INVALID_CHANGES';
  end if;

  for v_change in
    select x.value
    from (
      select distinct on (btrim(e.value->>'route'))
             e.value,e.ord
      from jsonb_array_elements(coalesce(p_changes,'[]'::jsonb))
           with ordinality as e(value,ord)
      where coalesce(btrim(e.value->>'route'),'')<>''
        and e.value ? 'enabled'
      order by btrim(e.value->>'route'),e.ord desc
    ) x
  loop
    v_route:=btrim(v_change->>'route');
    begin
      v_enabled:=(v_change->>'enabled')::boolean;
    exception when others then
      raise exception 'INVALID_ENABLED_VALUE';
    end;

    select * into v_row
    from public.health_screening_target_groups_v2026
    where route=v_route
    for update;

    if not found then
      raise exception 'UNKNOWN_TARGET_GROUP: %',v_route;
    end if;
    if v_row.locked and v_enabled=false then
      raise exception 'AGE_35_PLUS_TARGET_IS_REQUIRED';
    end if;

    update public.health_screening_target_groups_v2026
       set enabled=v_enabled,
           updated_by=auth.uid(),
           updated_at=now()
     where route=v_route
       and enabled is distinct from v_enabled;

    get diagnostics v_one=row_count;
    v_changed:=v_changed+v_one;
  end loop;

  if v_changed>0 then
    -- One plan refresh + one denormalized cache refresh for the whole click burst.
    v_refresh:=public.refresh_health_screening_plan_v2023(current_date);
    v_cache:=public.refresh_screening_target_cache_v2030();

    insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
    values(
      auth.uid(),'UPDATE','screening_target_groups','batch','',
      jsonb_build_object(
        'version','2.0.57',
        'coalesced',true,
        'changed_count',v_changed,
        'changes',p_changes,
        'refresh',v_refresh,
        'cache',v_cache
      )
    );
  end if;

  v_settings:=public.screening_target_settings_v2026();
  return jsonb_build_object(
    'ok',true,
    'version','2.0.57',
    'coalesced',true,
    'changed_count',v_changed,
    'refreshed',v_changed>0,
    'refresh',v_refresh,
    'cache',v_cache,
    'settings',v_settings
  );
end;
$$;

revoke all on function public.admin_set_screening_target_groups_v2057(jsonb) from public,anon;

grant execute on function public.admin_set_screening_target_groups_v2057(jsonb) to authenticated;

create or replace function public.admin_refresh_screening_targets_v2026()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_refresh jsonb;
  v_cache jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  v_refresh:=public.refresh_health_screening_plan_v2023(current_date);
  v_cache:=public.refresh_screening_target_cache_v2030();

  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(
    auth.uid(),'REFRESH','screening_targets','all','',
    jsonb_build_object('version','2.0.57','refresh',v_refresh,'cache',v_cache)
  );

  return jsonb_build_object(
    'ok',true,
    'version','2.0.57',
    'refresh',v_refresh,
    'cache',v_cache,
    'settings',public.screening_target_settings_v2026()
  );
end;
$$;

revoke all on function public.admin_refresh_screening_targets_v2026() from public,anon;

grant execute on function public.admin_refresh_screening_targets_v2026() to authenticated;

insert into public.app_settings(key,value)
values('phase2h_admin_house_community_fastpath_v2057',jsonb_build_object(
  'version','2.0.57',
  'scope',jsonb_build_array('admin','house','community'),
  'admin_work_loading','progressive',
  'community_rpc','single_shared_admin_bundle',
  'volunteer_photos','lazy_on_intersection',
  'target_config_refresh','coalesced_batch',
  'auth_login_unchanged',true,
  'line_login_unchanged',true,
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
