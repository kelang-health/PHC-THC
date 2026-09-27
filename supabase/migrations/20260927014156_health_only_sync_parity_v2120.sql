
create or replace function public.health_parity_snapshot_v2120()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_health_hash text;
begin
  if auth.role()<>'service_role'
     and (auth.uid() is null or private.current_role()<>'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;

  select md5(coalesce(string_agg(
    concat_ws('|',
      p.source_pcucode,
      p.source_pid::text,
      coalesce(p.hcode,''),
      coalesce(p.jhcis_typelive::text,''),
      coalesce(p.has_dm::text,'false'),
      coalesce(p.has_ht::text,'false'),
      coalesce(p.birth_date::text,''),
      coalesce(p.source_updated_at,'')
    ),
    E'\n' order by p.source_pcucode,p.source_pid
  ),'')) into v_health_hash
  from public.health_persons p
  where p.active=true and p.service_population_eligible=true;

  return jsonb_build_object(
    'version','2.0.120',
    'as_of',now(),
    'health_state_hash',v_health_hash,
    'health_active_service',(
      select count(*) from public.health_persons p
      where p.active=true and p.service_population_eligible=true
    ),
    'age35',(
      select count(*) from public.health_persons p
      where p.active=true and p.service_population_eligible=true
        and p.birth_date is not null
        and extract(year from age(current_date,p.birth_date))::int>=35
    ),
    'none_age35',(
      select count(*) from public.health_persons p
      where p.active=true and p.service_population_eligible=true
        and p.birth_date is not null
        and extract(year from age(current_date,p.birth_date))::int>=35
        and not coalesce(p.has_dm,false) and not coalesce(p.has_ht,false)
    ),
    'dm_only_age35',(
      select count(*) from public.health_persons p
      where p.active=true and p.service_population_eligible=true
        and p.birth_date is not null
        and extract(year from age(current_date,p.birth_date))::int>=35
        and coalesce(p.has_dm,false) and not coalesce(p.has_ht,false)
    ),
    'ht_only_age35',(
      select count(*) from public.health_persons p
      where p.active=true and p.service_population_eligible=true
        and p.birth_date is not null
        and extract(year from age(current_date,p.birth_date))::int>=35
        and not coalesce(p.has_dm,false) and coalesce(p.has_ht,false)
    ),
    'both_age35',(
      select count(*) from public.health_persons p
      where p.active=true and p.service_population_eligible=true
        and p.birth_date is not null
        and extract(year from age(current_date,p.birth_date))::int>=35
        and coalesce(p.has_dm,false) and coalesce(p.has_ht,false)
    ),
    'dm_target_expected',(
      select count(*) from public.health_persons p
      where p.active=true and p.service_population_eligible=true
        and p.birth_date is not null
        and extract(year from age(current_date,p.birth_date))::int>=35
        and not coalesce(p.has_dm,false)
    ),
    'ht_target_expected',(
      select count(*) from public.health_persons p
      where p.active=true and p.service_population_eligible=true
        and p.birth_date is not null
        and extract(year from age(current_date,p.birth_date))::int>=35
        and not coalesce(p.has_ht,false)
    ),
    'target_cache_rows',(select count(*) from public.health_screening_target_cache_v2030),
    'target_cache_age35',(select count(*) from public.health_screening_target_cache_v2030 where age_years>=35),
    'target_cache_dm_target',(select count(*) from public.health_screening_target_cache_v2030 where dm_target),
    'target_cache_ht_target',(select count(*) from public.health_screening_target_cache_v2030 where ht_target),
    'verified_houses',(
      select count(*) from public.houses h
      where h.source_pcucode='06116'
        and h.verification_status='verified_jhcis'
        and h.superseded_by is null
    )
  );
end;
$function$;

revoke all on function public.health_parity_snapshot_v2120() from public;
revoke all on function public.health_parity_snapshot_v2120() from anon;
grant execute on function public.health_parity_snapshot_v2120() to authenticated,service_role;

insert into public.app_settings(key,value)
values(
  'health_only_sync_policy_v2120',
  jsonb_build_object(
    'version','2.0.120',
    'source_of_truth','jhcisdb',
    'scope','health_persons + screening plan + target cache + report snapshot',
    'excludes',jsonb_build_array('houses','volunteers','training','auth','line'),
    'pre_target_guard','health state hash must match JHCIS after health upsert',
    'post_target_guard','age35 + DM target + HT target must match JHCIS'
  )
)
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';
