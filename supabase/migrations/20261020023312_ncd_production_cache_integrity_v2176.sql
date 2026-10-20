-- Cloud v2.0.176: Production FY evidence is independent of imported history.
set lock_timeout='3s';
-- Only derived cache fields are written. Production and imported history stay intact.
create or replace function private.reconcile_ncd_cache_v2176(p_pcucode text default null,p_pid bigint default null)
returns bigint language plpgsql security definer set search_path='' as $f$
declare v_rows bigint; v_today date:=(now() at time zone 'Asia/Bangkok')::date;
v_start date;
begin
  v_start:=make_date(extract(year from v_today)::int-case when extract(month from v_today)<10 then 1 else 0 end,10,1);
  with production as materialized (
    select s.* from public.health_ncd_screenings s
    where coalesce(s.record_mode,'production')='production'
      and s.screened_on<=v_today
      and (p_pcucode is null or s.source_pcucode=p_pcucode)
      and (p_pid is null or s.source_pid=p_pid)
  ), latest as (
    select distinct on(source_pcucode,source_pid) * from production
    order by source_pcucode,source_pid,screened_on desc,recorded_at desc nulls last,id desc
  ), done as (
    select source_pcucode,source_pid,bool_or(screened_on>=v_start) ncd,
      bool_or(screened_on>=v_start and glucose_mg_dl>0) dm,
      bool_or(screened_on>=v_start and sbp>0 and dbp>0) ht
    from production group by source_pcucode,source_pid
  ), source as (
    select c.source_pcucode,c.source_pid,s.id,s.screened_on,s.ncd_status,s.severity,
      coalesce(d.ncd,false) ncd,coalesce(d.dm,false) dm,coalesce(d.ht,false) ht,
      (s.id is not null and (p.previous_screened_on is null or s.screened_on>=p.previous_screened_on)) app_latest,
      s.weight_kg,s.height_cm,s.waist_cm,s.sbp,s.dbp,s.glucose_mg_dl,s.bmi,
      s.smoking_frequency,s.alcohol_frequency,s.exercise_frequency,
      p.previous_screened_on imported_on,p.previous_source imported_source,
      p.previous_weight_kg,p.previous_height_cm,p.previous_waist_cm,p.previous_sbp,p.previous_dbp,p.previous_glucose_mg_dl,p.previous_bmi
    from public.health_screening_target_cache_v2030 c
    join public.health_persons p using(source_pcucode,source_pid)
    left join latest s using(source_pcucode,source_pid)
    left join done d using(source_pcucode,source_pid)
    where (p_pcucode is null or c.source_pcucode=p_pcucode) and (p_pid is null or c.source_pid=p_pid)
  )
  update public.health_screening_target_cache_v2030 c set
    latest_screened_on=case when s.id is not null then s.screened_on else s.imported_on end,
    latest_ncd_status=case when s.id is not null then s.ncd_status when s.imported_on is not null then 'มีประวัติคัดกรองเดิม' else null end,
    latest_severity=s.severity,
    screened_current_fy=s.ncd,
    dm_screened_current_fy=c.dm_target and (s.dm or coalesce((s.imported_on between v_start and v_today and coalesce(s.previous_glucose_mg_dl,0)>0),false)),
    ht_screened_current_fy=c.ht_target and (s.ht or coalesce((s.imported_on between v_start and v_today and coalesce(s.previous_sbp,0)>0 and coalesce(s.previous_dbp,0)>0),false)),
    previous_screened_on=case when s.app_latest then s.screened_on else s.imported_on end,
    previous_source=case when s.app_latest then 'อสม. พลัส' else s.imported_source end,
    previous_weight_kg=case when s.app_latest then s.weight_kg else s.previous_weight_kg end,
    previous_height_cm=case when s.app_latest then s.height_cm else s.previous_height_cm end,
    previous_waist_cm=case when s.app_latest then s.waist_cm else s.previous_waist_cm end,
    previous_sbp=case when s.app_latest then s.sbp else s.previous_sbp end,
    previous_dbp=case when s.app_latest then s.dbp else s.previous_dbp end,
    previous_glucose_mg_dl=case when s.app_latest then s.glucose_mg_dl else s.previous_glucose_mg_dl end,
    previous_bmi=case when s.app_latest then s.bmi else s.previous_bmi end,
    previous_smoking=case when s.app_latest then coalesce(s.smoking_frequency,'') else '' end,
    previous_alcohol=case when s.app_latest then coalesce(s.alcohol_frequency,'') else '' end,
    previous_exercise=case when s.app_latest then coalesce(s.exercise_frequency,'') else '' end
  from source s where c.source_pcucode=s.source_pcucode and c.source_pid=s.source_pid;
  get diagnostics v_rows=row_count;
  return v_rows;
end $f$;
revoke all on function private.reconcile_ncd_cache_v2176(text,bigint) from public,anon,authenticated;

create or replace function private.sync_screening_target_cache_person_v2030()
returns trigger language plpgsql security definer set search_path='' as $f$
begin
  if tg_op='DELETE' then
    perform private.reconcile_ncd_cache_v2176(old.source_pcucode,old.source_pid);
    return old;
  end if;
  if tg_op='UPDATE' and (old.source_pcucode,old.source_pid) is distinct from (new.source_pcucode,new.source_pid) then
    perform private.reconcile_ncd_cache_v2176(old.source_pcucode,old.source_pid);
  end if;
  perform private.reconcile_ncd_cache_v2176(new.source_pcucode,new.source_pid);
  return new;
