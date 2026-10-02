
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
    a.id,h.id,h.house_no,h.moo,h.community,h.volunteer_pid,
    v.display_name,coalesce(p.display_name,'ผู้ใช้งาน'),
    a.role,a.source,a.accuracy_m,
    a.old_latitude,a.old_longitude,a.old_updated_at,
    a.new_latitude,a.new_longitude,a.created_at,
    case
      when a.old_latitude is null or a.old_longitude is null then null
      else extensions.st_distance(
        extensions.st_setsrid(extensions.st_makepoint(a.old_longitude,a.old_latitude),4326)::extensions.geography,
        extensions.st_setsrid(extensions.st_makepoint(a.new_longitude,a.new_latitude),4326)::extensions.geography
      )
    end::double precision,
    a.old_coordinate_status,a.new_coordinate_status,
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

revoke all on function public.coordinate_movement_report_v2132(text,bigint,date,date,boolean,integer) from public, anon;
grant execute on function public.coordinate_movement_report_v2132(text,bigint,date,date,boolean,integer) to authenticated;
