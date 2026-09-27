create or replace function public.spatial_scope_dashboard()
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_own_moo text;
  v_total bigint := 0;
  v_assigned bigint := 0;
  v_pinned bigint := 0;
  v_field bigint := 0;
  v_review bigint := 0;
  v_out_tambon bigint := 0;
  v_out_community bigint := 0;
  v_missing bigint := 0;
  v_missing_id11 bigint := 0;
  v_pct numeric := 0;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,'')) limit 1;
  end if;
  select
    count(h.id),
    count(h.id) filter (where h.volunteer_pid is not null),
    count(h.id) filter (where h.latitude is not null and h.longitude is not null),
    count(h.id) filter (where h.coordinate_status like 'resolved_%'),
    count(h.id) filter (where h.review_required=true),
    count(h.id) filter (where h.inside_tambon=false),
    count(h.id) filter (where h.inside_community=false and h.inside_tambon is distinct from false),
    count(h.id) filter (where h.latitude is null or h.longitude is null),
    count(h.id) filter (where h.house_id_11 is null or h.house_id_11 !~ '^[0-9]{11}$')
  into v_total,v_assigned,v_pinned,v_field,v_review,v_out_tambon,v_out_community,v_missing,v_missing_id11
  from public.houses h
  join public.communities c on c.active=true and btrim(c.name)=btrim(h.community)
  where v_profile.role='admin'
     or (v_profile.role='staff' and c.moo=v_own_moo)
     or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')));
  if v_total>0 then v_pct := round((v_field::numeric*100.0)/v_total,1); end if;
  return jsonb_build_object(
    'role',v_profile.role,'community',v_profile.community,'moo',v_own_moo,
    'total_houses',v_total,'assigned_houses',v_assigned,'pinned_houses',v_pinned,
    'field_confirmed',v_field,'review_houses',v_review,
    'outside_tambon',v_out_tambon,'outside_community',v_out_community,
    'outside_any',v_out_tambon+v_out_community,
    'missing_coordinates',v_missing,'missing_house_id_11',v_missing_id11,
    'field_progress_pct',v_pct
  );
end;
$$;
revoke all on function public.spatial_scope_dashboard() from public, anon;
grant execute on function public.spatial_scope_dashboard() to authenticated;

create or replace function public.spatial_community_cards()
returns table(community text, moo text, houses bigint, assigned_houses bigint, pinned_houses bigint, field_confirmed bigint, review_houses bigint, outside_tambon bigint, outside_community bigint, missing_coordinates bigint, volunteers bigint, access_mode text, is_assigned boolean)
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
    select c.moo into v_own_moo from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,'')) limit 1;
  end if;
  return query
  select c.name::text,c.moo::text,
    count(h.id)::bigint,
    count(h.id) filter (where h.volunteer_pid is not null)::bigint,
    count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint,
    count(h.id) filter (where h.coordinate_status like 'resolved_%')::bigint,
    count(h.id) filter (where h.review_required=true)::bigint,
    count(h.id) filter (where h.inside_tambon=false)::bigint,
    count(h.id) filter (where h.inside_community=false and h.inside_tambon is distinct from false)::bigint,
    count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint,
    count(distinct h.volunteer_pid) filter (where h.volunteer_pid is not null)::bigint,
    case when v_profile.role='admin' then 'manage'
         when v_profile.role='staff' and btrim(c.name)=btrim(coalesce(v_profile.community,'')) then 'manage'
         else 'view' end::text,
    (btrim(c.name)=btrim(coalesce(v_profile.community,'')))::boolean
  from public.communities c
  left join public.houses h on btrim(h.community)=btrim(c.name)
  where c.active=true and (
    v_profile.role='admin'
    or (v_profile.role='staff' and c.moo=v_own_moo)
    or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')))
  )
  group by c.name,c.moo
  order by nullif(c.moo,'')::int nulls last,c.name;
end;
$$;
revoke all on function public.spatial_community_cards() from public, anon;
grant execute on function public.spatial_community_cards() to authenticated;
