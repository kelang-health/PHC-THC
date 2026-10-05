-- Canonical NCD target alignment v2.1.90
-- Canonical proactive NCD denominator:
-- age >= 35 and no known DM and no known HT.
-- Disease-specific dm_target / ht_target remain available separately.

begin;

do $patch$
declare
  ddl text;
  old_text text := 'set ncd_target=(dm_target or ht_target) where source_pcucode is not null and source_pid is not null;';
  new_text text := 'set ncd_target=(coalesce(age_years,0)>=35 and not coalesce(has_dm,false) and not coalesce(has_ht,false)) where source_pcucode is not null and source_pid is not null;';
begin
  select pg_get_functiondef(p.oid) into ddl
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='refresh_screening_target_cache_v2030'
  order by p.oid desc
  limit 1;

  if ddl is null then
    raise exception 'REFRESH_SCREENING_TARGET_CACHE_FUNCTION_NOT_FOUND';
  end if;
  if position(old_text in ddl)=0 then
    raise exception 'NCD_TARGET_REFRESH_PATTERN_NOT_FOUND';
  end if;

  ddl := replace(ddl, old_text, new_text);
  execute ddl;
end
$patch$;

do $patch$
declare
  ddl text;
  old_text text := 'WHERE COALESCE(b.ncd_base_eligible, b.age_years >= 35 AND NOT (b.has_ht OR b.has_dm)) = true';
  new_text text := 'WHERE b.age_years >= 35 AND NOT COALESCE(b.has_ht, false) AND NOT COALESCE(b.has_dm, false)';
begin
  select pg_get_viewdef('public.field_work_items_v200'::regclass,true) into ddl;

  if ddl is null then
    raise exception 'FIELD_WORK_ITEMS_VIEW_NOT_FOUND';
  end if;
  if position(old_text in ddl)=0 then
    raise exception 'FIELD_WORK_NCD_PATTERN_NOT_FOUND';
  end if;

  ddl := replace(ddl, old_text, new_text);
  execute 'create or replace view public.field_work_items_v200 as ' || ddl;
end
$patch$;

update public.health_screening_target_cache_v2030
set ncd_target=(
  coalesce(age_years,0)>=35
  and not coalesce(has_dm,false)
  and not coalesce(has_ht,false)
)
where source_pcucode is not null and source_pid is not null;

insert into public.app_settings(key,value)
values(
  'canonical_ncd_target_v2190',
  jsonb_build_object(
    'version','2.1.90',
    'active',true,
    'definition','age_35_plus_and_no_dm_and_no_ht',
    'effective_fy_start','2026-10-01',
    'keeps_disease_specific_targets',true,
    'note','ncd_target is the proactive NCD denominator; dm_target/ht_target remain disease-specific operational flags'
  )
)
on conflict(key) do update
set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
