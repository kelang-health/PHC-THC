
alter table public.house_coordinate_audit
  add column if not exists accuracy_m double precision;

alter table public.house_coordinate_audit
  drop constraint if exists house_coordinate_audit_accuracy_m_check;

alter table public.house_coordinate_audit
  add constraint house_coordinate_audit_accuracy_m_check
  check (accuracy_m is null or (accuracy_m >= 0 and accuracy_m <= 10000));

create index if not exists idx_house_coordinate_audit_created_at_v2132
  on public.house_coordinate_audit(created_at desc);

create index if not exists idx_house_coordinate_audit_review_created_v2132
  on public.house_coordinate_audit(new_review_required, created_at desc);

create or replace function public.update_house_coordinates_v2132(
  p_house_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_source text default 'gps'::text,
  p_accuracy_m double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_house public.houses%rowtype;
  v_role text;
  v_uid uuid := auth.uid();
  v_source text := lower(coalesce(nullif(btrim(p_source),''),'gps'));
  v_accuracy double precision := case
    when p_accuracy_m is null then null
    when p_accuracy_m >= 0 and p_accuracy_m <= 10000 then p_accuracy_m
    else null
  end;
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
    new_coordinate_source,new_coordinate_status,new_review_required,new_review_reason,
    accuracy_m
  ) values (
    v_house.id,v_uid,v_role,v_source,
    v_house.latitude,v_house.longitude,p_latitude,p_longitude,
    v_house.coordinate_source,v_house.coordinate_status,v_house.coordinate_distance_m,
    v_house.inside_tambon,v_house.inside_community,v_house.review_required,v_house.review_reason,v_house.updated_at,
    v_source,v_status,v_review_required,v_reason,
    v_accuracy
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
    'accuracy_m',v_accuracy,
    'audit_saved',true
  );
end;
$function$;

