
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
  if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  v_role := private.current_role();
  if v_role not in ('admin','staff') then raise exception 'STAFF_ADMIN_REQUIRED' using errcode='42501'; end if;
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
        and h2.latitude is not null and h2.longitude is not null
        and h2.inside_tambon is not null and h2.inside_community is not null
        and not (h2.inside_tambon and h2.inside_community)
        and (v_role='admin' or private.community_key(h2.community)=private.community_key(v_community))
    )
  ) into v_result
  from public.house_coordinate_audit a
  join public.houses h on h.id=a.house_id
  where v_role='admin' or private.community_key(h.community)=private.community_key(v_community);

  return coalesce(v_result,'{}'::jsonb);
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
  if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  v_role := private.current_role();
  if v_role not in ('admin','staff') then raise exception 'STAFF_ADMIN_REQUIRED' using errcode='42501'; end if;
  v_scope_community := case when v_role='staff' then private.current_community() else null end;

  return query
  select
    h.id,h.house_no,h.moo,h.community,h.volunteer_pid,v.display_name,h.latitude,h.longitude,
    case
      when h.inside_tambon=false and h.inside_community=true then 'boundary_mismatch_community'
      when h.inside_tambon=true and h.inside_community=false then 'boundary_mismatch_tambon'
      when h.inside_tambon=false and h.inside_community=false then 'boundary_review'
      else h.coordinate_status
    end,
    h.inside_tambon,h.inside_community,
    case
      when coalesce(btrim(h.review_reason),'')<>'' then h.review_reason
      when h.inside_tambon=false and h.inside_community=true then 'พิกัดปัจจุบันอยู่ในชุมชน แต่เส้นอ้างอิง ต.พระบาท ไม่ครอบคลุม · รอตรวจแนวเขต'
      when h.inside_tambon=true and h.inside_community=false then 'พิกัดปัจจุบันอยู่ใน ต.พระบาท แต่เส้นชุมชนไม่ครอบคลุม · รอตรวจแนวเขต'
      when h.inside_tambon=false and h.inside_community=false then 'พิกัดปัจจุบันอยู่นอกเส้นอ้างอิงทั้งสองชุด · รอตรวจภาคสนาม/แนวเขต'
      else ''
    end,
    h.updated_at,la.created_at,coalesce(ap.display_name,'ผู้ใช้งาน'),la.source,la.accuracy_m
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
    and h.latitude is not null and h.longitude is not null
    and h.inside_tambon is not null and h.inside_community is not null
    and not (h.inside_tambon and h.inside_community)
    and (v_role='admin' or private.community_key(h.community)=private.community_key(v_scope_community))
    and (coalesce(btrim(p_community),'')='' or private.community_key(h.community)=private.community_key(p_community))
  order by
    case
      when h.inside_tambon=false and h.inside_community=false then 0
      when h.inside_tambon=false and h.inside_community=true then 1
      else 2
    end,
    h.updated_at desc
  limit v_limit;
end;
$function$;

revoke all on function public.coordinate_audit_summary_v2132() from public, anon;
grant execute on function public.coordinate_audit_summary_v2132() to authenticated;
revoke all on function public.coordinate_boundary_review_worklist_v2132(text,integer) from public, anon;
grant execute on function public.coordinate_boundary_review_worklist_v2132(text,integer) to authenticated;
