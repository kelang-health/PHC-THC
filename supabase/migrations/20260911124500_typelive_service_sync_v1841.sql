-- v1.8.41: narrowly scoped service-only typelive synchronization.
-- Updates existing health_persons rows only; it never inserts people.

create or replace function public.sync_health_person_typelive_v1841(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_updated integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'ROWS_MUST_BE_ARRAY' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) > 500 then
    raise exception 'BATCH_TOO_LARGE' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_rows) as x(source_pcucode text, source_pid bigint, jhcis_typelive smallint)
    where x.source_pcucode is null
       or x.source_pid is null
       or (x.jhcis_typelive is not null and x.jhcis_typelive not between 1 and 4)
  ) then
    raise exception 'INVALID_TYPELIVE_PAYLOAD' using errcode = '22023';
  end if;

  update public.health_persons as hp
     set jhcis_typelive = x.jhcis_typelive
    from jsonb_to_recordset(p_rows) as x(source_pcucode text, source_pid bigint, jhcis_typelive smallint)
   where hp.source_pcucode = x.source_pcucode
     and hp.source_pid = x.source_pid
     and hp.jhcis_typelive is distinct from x.jhcis_typelive;
  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

revoke all on function public.sync_health_person_typelive_v1841(jsonb) from public, anon, authenticated;

grant execute on function public.sync_health_person_typelive_v1841(jsonb) to service_role;

comment on function public.sync_health_person_typelive_v1841(jsonb) is
  'Service-only v1.8.41 sync: update existing JHCIS typelive values; never insert people.';