create or replace function public.update_house_coordinates_v1858(
  p_house_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_source text default 'gps'::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
begin
  return public.update_house_coordinates_v2132(
    p_house_id,p_latitude,p_longitude,p_source,null
  );
end;
$function$;

create or replace function public.coordinate_audit_summary_v2132()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_community text;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;
  v_role := private.current_role();
  if v_role not in ('admin','staff') then
    raise exception 'STAFF_ADMIN_REQUIRED' using errcode='42501';
  end if;
  v_community := case when v_role='staff' then private.current_community() else null end;

  select jsonb_build_object(
    'audit_total', count(*),
    'updates_7d', count(*) filter (where a.created_at >= now()-interval '7 days'),
    'gps_updates', count(*) filter (where a.source='gps'),
    'map_updates', count(*) filter (where a.source='map'),
    'review_events', count(*) filter (where coalesce(a.new_review_required,false)=true),
    'review_current', (
      select count(*)
      from public.houses h2
      where h2.superseded_at is null
        and h2.review_required=true
        and h2.coordinate_status in ('boundary_mismatch_community','boundary_mismatch_tambon','boundary_review')
        and (v_role='admin' or private.community_key(h2.community)=private.community_key(v_community))
    )
  )
  into v_result
  from public.house_coordinate_audit a
  join public.houses h on h.id=a.house_id
  where v_role='admin' or private.community_key(h.community)=private.community_key(v_community);

  return coalesce(v_result,'{}'::jsonb);
end;
$function$;

create or replace function public.coordinate_movement_report_v2132(
  p_community text default null,
  p_volunteer_pid bigint default null,
  p_from date default null,
  p_to date default null,
  p_review_only boolean default false,
  p_limit integer default 500
)
returns table(
  audit_id bigint,
  house_id uuid,
  house_no text,
  moo text,
  community text,
  volunteer_pid bigint,
  volunteer_name text,
  actor_name text,
  actor_role text,
  source text,
  accuracy_m double precision,
  old_latitude double precision,
  old_longitude double precision,
  old_updated_at timestamptz,
  new_latitude double precision,
  new_longitude double precision,
  new_updated_at timestamptz,
  moved_distance_m double precision,
  old_coordinate_status text,
  new_coordinate_status text,
  event_review_required boolean,
  current_review_required boolean,
  current_review_reason text
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_scope_community text;
  v_limit integer := least(greatest(coalesce(p_limit,500),1),2000);
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;
  v_role := private.current_role();
  if v_role not in ('admin','staff') then
    raise exception 'STAFF_ADMIN_REQUIRED' using errcode='42501';
  end if;
  v_scope_community := case when v_role='staff' then private.current_community() else null end;

  return query
  select
    a.id,
    h.id,
    h.house_no,
    h.moo,
    h.community,
    h.volunteer_pid,
    v.display_name,
    coalesce(p.display_name,'ผู้ใช้งาน'),
    a.role,
    a.source,
    a.accuracy_m,
    a.old_latitude,
    a.old_longitude,
    a.old_updated_at,
    a.new_latitude,
    a.new_longitude,
    a.created_at,
    case
      when a.old_latitude is null or a.old_longitude is null then null
      else extensions.st_distance(
        extensions.st_setsrid(extensions.st_makepoint(a.old_longitude,a.old_latitude),4326)::geography,
        extensions.st_setsrid(extensions.st_makepoint(a.new_longitude,a.new_latitude),4326)::geography
      )
    end::double precision,
    a.old_coordinate_status,
    a.new_coordinate_status,
    coalesce(a.new_review_required,false),
    coalesce(h.review_required,false),
    h.review_reason
  from public.house_coordinate_audit a
  join public.houses h on h.id=a.house_id
  left join public.profiles p on p.user_id=a.user_id
  left join public.volunteers v on v.source_pid=h.volunteer_pid and v.active=true
  where
    (v_role='admin' or private.community_key(h.community)=private.community_key(v_scope_community))
    and (coalesce(btrim(p_community),'')='' or private.community_key(h.community)=private.community_key(p_community))
    and (p_volunteer_pid is null or h.volunteer_pid=p_volunteer_pid)
    and (p_from is null or a.created_at >= (p_from::timestamp at time zone 'Asia/Bangkok'))
    and (p_to is null or a.created_at < (((p_to+1)::timestamp) at time zone 'Asia/Bangkok'))
    and (not coalesce(p_review_only,false) or coalesce(a.new_review_required,false) or coalesce(h.review_required,false))
  order by a.created_at desc
  limit v_limit;
end;
$function$;

create or replace function public.coordinate_boundary_review_worklist_v2132(
  p_community text default null,
  p_limit integer default 500
)
returns table(
  house_id uuid,
  house_no text,
  moo text,
  community text,
  volunteer_pid bigint,
  volunteer_name text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  inside_tambon boolean,
  inside_community boolean,
  review_reason text,
  updated_at timestamptz,
  latest_audit_at timestamptz,
  latest_actor_name text,
  latest_source text,
  latest_accuracy_m double precision
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_scope_community text;
  v_limit integer := least(greatest(coalesce(p_limit,500),1),2000);
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode='42501';
  end if;
  v_role := private.current_role();
  if v_role not in ('admin','staff') then
    raise exception 'STAFF_ADMIN_REQUIRED' using errcode='42501';
  end if;
  v_scope_community := case when v_role='staff' then private.current_community() else null end;

  return query
  select
    h.id,h.house_no,h.moo,h.community,h.volunteer_pid,
    v.display_name,h.latitude,h.longitude,h.coordinate_status,
    h.inside_tambon,h.inside_community,h.review_reason,h.updated_at,
    la.created_at,coalesce(ap.display_name,'ผู้ใช้งาน'),la.source,la.accuracy_m
  from public.houses h
  left join public.volunteers v on v.source_pid=h.volunteer_pid and v.active=true
  left join lateral (
    select a.created_at,a.user_id,a.source,a.accuracy_m
    from public.house_coordinate_audit a
    where a.house_id=h.id
    order by a.created_at desc
    limit 1
  ) la on true
  left join public.profiles ap on ap.user_id=la.user_id
  where h.superseded_at is null
    and h.review_required=true
    and h.coordinate_status in ('boundary_mismatch_community','boundary_mismatch_tambon','boundary_review')
    and (v_role='admin' or private.community_key(h.community)=private.community_key(v_scope_community))
    and (coalesce(btrim(p_community),'')='' or private.community_key(h.community)=private.community_key(p_community))
  order by
    case h.coordinate_status when 'boundary_review' then 0 else 1 end,
    h.updated_at desc
  limit v_limit;
end;
$function$;

revoke all on function public.update_house_coordinates_v2132(uuid,double precision,double precision,text,double precision) from public, anon;
grant execute on function public.update_house_coordinates_v2132(uuid,double precision,double precision,text,double precision) to authenticated;

revoke all on function public.coordinate_audit_summary_v2132() from public, anon;
grant execute on function public.coordinate_audit_summary_v2132() to authenticated;

revoke all on function public.coordinate_movement_report_v2132(text,bigint,date,date,boolean,integer) from public, anon;
grant execute on function public.coordinate_movement_report_v2132(text,bigint,date,date,boolean,integer) to authenticated;

revoke all on function public.coordinate_boundary_review_worklist_v2132(text,integer) from public, anon;
grant execute on function public.coordinate_boundary_review_worklist_v2132(text,integer) to authenticated;

insert into public.app_settings(key,value,updated_at)
values(
  'phase6_coordinate_audit_v2132',
  jsonb_build_object(
    'version','2.0.132',
    'audit_accuracy_m',true,
    'movement_report',true,
    'boundary_review_worklist',true,
    'old_new_coordinates',true,
    'old_new_timestamps',true,
    'distance_report_only',true,
    'distance_is_blocker',false,
    'roles',jsonb_build_array('admin','staff')
  ),
  now()
)
on conflict (key) do update
set value=excluded.value,updated_at=excluded.updated_at;
