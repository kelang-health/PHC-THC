-- Keep the complete target-cache rebuild compatible with safeupdate.
-- Cache keys are NOT NULL; permissions, target rules and production reconciliation are unchanged.
CREATE OR REPLACE FUNCTION public.refresh_screening_target_cache_v2030()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count bigint;
  v_production_merged bigint:=0;
  v_fy_start date;
begin
  if auth.role() IS DISTINCT FROM 'service_role' and (auth.uid() is null or private.current_role() IS DISTINCT FROM 'admin') then
    raise exception 'ADMIN_OR_SERVICE_REQUIRED';
  end if;

  v_fy_start:=greatest(
    date '2026-10-01',
    case when extract(month from current_date)>=10
      then make_date(extract(year from current_date)::int,10,1)
      else make_date(extract(year from current_date)::int-1,10,1)
    end
  );

  delete from public.health_screening_target_cache_v2030
    where source_pcucode is not null and source_pid is not null;

  insert into public.health_screening_target_cache_v2030
  select w.*,
    (coalesce(w.age_years,0)>=35 and not coalesce(w.has_dm,false)) as dm_target,
    (coalesce(w.age_years,0)>=35 and not coalesce(w.has_ht,false)) as ht_target,
    (
      coalesce(w.age_years,0)>=35
      and not coalesce(w.has_dm,false)
      and w.previous_screened_on between v_fy_start and current_date
      and coalesce(w.previous_glucose_mg_dl,0)>0
    ) as dm_screened_current_fy,
    (
      coalesce(w.age_years,0)>=35
      and not coalesce(w.has_ht,false)
      and w.previous_screened_on between v_fy_start and current_date
      and coalesce(w.previous_sbp,0)>0
      and coalesce(w.previous_dbp,0)>0
    ) as ht_screened_current_fy,
    case when coalesce(w.screening_route,'')='elderly_60_plus' then 'not_started' else 'not_required' end as elderly9_status_current_fy,
    false as elderly9_completed_current_fy,
    0::smallint as elderly9_completed_domains_current_fy,
    null::date as latest_elderly9_screened_on
  from public.health_screening_target_worklist_v2026 w;

  update public.health_screening_target_cache_v2030
     set ncd_target=(birth_date is not null and extract(year from age(v_fy_start,birth_date))::int>=35 and not coalesce(has_dm,false) and not coalesce(has_ht,false)) where source_pcucode is not null and source_pid is not null;

  get diagnostics v_count=row_count;

  v_production_merged:=private.reconcile_ncd_cache_v2176();

  with e as (
    select s.source_pcucode,s.source_pid,
      coalesce(bool_or(s.elderly9_status='complete'),false) as is_complete,
      coalesce(bool_or(s.elderly9_status='in_progress'),false) as is_progress,
      max(s.screening_date) filter(where s.elderly9_status='complete') as complete_on,
      max(s.screening_date) filter(where s.elderly9_status='in_progress') as progress_on,
      greatest(coalesce(max(cardinality(coalesce(s.completed_domains,'{}'::text[]))),0),
        case when coalesce(bool_or(s.elderly9_status='complete'),false) then 9 else 0 end)::smallint as completed_domains
    from public.screening_sessions s
    where s.route='elderly_60_plus'
      and s.screening_date between v_fy_start and current_date
      and s.elderly9_status in ('complete','in_progress')
    group by s.source_pcucode,s.source_pid
  )
  update public.health_screening_target_cache_v2030 c set
    elderly9_status_current_fy=case when coalesce(c.screening_route,'')<>'elderly_60_plus' then 'not_required'
      when coalesce(e.is_complete,false) then 'complete'
      when coalesce(e.is_progress,false) then 'in_progress' else 'not_started' end,
    elderly9_completed_current_fy=case when coalesce(c.screening_route,'')='elderly_60_plus' then coalesce(e.is_complete,false) else false end,
    elderly9_completed_domains_current_fy=case when coalesce(c.screening_route,'')='elderly_60_plus' then coalesce(e.completed_domains,0) else 0 end,
    latest_elderly9_screened_on=case when coalesce(c.screening_route,'')<>'elderly_60_plus' then null
      when coalesce(e.is_complete,false) then e.complete_on
      when coalesce(e.is_progress,false) then e.progress_on else null end
  from e
  where c.source_pcucode=e.source_pcucode and c.source_pid=e.source_pid;

  return jsonb_build_object(
    'ok',true,
    'cached_rows',(select count(*) from public.health_screening_target_cache_v2030),
    'dm_targets',(select count(*) from public.health_screening_target_cache_v2030 where dm_target),
    'ht_targets',(select count(*) from public.health_screening_target_cache_v2030 where ht_target),
    'production_screenings_restored',v_production_merged,
    'version','2.0.176'
  );
end;
$function$
;

