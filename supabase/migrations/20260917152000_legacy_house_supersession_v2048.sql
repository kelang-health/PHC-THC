-- OSM-PHC Cloud v2.0.48 โ€” Legacy House Supersession
-- Keep legacy rows for audit/history, but retire only high-confidence synthetic duplicates.
-- JHCIS remains read-only. No health/person history is deleted.
begin;

alter table public.houses
  add column if not exists superseded_by uuid references public.houses(id) on delete restrict,
  add column if not exists superseded_at timestamptz,
  add column if not exists superseded_reason text not null default '';

alter table public.houses drop constraint if exists houses_superseded_not_self_v2048;

alter table public.houses add constraint houses_superseded_not_self_v2048
  check (superseded_by is null or superseded_by <> id);

create index if not exists houses_active_scope_v2048
  on public.houses(community,volunteer_pid,source_pcucode,hcode)
  where superseded_by is null;

create index if not exists houses_superseded_by_v2048
  on public.houses(superseded_by) where superseded_by is not null;

create table if not exists public.house_reconcile_audit_v2048(
  id bigint generated always as identity primary key,
  legacy_house_id uuid not null unique references public.houses(id) on delete restrict,
  canonical_house_id uuid not null references public.houses(id) on delete restrict,
  legacy_hcode text not null,
  canonical_hcode text not null,
  house_no text not null default '',
  moo text not null default '',
  community text not null default '',
  volunteer_pid bigint,
  reason text not null,
  created_at timestamptz not null default now()
);

alter table public.house_reconcile_audit_v2048 enable row level security;

revoke all on public.house_reconcile_audit_v2048 from public,anon,authenticated;

grant all on public.house_reconcile_audit_v2048 to service_role;

create or replace function private.house_no_key_v2048(p_value text)
returns text language sql immutable set search_path=''
as $$ select regexp_replace(lower(btrim(coalesce(p_value,''))),'[[:space:]]+','','g') $$;

revoke all on function private.house_no_key_v2048(text) from public,anon,authenticated;

create or replace function private.moo_key_v2048(p_value text)
returns text language sql immutable set search_path=''
as $$
  select case when btrim(coalesce(p_value,'')) ~ '^[0-9]+$'
    then (btrim(p_value)::integer)::text else lower(btrim(coalesce(p_value,''))) end
$$;

revoke all on function private.moo_key_v2048(text) from public,anon,authenticated;

create or replace function public.service_reconcile_jhcis_houses_v2048(p_rows jsonb)
returns jsonb
language plpgsql security definer
set search_path=public,private,extensions
as $$
declare
  v_base jsonb;
  v_item jsonb;
  v_pcucode text;
  v_hcode text;
  v_id11 text;
  v_canonical public.houses%rowtype;
  v_legacy_id uuid;
  v_area_candidates integer;
  v_safe_candidates integer;
  v_superseded integer:=0;
  v_review integer:=0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'ROWS_ARRAY_REQUIRED'; end if;

  v_base:=public.service_reconcile_jhcis_houses_v2045(p_rows);

  for v_item in select value from jsonb_array_elements(p_rows)
  loop
    v_pcucode:=btrim(coalesce(v_item->>'source_pcucode',''));
    v_hcode:=btrim(coalesce(v_item->>'hcode',''));
    v_id11:=nullif(btrim(coalesce(v_item->>'house_id_11','')),'');
    if v_pcucode='' or v_hcode='' or v_id11 is null or v_id11 !~ '^[0-9]{11}$' then continue; end if;

    select * into v_canonical from public.houses
    where source_pcucode=v_pcucode and hcode=v_hcode and superseded_by is null
    limit 1;
    if not found or v_canonical.house_id_11 is distinct from v_id11 then continue; end if;

    select count(*)::integer,
           min(l.id) filter(where l.volunteer_pid is not distinct from v_canonical.volunteer_pid)
      into v_area_candidates,v_legacy_id
    from public.houses l
    where l.id<>v_canonical.id
      and l.superseded_by is null
      and l.entry_source='import'
      and l.house_id_11 is null
      and l.hcode ~* '^H[0-9]+$'
      and private.house_no_key_v2048(l.house_no)=private.house_no_key_v2048(v_canonical.house_no)
      and private.moo_key_v2048(l.moo)=private.moo_key_v2048(v_canonical.moo)
      and private.community_key(l.community)=private.community_key(v_canonical.community);

    select count(*)::integer into v_safe_candidates
    from public.houses l
    where l.id<>v_canonical.id
      and l.superseded_by is null
      and l.entry_source='import'
      and l.house_id_11 is null
      and l.hcode ~* '^H[0-9]+$'
      and l.volunteer_pid is not distinct from v_canonical.volunteer_pid
      and private.house_no_key_v2048(l.house_no)=private.house_no_key_v2048(v_canonical.house_no)
      and private.moo_key_v2048(l.moo)=private.moo_key_v2048(v_canonical.moo)
      and private.community_key(l.community)=private.community_key(v_canonical.community);

    if v_area_candidates=1 and v_safe_candidates=1 and v_legacy_id is not null then
      insert into public.house_reconcile_audit_v2048(
        legacy_house_id,canonical_house_id,legacy_hcode,canonical_hcode,house_no,moo,community,volunteer_pid,reason
      )
      select l.id,v_canonical.id,l.hcode,v_canonical.hcode,l.house_no,l.moo,l.community,l.volunteer_pid,
             'legacy_synthetic_same_area_owner_jhcis_v2048'
      from public.houses l where l.id=v_legacy_id
      on conflict(legacy_house_id) do nothing;

      update public.houses
         set superseded_by=v_canonical.id,
             superseded_at=now(),
             superseded_reason='legacy_synthetic_same_area_owner_jhcis_v2048',
             review_required=true,
             review_reason=trim(both '; ' from coalesce(review_reason,'') || '; เนเธ—เธเธ—เธตเนเธ”เนเธงเธขเธ—เธฐเน€เธเธตเธขเธเธเนเธฒเธ JHCIS canonical'),
             updated_at=now()
       where id=v_legacy_id and superseded_by is null;
      if found then v_superseded:=v_superseded+1; end if;
    elsif v_area_candidates>0 then
      v_review:=v_review+1;
    end if;
  end loop;

  return coalesce(v_base,'{}'::jsonb)||jsonb_build_object(
    'legacy_superseded',v_superseded,
    'legacy_review',v_review,
    'legacy_policy','synthetic H + blank ID11 + unique exact area + same volunteer_pid only',
    'jhcis_write_back',false
  );
