
create or replace function public.health_delta_signatures_v2121()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
begin
  if auth.role()<>'service_role'
     and (auth.uid() is null or private.current_role()<>'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'source_pcucode',p.source_pcucode,
        'source_pid',p.source_pid,
        'signature',
        md5(concat_ws('|',
          coalesce(p.house_pcucode,''),
          coalesce(p.hcode,''),
          coalesce(p.display_name,''),
          coalesce(p.gender,''),
          coalesce(p.birth_date::text,''),
          case when coalesce(p.has_ht,false) then '1' else '0' end,
          case when coalesce(p.has_dm,false) then '1' else '0' end,
          case when coalesce(p.has_cvd,false) then '1' else '0' end,
          case when coalesce(p.cvd_population_eligible,false) then '1' else '0' end,
          case when coalesce(p.is_student,false) then '1' else '0' end,
          case when coalesce(p.is_disabled,false) then '1' else '0' end,
          case when coalesce(p.service_population_eligible,false) then '1' else '0' end,
          coalesce(p.adl_group_code,''),
          coalesce(p.adl_assessed_on::text,''),
          coalesce(p.care_group_code,''),
          coalesce(p.jhcis_typelive::text,''),
          case when coalesce(p.ncd_base_eligible,false) then '1' else '0' end,
          coalesce(p.source_updated_at,''),
          coalesce(p.previous_screened_on::text,''),
          coalesce(to_char(round(p.previous_weight_kg::numeric,2),'FM999999990.00'),''),
          coalesce(to_char(round(p.previous_height_cm::numeric,2),'FM999999990.00'),''),
          coalesce(to_char(round(p.previous_waist_cm::numeric,2),'FM999999990.00'),''),
          coalesce(p.previous_sbp::text,''),
          coalesce(p.previous_dbp::text,''),
          coalesce(p.previous_glucose_mg_dl::text,''),
          coalesce(to_char(round(p.previous_bmi::numeric,2),'FM999999990.00'),''),
          coalesce(p.previous_source,''),
          coalesce(p.growth_previous_on::text,''),
          coalesce(to_char(round(p.growth_previous_weight_kg::numeric,2),'FM999999990.00'),''),
          coalesce(to_char(round(p.growth_previous_height_cm::numeric,2),'FM999999990.00'),''),
          coalesce(p.growth_previous_source,'')
        ))
      )
      order by p.source_pcucode,p.source_pid
    )
    from public.health_persons p
    where p.active=true and p.service_population_eligible=true
  ),'[]'::jsonb);
end;
$function$;

revoke all on function public.health_delta_signatures_v2121() from public;
revoke all on function public.health_delta_signatures_v2121() from anon;
grant execute on function public.health_delta_signatures_v2121() to authenticated,service_role;

insert into public.app_settings(key,value)
values(
  'health_delta_sync_policy_v2121',
  jsonb_build_object(
    'version','2.0.121',
    'mode','row_signature_delta',
    'population_create_or_inactivate',false,
    'changed_health_rows_only',true,
    'population_mismatch_blocks_apply',true,
    'source_of_truth','jhcisdb'
  )
)
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';
