-- Phase 2I โ€” House Ownership & JHCIS Reconciliation
-- Cloud field houses are owned by the linked VHV PID. Normal user/staff sessions
-- may mutate only their own houses. Local service sync can link a field house to
-- its later JHCIS hcode by the unique 11-digit house id without stealing ownership.

create or replace function private.protect_house_owner_v2045()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_auth_role text := coalesce(auth.role(),'');
  v_profile public.profiles%rowtype;
begin
  if v_auth_role = 'authenticated' then
    select * into v_profile
    from public.profiles
    where user_id = auth.uid() and active = true
    limit 1;

    if not found then
      raise exception 'PROFILE_NOT_ACTIVE';
    end if;

    if v_profile.role in ('user','staff') then
      if v_profile.volunteer_pid is null
         or old.volunteer_pid is null
         or old.volunteer_pid <> v_profile.volunteer_pid then
        raise exception 'HOUSE_OUT_OF_SCOPE';
      end if;

      if new.volunteer_pid is distinct from old.volunteer_pid
         or new.created_by_volunteer_pid is distinct from old.created_by_volunteer_pid
         or new.created_by_user_id is distinct from old.created_by_user_id
         or new.entry_source is distinct from old.entry_source then
        raise exception 'HOUSE_OWNER_LOCKED';
      end if;
    elsif v_profile.role <> 'admin' then
      raise exception 'HOUSE_OUT_OF_SCOPE';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.protect_house_owner_v2045() from public, anon, authenticated;

drop trigger if exists trg_houses_owner_v2045 on public.houses;

create trigger trg_houses_owner_v2045
before update on public.houses
for each row execute function private.protect_house_owner_v2045();

-- Count quota by the locked owner PID, not by account id. This keeps one quota
-- even when the same VHV later signs in through another linked role/account.
create or replace function public.house_add_quota()
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_used integer := 0;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_profile.role='admin' then
    return jsonb_build_object('limit',null,'used',0,'remaining',null,'role',v_profile.role);
  end if;
  if v_profile.role not in ('staff','user') or v_profile.volunteer_pid is null then
    raise exception 'HOUSE_ADD_NOT_ALLOWED';
  end if;

  select count(*) into v_used
  from public.houses
  where entry_source='field'
    and volunteer_pid=v_profile.volunteer_pid;

  return jsonb_build_object(
    'limit',30,
    'used',v_used,
    'remaining',greatest(30-v_used,0),
    'role',v_profile.role,
    'volunteer_pid',v_profile.volunteer_pid
  );
end;
$$;

revoke all on function public.house_add_quota() from public, anon;

grant execute on function public.house_add_quota() to authenticated;

