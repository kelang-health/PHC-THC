-- Cloud v2.0.30e: keep denormalized target cache aligned when Admin changes enabled age groups.
begin;

create or replace function public.admin_set_screening_target_group_v2026(p_route text,p_enabled boolean)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_row public.health_screening_target_groups_v2026%rowtype;
  v_refresh jsonb;
  v_cache jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  select * into v_row from public.health_screening_target_groups_v2026 where route=btrim(p_route) for update;
  if not found then raise exception 'UNKNOWN_TARGET_GROUP'; end if;
  if v_row.locked and coalesce(p_enabled,false)=false then raise exception 'AGE_35_PLUS_TARGET_IS_REQUIRED'; end if;

  update public.health_screening_target_groups_v2026
  set enabled=coalesce(p_enabled,false),updated_by=auth.uid(),updated_at=now()
  where route=v_row.route;

  v_refresh:=public.refresh_health_screening_plan_v2023(current_date);
  v_cache:=public.refresh_screening_target_cache_v2030();
  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'UPDATE','screening_target_group',v_row.route,'',jsonb_build_object('enabled',coalesce(p_enabled,false),'refresh',v_refresh,'cache',v_cache));
  return public.screening_target_settings_v2026() || jsonb_build_object('cache',v_cache);
end;
$$;

revoke all on function public.admin_set_screening_target_group_v2026(text,boolean) from public,anon;

grant execute on function public.admin_set_screening_target_group_v2026(text,boolean) to authenticated;

notify pgrst,'reload schema';

commit;