end;
$$;

revoke all on function public.service_reconcile_jhcis_houses_v2048(jsonb) from public,anon,authenticated;

grant execute on function public.service_reconcile_jhcis_houses_v2048(jsonb) to service_role;

-- Normal clients never see retired rows. Service role still retains them for audit/reconciliation.
drop policy if exists houses_select on public.houses;

create policy houses_select on public.houses for select to authenticated
using (
  superseded_by is null and (
    private.current_role()='admin'
    or (private.current_role()='staff' and coalesce(btrim(private.current_moo()),'')<>'' and btrim(moo)=btrim(private.current_moo()))
    or (private.current_role()='user' and volunteer_pid=private.current_volunteer_pid())
  )
);

create or replace function private.health_can_access_house(p_pcucode text,p_hcode text)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1 from public.houses h
    where h.source_pcucode=p_pcucode and h.hcode=p_hcode and h.superseded_by is null
      and (
        private.current_role()='admin'
        or (private.current_role()='staff' and private.community_key(private.current_community())<>'' and private.community_key(h.community)=private.community_key(private.current_community()))
        or (private.current_role()='user' and h.volunteer_pid=private.current_volunteer_pid())
      )
  )
$$;

revoke all on function private.health_can_access_house(text,text) from public,anon,authenticated;

