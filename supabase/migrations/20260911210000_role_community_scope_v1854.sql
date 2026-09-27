-- OSM-PHC Cloud v1.8.54
-- Role-specific Community view:
--   user  = own assigned houses only in dashboard; exact house-number lookup may locate another house.
--   staff = own community is managed; other communities in the same moo are read-only.
--   admin = all communities.
-- Health/member access remains controlled by private.health_can_access_house(), which is intentionally
-- NOT widened here. A staff member may therefore see house/spatial data in the same moo but health data
-- remains limited to the staff member's own community.

begin;

create or replace function private.current_moo()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select c.moo
  from public.communities c
  where c.active = true
    and private.community_key(c.name) = private.community_key(private.current_community())
  order by c.id
  limit 1
$$;

revoke all on function private.current_moo() from public, anon, authenticated;

grant execute on function private.current_moo() to authenticated;

-- Read scope. Staff can see spatial/house rows in the same moo, but this does not grant writes.
drop policy if exists communities_select on public.communities;

create policy communities_select on public.communities for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and coalesce(btrim(private.current_moo()), '') <> ''
    and btrim(moo) = btrim(private.current_moo())
  )
  or (
    private.current_role() = 'user'
    and exists (
      select 1
      from public.houses h
      where h.volunteer_pid = private.current_volunteer_pid()
        and private.community_key(h.community) = private.community_key(communities.name)
    )
  )
);

drop policy if exists houses_select on public.houses;

create policy houses_select on public.houses for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and coalesce(btrim(private.current_moo()), '') <> ''
    and btrim(moo) = btrim(private.current_moo())
  )
  or (
    private.current_role() = 'user'
    and volunteer_pid = private.current_volunteer_pid()
  )
);

-- Staff may see the VHV name attached to houses in the same moo, but cannot edit those volunteer rows.
drop policy if exists volunteers_select on public.volunteers;

create policy volunteers_select on public.volunteers for select to authenticated
using (
  private.current_role() = 'admin'
  or (
    private.current_role() = 'staff'
    and coalesce(btrim(private.current_moo()), '') <> ''
    and btrim(moo) = btrim(private.current_moo())
  )
  or (
    private.current_role() = 'user'
    and source_pid = private.current_volunteer_pid()
  )
);

-- Defence in depth: widening SELECT for staff must never widen UPDATE.
-- Service-role/database sync has auth.uid() = null and is left unaffected.
create or replace function private.guard_house_client_update_v1854()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    return new;
  end if;

  v_role := private.current_role();
  if v_role = 'admin' then
    return new;
  end if;

  if v_role = 'staff'
     and private.community_key(old.community) = private.community_key(private.current_community()) then
    return new;
  end if;

  if v_role = 'user' and old.volunteer_pid = private.current_volunteer_pid() then
    return new;
  end if;

  raise exception 'HOUSE_READ_ONLY_SCOPE' using errcode = '42501';
end;
$$;

revoke all on function private.guard_house_client_update_v1854() from public, anon, authenticated;

drop trigger if exists trg_guard_house_client_update_v1854 on public.houses;

create trigger trg_guard_house_client_update_v1854
before update on public.houses
for each row execute function private.guard_house_client_update_v1854();

-- Dashboard counts follow the role's intended landing scope.
-- staff deliberately gets OWN COMMUNITY counts, not whole-moo counts.
create or replace function public.spatial_role_dashboard_v1854()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as community,
      private.current_volunteer_pid() as volunteer_pid
  ), scoped as (
    select h.*
    from public.houses h, ctx
    where
      ctx.role = 'admin'
      or (
        ctx.role = 'staff'
        and private.community_key(h.community) = private.community_key(ctx.community)
      )
      or (
        ctx.role = 'user'
        and h.volunteer_pid = ctx.volunteer_pid
      )
  )
  select jsonb_build_object(
    'role', coalesce((select role from ctx), ''),
    'scope_community', coalesce((select community from ctx), ''),
    'total_houses', count(*),
    'pinned_houses', count(*) filter (where latitude is not null and longitude is not null),
    'missing_coordinates', count(*) filter (where latitude is null or longitude is null),
    'review_houses', count(*) filter (where review_required = true),
    'field_confirmed', count(*) filter (where coordinate_status like 'resolved_%'),
    'outside_tambon', count(*) filter (where inside_tambon = false),
    'outside_community', count(*) filter (where inside_community = false)
  )
  from scoped
$$;

revoke all on function public.spatial_role_dashboard_v1854() from public, anon;

grant execute on function public.spatial_role_dashboard_v1854() to authenticated;

-- Community cards are role-aware and ordered by the caller's own community first.
create or replace function public.spatial_community_cards_v1854()
returns table (
  community text,
  moo text,
  volunteers bigint,
  houses bigint,
  pinned_houses bigint,
  review_houses bigint,
  assigned_houses bigint,
  outside_tambon bigint,
  outside_community bigint,
  missing_coordinates bigint,
  is_assigned boolean,
  access_mode text
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  ), allowed as (
    select c.name as community, c.moo
    from public.communities c, ctx
    where c.active = true
      and (
        ctx.role = 'admin'
        or (ctx.role = 'staff' and btrim(c.moo) = btrim(ctx.own_moo))
        or (
          ctx.role = 'user'
          and exists (
            select 1 from public.houses h
            where h.volunteer_pid = ctx.volunteer_pid
              and private.community_key(h.community) = private.community_key(c.name)
          )
        )
      )
  )
  select
    a.community,
    a.moo,
    count(distinct h.volunteer_pid) filter (where h.volunteer_pid is not null)::bigint as volunteers,
    count(h.id)::bigint as houses,
    count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint as pinned_houses,
    count(h.id) filter (where h.review_required = true)::bigint as review_houses,
    count(h.id) filter (where h.volunteer_pid is not null)::bigint as assigned_houses,
    count(h.id) filter (where h.inside_tambon = false)::bigint as outside_tambon,
    count(h.id) filter (where h.inside_community = false)::bigint as outside_community,
    count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint as missing_coordinates,
    (private.community_key(a.community) = private.community_key((select own_community from ctx))) as is_assigned,
    case
      when (select role from ctx) = 'admin' then 'manage'
      when (select role from ctx) = 'staff'
           and private.community_key(a.community) = private.community_key((select own_community from ctx)) then 'manage'
      else 'view'
    end as access_mode
  from allowed a
  left join public.houses h
    on private.community_key(h.community) = private.community_key(a.community)
    and (
      (select role from ctx) <> 'user'
      or h.volunteer_pid = (select volunteer_pid from ctx)
    )
  group by a.community, a.moo
  order by
    (private.community_key(a.community) = private.community_key((select own_community from ctx))) desc,
    a.moo,
    a.community
