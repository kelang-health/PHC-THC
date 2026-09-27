
create or replace function public.update_house_coordinates_v1858(
  p_house_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_source text default 'gps'::text
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_house public.houses%rowtype;
  v_role text;
  v_uid uuid := auth.uid();
  v_source text := lower(coalesce(nullif(btrim(p_source),''),'gps'));
  v_check jsonb;
  v_inside_tambon boolean;
  v_inside_community boolean;
  v_status text;
  v_reason text := '';
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;
  if v_source not in ('gps','map') then
    raise exception 'INVALID_COORDINATE_SOURCE' using errcode='22023';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude < 5 or p_latitude > 21
     or p_longitude < 97 or p_longitude > 106 then
    raise exception 'INVALID_COORDINATES' using errcode='22023';
  end if;

  select * into v_house
  from public.houses
  where id=p_house_id
  for update;
  if not found then
    raise exception 'HOUSE_NOT_FOUND' using errcode='P0002';
  end if;

  v_role := private.current_role();
  if v_role is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;

  if not (
    v_role='admin'
    or (v_role='staff' and private.community_key(v_house.community)=private.community_key(private.current_community()))
    or (v_role='user' and v_house.volunteer_pid=private.current_volunteer_pid())
  ) then
    raise exception 'HOUSE_READ_ONLY_SCOPE' using errcode='42501';
  end if;

  v_check := public.check_house_location_v1858(p_latitude,p_longitude,v_house.community);
  if not coalesce((v_check->>'allowed')::boolean,false) then
    raise exception 'OUTSIDE_BOTH_BOUNDARIES' using errcode='22023';
  end if;

  v_inside_tambon := coalesce((v_check->>'inside_tambon')::boolean,false);
  v_inside_community := coalesce((v_check->>'inside_community')::boolean,false);
  v_status := case when v_inside_community then 'resolved_by_community' else 'resolved_by_tambon' end;
  v_reason := case
    when v_inside_tambon and v_inside_community then ''
    when v_inside_community then 'เธขเธทเธเธขเธฑเธเธ เธฒเธเธชเธเธฒเธก: เธญเธขเธนเนเนเธเน€เธเธ•เธเธธเธกเธเธ เนเธกเนเน€เธชเนเธเธเธญเธเน€เธเธ• เธ•.เธเธฃเธฐเธเธฒเธ— เนเธกเนเธเธฃเธญเธเธเธฅเธธเธกเธเธธเธ”เธเธตเน'
    when v_inside_tambon then 'เธขเธทเธเธขเธฑเธเธ เธฒเธเธชเธเธฒเธก: เธญเธขเธนเนเนเธเน€เธเธ• เธ•.เธเธฃเธฐเธเธฒเธ— เนเธกเนเน€เธชเนเธเธเธญเธเน€เธเธ•เธเธธเธกเธเธเนเธกเนเธเธฃเธญเธเธเธฅเธธเธกเธเธธเธ”เธเธตเน'
    else ''
  end;

  insert into public.house_coordinate_audit(
    house_id,user_id,role,source,
    old_latitude,old_longitude,new_latitude,new_longitude,
    old_coordinate_source,old_coordinate_status,old_coordinate_distance_m,
    old_inside_tambon,old_inside_community,old_review_required,old_review_reason,old_updated_at,
    new_coordinate_source,new_coordinate_status,new_review_required,new_review_reason
  ) values (
    v_house.id,v_uid,v_role,v_source,
    v_house.latitude,v_house.longitude,p_latitude,p_longitude,
    v_house.coordinate_source,v_house.coordinate_status,v_house.coordinate_distance_m,
    v_house.inside_tambon,v_house.inside_community,v_house.review_required,v_house.review_reason,v_house.updated_at,
    v_source,v_status,false,v_reason
  );

  update public.houses h
  set latitude=p_latitude,
      longitude=p_longitude,
      geom=extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326),
      coordinate_source=v_source,
      coordinate_status=v_status,
      coordinate_distance_m=null,
      inside_tambon=v_inside_tambon,
      inside_community=v_inside_community,
      review_required=false,
      review_reason=v_reason,
      updated_at=now()
  where h.id=p_house_id
  returning h.* into v_house;

  return v_check || jsonb_build_object(
    'id',v_house.id,
    'latitude',v_house.latitude,
    'longitude',v_house.longitude,
    'coordinate_source',v_house.coordinate_source,
    'coordinate_status',v_house.coordinate_status,
    'inside_tambon',v_house.inside_tambon,
    'inside_community',v_house.inside_community,
    'review_required',v_house.review_required,
    'review_reason',v_house.review_reason,
    'source',v_source,
    'audit_saved',true
  );
end;
$function$;

revoke all on function public.update_house_coordinates_v1858(uuid,double precision,double precision,text) from public,anon;
grant execute on function public.update_house_coordinates_v1858(uuid,double precision,double precision,text) to authenticated;
