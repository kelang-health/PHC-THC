create or replace function public.spatial_community_cards()
returns table(
  community text,
  moo text,
  houses bigint,
  assigned_houses bigint,
  pinned_houses bigint,
  field_confirmed bigint,
  review_houses bigint,
  outside_tambon bigint,
  outside_community bigint,
  missing_coordinates bigint,
  volunteers bigint,
  access_mode text,
  is_assigned boolean
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_own_moo text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo
    from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,''))
    limit 1;
  end if;

  return query
  select
    c.name::text,
    c.moo::text,
    count(h.id)::bigint,
    count(h.id) filter (where h.volunteer_pid is not null)::bigint,
    count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint,
    count(h.id) filter (where h.coordinate_status like 'resolved_%')::bigint,
    count(h.id) filter (where h.review_required=true)::bigint,
    count(h.id) filter (where h.inside_tambon=false)::bigint,
    count(h.id) filter (where h.inside_community=false)::bigint,
    count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint,
    count(distinct h.volunteer_pid) filter (where h.volunteer_pid is not null)::bigint,
    case
      when v_profile.role='admin' then 'manage'
      when v_profile.role='staff' and btrim(c.name)=btrim(coalesce(v_profile.community,'')) then 'manage'
      else 'view'
    end::text,
    (btrim(c.name)=btrim(coalesce(v_profile.community,'')))::boolean
  from public.communities c
  left join public.houses h on btrim(h.community)=btrim(c.name)
  where c.active=true
    and (
      v_profile.role='admin'
      or (v_profile.role='staff' and c.moo=v_own_moo)
      or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')))
    )
  group by c.name,c.moo
  order by nullif(c.moo,'')::int nulls last, c.name;
end;
$$;

create or replace function public.spatial_community_houses(p_community text)
returns table(
  id uuid,
  house_no text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  volunteer_pid bigint,
  volunteer_name text,
  can_edit boolean
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_target_moo text;
  v_own_moo text;
  v_allowed boolean := false;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select c.moo into v_target_moo from public.communities c where c.active=true and btrim(c.name)=btrim(coalesce(p_community,'')) limit 1;
  if v_target_moo is null then raise exception 'COMMUNITY_NOT_FOUND'; end if;

  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo from public.communities c where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,'')) limit 1;
  end if;

  v_allowed := coalesce(
    v_profile.role='admin'
    or (v_profile.role='staff' and v_target_moo=v_own_moo)
    or (v_profile.role='user' and btrim(coalesce(p_community,''))=btrim(coalesce(v_profile.community,''))),
    false
  );
  if not v_allowed then raise exception 'COMMUNITY_OUT_OF_SCOPE'; end if;

  return query
  select
    h.id,
    h.house_no,
    h.moo,
    h.community,
    h.latitude,
    h.longitude,
    h.coordinate_status,
    h.review_required,
    h.inside_tambon,
    h.inside_community,
    h.volunteer_pid,
    coalesce(v.display_name,'เธขเธฑเธเนเธกเนเนเธ”เนเธกเธญเธเธซเธกเธฒเธข')::text,
    case
      when v_profile.role='admin' then true
      when v_profile.role='staff' then btrim(h.community)=btrim(coalesce(v_profile.community,''))
      when v_profile.role='user' then h.volunteer_pid is not null and h.volunteer_pid=v_profile.volunteer_pid
      else false
    end::boolean
  from public.houses h
  left join public.volunteers v on v.source_pid=h.volunteer_pid and v.active=true
  where btrim(h.community)=btrim(p_community)
  order by h.house_no collate "C";
end;
$$;

create or replace function public.spatial_volunteer_cards()
returns table(
  source_pid bigint,
  display_name text,
  community text,
  moo text,
  anchor_status text,
  house_count bigint,
  pinned_count bigint,
  field_confirmed_count bigint,
  review_count bigint,
  outside_tambon_count bigint,
  outside_community_count bigint,
  missing_count bigint,
  cross_community_count bigint
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  return query
  select
    v.source_pid,
    v.display_name,
    v.community,
    v.moo,
    v.anchor_status,
    count(h.id)::bigint,
    count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint,
    count(h.id) filter (where h.coordinate_status like 'resolved_%')::bigint,
    count(h.id) filter (where h.review_required=true)::bigint,
    count(h.id) filter (where h.inside_tambon=false)::bigint,
    count(h.id) filter (where h.inside_community=false)::bigint,
    count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint,
    count(h.id) filter (where btrim(coalesce(h.community,''))<>btrim(coalesce(v.community,'')))::bigint
  from public.volunteers v
  left join public.houses h on h.volunteer_pid=v.source_pid
  where v.active=true
    and (
      v_profile.role='admin'
      or (v_profile.role='staff' and btrim(v.community)=btrim(coalesce(v_profile.community,'')))
      or (v_profile.role='user' and v.source_pid=v_profile.volunteer_pid)
    )
  group by v.source_pid,v.display_name,v.community,v.moo,v.anchor_status
  order by v.display_name;
end;
$$;

create or replace function public.spatial_volunteer_houses(p_source_pid bigint)
returns table(
  id uuid,
  house_no text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  can_edit boolean
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_vol public.volunteers%rowtype;
  v_allowed boolean := false;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  select * into v_vol from public.volunteers where source_pid=p_source_pid and active=true limit 1;
  if not found then raise exception 'VOLUNTEER_NOT_FOUND'; end if;

  v_allowed := coalesce(
    v_profile.role='admin'
    or (v_profile.role='staff' and btrim(v_vol.community)=btrim(coalesce(v_profile.community,'')))
    or (v_profile.role='user' and v_vol.source_pid=v_profile.volunteer_pid),
    false
  );
  if not v_allowed then raise exception 'VOLUNTEER_OUT_OF_SCOPE'; end if;

  return query
  select h.id,h.house_no,h.moo,h.community,h.latitude,h.longitude,h.coordinate_status,h.review_required,h.inside_tambon,h.inside_community,
    case
      when v_profile.role='admin' then true
      when v_profile.role='staff' then btrim(h.community)=btrim(coalesce(v_profile.community,''))
      when v_profile.role='user' then h.volunteer_pid=v_profile.volunteer_pid
      else false
    end::boolean
  from public.houses h
  where h.volunteer_pid=p_source_pid
  order by h.house_no collate "C";
end;
$$;

revoke all on function public.spatial_community_cards() from public, anon;
revoke all on function public.spatial_community_houses(text) from public, anon;
revoke all on function public.spatial_volunteer_cards() from public, anon;
revoke all on function public.spatial_volunteer_houses(bigint) from public, anon;
grant execute on function public.spatial_community_cards() to authenticated, service_role;
grant execute on function public.spatial_community_houses(text) to authenticated, service_role;
grant execute on function public.spatial_volunteer_cards() to authenticated, service_role;
grant execute on function public.spatial_volunteer_houses(bigint) to authenticated, service_role;

insert into public.app_settings(key,value)
values ('mobile_spatial_cards_policy', jsonb_build_object(
  'version','1.8.21',
  'community_cards',true,
  'volunteer_detail_cards',true,
  'staff_spatial_view_scope','same_moo',
  'staff_write_scope','assigned_community',
  'vhv_spatial_view_scope','assigned_community',
  'vhv_write_scope','assigned_houses',
  'health_scope_unchanged',true,
  'personal_health_data_exposed',false
))
on conflict (key) do update set value=excluded.value;
