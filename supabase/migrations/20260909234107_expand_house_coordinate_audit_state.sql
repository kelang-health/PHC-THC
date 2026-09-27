alter table public.house_coordinate_audit
  add column if not exists old_coordinate_source text,
  add column if not exists old_coordinate_status text,
  add column if not exists old_coordinate_distance_m double precision,
  add column if not exists old_inside_tambon boolean,
  add column if not exists old_inside_community boolean,
  add column if not exists old_review_required boolean,
  add column if not exists old_review_reason text,
  add column if not exists old_updated_at timestamptz,
  add column if not exists new_coordinate_source text,
  add column if not exists new_coordinate_status text,
  add column if not exists new_review_required boolean,
  add column if not exists new_review_reason text;

create or replace function public.update_house_coordinates(
  p_house_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_source text default 'gps'
) returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_house public.houses%rowtype;
  v_source text := lower(coalesce(p_source,'gps'));
  v_status text;
  v_allowed boolean := false;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_latitude is null or p_longitude is null or p_latitude < 5 or p_latitude > 21 or p_longitude < 97 or p_longitude > 106 then
    raise exception 'INVALID_COORDINATES';
  end if;
  if v_source not in ('gps','map') then raise exception 'INVALID_COORDINATE_SOURCE'; end if;

  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select * into v_house from public.houses where id=p_house_id for update;
  if not found then raise exception 'HOUSE_NOT_FOUND'; end if;

  v_allowed := coalesce(
    v_profile.role='admin'
    or (
      v_profile.role='staff'
      and coalesce(btrim(v_profile.community),'')<>''
      and coalesce(btrim(v_house.community),'')=btrim(v_profile.community)
    )
    or (
      v_profile.role='user'
      and v_profile.volunteer_pid is not null
      and v_house.volunteer_pid is not null
      and v_house.volunteer_pid=v_profile.volunteer_pid
    ),
    false
  );
  if not v_allowed then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;

  v_status := case when v_profile.role='admin' then 'resolved_by_tambon' else 'resolved_by_community' end;

  insert into public.house_coordinate_audit(
    house_id,user_id,role,source,
    old_latitude,old_longitude,new_latitude,new_longitude,
    old_coordinate_source,old_coordinate_status,old_coordinate_distance_m,
    old_inside_tambon,old_inside_community,old_review_required,old_review_reason,old_updated_at,
    new_coordinate_source,new_coordinate_status,new_review_required,new_review_reason
  ) values (
    v_house.id,v_uid,v_profile.role,v_source,
    v_house.latitude,v_house.longitude,p_latitude,p_longitude,
    v_house.coordinate_source,v_house.coordinate_status,v_house.coordinate_distance_m,
    v_house.inside_tambon,v_house.inside_community,v_house.review_required,v_house.review_reason,v_house.updated_at,
    v_source,v_status,false,''
  );

  update public.houses
     set latitude=p_latitude,
         longitude=p_longitude,
         geom=extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326),
         coordinate_source=v_source,
         coordinate_status=v_status,
         coordinate_distance_m=null,
         inside_tambon=null,
         inside_community=null,
         review_required=false,
         review_reason='',
         updated_at=now()
   where id=v_house.id;

  return jsonb_build_object('success',true,'house_id',v_house.id,'latitude',p_latitude,'longitude',p_longitude,'coordinate_source',v_source,'coordinate_status',v_status,'review_required',false,'saved_at',now());
end;
$$;
revoke all on function public.update_house_coordinates(uuid,double precision,double precision,text) from public, anon;
grant execute on function public.update_house_coordinates(uuid,double precision,double precision,text) to authenticated;
