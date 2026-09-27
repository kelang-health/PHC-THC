-- OSM-PHC Cloud v1.8.55
-- Restore the VHV "house -> member count -> member names" workflow without widening scope.
-- The list RPC returns only houses assigned to the current user/volunteer_pid.

begin;

create or replace function public.user_household_cards_v1855()
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  spatial_status text,
  member_count bigint,
  older_count bigint,
  ncd_due_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_pid bigint;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_role := private.current_role();
  v_pid := private.current_volunteer_pid();
  if v_role <> 'user' or v_pid is null then
    raise exception 'USER_SCOPE_REQUIRED';
  end if;

  return query
  select
    h.id,
    h.house_no,
    h.hcode,
    h.moo,
    h.community,
    h.latitude,
    h.longitude,
    case
      when h.latitude is null or h.longitude is null then 'missing'
      when h.inside_tambon = false then 'outside_tambon'
      when h.inside_community = false then 'outside_community'
      when h.review_required = true then 'review'
      when h.coordinate_status like 'resolved_%' then 'field_confirmed'
      else 'pinned'
    end::text as spatial_status,
    coalesce(x.member_count, 0)::bigint,
    coalesce(x.older_count, 0)::bigint,
    coalesce(x.ncd_due_count, 0)::bigint
  from public.houses h
  left join lateral (
    select
      count(*)::bigint as member_count,
      count(*) filter (where w.age_years >= 60)::bigint as older_count,
      count(*) filter (
        where w.ncd_target and not coalesce(w.screened_current_fy, false)
      )::bigint as ncd_due_count
    from public.health_person_worklist_active_v1841 w
    where w.source_pcucode = h.source_pcucode
      and w.hcode = h.hcode
  ) x on true
  where h.volunteer_pid = v_pid
  order by
    nullif(regexp_replace(coalesce(h.house_no,''), '[^0-9].*$', ''), '')::integer nulls last,
    h.house_no;
end;
$$;

revoke all on function public.user_household_cards_v1855() from public, anon;

grant execute on function public.user_household_cards_v1855() to authenticated;

insert into public.app_settings(key,value)
values ('role_scope',jsonb_build_object(
  'version','1.8.55',
  'admin','all_communities_manage',
  'staff','own_community_manage_same_moo_readonly',
  'user','own_assigned_houses_dashboard_member_drilldown_exact_house_lookup',
  'health_scope','staff_health_stays_own_community_user_health_stays_assigned_houses'
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