$$;

revoke all on function public.spatial_community_cards_v1854() from public, anon;

grant execute on function public.spatial_community_cards_v1854() to authenticated;

-- Exact house-number lookup for field navigation. It intentionally returns no resident/member health data.
-- user may locate another house by exact house number as requested, but can_edit remains false unless assigned.
create or replace function public.spatial_house_exact_search_v1854(p_house_no text)
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  volunteer_name text,
  spatial_status text,
  can_edit boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  )
  select
    h.id,
    h.house_no,
    h.hcode,
    h.moo,
    h.community,
    h.latitude,
    h.longitude,
    h.coordinate_status,
    h.review_required,
    h.inside_tambon,
    h.inside_community,
    coalesce(v.display_name, '') as volunteer_name,
    case
      when h.latitude is null or h.longitude is null then 'missing'
      when h.inside_tambon = false then 'outside_tambon'
      when h.inside_community = false then 'outside_community'
      when h.review_required = true then 'review'
      when h.coordinate_status like 'resolved_%' then 'field_confirmed'
      else 'pinned'
    end as spatial_status,
    case
      when (select role from ctx) = 'admin' then true
      when (select role from ctx) = 'staff'
        then private.community_key(h.community) = private.community_key((select own_community from ctx))
      when (select role from ctx) = 'user'
        then h.volunteer_pid = (select volunteer_pid from ctx)
      else false
    end as can_edit
  from public.houses h
  left join public.volunteers v
    on v.source_pcucode = h.source_pcucode and v.source_pid = h.volunteer_pid
  where coalesce(btrim(p_house_no), '') <> ''
    and lower(btrim(h.house_no)) = lower(btrim(p_house_no))
    and (
      (select role from ctx) = 'admin'
      or (select role from ctx) = 'user'
      or (
        (select role from ctx) = 'staff'
        and btrim(h.moo) = btrim((select own_moo from ctx))
      )
    )
  order by
    (private.community_key(h.community) = private.community_key((select own_community from ctx))) desc,
    h.moo,
    h.community,
    h.house_no
  limit 25
$$;

revoke all on function public.spatial_house_exact_search_v1854(text) from public, anon;

grant execute on function public.spatial_house_exact_search_v1854(text) to authenticated;

-- Read-only house rows for community spatial view.
create or replace function public.spatial_community_houses_v1854(p_community text)
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  volunteer_pid bigint,
  volunteer_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  )
  select
    h.id, h.house_no, h.hcode, h.moo, h.community,
    h.latitude, h.longitude, h.coordinate_status, h.review_required,
    h.inside_tambon, h.inside_community, h.volunteer_pid,
    coalesce(v.display_name, '') as volunteer_name
  from public.houses h
  left join public.volunteers v
    on v.source_pcucode = h.source_pcucode and v.source_pid = h.volunteer_pid
  where private.community_key(h.community) = private.community_key(p_community)
    and (
      (select role from ctx) = 'admin'
      or (
        (select role from ctx) = 'staff'
        and btrim(h.moo) = btrim((select own_moo from ctx))
      )
      or (
        (select role from ctx) = 'user'
        and h.volunteer_pid = (select volunteer_pid from ctx)
      )
    )
  order by h.house_no
$$;

revoke all on function public.spatial_community_houses_v1854(text) from public, anon;

grant execute on function public.spatial_community_houses_v1854(text) to authenticated;

create or replace function public.spatial_community_boundaries_v1854()
returns table (
  community text,
  moo text,
  geometry_geojson jsonb,
  is_assigned boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  )
  select
    c.name as community,
    c.moo,
    c.geometry_geojson,
    private.community_key(c.name) = private.community_key((select own_community from ctx)) as is_assigned
  from public.communities c
  where c.active = true
    and c.geometry_geojson is not null
    and (
      (select role from ctx) = 'admin'
      or (
        (select role from ctx) = 'staff'
        and btrim(c.moo) = btrim((select own_moo from ctx))
      )
      or (
        (select role from ctx) = 'user'
        and exists (
          select 1 from public.houses h
          where h.volunteer_pid = (select volunteer_pid from ctx)
            and private.community_key(h.community) = private.community_key(c.name)
        )
      )
    )
  order by is_assigned desc, c.moo, c.name
$$;

revoke all on function public.spatial_community_boundaries_v1854() from public, anon;

grant execute on function public.spatial_community_boundaries_v1854() to authenticated;

insert into public.app_settings(key,value)
values ('role_scope',jsonb_build_object(
  'version','1.8.54',
  'admin','all_communities_manage',
  'staff','own_community_manage_same_moo_readonly',
  'user','own_assigned_houses_dashboard_exact_house_lookup',
  'health_scope','staff_health_stays_own_community_user_health_stays_assigned_houses'
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