end $f$;

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

  delete from public.health_screening_target_cache_v2030;

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
create table if not exists private.ncd_integrity_runs_v2176 (
  id bigint generated always as identity primary key,
  checked_at timestamptz not null default now(), generation uuid,
  passed boolean not null, details jsonb not null
);
alter table private.ncd_integrity_runs_v2176 enable row level security;
revoke all on private.ncd_integrity_runs_v2176 from public,anon,authenticated;

create or replace function private.ncd_integrity_v2176(p_generation uuid default null)
returns jsonb language sql stable security definer set search_path='' as $f$
with dates as (
 select (now() at time zone 'Asia/Bangkok')::date today
), fy as (
 select today,make_date(extract(year from today)::int-case when extract(month from today)<10 then 1 else 0 end,10,1) start_on from dates
), actual as materialized (
 select distinct s.source_pcucode,s.source_pid from public.health_ncd_screenings s cross join fy
 where coalesce(s.record_mode,'production')='production' and s.screened_on between fy.start_on and fy.today
), grouped as (
 select coalesce(cm.name,'ยังไม่ระบุชุมชน') community,
   coalesce(private.community_key(cm.name),'') scope_key,
   count(*) filter(where c.ncd_target) targets,
   count(*) filter(where c.ncd_target and a.source_pid is not null) production,
   count(*) filter(where c.ncd_target and c.screened_current_fy) cached,
   count(*) filter(where c.ncd_target and c.screened_current_fy is distinct from (a.source_pid is not null)) mismatched_people,
   count(*) filter(where nullif(btrim(c.community),'') is not null and cm.name is null) invalid_community_people
 from public.health_screening_target_cache_v2030 c
 left join actual a using(source_pcucode,source_pid)
 left join public.communities cm on cm.active and cm.name=c.community and cm.moo=c.moo
 group by 1,2
), checked as (
 select g.*,coalesce((r.payload->>'ncd_targets')::bigint,0) snapshot_targets,
   coalesce((r.payload->>'ncd_done')::bigint,0) snapshot_done,
   coalesce((f.task->>'target')::bigint,0) field_targets,
   coalesce((f.task->>'complete')::bigint,0) field_done
 from grouped g left join public.report_snapshot_cache_v2031 r on r.generation=p_generation
   and r.report_key='care' and r.scope_type='community'
   and r.scope_key=case when g.scope_key='' then private.community_key('ยังไม่ระบุชุมชน') else g.scope_key end
 left join lateral (
   select task from public.report_snapshot_cache_v2031 s cross join lateral jsonb_array_elements(s.payload->'tasks') task
   where s.generation=p_generation and s.report_key='field' and s.scope_type='community'
     and s.scope_key=case when g.scope_key='' then private.community_key('ยังไม่ระบุชุมชน') else g.scope_key end and task->>'task_type'='ncd'
 ) f on true
), summary as (
 select coalesce(sum(targets),0) targets,coalesce(sum(production),0) production,coalesce(sum(cached),0) cached,
   coalesce(sum(mismatched_people),0) mismatched_people,
   coalesce(sum(invalid_community_people),0) invalid_community_people,
   coalesce(sum(case when p_generation is not null then abs(targets-snapshot_targets)+abs(production-snapshot_done)+abs(targets-field_targets)+abs(production-field_done) else 0 end),0) snapshot_difference,
   coalesce(jsonb_agg(to_jsonb(checked) order by community),'[]'::jsonb) communities from checked
), overall as (
 select coalesce((payload->>'ncd_targets')::bigint,0) targets,coalesce((payload->>'ncd_done')::bigint,0) done
 from public.report_snapshot_cache_v2031 where generation=p_generation and report_key='care' and scope_type='all' and scope_key='*'
)
select jsonb_build_object(
 'passed',s.mismatched_people=0 and s.invalid_community_people=0 and s.snapshot_difference=0
   and (p_generation is null or (s.targets=coalesce(o.targets,-1) and s.production=coalesce(o.done,-1))),
 'checked_at',now(),'fiscal_start',(select start_on from fy),'targets',s.targets,'production',s.production,'cached',s.cached,
 'mismatched_people',s.mismatched_people,'snapshot_difference',s.snapshot_difference,
 'snapshot_total_difference',case when p_generation is null then 0 else abs(s.targets-coalesce(o.targets,-1))+abs(s.production-coalesce(o.done,-1)) end,
 'invalid_community_people',s.invalid_community_people,'communities',s.communities,
 'cause',case when s.mismatched_people>0 then 'Production/cache identity mismatch' when s.snapshot_difference>0 then 'Snapshot/cache mismatch' when s.invalid_community_people>0 then 'Inactive or unknown community' else 'consistent' end)
from summary s left join overall o on true;
$f$;
revoke all on function private.ncd_integrity_v2176(uuid) from public,anon,authenticated;

create or replace function private.monitor_ncd_integrity_v2176()
returns jsonb language plpgsql security definer set search_path='' as $f$
declare v_generation uuid; v_result jsonb;
begin
 select current_generation into v_generation from public.report_snapshot_state_v2031 where singleton;
 v_result:=private.ncd_integrity_v2176(v_generation);
 insert into private.ncd_integrity_runs_v2176(generation,passed,details) values(v_generation,(v_result->>'passed')::boolean,v_result);
 return v_result;
end $f$;
revoke all on function private.monitor_ncd_integrity_v2176() from public,anon,authenticated;