grant execute on function private.health_can_access_house(text,text) to authenticated;

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
  where h.superseded_by is null
    and (v_profile.role='admin'
     or (v_profile.role='staff' and c.moo=v_own_moo)
     or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,''))));
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
  left join public.houses h on btrim(h.community)=btrim(c.name) and h.superseded_by is null
  where c.active=true and (
    v_profile.role='admin'
    or (v_profile.role='staff' and c.moo=v_own_moo)
    or (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')))
  )
  group by c.name,c.moo
  order by nullif(c.moo,'')::int nulls last,c.name;
end;
$$;

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
  where h.superseded_by is null
    and (
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

create or replace function public.spatial_house_exact_search_v1854(p_house_no text)
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  volunteer_name text,
  spatial_status text,
  can_edit boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  )
  select
    h.id,
    h.house_no,
    h.hcode,
    h.moo,
    h.community,
    h.latitude,
    h.longitude,
    h.coordinate_status,
    h.review_required,
    h.inside_tambon,
    h.inside_community,
    coalesce(v.display_name, '') as volunteer_name,
    case
      when h.latitude is null or h.longitude is null then 'missing'
      when h.inside_tambon = false then 'outside_tambon'
      when h.inside_community = false then 'outside_community'
      when h.review_required = true then 'review'
      when h.coordinate_status like 'resolved_%' then 'field_confirmed'
      else 'pinned'
    end as spatial_status,
    case
      when (select role from ctx) = 'admin' then true
      when (select role from ctx) = 'staff'
        then private.community_key(h.community) = private.community_key((select own_community from ctx))
      when (select role from ctx) = 'user'
        then h.volunteer_pid = (select volunteer_pid from ctx)
      else false
    end as can_edit
  from public.houses h
  left join public.volunteers v
    on v.source_pcucode = h.source_pcucode and v.source_pid = h.volunteer_pid
  where h.superseded_by is null
    and coalesce(btrim(p_house_no), '') <> ''
    and lower(btrim(h.house_no)) = lower(btrim(p_house_no))
    and (
      (select role from ctx) = 'admin'
      or (select role from ctx) = 'user'
      or (
        (select role from ctx) = 'staff'
        and btrim(h.moo) = btrim((select own_moo from ctx))
      )
    )
  order by
    (private.community_key(h.community) = private.community_key((select own_community from ctx))) desc,
    h.moo,
    h.community,
    h.house_no
  limit 25
$$;

create or replace function public.spatial_community_houses_v1854(p_community text)
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_status text,
  review_required boolean,
  inside_tambon boolean,
  inside_community boolean,
  volunteer_pid bigint,
  volunteer_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  with ctx as (
    select
      private.current_role() as role,
      private.current_community() as own_community,
      private.current_volunteer_pid() as volunteer_pid,
      private.current_moo() as own_moo
  )
  select
    h.id, h.house_no, h.hcode, h.moo, h.community,
    h.latitude, h.longitude, h.coordinate_status, h.review_required,
    h.inside_tambon, h.inside_community, h.volunteer_pid,
    coalesce(v.display_name, '') as volunteer_name
  from public.houses h
  left join public.volunteers v
    on v.source_pcucode = h.source_pcucode and v.source_pid = h.volunteer_pid
  where h.superseded_by is null
    and private.community_key(h.community) = private.community_key(p_community)
    and (
      (select role from ctx) = 'admin'
      or (
        (select role from ctx) = 'staff'
        and btrim(h.moo) = btrim((select own_moo from ctx))
      )
      or (
        (select role from ctx) = 'user'
        and h.volunteer_pid = (select volunteer_pid from ctx)
      )
    )
  order by h.house_no
$$;

create or replace function public.user_household_cards_v1855()
returns table (
  id uuid,
  house_no text,
  hcode text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  spatial_status text,
  member_count bigint,
  older_count bigint,
  ncd_due_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_pid bigint;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  v_role := private.current_role();
  v_pid := private.current_volunteer_pid();
  if v_role <> 'user' or v_pid is null then
    raise exception 'USER_SCOPE_REQUIRED';
  end if;

  return query
  select
    h.id,
    h.house_no,
    h.hcode,
    h.moo,
    h.community,
    h.latitude,
    h.longitude,
    case
      when h.latitude is null or h.longitude is null then 'missing'
      when h.inside_tambon = false then 'outside_tambon'
      when h.inside_community = false then 'outside_community'
      when h.review_required = true then 'review'
      when h.coordinate_status like 'resolved_%' then 'field_confirmed'
      else 'pinned'
    end::text as spatial_status,
    coalesce(x.member_count, 0)::bigint,
    coalesce(x.older_count, 0)::bigint,
    coalesce(x.ncd_due_count, 0)::bigint
  from public.houses h
  left join lateral (
    select
      count(*)::bigint as member_count,
      count(*) filter (where w.age_years >= 60)::bigint as older_count,
      count(*) filter (
        where w.ncd_target and not coalesce(w.screened_current_fy, false)
      )::bigint as ncd_due_count
    from public.health_person_worklist_active_v1841 w
    where w.source_pcucode = h.source_pcucode
      and w.hcode = h.hcode
  ) x on true
  where h.superseded_by is null and h.volunteer_pid = v_pid
  order by
    nullif(regexp_replace(coalesce(h.house_no,''), '[^0-9].*$', ''), '')::integer nulls last,
    h.house_no;
end;
$$;

create or replace function public.my_household_cards_v1860()
returns table (
  id uuid,
  hcode text,
  house_no text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_source text,
  coordinate_status text,
  record_status text,
  review_required boolean,
  review_reason text,
  volunteer_pid bigint,
  house_id_11 text,
  entry_source text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_pid bigint;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  v_role := private.current_role();
  v_pid := private.current_volunteer_pid();
  if v_role not in ('user','staff') or v_pid is null then
    raise exception 'VHV_SCOPE_REQUIRED';
  end if;

  return query
  select h.id,h.hcode,h.house_no,h.moo,h.community,h.latitude,h.longitude,
         h.coordinate_source,h.coordinate_status,h.record_status,h.review_required,
         h.review_reason,h.volunteer_pid,h.house_id_11,h.entry_source
  from public.houses h
  where h.superseded_by is null and h.volunteer_pid=v_pid
  order by
    nullif(regexp_replace(coalesce(h.house_no,''), '[^0-9].*$', ''), '')::integer nulls last,
    h.house_no;
end;
$$;

create or replace function public.care_dashboard_v1861(p_scope text default 'self')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_result jsonb;
  v_hdc jsonb:=null;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select p.role,p.community,p.volunteer_pid
    into v_role,v_community,v_pid
  from public.profiles p
  where p.user_id=v_uid and p.active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';
  elsif v_role='user' then v_scope:='self';
  elsif v_role='staff' and v_scope not in ('self','community') then v_scope:='self';
  end if;

  if v_role='admin' then
    select s.value into v_hdc
    from public.app_settings s
    where s.key='care_reference_hdc'
    limit 1;
  end if;

  with scoped_houses as (
    select h.*
    from public.houses h
    where h.superseded_by is null
      and (v_role='admin'
      or (v_scope='self' and v_pid is not null and h.volunteer_pid=v_pid)
      or (v_role='staff' and v_scope='community'
          and private.community_key(h.community)=private.community_key(v_community)))
  ), scoped_people as (
    select w.*,p.is_student,p.is_disabled,p.service_population_eligible,
           p.adl_group_code,p.adl_assessed_on
    from public.health_person_worklist_active_v1847 w
    join public.health_persons p
      on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
    join scoped_houses h
      on h.source_pcucode=w.house_pcucode and h.hcode=w.hcode
  ), latest_2q as (
    select distinct on (s.source_pcucode,s.source_pid)
           s.source_pcucode,s.source_pid,s.mental_2q_status,s.mental_2q_result
    from public.health_ncd_screenings s
    join scoped_people p
      on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
     and p.service_population_eligible=true
    where coalesce(s.record_mode,'production')='production'
    order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
  ), hstat as (
    select count(*)::bigint houses,
           count(*) filter(where latitude is not null and longitude is not null)::bigint mapped_houses,
           count(*) filter(where latitude is null or longitude is null)::bigint missing_coordinates,
           count(*) filter(where review_required=true)::bigint review_houses
    from scoped_houses
  ), pstat as (
    select count(*)::bigint household_people,
           count(*) filter(where service_population_eligible)::bigint service_people,
           count(*) filter(where service_population_eligible and ncd_target)::bigint ncd_targets,
           count(*) filter(where service_population_eligible and ncd_target and coalesce(screened_current_fy,false))::bigint ncd_done,
           count(*) filter(where service_population_eligible and ncd_target and not coalesce(screened_current_fy,false))::bigint ncd_due,
           count(*) filter(where service_population_eligible and known_ncd)::bigint known_ncd,
           count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข')::bigint early_child,
           count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ')::bigint school_age,
           count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ')::bigint youth,
           count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ')::bigint working_age,
           count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ')::bigint older_people,
           count(*) filter(where service_population_eligible and is_student)::bigint students,
           count(*) filter(where service_population_eligible and is_disabled)::bigint disabled_people,
           count(*) filter(where service_population_eligible and adl_group_code<>'')::bigint adl_assessed_people,
           count(*) filter(where service_population_eligible and adl_group_code='1B1280')::bigint social_people,
           count(*) filter(where service_population_eligible and adl_group_code='1B1281')::bigint homebound_people,
           count(*) filter(where service_population_eligible and adl_group_code='1B1282')::bigint bedridden_people,
           count(*) filter(where service_population_eligible and latest_severity in ('alert','urgent'))::bigint urgent_attention
    from scoped_people
  ), qstat as (
    select count(*) filter(where mental_2q_status='assessed')::bigint mental_2q_assessed,
           count(*) filter(where mental_2q_status='not_assessed')::bigint mental_2q_not_assessed,
           count(*) filter(where mental_2q_status='incomplete')::bigint mental_2q_incomplete,
           count(*) filter(where mental_2q_status='assessed' and mental_2q_result=true)::bigint mental_2q_positive
    from latest_2q
  )
  select jsonb_build_object(
    'version','1.8.61',
    'role',v_role,
    'scope',v_scope,
    'scope_label',case
      when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเนเธ•เธฒเธกเธชเธดเธ—เธเธดเนเธเธนเนเธ”เธนเนเธฅเธฃเธฐเธเธ'
      when v_role='staff' and v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ'
    end,
    'community',coalesce(v_community,''),
    'has_personal_scope',(v_pid is not null),
    'houses',coalesce(hstat.houses,0),
    'mapped_houses',coalesce(hstat.mapped_houses,0),
    'missing_coordinates',coalesce(hstat.missing_coordinates,0),
    'review_houses',coalesce(hstat.review_houses,0),
    'household_people',coalesce(pstat.household_people,0),
    'people',coalesce(pstat.service_people,0),
    'service_people',coalesce(pstat.service_people,0),
    'ncd_targets',coalesce(pstat.ncd_targets,0),
    'ncd_done',coalesce(pstat.ncd_done,0),
    'ncd_due',coalesce(pstat.ncd_due,0),
    'known_ncd',coalesce(pstat.known_ncd,0),
    'early_child',coalesce(pstat.early_child,0),
    'school_age',coalesce(pstat.school_age,0),
    'youth',coalesce(pstat.youth,0),
    'working_age',coalesce(pstat.working_age,0),
    'older_people',coalesce(pstat.older_people,0),
    'students',coalesce(pstat.students,0),
    'disabled_people',coalesce(pstat.disabled_people,0),
    'adl_assessed_people',coalesce(pstat.adl_assessed_people,0),
    'social_people',coalesce(pstat.social_people,0),
    'homebound_people',coalesce(pstat.homebound_people,0),
    'bedridden_people',coalesce(pstat.bedridden_people,0),
    'urgent_attention',coalesce(pstat.urgent_attention,0),
    'mental_2q_assessed',coalesce(qstat.mental_2q_assessed,0),
    'mental_2q_not_assessed',coalesce(qstat.mental_2q_not_assessed,0),
    'mental_2q_incomplete',coalesce(qstat.mental_2q_incomplete,0),
    'mental_2q_positive',coalesce(qstat.mental_2q_positive,0),
    'metric_sources',jsonb_build_object(
      'person_level','JHCIS read-only / J-Report operational definition',
      'service_population','typelive 1,3 + nation 99 + alive + non-00 village',
      'ncd','J-Report operational worklist; official HDC DM/HT denominators are separate',
      'adl','latest JHCIS f43specialpp 1B1280/1B1281/1B1282',
      'official_comparator','MoPH Open Data via hdc-app; aggregate only'
    ),
    'hdc_reference',case when v_role='admin' then v_hdc else null end
  ) into v_result
  from hstat cross join pstat cross join qstat;

  return v_result;
end;
$$;

create or replace function public.assignment_summary_v2033(
  p_scope text default 'self',
  p_owner_pid bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));v_owner bigint:=p_owner_pid;v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid
  from public.profiles where user_id=v_uid and active=true limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';v_owner:=null;
  elsif v_role='user' then v_scope:='self';v_owner:=v_pid;
  elsif v_role='staff' then
    if v_scope='volunteer' then
      if v_owner is null or not exists(
        select 1 from public.profiles p join public.volunteers v on v.source_pid=p.volunteer_pid and v.active=true
        where p.active=true and p.role='user' and p.volunteer_pid=v_owner
          and private.community_key(p.community)=private.community_key(v_community)
      ) then raise exception 'VOLUNTEER_SCOPE_NOT_ALLOWED'; end if;
    elsif v_scope not in ('self','community') then v_scope:='self';v_owner:=v_pid;
    else v_owner:=case when v_scope='self' then v_pid else null end;
    end if;
  else raise exception 'ROLE_NOT_ALLOWED';
  end if;

  with active_vhv as materialized(
    select distinct v.source_pid from public.volunteers v where v.active=true
  ), active_ops as materialized(
    select distinct v.source_pid
    from public.volunteers v join public.profiles p on p.volunteer_pid=v.source_pid
    where v.active=true and p.active=true and p.role in ('user','staff')
  ), scoped_houses as materialized(
    select h.*,
      case when nullif(private.community_key(h.community),'') is null then 'unresolved'
           when h.volunteer_pid is null or av.source_pid is null or ao.source_pid is null then 'staff_fallback'
           else 'assigned' end assignment_status,
      case when nullif(private.community_key(h.community),'') is null then 'missing_community'
           when h.volunteer_pid is null then 'no_volunteer'
           when av.source_pid is null then 'inactive_volunteer'
           when ao.source_pid is null then 'no_active_user'
           else 'assigned' end assignment_reason
    from public.houses h
    left join active_vhv av on av.source_pid=h.volunteer_pid
    left join active_ops ao on ao.source_pid=h.volunteer_pid
    where h.superseded_by is null
      and (v_role='admin'
       or (v_scope in ('self','volunteer') and v_owner is not null and h.volunteer_pid=v_owner)
       or (v_role='staff' and v_scope='community' and private.community_key(h.community)=private.community_key(v_community)))
  ), people as materialized(
    select p.source_pcucode,p.source_pid,h.assignment_status,h.assignment_reason
    from public.health_persons p join scoped_houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
    where p.active=true and coalesce(p.service_population_eligible,false)=true
  ), hstat as(
    select count(*)::bigint houses,count(*) filter(where assignment_status='assigned')::bigint assigned_houses,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_houses,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_houses,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_houses,
      count(*) filter(where assignment_reason='inactive_volunteer')::bigint inactive_volunteer_houses,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_houses from scoped_houses
  ), pstat as(
    select count(*)::bigint people,count(*) filter(where assignment_status='assigned')::bigint assigned_people,
      count(*) filter(where assignment_status='staff_fallback')::bigint fallback_people,
      count(*) filter(where assignment_status='unresolved')::bigint unresolved_people,
      count(*) filter(where assignment_reason='no_volunteer')::bigint no_volunteer_people,
      count(*) filter(where assignment_reason='inactive_volunteer')::bigint inactive_volunteer_people,
      count(*) filter(where assignment_reason='no_active_user')::bigint no_active_user_people from people
  )
  select jsonb_build_object(
    'version','2.0.33','role',v_role,'scope',v_scope,'community',coalesce(v_community,''),'owner_pid',v_owner,
    'houses',h.houses,'assigned_houses',h.assigned_houses,'fallback_houses',h.fallback_houses,'unresolved_houses',h.unresolved_houses,
    'no_volunteer_houses',h.no_volunteer_houses,'inactive_volunteer_houses',h.inactive_volunteer_houses,'no_active_user_houses',h.no_active_user_houses,
    'people',p.people,'assigned_people',p.assigned_people,'fallback_people',p.fallback_people,'unresolved_people',p.unresolved_people,
    'no_volunteer_people',p.no_volunteer_people,'inactive_volunteer_people',p.inactive_volunteer_people,'no_active_user_people',p.no_active_user_people,
    'fallback_policy','staff_community','auto_reassign_volunteer_pid',false,
    'scope_label',case when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเน'
      when v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      when v_scope='volunteer' then 'เธเธฒเธเธเธญเธ เธญเธชเธก. เธ—เธตเนเน€เธฅเธทเธญเธ'
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' end
  ) into v_result from hstat h cross join pstat p;
  return v_result;
end;
$$;

create or replace function private.refresh_report_snapshots_v2031(p_reason text default 'manual')
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_generation uuid:=gen_random_uuid();
  v_started timestamptz:=clock_timestamp();
  v_rows bigint:=0;
  v_added bigint:=0;
  v_reason text:=left(coalesce(nullif(btrim(p_reason),''),'manual'),80);
begin
  if not pg_try_advisory_xact_lock(hashtext('osm_phc_report_snapshot_v2031')) then
    return jsonb_build_object('ok',false,'status','busy','version','2.0.31');
  end if;

  insert into public.report_snapshot_runs_v2031(id,status,reason,started_at)
  values(v_generation,'running',v_reason,v_started);
  update public.report_snapshot_state_v2031
  set status='running',last_reason=v_reason,last_error=''
  where singleton=true;

  begin
    -- Care dashboard: scan each base relation once and fan rows into all/community/volunteer scopes.
    with house_scoped as materialized (
      select s.scope_type,s.scope_key,h.latitude,h.longitude,h.review_required
      from public.houses h
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(h.community),'')),
        ('volunteer'::text,h.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where h.superseded_by is null and s.scope_key is not null
    ), hagg as (
      select scope_type,scope_key,count(*)::bigint houses,
        count(*) filter(where latitude is not null and longitude is not null)::bigint mapped_houses,
        count(*) filter(where latitude is null or longitude is null)::bigint missing_coordinates,
        count(*) filter(where review_required=true)::bigint review_houses
      from house_scoped group by scope_type,scope_key
    ), person_base as materialized (
      select w.source_pcucode,w.source_pid,w.life_stage,w.ncd_target,w.screened_current_fy,w.known_ncd,w.latest_severity,
        p.is_student,p.is_disabled,p.service_population_eligible,p.adl_group_code,
        h.community,h.volunteer_pid
      from public.health_person_worklist_active_v1847 w
      join public.health_persons p on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
      join public.houses h on h.source_pcucode=w.house_pcucode and h.hcode=w.hcode and h.superseded_by is null
    ), person_scoped as materialized (
      select s.scope_type,s.scope_key,p.*
      from person_base p
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(p.community),'')),
        ('volunteer'::text,p.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), pagg as (
      select scope_type,scope_key,count(*)::bigint household_people,
        count(*) filter(where service_population_eligible)::bigint service_people,
        count(*) filter(where service_population_eligible and ncd_target)::bigint ncd_targets,
        count(*) filter(where service_population_eligible and ncd_target and coalesce(screened_current_fy,false))::bigint ncd_done,
        count(*) filter(where service_population_eligible and ncd_target and not coalesce(screened_current_fy,false))::bigint ncd_due,
        count(*) filter(where service_population_eligible and known_ncd)::bigint known_ncd,
        count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข')::bigint early_child,
        count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ')::bigint school_age,
        count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ')::bigint youth,
        count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ')::bigint working_age,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ')::bigint older_people,
        count(*) filter(where service_population_eligible and is_student)::bigint students,
        count(*) filter(where service_population_eligible and is_disabled)::bigint disabled_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code<>'')::bigint adl_assessed_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1280')::bigint social_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1281')::bigint homebound_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1282')::bigint bedridden_people,
        count(*) filter(where service_population_eligible and latest_severity in ('alert','urgent'))::bigint urgent_attention
      from person_scoped group by scope_type,scope_key
    ), latest_2q as materialized (
      select distinct on (s.source_pcucode,s.source_pid)
        s.source_pcucode,s.source_pid,s.mental_2q_status,s.mental_2q_result
      from public.health_ncd_screenings s
      join person_base p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
      where p.service_population_eligible=true and coalesce(s.record_mode,'production')='production'
      order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
    ), qagg as (
      select ps.scope_type,ps.scope_key,
        count(*) filter(where q.mental_2q_status='assessed')::bigint mental_2q_assessed,
        count(*) filter(where q.mental_2q_status='not_assessed')::bigint mental_2q_not_assessed,
        count(*) filter(where q.mental_2q_status='incomplete')::bigint mental_2q_incomplete,
        count(*) filter(where q.mental_2q_status='assessed' and q.mental_2q_result=true)::bigint mental_2q_positive
      from person_scoped ps join latest_2q q on q.source_pcucode=ps.source_pcucode and q.source_pid=ps.source_pid
      group by ps.scope_type,ps.scope_key
    ), scopes as (
      select scope_type,scope_key from hagg union select scope_type,scope_key from pagg union select scope_type,scope_key from qagg
    )
    insert into public.report_snapshot_cache_v2031(generation,report_key,scope_type,scope_key,payload,generated_at)
    select v_generation,'care',s.scope_type,s.scope_key,jsonb_build_object(
      'houses',coalesce(h.houses,0),'mapped_houses',coalesce(h.mapped_houses,0),
      'missing_coordinates',coalesce(h.missing_coordinates,0),'review_houses',coalesce(h.review_houses,0),
      'household_people',coalesce(p.household_people,0),'people',coalesce(p.service_people,0),'service_people',coalesce(p.service_people,0),
      'ncd_targets',coalesce(p.ncd_targets,0),'ncd_done',coalesce(p.ncd_done,0),'ncd_due',coalesce(p.ncd_due,0),'known_ncd',coalesce(p.known_ncd,0),
      'early_child',coalesce(p.early_child,0),'school_age',coalesce(p.school_age,0),'youth',coalesce(p.youth,0),
      'working_age',coalesce(p.working_age,0),'older_people',coalesce(p.older_people,0),'students',coalesce(p.students,0),
      'disabled_people',coalesce(p.disabled_people,0),'adl_assessed_people',coalesce(p.adl_assessed_people,0),
      'social_people',coalesce(p.social_people,0),'homebound_people',coalesce(p.homebound_people,0),'bedridden_people',coalesce(p.bedridden_people,0),
      'urgent_attention',coalesce(p.urgent_attention,0),'mental_2q_assessed',coalesce(q.mental_2q_assessed,0),
      'mental_2q_not_assessed',coalesce(q.mental_2q_not_assessed,0),'mental_2q_incomplete',coalesce(q.mental_2q_incomplete,0),
      'mental_2q_positive',coalesce(q.mental_2q_positive,0),
      'metric_sources',jsonb_build_object(
        'person_level','JHCIS read-only / J-Report operational definition',
        'service_population','typelive 1,3 + nation 99 + alive + non-00 village',
        'ncd','J-Report operational worklist; official HDC DM/HT denominators are separate',
        'adl','latest JHCIS f43specialpp 1B1280/1B1281/1B1282',
        'official_comparator','MoPH Open Data via hdc-app; aggregate only'
      )
    ),clock_timestamp()
    from scopes s
    left join hagg h using(scope_type,scope_key)
    left join pagg p using(scope_type,scope_key)
    left join qagg q using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;

    -- Field-work dashboard: materialize once, then aggregate the same rows for each permitted scope.
    with work_scoped as materialized (
      select s.scope_type,s.scope_key,w.*
      from public.field_work_items_v200 w
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(w.community),'')),
        ('volunteer'::text,w.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), base_summary as (
      select scope_type,scope_key,count(*)::bigint total,
        count(*) filter(where status='complete')::bigint complete,
        count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due,
        count(*) filter(where priority='red')::bigint red,
        count(*) filter(where priority='orange')::bigint orange
      from work_scoped group by scope_type,scope_key
    ), task_rows as (
      select scope_type,scope_key,task_type,max(task_label) task_label,count(*)::bigint target,
        count(*) filter(where status='complete')::bigint complete,
        count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due
      from work_scoped group by scope_type,scope_key,task_type
    ), task_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'task_type',task_type,'task_label',task_label,'target',target,'complete',complete,'partial',partial,'due',due,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by task_type) value from task_rows group by scope_type,scope_key
    ), person_keys as (
      select distinct scope_type,scope_key,source_pcucode,source_pid from work_scoped
    ), follow_stat as (
      select p.scope_type,p.scope_key,
        count(*) filter(where f.status in ('open','in_progress'))::bigint open_count,
        count(*) filter(where f.status='done')::bigint done_count,
        count(*) filter(where f.status in ('open','in_progress') and f.priority='red')::bigint red_count,
        count(*) filter(where f.status in ('open','in_progress') and f.priority='orange')::bigint orange_count
      from person_keys p join public.screening_followups f on f.source_pcucode=p.source_pcucode and f.source_pid=p.source_pid
      group by p.scope_type,p.scope_key
    ), volunteer_rows as (
      select s.scope_type,s.scope_key,s.volunteer_pid,max(v.display_name) display_name,max(s.community) community,
        count(*)::bigint target,count(*) filter(where s.status='complete')::bigint complete,
        count(*) filter(where s.status='partial')::bigint partial,count(*) filter(where s.status='due')::bigint due
      from work_scoped s left join public.volunteers v on v.source_pid=s.volunteer_pid
      where s.volunteer_pid is not null group by s.scope_type,s.scope_key,s.volunteer_pid
    ), volunteer_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'volunteer_pid',volunteer_pid,'display_name',coalesce(display_name,'เนเธกเนเธฃเธฐเธเธธ'),'community',community,
        'target',target,'complete',complete,'partial',partial,'due',due,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by (case when target>0 then complete*100.0/target else 0 end),display_name) value
      from volunteer_rows group by scope_type,scope_key
    ), community_rows as (
      select scope_type,scope_key,community,count(*)::bigint target,
        count(*) filter(where status='complete')::bigint complete,count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due,count(distinct volunteer_pid) filter(where volunteer_pid is not null)::bigint volunteers
      from work_scoped group by scope_type,scope_key,community
    ), community_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'community',community,'target',target,'complete',complete,'partial',partial,'due',due,'volunteers',volunteers,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by (case when target>0 then complete*100.0/target else 0 end),community) value
      from community_rows group by scope_type,scope_key
    )
    insert into public.report_snapshot_cache_v2031(generation,report_key,scope_type,scope_key,payload,generated_at)
    select v_generation,'field',b.scope_type,b.scope_key,jsonb_build_object(
      'period_start',private.field_period_start_v200(),'period_mode',private.field_period_mode_v200(),
      'target_tasks',coalesce(b.total,0),'complete_tasks',coalesce(b.complete,0),'partial_tasks',coalesce(b.partial,0),'due_tasks',coalesce(b.due,0),
      'coverage_percent',case when coalesce(b.total,0)>0 then round(b.complete*100.0/b.total,1) else 0 end,
      'red_tasks',coalesce(b.red,0),'orange_tasks',coalesce(b.orange,0),
      'followup_open',coalesce(f.open_count,0),'followup_done',coalesce(f.done_count,0),
      'followup_red',coalesce(f.red_count,0),'followup_orange',coalesce(f.orange_count,0),
      'tasks',coalesce(t.value,'[]'::jsonb),'volunteers',coalesce(v.value,'[]'::jsonb),'communities',coalesce(c.value,'[]'::jsonb),
      'metric_note','เน€เธเธญเธฃเนเน€เธเนเธเธ•เนเธฃเธงเธกเน€เธเนเธ Operational Task Completion; เนเธกเนเนเธเนเนเธ—เธ KPI HDC เธ—เธฒเธเธเธฒเธฃ เนเธฅเธฐเธฃเธฒเธขเธเธฒเธฃเธ•เธดเธ”เธ•เธฒเธกเนเธกเนเธ–เธนเธเธเธณเธกเธฒเธซเธฑเธ Coverage'
    ),clock_timestamp()
    from base_summary b
    left join task_json t using(scope_type,scope_key)
    left join follow_stat f using(scope_type,scope_key)
    left join volunteer_json v using(scope_type,scope_key)
    left join community_json c using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;

    update public.report_snapshot_runs_v2031 set status='success',finished_at=clock_timestamp(),
      duration_ms=round(extract(epoch from (clock_timestamp()-v_started))*1000),cache_rows=v_rows
    where id=v_generation;
    update public.report_snapshot_state_v2031 set current_generation=v_generation,generated_at=clock_timestamp(),
      status='ready',last_reason=v_reason,last_error='' where singleton=true;

    -- Keep four completed generations so readers always have a valid previous generation.
    delete from public.report_snapshot_runs_v2031 r
    where r.status<>'running' and r.id not in (
      select id from public.report_snapshot_runs_v2031 where status='success' order by finished_at desc nulls last limit 4
    ) and coalesce(r.finished_at,r.started_at)<now()-interval '7 days';

    return jsonb_build_object('ok',true,'status','ready','generation',v_generation,'cache_rows',v_rows,
      'duration_ms',round(extract(epoch from (clock_timestamp()-v_started))*1000),'generated_at',clock_timestamp(),'version','2.0.31');
  exception when others then
    update public.report_snapshot_runs_v2031 set status='failed',finished_at=clock_timestamp(),
      duration_ms=round(extract(epoch from (clock_timestamp()-v_started))*1000),error_message=left(sqlerrm,500)
    where id=v_generation;
    update public.report_snapshot_state_v2031 set status=case when current_generation is null then 'failed' else 'ready' end,
      last_reason=v_reason,last_error=left(sqlerrm,500) where singleton=true;
    return jsonb_build_object('ok',false,'status','failed','error',left(sqlerrm,500),'version','2.0.31');
  end;
