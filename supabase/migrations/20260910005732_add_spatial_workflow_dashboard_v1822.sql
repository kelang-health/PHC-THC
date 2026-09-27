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
    select c.moo into v_own_moo
    from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,''))
    limit 1;
  end if;

  select
    count(h.id),
    count(h.id) filter (where h.volunteer_pid is not null),
    count(h.id) filter (where h.latitude is not null and h.longitude is not null),
    count(h.id) filter (where h.coordinate_status like 'resolved_%'),
    count(h.id) filter (where h.review_required=true),
    count(h.id) filter (where h.inside_tambon=false),
    count(h.id) filter (where h.inside_community=false),
    count(h.id) filter (where h.latitude is null or h.longitude is null),
    count(h.id) filter (where h.house_id_11 is null or h.house_id_11 !~ '^[0-9]{11}$')
  into v_total,v_assigned,v_pinned,v_field,v_review,v_out_tambon,v_out_community,v_missing,v_missing_id11
  from public.houses h
  join public.communities c on c.active=true and btrim(c.name)=btrim(h.community)
  where
    v_profile.role='admin'
    or (v_profile.role='staff' and c.moo=v_own_moo)
    or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')));

  if v_total>0 then v_pct := round((v_field::numeric*100.0)/v_total,1); end if;

  return jsonb_build_object(
    'role',v_profile.role,
    'community',v_profile.community,
    'moo',v_own_moo,
    'total_houses',v_total,
    'assigned_houses',v_assigned,
    'pinned_houses',v_pinned,
    'field_confirmed',v_field,
    'review_houses',v_review,
    'outside_tambon',v_out_tambon,
    'outside_community',v_out_community,
    'missing_coordinates',v_missing,
    'missing_house_id_11',v_missing_id11,
    'field_progress_pct',v_pct
  );
end;
$$;

revoke all on function public.spatial_scope_dashboard() from public, anon;
grant execute on function public.spatial_scope_dashboard() to authenticated;

create or replace function public.spatial_house_quick_search(p_term text)
returns table(
  id uuid,
  house_no text,
  hcode text,
  house_id_11 text,
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
  can_edit boolean,
  spatial_status text
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_own_moo text;
  v_term text := left(btrim(coalesce(p_term,'')),60);
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(v_term)<1 then return; end if;
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
    h.id,h.house_no,h.hcode,h.house_id_11,h.moo,h.community,h.latitude,h.longitude,
    h.coordinate_status,h.review_required,h.inside_tambon,h.inside_community,h.volunteer_pid,
    coalesce(v.display_name,'เธขเธฑเธเนเธกเนเนเธ”เนเธกเธญเธเธซเธกเธฒเธข')::text,
    case
      when v_profile.role='admin' then true
      when v_profile.role='staff' then btrim(h.community)=btrim(coalesce(v_profile.community,''))
      when v_profile.role='user' then h.volunteer_pid is not null and h.volunteer_pid=v_profile.volunteer_pid
      else false
    end::boolean,
    case
      when h.latitude is null or h.longitude is null then 'missing'
      when h.inside_tambon=false then 'outside_tambon'
      when h.inside_community=false then 'outside_community'
      when h.review_required=true then 'review'
      when h.coordinate_status like 'resolved_%' then 'field_confirmed'
      else 'pinned'
    end::text
  from public.houses h
  join public.communities c on c.active=true and btrim(c.name)=btrim(h.community)
  left join public.volunteers v on v.source_pid=h.volunteer_pid and v.active=true
  where (
      v_profile.role='admin'
      or (v_profile.role='staff' and c.moo=v_own_moo)
      or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')))
    )
    and (
      h.house_no ilike '%'||v_term||'%'
      or coalesce(h.hcode,'') ilike '%'||v_term||'%'
      or coalesce(h.house_id_11,'') ilike '%'||v_term||'%'
    )
  order by
    case when h.house_no=v_term then 0 else 1 end,
    h.moo,
    h.community,
    h.house_no collate "C"
  limit 30;
end;
$$;

revoke all on function public.spatial_house_quick_search(text) from public, anon;
grant execute on function public.spatial_house_quick_search(text) to authenticated;