create or replace function private.ncd_activity_v2176(p_scope_type text,p_scope_key text)
returns jsonb language sql stable security definer set search_path='' as $f$
with base as materialized (
 select s.source_pcucode,s.source_pid,s.screened_on
 from public.health_ncd_screenings s
 join public.health_screening_target_cache_v2030 c using(source_pcucode,source_pid)
 where c.ncd_target and coalesce(s.record_mode,'production')='production'
   and s.screened_on between private.field_period_start_v200() and (now() at time zone 'Asia/Bangkok')::date
   and (p_scope_type='all' or (p_scope_type='community' and private.community_key(coalesce(nullif(btrim(c.community),''),'ยังไม่ระบุชุมชน'))=p_scope_key)
     or (p_scope_type='volunteer' and c.volunteer_pid::text=p_scope_key))
), daily as (
 select screened_on service_day,count(distinct (source_pcucode,source_pid)) people from base group by 1
), weekly as (
 select date_trunc('week',screened_on)::date week_start,count(distinct (source_pcucode,source_pid)) people from base group by 1
)
select jsonb_build_object('basis','service_date_distinct_current_target_person','daily',coalesce((select jsonb_agg(to_jsonb(d) order by service_day) from daily d),'[]'::jsonb),
 'weekly',coalesce((select jsonb_agg(to_jsonb(w) order by week_start) from weekly w),'[]'::jsonb));
$f$;
revoke all on function private.ncd_activity_v2176(text,text) from public,anon,authenticated;


