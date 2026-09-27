
create or replace function public.service_reconcile_jhcis_houses_v2045(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','extensions'
as $function$
declare
  v_item jsonb;
  v_house public.houses%rowtype;
  v_id11 text;
  v_pcucode text;
  v_hcode text;
  v_exact_id uuid;
  v_id11_id uuid;
  v_preserve_owner boolean;
  v_protect_coordinate boolean;
  v_created integer := 0;
  v_updated integer := 0;
  v_linked integer := 0;
  v_conflict integer := 0;
  v_coordinate_protected integer := 0;
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
      v_protect_coordinate :=
        coalesce(v_house.coordinate_source,'') in ('gps','map')
        and v_house.latitude is not null
        and v_house.longitude is not null;

      update public.houses
         set source_pcucode=v_pcucode,
             hcode=v_hcode,
             house_id_11=coalesce(v_id11,house_id_11),
             house_no=coalesce(nullif(v_item->>'house_no',''),house_no),
             moo=coalesce(nullif(v_item->>'moo',''),moo),
             community=coalesce(nullif(v_item->>'community',''),community),
             latitude=case
               when v_protect_coordinate then latitude
               when v_item ? 'latitude' then nullif(v_item->>'latitude','')::double precision
               else latitude end,
             longitude=case
               when v_protect_coordinate then longitude
               when v_item ? 'longitude' then nullif(v_item->>'longitude','')::double precision
               else longitude end,
             coordinate_source=case
               when v_protect_coordinate then coordinate_source
               else coalesce(nullif(v_item->>'coordinate_source',''),coordinate_source) end,
             coordinate_status=case
               when v_protect_coordinate then coordinate_status
               else coalesce(nullif(v_item->>'coordinate_status',''),coordinate_status) end,
             coordinate_distance_m=case
               when v_protect_coordinate then coordinate_distance_m
               when v_item ? 'coordinate_distance_m' then nullif(v_item->>'coordinate_distance_m','')::double precision
               else coordinate_distance_m end,
             inside_tambon=case
               when v_protect_coordinate then inside_tambon
               when v_item ? 'inside_tambon' then nullif(v_item->>'inside_tambon','')::boolean
               else inside_tambon end,
             inside_community=case
               when v_protect_coordinate then inside_community
               when v_item ? 'inside_community' then nullif(v_item->>'inside_community','')::boolean
               else inside_community end,
             volunteer_pid=case when v_preserve_owner then volunteer_pid else nullif(v_item->>'volunteer_pid','')::bigint end,
             record_status=coalesce(nullif(v_item->>'record_status',''),record_status),
             review_required=case
               when v_protect_coordinate then review_required
               else coalesce((v_item->>'review_required')::boolean,review_required) end,
             review_reason=case
               when v_protect_coordinate then review_reason
               else coalesce(v_item->>'review_reason',review_reason) end,
             updated_at=now()
       where id=v_house.id;
      if v_protect_coordinate then
        v_coordinate_protected := v_coordinate_protected + 1;
      end if;
      v_updated := v_updated + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'created',v_created,
    'updated',v_updated,
    'linked_by_house_id_11',v_linked,
    'conflicts',v_conflict,
    'coordinate_protected',v_coordinate_protected,
    'ownership_policy','preserve_field_volunteer_pid',
    'coordinate_policy','cloud_gps_map_wins_over_jhcis_local_sync'
  );
end;
$function$;

revoke execute on function public.service_reconcile_jhcis_houses_v2045(jsonb) from public, anon, authenticated;
grant execute on function public.service_reconcile_jhcis_houses_v2045(jsonb) to service_role;
