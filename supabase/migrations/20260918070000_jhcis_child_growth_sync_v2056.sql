-- Cloud v2.0.56 โ€” Local Admin child growth selective sync controls.
-- Updates only existing health_persons growth snapshot columns. JHCIS remains read-only.
begin;

alter table public.health_persons
  add column if not exists growth_previous_synced_at timestamptz;

create or replace function public.service_sync_child_growth_snapshot_v2056(
  p_age_group text,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_group text:=lower(btrim(coalesce(p_age_group,'')));
  v_received integer:=0;
  v_updated integer:=0;
begin
  if coalesce(auth.role(),'')<>'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;
  if v_group not in ('child_0_5','school_6_14') then
    raise exception 'INVALID_AGE_GROUP';
  end if;
  if jsonb_typeof(coalesce(p_rows,'[]'::jsonb))<>'array' then
    raise exception 'INVALID_ROWS';
  end if;

  select count(*) into v_received
  from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb));

  with incoming as materialized (
    select
      nullif(btrim(x.source_pcucode),'') as source_pcucode,
      x.source_pid,
      x.growth_previous_on,
      x.growth_previous_weight_kg,
      x.growth_previous_height_cm,
      left(coalesce(x.growth_previous_source,''),120) as growth_previous_source
    from jsonb_to_recordset(coalesce(p_rows,'[]'::jsonb)) as x(
      source_pcucode text,
      source_pid bigint,
      growth_previous_on date,
      growth_previous_weight_kg numeric,
      growth_previous_height_cm numeric,
      growth_previous_source text
    )
    where x.source_pid is not null
      and x.source_pid>0
      and x.growth_previous_on is not null
      and x.growth_previous_weight_kg between 0.1 and 300
      and x.growth_previous_height_cm between 30 and 250
  )
  update public.health_persons p
  set growth_previous_on=i.growth_previous_on,
      growth_previous_weight_kg=i.growth_previous_weight_kg,
      growth_previous_height_cm=i.growth_previous_height_cm,
      growth_previous_source=i.growth_previous_source,
      growth_previous_synced_at=now()
  from incoming i
  where p.source_pcucode=i.source_pcucode
    and p.source_pid=i.source_pid
    and p.active=true
    and coalesce(p.service_population_eligible,false)=true
    and p.birth_date is not null
    and (
      (v_group='child_0_5' and extract(year from age(current_date,p.birth_date))::integer between 0 and 5)
      or
      (v_group='school_6_14' and extract(year from age(current_date,p.birth_date))::integer between 6 and 14)
    );

  get diagnostics v_updated = row_count;

  return jsonb_build_object(
    'ok',true,
    'version','2.0.56',
    'age_group',v_group,
    'received',v_received,
    'updated',v_updated,
    'skipped_missing_or_out_of_scope',greatest(v_received-v_updated,0),
    'synced_at',now()
  );
end;
$$;

revoke all on function public.service_sync_child_growth_snapshot_v2056(text,jsonb)
  from public,anon,authenticated;

grant execute on function public.service_sync_child_growth_snapshot_v2056(text,jsonb)
  to service_role;

create or replace function public.service_child_growth_sync_status_v2056()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if coalesce(auth.role(),'')<>'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;
  return jsonb_build_object(
    'version','2.0.56',
    'child_0_5',jsonb_build_object(
      'cloud_population',(select count(*) from public.health_persons p where p.active=true and coalesce(p.service_population_eligible,false)=true and p.birth_date is not null and extract(year from age(current_date,p.birth_date))::integer between 0 and 5),
      'with_history',(select count(*) from public.health_persons p where p.active=true and coalesce(p.service_population_eligible,false)=true and p.birth_date is not null and extract(year from age(current_date,p.birth_date))::integer between 0 and 5 and p.growth_previous_on is not null),
      'latest_measured_on',(select max(p.growth_previous_on) from public.health_persons p where p.active=true and p.birth_date is not null and extract(year from age(current_date,p.birth_date))::integer between 0 and 5),
      'last_synced_at',(select max(p.growth_previous_synced_at) from public.health_persons p where p.birth_date is not null and extract(year from age(current_date,p.birth_date))::integer between 0 and 5)
    ),
    'school_6_14',jsonb_build_object(
      'cloud_population',(select count(*) from public.health_persons p where p.active=true and coalesce(p.service_population_eligible,false)=true and p.birth_date is not null and extract(year from age(current_date,p.birth_date))::integer between 6 and 14),
      'with_history',(select count(*) from public.health_persons p where p.active=true and coalesce(p.service_population_eligible,false)=true and p.birth_date is not null and extract(year from age(current_date,p.birth_date))::integer between 6 and 14 and p.growth_previous_on is not null),
      'latest_measured_on',(select max(p.growth_previous_on) from public.health_persons p where p.active=true and p.birth_date is not null and extract(year from age(current_date,p.birth_date))::integer between 6 and 14),
      'last_synced_at',(select max(p.growth_previous_synced_at) from public.health_persons p where p.birth_date is not null and extract(year from age(current_date,p.birth_date))::integer between 6 and 14)
    )
  );
end;
$$;

revoke all on function public.service_child_growth_sync_status_v2056()
  from public,anon,authenticated;

grant execute on function public.service_child_growth_sync_status_v2056()
  to service_role;

insert into public.app_settings(key,value)
values('child_growth_selective_sync_v2056',jsonb_build_object(
  'version','2.0.56',
  'local_admin_buttons',jsonb_build_array('child_0_5','school_6_14'),
  'updates_existing_health_persons_only',true,
  'jhcis_write_back',false,
  'direct_identifiers_uploaded',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