create or replace view public.health_person_worklist as
 WITH fy AS (
         SELECT GREATEST('2026-10-01'::date,
                CASE
                    WHEN EXTRACT(month FROM CURRENT_DATE) >= 10::numeric THEN make_date(EXTRACT(year FROM CURRENT_DATE)::integer, 10, 1)
                    ELSE make_date(EXTRACT(year FROM CURRENT_DATE)::integer - 1, 10, 1)
                END) AS fy_start
        ), base AS (
         SELECT p.source_pcucode,
            p.source_pid,
            p.house_pcucode,
            p.hcode,
            p.display_name,
            p.gender,
            p.birth_date,
            p.active,
            p.has_ht,
            p.has_dm,
            p.source_updated_at,
            p.sync_token,
            p.synced_at,
            p.previous_screened_on,
            p.previous_weight_kg,
            p.previous_height_cm,
            p.previous_waist_cm,
            p.previous_sbp,
            p.previous_dbp,
            p.previous_glucose_mg_dl,
            p.previous_bmi,
            p.previous_source,
            p.ncd_base_eligible,
            h.house_no,
            h.moo,
            h.community,
            h.volunteer_pid,
                CASE
                    WHEN p.birth_date IS NULL THEN NULL::integer
                    ELSE EXTRACT(year FROM age(CURRENT_DATE::timestamp with time zone, p.birth_date::timestamp with time zone))::integer
                END AS age_years
           FROM health_persons p
             JOIN houses h ON h.source_pcucode = p.house_pcucode AND h.hcode = p.hcode
          WHERE p.active = true
        ), app_latest AS (select distinct on (source_pcucode,source_pid) * from public.health_ncd_screenings where coalesce(record_mode,'production')='production' and screened_on <= (now() at time zone 'Asia/Bangkok')::date order by source_pcucode,source_pid,screened_on desc,recorded_at desc nulls last,id desc
        ), ranked AS (
         SELECT b.source_pcucode,
            b.source_pid,
            b.house_pcucode,
            b.hcode,
            b.display_name,
            b.gender,
            b.birth_date,
            b.active,
            b.has_ht,
            b.has_dm,
            b.source_updated_at,
            b.sync_token,
            b.synced_at,
            b.previous_screened_on,
            b.previous_weight_kg,
            b.previous_height_cm,
            b.previous_waist_cm,
            b.previous_sbp,
            b.previous_dbp,
            b.previous_glucose_mg_dl,
            b.previous_bmi,
            b.previous_source,
            b.ncd_base_eligible,
            b.house_no,
            b.moo,
            b.community,
            b.volunteer_pid,
            b.age_years,
            a.screened_on AS app_screened_on,
            a.ncd_status AS app_ncd_status,
            a.severity AS app_severity,
            a.weight_kg AS app_weight_kg,
            a.height_cm AS app_height_cm,
            a.waist_cm AS app_waist_cm,
            a.sbp AS app_sbp,
            a.dbp AS app_dbp,
            a.glucose_mg_dl AS app_glucose_mg_dl,
            a.bmi AS app_bmi,
            a.smoker AS app_smoker,
            a.alcohol_risk AS app_alcohol_risk,
            a.exercise_sufficient AS app_exercise_sufficient,
            a.smoking_frequency AS app_smoking_frequency,
            a.alcohol_frequency AS app_alcohol_frequency,
            a.exercise_frequency AS app_exercise_frequency,
            a.screened_on IS NOT NULL AND (b.previous_screened_on IS NULL OR a.screened_on >= b.previous_screened_on) AS app_is_latest
           FROM base b
             LEFT JOIN app_latest a ON a.screened_on <= (now() at time zone 'Asia/Bangkok')::date AND a.source_pcucode = b.source_pcucode AND a.source_pid = b.source_pid
        )
 SELECT r.source_pcucode,
    r.source_pid,
    r.house_pcucode,
    r.hcode,
    r.house_no,
    r.moo,
    r.community,
    r.volunteer_pid,
    r.display_name,
    r.gender,
    r.birth_date,
    r.age_years,
        CASE
            WHEN r.age_years IS NULL THEN 'ไม่ทราบ'::text
            WHEN r.age_years <= 5 THEN 'เด็กปฐมวัย'::text
            WHEN r.age_years <= 14 THEN 'เด็กวัยเรียน'::text
            WHEN r.age_years <= 24 THEN 'วัยรุ่นและเยาวชน'::text
            WHEN r.age_years <= 59 THEN 'วัยทำงาน'::text
            ELSE 'ผู้สูงอายุ'::text
        END AS life_stage,
    r.has_ht,
    r.has_dm,
    r.has_ht OR r.has_dm AS known_ncd,
    r.ncd_base_eligible AND r.birth_date IS NOT NULL AND EXTRACT(year FROM age(fy.fy_start::timestamp with time zone, r.birth_date::timestamp with time zone))::integer >= 35 AND NOT (r.has_ht OR r.has_dm) AS ncd_target,
        CASE
            WHEN r.app_screened_on IS NOT NULL THEN r.app_screened_on
            ELSE r.previous_screened_on
        END AS latest_screened_on,
        CASE
            WHEN r.app_screened_on IS NOT NULL THEN r.app_ncd_status
            WHEN r.previous_screened_on IS NOT NULL THEN 'มีประวัติคัดกรองใน JHCIS'::text
            ELSE NULL::text
        END AS latest_ncd_status,
        CASE
            WHEN r.app_screened_on IS NOT NULL THEN r.app_severity
            ELSE NULL::text
        END AS latest_severity,
    exists(select 1 from public.health_ncd_screenings s where s.source_pcucode=r.source_pcucode and s.source_pid=r.source_pid and coalesce(s.record_mode,'production')='production' and s.screened_on between fy.fy_start and (now() at time zone 'Asia/Bangkok')::date) AS screened_current_fy,
        CASE
            WHEN r.app_is_latest THEN r.app_screened_on
            ELSE r.previous_screened_on
        END AS previous_screened_on,
        CASE
            WHEN r.app_is_latest THEN r.app_weight_kg
            ELSE r.previous_weight_kg
        END AS previous_weight_kg,
        CASE
            WHEN r.app_is_latest THEN r.app_height_cm
            ELSE r.previous_height_cm
        END AS previous_height_cm,
        CASE
            WHEN r.app_is_latest THEN r.app_waist_cm
            ELSE r.previous_waist_cm
        END AS previous_waist_cm,
        CASE
            WHEN r.app_is_latest THEN r.app_sbp
            ELSE r.previous_sbp
        END AS previous_sbp,
        CASE
            WHEN r.app_is_latest THEN r.app_dbp
            ELSE r.previous_dbp
        END AS previous_dbp,
        CASE
            WHEN r.app_is_latest THEN r.app_glucose_mg_dl
            ELSE r.previous_glucose_mg_dl
        END AS previous_glucose_mg_dl,
        CASE
            WHEN r.app_is_latest THEN r.app_bmi
            ELSE r.previous_bmi
        END AS previous_bmi,
        CASE
            WHEN r.app_is_latest THEN 'อสม. พลัส'::text
            WHEN r.previous_screened_on IS NOT NULL THEN COALESCE(NULLIF(r.previous_source, ''::text), 'JHCIS / j-report NCD Export'::text)
            ELSE ''::text
        END AS previous_source,
        CASE
            WHEN r.app_is_latest THEN COALESCE(NULLIF(r.app_smoking_frequency, ''::text),
            CASE
                WHEN r.app_smoker THEN 'สูบ'::text
                ELSE 'ไม่สูบ'::text
            END)
            ELSE ''::text
        END AS previous_smoking,
        CASE
            WHEN r.app_is_latest THEN COALESCE(NULLIF(r.app_alcohol_frequency, ''::text),
            CASE
                WHEN r.app_alcohol_risk THEN 'ดื่ม'::text
                ELSE 'ไม่ดื่ม'::text
            END)
            ELSE ''::text
        END AS previous_alcohol,
        CASE
            WHEN r.app_is_latest THEN COALESCE(NULLIF(r.app_exercise_frequency, ''::text),
            CASE
                WHEN r.app_exercise_sufficient THEN 'เพียงพอ'::text
                ELSE 'ไม่เพียงพอ'::text
            END)
            ELSE ''::text
        END AS previous_exercise
   FROM ranked r
     CROSS JOIN fy;