-- Service-only registry reconciliation. Incoming rows are the privacy allowlisted
-- JHCIS projection. Match order is exact pcucode+hcode, then unique house_id_11.
-- A field-created row keeps volunteer_pid and creator metadata when it receives
-- the real JHCIS hcode. Approximate house-number matching is deliberately absent.
create or replace function public.service_reconcile_jhcis_houses_v2045(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_item jsonb;
  v_house public.houses%rowtype;
  v_id11 text;
  v_pcucode text;
  v_hcode text;
  v_exact_id uuid;
  v_id11_id uuid;
  v_preserve_owner boolean;
  v_created integer := 0;
  v_updated integer := 0;
  v_linked integer := 0;
  v_conflict integer := 0;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'ROWS_ARRAY_REQUIRED';
  end if;

  for v_item in select value from jsonb_array_elements(p_rows)
  loop
    v_pcucode := btrim(coalesce(v_item->>'source_pcucode',''));
    v_hcode := btrim(coalesce(v_item->>'hcode',''));
    v_id11 := nullif(btrim(coalesce(v_item->>'house_id_11','')),'');
    if v_pcucode='' or v_hcode='' then
      v_conflict := v_conflict + 1;
      continue;
    end if;
    if v_id11 is not null and v_id11 !~ '^[0-9]{11}$' then
      v_id11 := null;
    end if;

    select id into v_exact_id
    from public.houses
    where source_pcucode=v_pcucode and hcode=v_hcode
    limit 1;

    v_id11_id := null;
    if v_id11 is not null then
      select id into v_id11_id
      from public.houses
      where house_id_11=v_id11
      limit 1;
    end if;

    -- If the real JHCIS key and the 11-digit id point at two different Cloud
    -- rows, do not auto-merge or delete either row. Flag the exact row for review.
    if v_exact_id is not null and v_id11_id is not null and v_exact_id <> v_id11_id then
      update public.houses
         set review_required=true,
             review_reason=trim(both '; ' from coalesce(review_reason,'') || '; JHCIS reconciliation key conflict')
       where id=v_exact_id;
      v_conflict := v_conflict + 1;
      continue;
    end if;

    if v_exact_id is not null then
      select * into v_house from public.houses where id=v_exact_id for update;
    elsif v_id11_id is not null then
      select * into v_house from public.houses where id=v_id11_id for update;
      v_linked := v_linked + 1;
    else
      v_house.id := null;
    end if;

    if v_house.id is null then
      insert into public.houses(
        source_pcucode,hcode,house_id_11,house_no,moo,community,
        latitude,longitude,coordinate_source,coordinate_status,coordinate_distance_m,
        inside_tambon,inside_community,volunteer_pid,record_status,
        review_required,review_reason,entry_source
      ) values (
        v_pcucode,v_hcode,v_id11,
        coalesce(v_item->>'house_no',''),coalesce(v_item->>'moo',''),coalesce(v_item->>'community',''),
        nullif(v_item->>'latitude','')::double precision,
        nullif(v_item->>'longitude','')::double precision,
        coalesce(nullif(v_item->>'coordinate_source',''),'none'),
        coalesce(nullif(v_item->>'coordinate_status',''),'missing'),
        nullif(v_item->>'coordinate_distance_m','')::double precision,
        nullif(v_item->>'inside_tambon','')::boolean,
        nullif(v_item->>'inside_community','')::boolean,
        nullif(v_item->>'volunteer_pid','')::bigint,
        coalesce(v_item->>'record_status',''),
        coalesce((v_item->>'review_required')::boolean,false),
        coalesce(v_item->>'review_reason',''),
        'import'
      );
      v_created := v_created + 1;
    else
      v_preserve_owner := v_house.entry_source='field' and v_house.volunteer_pid is not null;
      update public.houses
         set source_pcucode=v_pcucode,
             hcode=v_hcode,
             house_id_11=coalesce(v_id11,house_id_11),
             house_no=coalesce(nullif(v_item->>'house_no',''),house_no),
             moo=coalesce(nullif(v_item->>'moo',''),moo),
             community=coalesce(nullif(v_item->>'community',''),community),
             latitude=case when v_item ? 'latitude' then nullif(v_item->>'latitude','')::double precision else latitude end,
             longitude=case when v_item ? 'longitude' then nullif(v_item->>'longitude','')::double precision else longitude end,
             coordinate_source=coalesce(nullif(v_item->>'coordinate_source',''),coordinate_source),
             coordinate_status=coalesce(nullif(v_item->>'coordinate_status',''),coordinate_status),
             coordinate_distance_m=case when v_item ? 'coordinate_distance_m' then nullif(v_item->>'coordinate_distance_m','')::double precision else coordinate_distance_m end,
             inside_tambon=case when v_item ? 'inside_tambon' then nullif(v_item->>'inside_tambon','')::boolean else inside_tambon end,
             inside_community=case when v_item ? 'inside_community' then nullif(v_item->>'inside_community','')::boolean else inside_community end,
             volunteer_pid=case when v_preserve_owner then volunteer_pid else nullif(v_item->>'volunteer_pid','')::bigint end,
             record_status=coalesce(nullif(v_item->>'record_status',''),record_status),
             review_required=coalesce((v_item->>'review_required')::boolean,review_required),
             review_reason=coalesce(v_item->>'review_reason',review_reason),
             updated_at=now()
       where id=v_house.id;
      v_updated := v_updated + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'created',v_created,
    'updated',v_updated,
    'linked_by_house_id_11',v_linked,
    'conflicts',v_conflict,
    'ownership_policy','preserve_field_volunteer_pid'
  );
end;
$$;

revoke all on function public.service_reconcile_jhcis_houses_v2045(jsonb) from public, anon, authenticated;

grant execute on function public.service_reconcile_jhcis_houses_v2045(jsonb) to service_role;

insert into public.app_settings(key,value)
values('house_ownership_policy_v2045',jsonb_build_object(
  'version','2I',
  'cloud_field_add_roles',jsonb_build_array('user','staff'),
  'field_house_owner','profile.volunteer_pid',
  'owner_locked_for_user_staff',true,
  'staff_add_location','my_houses_only',
  'community_mutation_for_user_staff',false,
  'jhcis_match_order',jsonb_build_array('source_pcucode+hcode','house_id_11','manual_review_area_key'),
  'service_sync_preserves_field_owner',true,
  'write_back_to_jhcis',false
))
on conflict (key) do update set value=excluded.value, updated_at=now();
