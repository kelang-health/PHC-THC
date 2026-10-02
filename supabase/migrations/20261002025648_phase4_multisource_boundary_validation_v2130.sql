
-- Phase 4: multi-source boundary validation for field house coordinates.
-- Canonical rule:
--   * inside tambon OR inside assigned community => save allowed
--   * only one boundary matches => save + review_required
--   * outside both => USER blocked; STAFF/ADMIN may save as boundary-review evidence
-- Existing coordinate history remains in house_coordinate_audit.

create or replace function public.check_house_location_v1858(
  p_latitude double precision,
  p_longitude double precision,
  p_community text
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_point extensions.geometry;
  v_inside_tambon boolean := false;
  v_inside_community boolean := false;
  v_basis text := 'outside_both';
  v_override_allowed boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;

  v_role := private.current_role();
  if v_role is null then
    raise exception 'PROFILE_NOT_ACTIVE' using errcode='42501';
  end if;

  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    return jsonb_build_object(
      'allowed', false,
      'inside_tambon', false,
      'inside_community', false,
      'validation_basis', 'invalid_coordinate',
      'boundary_mismatch', false,
      'review_required', false,
      'boundary_override_allowed', false
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
      and extensions.st_covers(extensions.st_makevalid(t.geom), v_point)
  ) into v_inside_tambon;

  select exists (
    select 1
    from public.communities c
    where c.active = true
      and c.geom is not null
      and private.community_key(c.name) = private.community_key(p_community)
      and extensions.st_covers(extensions.st_makevalid(c.geom), v_point)
  ) into v_inside_community;

  v_basis := case
    when v_inside_tambon and v_inside_community then 'both'
    when v_inside_community then 'community_only'
    when v_inside_tambon then 'tambon_only'
    else 'outside_both'
  end;

  v_override_allowed := (not v_inside_tambon and not v_inside_community and v_role in ('admin','staff'));

  return jsonb_build_object(
    'allowed', (v_inside_tambon or v_inside_community),
    'inside_tambon', v_inside_tambon,
    'inside_community', v_inside_community,
    'validation_basis', v_basis,
    'boundary_mismatch', (v_inside_tambon <> v_inside_community),
    'review_required', (v_inside_tambon <> v_inside_community) or (not v_inside_tambon and not v_inside_community),
    'boundary_override_allowed', v_override_allowed,
    'tambon_reference', 'DPM_TH_Boundary:520105',
    'community_reference', 'j-report'
  );
end;
$function$;

revoke all on function public.check_house_location_v1858(double precision,double precision,text) from public,anon;
grant execute on function public.check_house_location_v1858(double precision,double precision,text) to authenticated,service_role;

create or replace function public.check_house_location(
  p_latitude double precision,
  p_longitude double precision,
  p_community text default null::text
) returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_community_name text;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;

  v_role := private.current_role();
  if v_role is null then
    raise exception 'PROFILE_NOT_ACTIVE' using errcode='42501';
  end if;

  v_community_name := case
    when v_role='admin' then btrim(coalesce(p_community,''))
    else btrim(coalesce(private.current_community(),''))
  end;

  if v_community_name='' then
    raise exception 'COMMUNITY_REQUIRED' using errcode='22023';
  end if;

  if not exists (
    select 1 from public.communities c
    where c.active=true and private.community_key(c.name)=private.community_key(v_community_name)
  ) then
    raise exception 'COMMUNITY_NOT_FOUND' using errcode='P0002';
  end if;

  return public.check_house_location_v1858(p_latitude,p_longitude,v_community_name)
    || jsonb_build_object('community',v_community_name);
end;
$function$;

revoke all on function public.check_house_location(double precision,double precision,text) from public,anon;
grant execute on function public.check_house_location(double precision,double precision,text) to authenticated,service_role;

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
  v_allowed boolean;
  v_override_allowed boolean;
  v_status text;
  v_reason text := '';
  v_review_required boolean := false;
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
  v_allowed := coalesce((v_check->>'allowed')::boolean,false);
  v_override_allowed := coalesce((v_check->>'boundary_override_allowed')::boolean,false);

  if not v_allowed and not v_override_allowed then
    raise exception 'OUTSIDE_BOTH_BOUNDARIES' using errcode='22023';
  end if;

  v_inside_tambon := coalesce((v_check->>'inside_tambon')::boolean,false);
  v_inside_community := coalesce((v_check->>'inside_community')::boolean,false);

  if v_inside_tambon and v_inside_community then
    v_status := 'resolved_by_community';
    v_reason := '';
    v_review_required := false;
  elsif v_inside_community then
    v_status := 'boundary_mismatch_community';
    v_reason := 'ยืนยันภาคสนาม: อยู่ในเขตชุมชน แต่เส้นอ้างอิง ต.พระบาท ไม่ครอบคลุมจุดนี้ · รอตรวจแนวเขต';
    v_review_required := true;
  elsif v_inside_tambon then
    v_status := 'boundary_mismatch_tambon';
    v_reason := 'ยืนยันภาคสนาม: อยู่ในเขต ต.พระบาท แต่เส้นขอบเขตชุมชนไม่ครอบคลุมจุดนี้ · รอตรวจแนวเขต';
    v_review_required := true;
  else
    v_status := 'boundary_review';
    v_reason := 'ยืนยันภาคสนามโดย STAFF/ADMIN: จุดอยู่นอกเส้นอ้างอิงทั้งตำบลและชุมชน · เก็บพิกัดไว้เพื่อรอตรวจแนวเขต';
    v_review_required := true;
  end if;

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
    v_source,v_status,v_review_required,v_reason
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
      review_required=v_review_required,
      review_reason=v_reason,
      updated_at=now()
  where h.id=p_house_id
  returning h.* into v_house;

  return v_check || jsonb_build_object(
    'success',true,
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
grant execute on function public.update_house_coordinates_v1858(uuid,double precision,double precision,text) to authenticated,service_role;

create or replace function public.update_house_coordinates(
  p_house_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_source text default 'gps'::text
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  return public.update_house_coordinates_v1858(
    p_house_id,p_latitude,p_longitude,p_source
  );
end;
$function$;

revoke all on function public.update_house_coordinates(uuid,double precision,double precision,text) from public,anon;
grant execute on function public.update_house_coordinates(uuid,double precision,double precision,text) to authenticated,service_role;

create or replace function public.add_house_field(
  p_house_no text,
  p_house_id_11 text,
  p_latitude double precision,
  p_longitude double precision,
  p_source text default 'gps'::text,
  p_community text default null::text
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_profile public.profiles%rowtype;
  v_community public.communities%rowtype;
  v_house_no text:=btrim(coalesce(p_house_no,''));
  v_house_no_key text;
  v_house_id text:=btrim(coalesce(p_house_id_11,''));
  v_source text:=lower(btrim(coalesce(p_source,'gps')));
  v_community_name text;
  v_count integer:=0;
  v_new_id uuid:=extensions.gen_random_uuid();
  v_hcode text;
  v_check jsonb;
  v_inside_tambon boolean:=false;
  v_inside_community boolean:=false;
  v_allowed boolean:=false;
  v_override_allowed boolean:=false;
  v_status text;
  v_boundary_reason text:='';
  v_review_reason text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_profile.role not in ('admin','staff','user') then raise exception 'HOUSE_ADD_NOT_ALLOWED'; end if;
  if v_house_no='' or length(v_house_no)>50 then raise exception 'INVALID_HOUSE_NO'; end if;
  v_house_no_key:=lower(regexp_replace(v_house_no,'\s+','','g'));
  if v_house_id !~ '^[0-9]{11}$' then raise exception 'HOUSE_ID_11_REQUIRED'; end if;
  if p_latitude is null or p_longitude is null or p_latitude<5 or p_latitude>21 or p_longitude<97 or p_longitude>106 then raise exception 'INVALID_COORDINATES'; end if;
  if v_source not in ('gps','map') then raise exception 'INVALID_COORDINATE_SOURCE'; end if;

  v_community_name:=case when v_profile.role='admin' then btrim(coalesce(p_community,'')) else btrim(coalesce(v_profile.community,'')) end;
  if v_community_name='' then raise exception 'COMMUNITY_REQUIRED'; end if;
  select * into v_community
  from public.communities
  where active=true and private.community_key(name)=private.community_key(v_community_name)
  limit 1;
  if not found then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  if v_profile.role='staff' and private.community_key(v_community.name)<>private.community_key(v_profile.community) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;

  v_check := public.check_house_location_v1858(p_latitude,p_longitude,v_community.name);
  v_inside_tambon := coalesce((v_check->>'inside_tambon')::boolean,false);
  v_inside_community := coalesce((v_check->>'inside_community')::boolean,false);
  v_allowed := coalesce((v_check->>'allowed')::boolean,false);
  v_override_allowed := coalesce((v_check->>'boundary_override_allowed')::boolean,false);

  if not v_allowed and not v_override_allowed then
    raise exception 'OUTSIDE_BOTH_BOUNDARIES';
  end if;

  if v_inside_tambon and v_inside_community then
    v_status := 'resolved_by_community';
  elsif v_inside_community then
    v_status := 'boundary_mismatch_community';
    v_boundary_reason := 'แนวเขตอ้างอิงไม่ตรงกัน: จุดอยู่ในชุมชน แต่เส้น ต.พระบาท ไม่ครอบคลุม';
  elsif v_inside_tambon then
    v_status := 'boundary_mismatch_tambon';
    v_boundary_reason := 'แนวเขตอ้างอิงไม่ตรงกัน: จุดอยู่ใน ต.พระบาท แต่เส้นชุมชนไม่ครอบคลุม';
  else
    v_status := 'boundary_review';
    v_boundary_reason := 'STAFF/ADMIN บันทึกจุดนอกเส้นอ้างอิงทั้งสองชุดเพื่อรอตรวจแนวเขต';
  end if;

  v_review_reason := case
    when v_boundary_reason='' then 'บ้านเพิ่มจาก Cloud รอเจ้าหน้าที่ตรวจ/บันทึก JHCIS'
    else v_boundary_reason || ' · บ้านเพิ่มจาก Cloud รอเจ้าหน้าที่ตรวจ/บันทึก JHCIS'
  end;

  perform pg_advisory_xact_lock(pg_catalog.hashtextextended('house11:'||v_house_id,0));
  if exists(select 1 from public.houses where house_id_11=v_house_id and superseded_by is null and verification_status<>'rejected') then raise exception 'DUPLICATE_HOUSE_ID_11'; end if;
  perform pg_advisory_xact_lock(pg_catalog.hashtextextended('houseno:'||v_community.moo||':'||v_house_no_key,0));
  if exists(
    select 1 from public.houses h
    where h.superseded_by is null
      and h.verification_status<>'rejected'
      and btrim(h.moo)=btrim(v_community.moo)
      and lower(regexp_replace(btrim(h.house_no),'\s+','','g'))=v_house_no_key
  ) then raise exception 'DUPLICATE_HOUSE_NO_MOO'; end if;

  if v_profile.role in ('staff','user') then
    if v_profile.volunteer_pid is null then raise exception 'VOLUNTEER_NOT_LINKED'; end if;
    perform pg_advisory_xact_lock(pg_catalog.hashtextextended('vhvquota:'||v_profile.volunteer_pid::text,0));
    select count(*) into v_count
    from public.houses
    where entry_source='field'
      and created_by_volunteer_pid=v_profile.volunteer_pid
      and superseded_by is null
      and verification_status<>'rejected';
    if v_count>=30 then raise exception 'VHV_HOUSE_LIMIT'; end if;
  end if;

  v_hcode:='field-'||replace(v_new_id::text,'-','');

  insert into public.houses(
    id,source_pcucode,hcode,house_no,moo,community,latitude,longitude,geom,coordinate_source,coordinate_status,
    coordinate_distance_m,inside_tambon,inside_community,volunteer_pid,record_status,review_required,review_reason,
    house_id_11,entry_source,created_by_user_id,created_by_volunteer_pid,field_created_at,updated_at,
    verification_status,verification_note
  ) values (
    v_new_id,'06116',v_hcode,v_house_no,v_community.moo,v_community.name,p_latitude,p_longitude,
    extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326),v_source,v_status,
    null,v_inside_tambon,v_inside_community,null,'รอตรวจ JHCIS',true,v_review_reason,
    v_house_id,'field',v_uid,v_profile.volunteer_pid,now(),now(),
    'pending_jhcis_create','รอเจ้าหน้าที่ตรวจและบันทึกใน JHCIS'
  );

  insert into public.house_registration_audit(house_id,user_id,role,volunteer_pid,action,before_data,after_data)
  select v_new_id,v_uid,v_profile.role,v_profile.volunteer_pid,'add',null,to_jsonb(h)
  from public.houses h where h.id=v_new_id;

  if v_profile.role in ('staff','user') then v_count:=v_count+1; end if;

  return v_check || jsonb_build_object(
    'success',true,
    'house_id',v_new_id,
    'house_no',v_house_no,
    'house_id_11',v_house_id,
    'moo',v_community.moo,
    'community',v_community.name,
    'coordinate_status',v_status,
    'review_required',true,
    'review_reason',v_review_reason,
    'verification_status','pending_jhcis_create',
    'status_label','รอตรวจ JHCIS',
    'quota_limit',case when v_profile.role='admin' then null else 30 end,
    'quota_used',case when v_profile.role='admin' then null else v_count end,
    'quota_remaining',case when v_profile.role='admin' then null else greatest(30-v_count,0) end
  );
end;
$function$;

revoke all on function public.add_house_field(text,text,double precision,double precision,text,text) from public,anon;
grant execute on function public.add_house_field(text,text,double precision,double precision,text,text) to authenticated,service_role;

insert into public.app_settings(key,value,updated_at)
values (
  'boundary_validation_policy_v2130',
  jsonb_build_object(
    'version','2.0.130',
    'mode','multi_source_or_with_review',
    'tambon_reference','DPM_TH_Boundary:520105',
    'community_reference','j-report',
    'inside_both','save_verified',
    'inside_one','save_review_boundary_mismatch',
    'outside_both_user','blocked',
    'outside_both_staff_admin','save_boundary_review',
    'old_coordinate_distance_used_as_blocker',false,
    'audit_required',true
  ),
  now()
)
on conflict (key) do update
set value=excluded.value,updated_at=excluded.updated_at;

update public.app_settings
set value = coalesce(value,'{}'::jsonb) || jsonb_build_object(
      'version','2.0.130',
      'spatial_check','multi_source_or_with_review',
      'must_be_inside_tambon_phrabat',false,
      'must_be_inside_assigned_community',false,
      'must_match_at_least_one_boundary',true,
      'boundary_mismatch_review',true,
      'outside_both_user_blocked',true,
      'outside_both_staff_admin_review',true
    ),
    updated_at=now()
where key='house_field_registration_policy';