CREATE OR REPLACE FUNCTION private.refresh_report_snapshots_v2031(p_reason text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET work_mem TO '16MB'
AS $function$
declare
  v_generation uuid:=gen_random_uuid();
  v_started timestamptz:=clock_timestamp();
  v_rows bigint:=0;
  v_added bigint:=0;
  v_reason text:=left(coalesce(nullif(btrim(p_reason),''),'manual'),80);
begin
  if not pg_try_advisory_xact_lock(hashtext('osm_phc_report_snapshot_v2031')) then
    if v_reason='nightly_00_05_bangkok' then
      insert into private.nightly_snapshot_outcomes_v2077
        (day_bkk,status,started_at,finished_at,error_message)
      values ((v_started at time zone 'Asia/Bangkok')::date,'busy',v_started,clock_timestamp(),
              'A concurrent report refresh held the snapshot lock')
      on conflict(day_bkk) do update set
        status=case when private.nightly_snapshot_outcomes_v2077.status='success' then 'success' else excluded.status end,
        checked_at=clock_timestamp();
    end if;
    return jsonb_build_object('ok',false,'status','busy','version','2.0.31');
  end if;

  insert into public.report_snapshot_runs_v2031(id,status,reason,started_at)
  values(v_generation,'running',v_reason,v_started);
  update public.report_snapshot_state_v2031
  set status='running',last_reason=v_reason,last_error=''
  where singleton=true;

  begin
    -- Care dashboard: scan each base relation once and fan rows into all/community/volunteer scopes.
    with house_scoped as materialized (
      select s.scope_type,s.scope_key,h.latitude,h.longitude,h.review_required
      from public.houses h
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,private.community_key(coalesce(nullif(btrim(h.community),''),'ยังไม่ระบุชุมชน'))),
        ('volunteer'::text,h.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where h.superseded_by is null and h.verification_status='verified_jhcis' and s.scope_key is not null
    ), hagg as (
      select scope_type,scope_key,count(*)::bigint houses,
        count(*) filter(where latitude is not null and longitude is not null)::bigint mapped_houses,
        count(*) filter(where latitude is null or longitude is null)::bigint missing_coordinates,
        count(*) filter(where review_required=true)::bigint review_houses
      from house_scoped group by scope_type,scope_key
    ), person_base as materialized (
      select w.source_pcucode,w.source_pid,w.life_stage,coalesce(c.ncd_target,false) ncd_target,coalesce(c.screened_current_fy,false) screened_current_fy,w.known_ncd,c.latest_severity,
        p.is_student,p.is_disabled,p.service_population_eligible,p.adl_group_code,
        h.community,h.volunteer_pid
      from public.health_person_worklist_active_v1847 w
      left join public.health_screening_target_cache_v2030 c on c.source_pcucode=w.source_pcucode and c.source_pid=w.source_pid
      join public.health_persons p on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
      join public.houses h on h.source_pcucode=w.house_pcucode and h.hcode=w.hcode and h.superseded_by is null and h.verification_status='verified_jhcis'
    ), person_scoped as materialized (
      select s.scope_type,s.scope_key,p.*
      from person_base p
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,private.community_key(coalesce(nullif(btrim(p.community),''),'ยังไม่ระบุชุมชน'))),
        ('volunteer'::text,p.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), pagg as (
      select scope_type,scope_key,count(*)::bigint household_people,
        count(*) filter(where service_population_eligible)::bigint service_people,
        count(*) filter(where service_population_eligible and ncd_target)::bigint ncd_targets,
        count(*) filter(where service_population_eligible and ncd_target and coalesce(screened_current_fy,false))::bigint ncd_done,
        count(*) filter(where service_population_eligible and ncd_target and not coalesce(screened_current_fy,false))::bigint ncd_due,
        count(*) filter(where service_population_eligible and known_ncd)::bigint known_ncd,
        count(*) filter(where service_population_eligible and life_stage='เด็กปฐมวัย')::bigint early_child,
        count(*) filter(where service_population_eligible and life_stage='เด็กวัยเรียน')::bigint school_age,
        count(*) filter(where service_population_eligible and life_stage='วัยรุ่นและเยาวชน')::bigint youth,
        count(*) filter(where service_population_eligible and life_stage='วัยทำงาน')::bigint working_age,
        count(*) filter(where service_population_eligible and life_stage='ผู้สูงอายุ')::bigint older_people,
        count(*) filter(where service_population_eligible and is_student)::bigint students,
        count(*) filter(where service_population_eligible and is_disabled)::bigint disabled_people,
        count(*) filter(where service_population_eligible and life_stage='ผู้สูงอายุ' and adl_group_code<>'')::bigint adl_assessed_people,
        count(*) filter(where service_population_eligible and life_stage='ผู้สูงอายุ' and adl_group_code='1B1280')::bigint social_people,
        count(*) filter(where service_population_eligible and life_stage='ผู้สูงอายุ' and adl_group_code='1B1281')::bigint homebound_people,
        count(*) filter(where service_population_eligible and life_stage='ผู้สูงอายุ' and adl_group_code='1B1282')::bigint bedridden_people,
        count(*) filter(where service_population_eligible and latest_severity in ('alert','urgent'))::bigint urgent_attention
      from person_scoped group by scope_type,scope_key
    ), latest_2q as materialized (
      select distinct on (s.source_pcucode,s.source_pid)
        s.source_pcucode,s.source_pid,s.mental_2q_status,s.mental_2q_result
      from public.health_ncd_screenings s
      join person_base p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
      where p.service_population_eligible=true and coalesce(s.record_mode,'production')='production'
      order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
    ), qagg as (
      select ps.scope_type,ps.scope_key,
        count(*) filter(where q.mental_2q_status='assessed')::bigint mental_2q_assessed,
        count(*) filter(where q.mental_2q_status='not_assessed')::bigint mental_2q_not_assessed,
        count(*) filter(where q.mental_2q_status='incomplete')::bigint mental_2q_incomplete,
        count(*) filter(where q.mental_2q_status='assessed' and q.mental_2q_result=true)::bigint mental_2q_positive
      from person_scoped ps join latest_2q q on q.source_pcucode=ps.source_pcucode and q.source_pid=ps.source_pid
      group by ps.scope_type,ps.scope_key
    ), scopes as (
      select scope_type,scope_key from hagg union select scope_type,scope_key from pagg union select scope_type,scope_key from qagg
    )
    insert into public.report_snapshot_cache_v2031(generation,report_key,scope_type,scope_key,payload,generated_at)
    select v_generation,'care',s.scope_type,s.scope_key,jsonb_build_object(
      'houses',coalesce(h.houses,0),'mapped_houses',coalesce(h.mapped_houses,0),
      'missing_coordinates',coalesce(h.missing_coordinates,0),'review_houses',coalesce(h.review_houses,0),
      'household_people',coalesce(p.household_people,0),'people',coalesce(p.service_people,0),'service_people',coalesce(p.service_people,0),
      'ncd_targets',coalesce(p.ncd_targets,0),'ncd_done',coalesce(p.ncd_done,0),'ncd_due',coalesce(p.ncd_due,0),'known_ncd',coalesce(p.known_ncd,0),
      'early_child',coalesce(p.early_child,0),'school_age',coalesce(p.school_age,0),'youth',coalesce(p.youth,0),
      'working_age',coalesce(p.working_age,0),'older_people',coalesce(p.older_people,0),'students',coalesce(p.students,0),
      'disabled_people',coalesce(p.disabled_people,0),'adl_assessed_people',coalesce(p.adl_assessed_people,0),
      'social_people',coalesce(p.social_people,0),'homebound_people',coalesce(p.homebound_people,0),'bedridden_people',coalesce(p.bedridden_people,0),
      'urgent_attention',coalesce(p.urgent_attention,0),'mental_2q_assessed',coalesce(q.mental_2q_assessed,0),
      'mental_2q_not_assessed',coalesce(q.mental_2q_not_assessed,0),'mental_2q_incomplete',coalesce(q.mental_2q_incomplete,0),
      'mental_2q_positive',coalesce(q.mental_2q_positive,0),
      'metric_sources',jsonb_build_object(
        'person_level','JHCIS read-only / J-Report operational definition',
        'service_population','typelive 1,3 + nation 99 + alive + non-00 village',
        'ncd','J-Report operational worklist; official HDC DM/HT denominators are separate',
        'adl','latest JHCIS f43specialpp 1B1280/1B1281/1B1282',
        'official_comparator','MoPH Open Data via hdc-app; aggregate only'
      )
    ),clock_timestamp()
    from scopes s
    left join hagg h using(scope_type,scope_key)
    left join pagg p using(scope_type,scope_key)
    left join qagg q using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;

    -- Field-work dashboard: materialize once, then aggregate the same rows for each permitted scope.
    with work_scoped as materialized (
      select s.scope_type,s.scope_key,w.*
      from public.field_work_items_v200 w
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,private.community_key(coalesce(nullif(btrim(w.community),''),'ยังไม่ระบุชุมชน'))),
        ('volunteer'::text,w.volunteer_pid::text)
      ) s(scope_type,scope_key)
      where s.scope_key is not null
    ), base_summary as (
      select scope_type,scope_key,count(*)::bigint total,
        count(*) filter(where status='complete')::bigint complete,
        count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due,
        count(*) filter(where priority='red')::bigint red,
        count(*) filter(where priority='orange')::bigint orange
      from work_scoped group by scope_type,scope_key
    ), task_rows as (
      select scope_type,scope_key,task_type,max(task_label) task_label,count(*)::bigint target,
        count(*) filter(where status='complete')::bigint complete,
        count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due
      from work_scoped group by scope_type,scope_key,task_type
    ), task_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'task_type',task_type,'task_label',task_label,'target',target,'complete',complete,'partial',partial,'due',due,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by task_type) value from task_rows group by scope_type,scope_key
    ), person_keys as (
      select distinct scope_type,scope_key,source_pcucode,source_pid from work_scoped
    ), follow_stat as (
      select p.scope_type,p.scope_key,
        count(*) filter(where f.status in ('open','in_progress'))::bigint open_count,
        count(*) filter(where f.status='done')::bigint done_count,
        count(*) filter(where f.status in ('open','in_progress') and f.priority='red')::bigint red_count,
        count(*) filter(where f.status in ('open','in_progress') and f.priority='orange')::bigint orange_count
      from person_keys p join public.screening_followups f on f.source_pcucode=p.source_pcucode and f.source_pid=p.source_pid
      group by p.scope_type,p.scope_key
    ), volunteer_rows as (
      select s.scope_type,s.scope_key,s.volunteer_pid,max(v.display_name) display_name,max(s.community) community,
        count(*)::bigint target,count(*) filter(where s.status='complete')::bigint complete,
        count(*) filter(where s.status='partial')::bigint partial,count(*) filter(where s.status='due')::bigint due
      from work_scoped s left join public.volunteers v on v.source_pid=s.volunteer_pid
      where s.volunteer_pid is not null group by s.scope_type,s.scope_key,s.volunteer_pid
    ), volunteer_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'volunteer_pid',volunteer_pid,'display_name',coalesce(display_name,'ไม่ระบุ'),'community',coalesce(nullif(btrim(community),''),'ยังไม่ระบุชุมชน'),
        'target',target,'complete',complete,'partial',partial,'due',due,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by (case when target>0 then complete*100.0/target else 0 end),display_name) value
      from volunteer_rows group by scope_type,scope_key
    ), community_rows as (
      select scope_type,scope_key,community,count(*)::bigint target,
        count(*) filter(where status='complete')::bigint complete,count(*) filter(where status='partial')::bigint partial,
        count(*) filter(where status='due')::bigint due,count(distinct volunteer_pid) filter(where volunteer_pid is not null)::bigint volunteers
      from work_scoped group by scope_type,scope_key,community
    ), community_json as (
      select scope_type,scope_key,jsonb_agg(jsonb_build_object(
        'community',coalesce(nullif(btrim(community),''),'ยังไม่ระบุชุมชน'),'target',target,'complete',complete,'partial',partial,'due',due,'volunteers',volunteers,
        'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
      ) order by (case when target>0 then complete*100.0/target else 0 end),community) value
      from community_rows group by scope_type,scope_key
    )
    insert into public.report_snapshot_cache_v2031(generation,report_key,scope_type,scope_key,payload,generated_at)
    select v_generation,'field',b.scope_type,b.scope_key,jsonb_build_object(
      'period_start',private.field_period_start_v200(),'period_mode',private.field_period_mode_v200(),
      'target_tasks',coalesce(b.total,0),'complete_tasks',coalesce(b.complete,0),'partial_tasks',coalesce(b.partial,0),'due_tasks',coalesce(b.due,0),
      'coverage_percent',case when coalesce(b.total,0)>0 then round(b.complete*100.0/b.total,1) else 0 end,
      'red_tasks',coalesce(b.red,0),'orange_tasks',coalesce(b.orange,0),
      'followup_open',coalesce(f.open_count,0),'followup_done',coalesce(f.done_count,0),
      'followup_red',coalesce(f.red_count,0),'followup_orange',coalesce(f.orange_count,0),
      'tasks',coalesce(t.value,'[]'::jsonb),'volunteers',coalesce(v.value,'[]'::jsonb),'communities',coalesce(c.value,'[]'::jsonb),
      'metric_note','เปอร์เซ็นต์รวมเป็น Operational Task Completion; ไม่ใช้แทน KPI HDC ทางการ และรายการติดตามไม่ถูกนำมาหัก Coverage'
    ),clock_timestamp()
    from base_summary b
    left join task_json t using(scope_type,scope_key)
    left join follow_stat f using(scope_type,scope_key)
    left join volunteer_json v using(scope_type,scope_key)
    left join community_json c using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;


    -- Fail closed: a new generation is never published with mismatched NCD totals.
    if not coalesce((private.ncd_integrity_v2176(v_generation)->>'passed')::boolean,false) then
      raise exception 'NCD_INTEGRITY_FAILED: %',private.ncd_integrity_v2176(v_generation);
    end if;
    insert into private.ncd_integrity_runs_v2176(generation,passed,details)
    values(v_generation,true,private.ncd_integrity_v2176(v_generation));
    update public.report_snapshot_cache_v2031 set payload=payload||jsonb_build_object(
      'ncd_integrity',jsonb_build_object('passed',true,'checked_at',clock_timestamp(),'version','2.0.176'),
      'ncd_activity',private.ncd_activity_v2176(scope_type,scope_key))
    where generation=v_generation;

    update public.report_snapshot_runs_v2031 set status='success',finished_at=clock_timestamp(),
      duration_ms=round(extract(epoch from (clock_timestamp()-v_started))*1000),cache_rows=v_rows
    where id=v_generation;
    update public.report_snapshot_state_v2031 set current_generation=v_generation,generated_at=clock_timestamp(),
      status='ready',last_reason=v_reason,last_error='' where singleton=true;

    -- Requests pending before this snapshot began are included.
    -- Later changes remain pending for the next refresh.
    update public.report_refresh_requests_v2031
    set processed_at=clock_timestamp(),result_status='success'
    where processed_at is null and requested_at<=v_started;


    -- Persist the nightly outcome independently of four-generation cache pruning.
    if v_reason='nightly_00_05_bangkok' then
      insert into private.nightly_snapshot_outcomes_v2077
        (day_bkk,status,started_at,finished_at,generation,cache_rows,error_message)
      values ((v_started at time zone 'Asia/Bangkok')::date,'success',v_started,
        clock_timestamp(),v_generation,v_rows,null)
      on conflict(day_bkk) do update set
        status='success',started_at=excluded.started_at,
        finished_at=excluded.finished_at,generation=excluded.generation,
        cache_rows=excluded.cache_rows,error_message=null,checked_at=clock_timestamp();
    end if;

    -- Retain the current and three previous successful cache generations only.
    -- Failed/running run metadata is kept for diagnosis; FK cascade removes only redundant derived cache.
    delete from public.report_snapshot_runs_v2031 r
    where r.status='success'
      and r.id <> (select current_generation from public.report_snapshot_state_v2031 where singleton=true)
      and r.id not in (
        select id from public.report_snapshot_runs_v2031
        where status='success' order by finished_at desc nulls last limit 4
      );

    return jsonb_build_object('ok',true,'status','ready','generation',v_generation,'cache_rows',v_rows,
      'duration_ms',round(extract(epoch from (clock_timestamp()-v_started))*1000),'generated_at',clock_timestamp(),'version','2.0.31');
  exception when others then
    insert into private.ncd_integrity_runs_v2176(generation,passed,details) values(v_generation,false,jsonb_build_object('passed',false,'checked_at',clock_timestamp(),'cause',left(sqlerrm,500)));
    update public.report_snapshot_runs_v2031 set status='failed',finished_at=clock_timestamp(),
      duration_ms=round(extract(epoch from (clock_timestamp()-v_started))*1000),error_message=left(sqlerrm,500)
    where id=v_generation;
    update public.report_snapshot_state_v2031 set status=case when current_generation is null then 'failed' else 'ready' end,
      last_reason=v_reason,last_error=left(sqlerrm,500) where singleton=true;
    if v_reason='nightly_00_05_bangkok' then
      insert into private.nightly_snapshot_outcomes_v2077
        (day_bkk,status,started_at,finished_at,generation,cache_rows,error_message)
      values ((v_started at time zone 'Asia/Bangkok')::date,'failed',v_started,
        clock_timestamp(),v_generation,0,left(sqlerrm,500))
      on conflict(day_bkk) do update set
        status='failed',started_at=excluded.started_at,
        finished_at=excluded.finished_at,generation=excluded.generation,
        cache_rows=excluded.cache_rows,error_message=excluded.error_message,
        checked_at=clock_timestamp();
    end if;
    return jsonb_build_object('ok',false,'status','failed','error',left(sqlerrm,500),'version','2.0.31');
  end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.telegram_summary_metrics_20261016(p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_at timestamptz:=least(p_as_of,now());
 v_day date;
 v_start timestamptz;
 v_result jsonb;
 v_noon jsonb;
BEGIN
 IF coalesce(auth.role(),'')<>'service_role' THEN RAISE EXCEPTION 'SERVICE_ROLE_REQUIRED' USING ERRCODE='42501'; END IF;
 IF NOT coalesce((private.ncd_integrity_v2176((select current_generation from public.report_snapshot_state_v2031 where singleton))->>'passed')::boolean,false) THEN RAISE EXCEPTION 'NCD_INTEGRITY_FAILED'; END IF;
 v_day:=(v_at AT TIME ZONE 'Asia/Bangkok')::date;
 v_start:=v_day::timestamp AT TIME ZONE 'Asia/Bangkok';
 SELECT jsonb_build_object(
 'as_of',v_at,'day',v_day,'timezone','Asia/Bangkok',
 'houses_added',(
 SELECT count(*) FROM public.houses h
 WHERE h.field_created_at>=v_start AND h.field_created_at<=v_at
 AND h.superseded_by IS NULL AND h.superseded_at IS NULL
 AND h.verification_status='verified_jhcis'),
 'members_completed',(
 SELECT count(DISTINCT (r.linked_person_pcucode,r.linked_person_id))
 FROM public.household_member_requests r
 WHERE r.reviewed_at>=v_start AND r.reviewed_at<=v_at
 AND r.status='verified' AND r.linked_person_id IS NOT NULL AND r.linked_person_pcucode IS NOT NULL),
 'ncd_screened',(
 SELECT count(DISTINCT (n.source_pcucode,n.source_pid)) FROM public.health_ncd_screenings n
 JOIN public.health_persons p USING(source_pcucode,source_pid)
 JOIN public.health_screening_target_cache_v2030 c USING(source_pcucode,source_pid)
 WHERE c.ncd_target AND coalesce(n.record_mode,'production')='production' AND n.screened_on=v_day AND n.recorded_at<=v_at AND p.active
 AND p.service_population_eligible AND p.jhcis_typelive IN(1,3) AND date_part('year',age(v_day,p.birth_date))>=35),
 'ncd_abnormal',(
 SELECT count(DISTINCT (n.source_pcucode,n.source_pid)) FROM public.health_ncd_screenings n
 JOIN public.health_persons p USING(source_pcucode,source_pid)
 JOIN public.health_screening_target_cache_v2030 c USING(source_pcucode,source_pid)
 WHERE c.ncd_target AND coalesce(n.record_mode,'production')='production' AND n.screened_on=v_day AND n.recorded_at<=v_at AND p.active
 AND p.service_population_eligible AND p.jhcis_typelive IN(1,3) AND date_part('year',age(v_day,p.birth_date))>=35
 AND n.severity IN('risk','alert','urgent')),
 'elderly_abnormal',(
 SELECT count(DISTINCT (e.source_pcucode,e.source_pid))
 FROM public.elderly9_domain_results e JOIN public.screening_sessions s ON s.id=e.session_id
 JOIN public.health_persons p ON p.source_pcucode=e.source_pcucode AND p.source_pid=e.source_pid
 WHERE s.screening_date=v_day AND e.assessed_at<=v_at AND e.status='observation'
 AND p.active AND p.service_population_eligible AND p.jhcis_typelive IN(1,3)),
 'pending_houses',(
 SELECT count(*) FROM public.houses h WHERE h.superseded_by IS NULL
 AND h.verification_status NOT IN('verified_jhcis','rejected')),
 'pending_members',(
 SELECT count(*) FROM public.household_member_requests r
 JOIN public.houses h ON h.id=r.house_id
 WHERE r.status IN('pending','needs_correction','verified')
 AND r.linked_person_id IS NULL AND r.linked_person_pcucode IS NULL
 AND r.jhcis_verification_status<>'verified_jhcis'),
 'nightly',coalesce((
 SELECT jsonb_build_object('status',o.status,'started_at',o.started_at,'finished_at',o.finished_at)
 FROM private.nightly_snapshot_outcomes_v2077 o WHERE o.day_bkk=v_day),'{"status":"missing"}'::jsonb),
 'counting_basis','บ้านภาคสนามยืนยันแล้ว; สมาชิกคือคำขอที่เชื่อมสำเร็จ; คัดกรองวันที่วันนี้; ผิดปกติ NCD=risk/alert/urgent, elderly=observation; งานค้าง ณ เวลาตรวจ'
 ) INTO v_result;
 SELECT snapshot INTO v_noon FROM private.telegram_summary_deliveries_20261016
 WHERE summary_date=v_day AND period='noon' AND status='sent';
 RETURN v_result||jsonb_build_object('noon_baseline',v_noon);
END;
$function$
;

select cron.schedule('ncd-integrity-v2176','35 0 * * *','select private.monitor_ncd_integrity_v2176();');
select cron.schedule('report-0730-bangkok-v2176','30 0 * * *',$cron$select private.refresh_report_snapshots_v2031('daily_07_30_bangkok');$cron$);
