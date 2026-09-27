
do $patch$
declare ddl text;
begin
  select pg_get_functiondef(p.oid) into ddl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='refresh_screening_target_cache_v2030'
  order by p.oid desc limit 1;

  if ddl is null then raise exception 'REFRESH_FUNCTION_NOT_FOUND'; end if;
  if position('set ncd_target=(dm_target or ht_target);' in ddl)=0 then
    raise exception 'TARGET_UPDATE_PATTERN_NOT_FOUND';
  end if;

  ddl:=replace(
    ddl,
    'set ncd_target=(dm_target or ht_target);',
    'set ncd_target=(dm_target or ht_target) where source_pcucode is not null and source_pid is not null;'
  );
  execute ddl;
end
$patch$;

insert into public.app_settings(key,value)
values('ncd_target_cache_safeupdate_v2119',
       jsonb_build_object('version','2.0.119','fixed',true,'reason','service_role RPC safe-update requires explicit WHERE'))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';
