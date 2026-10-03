begin;

update public.health_screening_target_groups_v2026
set enabled=false,
    updated_at=now()
where route='child_0_5';

update public.health_screening_plan_v2023
set target_enabled=false,
    updated_at=now()
where route='child_0_5'
  and target_enabled is distinct from false;

update public.health_screening_target_cache_v2030
set field_target_enabled=false,
    screening_plan_updated_at=now()
where screening_route='child_0_5'
  and field_target_enabled is distinct from false;

create or replace function private.guard_disabled_child_screening_v2137()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_enabled boolean := false;
begin
  if new.route = 'child_0_5' then
    select coalesce(g.enabled,false)
      into v_enabled
    from public.health_screening_target_groups_v2026 g
    where g.route='child_0_5';

    if not coalesce(v_enabled,false) then
      raise exception 'SCREENING_ROUTE_DISABLED:child_0_5';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.guard_disabled_child_screening_v2137() from public,anon,authenticated;

drop trigger if exists trg_guard_disabled_child_screening_v2137 on public.screening_sessions;
create trigger trg_guard_disabled_child_screening_v2137
before insert or update on public.screening_sessions
for each row
execute function private.guard_disabled_child_screening_v2137();

insert into public.app_settings(key,value)
values(
  'field_screening_flow_v2137',
  jsonb_build_object(
    'version','2.0.137',
    'child_0_5_enabled',false,
    'child_0_5_history_preserved',true,
    'child_0_5_backend_guard',true,
    'elderly_ncd_first',true,
    'elderly9_after_ncd_prompt',true,
    'elderly9_session_creation','on_user_continue',
    'elderly9_can_defer',true,
    'jhcis_write_back',false
  )
)
on conflict(key) do update
set value=excluded.value,
    updated_at=now();

notify pgrst,'reload schema';
commit;