end;
$$;

create or replace view public.community_report_summary
with (security_invoker=true) as
select h.community,max(h.moo) as moo,count(*)::bigint as houses,
  count(*) filter(where h.volunteer_pid is not null)::bigint as assigned_houses,
  count(*) filter(where h.review_required)::bigint as review_houses,
  count(*) filter(where h.inside_tambon=false)::bigint as outside_tambon,
  count(*) filter(where h.latitude is null or h.longitude is null)::bigint as missing_coordinates,
  count(distinct h.volunteer_pid) filter(where h.volunteer_pid is not null)::bigint as volunteers_with_work
from public.houses h where h.superseded_by is null group by h.community;

grant select on public.community_report_summary to authenticated;

create or replace view public.volunteer_workload
with (security_invoker=true) as
select v.source_pid,v.display_name,v.community,v.moo,v.anchor_status,
  count(h.id)::bigint as house_count,
  count(h.id) filter(where h.review_required)::bigint as review_count,
  count(h.id) filter(where h.community=v.community)::bigint as in_community_count,
  count(h.id) filter(where h.community<>v.community)::bigint as cross_community_count
from public.volunteers v
left join public.houses h on h.volunteer_pid=v.source_pid and h.superseded_by is null
group by v.source_pid,v.display_name,v.community,v.moo,v.anchor_status;

grant select on public.volunteer_workload to authenticated;

insert into public.app_settings(key,value)
values('legacy_house_supersession_v2048',jsonb_build_object(
  'version','2.0.48','mode','soft_supersession','physical_delete',false,
  'auto_match','synthetic H + blank ID11 + unique exact house_no/moo/community + same volunteer_pid',
  'ambiguous_policy','keep visible/review; never auto merge','jhcis_write_back',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
