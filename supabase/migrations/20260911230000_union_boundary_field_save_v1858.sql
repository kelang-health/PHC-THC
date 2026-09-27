-- OSM-PHC Cloud v1.8.58
-- Field coordinate acceptance follows the practical survey-area rule:
-- save when the point is inside EITHER the assigned community polygon OR Tambon Phra Bat.
-- Block only when the point is outside BOTH boundaries.
-- Geometry facts are still stored independently so boundary mismatches remain auditable.

begin;

create or replace function public.check_house_location_v1858(
  p_latitude double precision,
  p_longitude double precision,
  p_community text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_point extensions.geometry;
  v_inside_tambon boolean := false;
  v_inside_community boolean := false;
  v_basis text := 'outside_both';
begin
  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    return jsonb_build_object(
      'allowed', false,
      'inside_tambon', false,
      'inside_community', false,
      'validation_basis', 'invalid_coordinate'
    );
  end if;

  v_point := extensions.st_setsrid(
    extensions.st_makepoint(p_longitude, p_latitude), 4326
  );

  select exists (
    select 1
    from public.tambon_boundaries t
    where t.geom is not null
      and t.tambon_code = '520105'
      and extensions.st_covers(t.geom, v_point)
  ) into v_inside_tambon;

  select exists (
    select 1
    from public.communities c
    where c.active = true
      and c.geom is not null
      and private.community_key(c.name) = private.community_key(p_community)
      and extensions.st_covers(c.geom, v_point)
  ) into v_inside_community;

  v_basis := case
    when v_inside_tambon and v_inside_community then 'both'
    when v_inside_community then 'community_only'
    when v_inside_tambon then 'tambon_only'
    else 'outside_both'
  end;

  return jsonb_build_object(
    'allowed', (v_inside_tambon or v_inside_community),
    'inside_tambon', v_inside_tambon,
    'inside_community', v_inside_community,
    'validation_basis', v_basis
  );
end;
$$;

revoke all on function public.check_house_location_v1858(double precision,double precision,text) from public, anon;

grant execute on function public.check_house_location_v1858(double precision,double precision,text) to authenticated;

create or replace function public.update_house_coordinates_v1858(
  p_house_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_source text default 'gps'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_house public.houses%rowtype;
  v_role text;
  v_check jsonb;
  v_inside_tambon boolean;
  v_inside_community boolean;
  v_status text;
  v_reason text := '';
begin
  select * into v_house
  from public.houses
  where id = p_house_id
  for update;

  if not found then
    raise exception 'HOUSE_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_role := private.current_role();
  if v_role is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if not (
    v_role = 'admin'
    or (
      v_role = 'staff'
      and private.community_key(v_house.community) = private.community_key(private.current_community())
    )
    or (
      v_role = 'user'
      and v_house.volunteer_pid = private.current_volunteer_pid()
    )
  ) then
    raise exception 'HOUSE_READ_ONLY_SCOPE' using errcode = '42501';
  end if;

  v_check := public.check_house_location_v1858(
    p_latitude,
    p_longitude,
    v_house.community
  );

  if not coalesce((v_check->>'allowed')::boolean, false) then
    raise exception 'OUTSIDE_BOTH_BOUNDARIES' using errcode = '22023';
  end if;

  v_inside_tambon := coalesce((v_check->>'inside_tambon')::boolean, false);
  v_inside_community := coalesce((v_check->>'inside_community')::boolean, false);

  if v_inside_community then
    v_status := 'resolved_by_community';
  else
    v_status := 'resolved_by_tambon';
  end if;

  v_reason := case
    when v_inside_tambon and v_inside_community then ''
    when v_inside_community then 'เธขเธทเธเธขเธฑเธเธ เธฒเธเธชเธเธฒเธก: เธญเธขเธนเนเนเธเน€เธเธ•เธเธธเธกเธเธ เนเธกเนเน€เธชเนเธเธเธญเธเน€เธเธ• เธ•.เธเธฃเธฐเธเธฒเธ— เนเธกเนเธเธฃเธญเธเธเธฅเธธเธกเธเธธเธ”เธเธตเน'
    when v_inside_tambon then 'เธขเธทเธเธขเธฑเธเธ เธฒเธเธชเธเธฒเธก: เธญเธขเธนเนเนเธเน€เธเธ• เธ•.เธเธฃเธฐเธเธฒเธ— เนเธกเนเน€เธชเนเธเธเธญเธเน€เธเธ•เธเธธเธกเธเธเนเธกเนเธเธฃเธญเธเธเธฅเธธเธกเธเธธเธ”เธเธตเน'
    else ''
  end;

  update public.houses h
  set latitude = p_latitude,
      longitude = p_longitude,
      coordinate_status = v_status,
      coordinate_distance_m = null,
      inside_tambon = v_inside_tambon,
      inside_community = v_inside_community,
      review_required = false,
      review_reason = v_reason,
      updated_at = now()
  where h.id = p_house_id
  returning h.* into v_house;

  return v_check || jsonb_build_object(
    'id', v_house.id,
    'latitude', v_house.latitude,
    'longitude', v_house.longitude,
    'coordinate_status', v_house.coordinate_status,
    'inside_tambon', v_house.inside_tambon,
    'inside_community', v_house.inside_community,
    'review_required', v_house.review_required,
    'review_reason', v_house.review_reason,
    'source', coalesce(nullif(btrim(p_source), ''), 'gps')
  );
end;
$$;

revoke all on function public.update_house_coordinates_v1858(uuid,double precision,double precision,text) from public, anon;

grant execute on function public.update_house_coordinates_v1858(uuid,double precision,double precision,text) to authenticated;

insert into public.app_settings(key,value)
values ('field_coordinate_acceptance', jsonb_build_object(
  'version','1.8.58',
  'rule','inside_community_or_tambon',
  'block_only_when','outside_both',
  'community_boundary','survey_area_reference',
  'tambon_boundary','fallback_when_community_polygon_is_offset',
  'store_both_geometry_checks',true
))
on conflict(key) do update set value=excluded.value, updated_at=now();

commit;
