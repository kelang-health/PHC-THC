-- OSM-PHC Cloud v2.0.0
-- Field Work & Reporting Center
-- Unified operational work items, role-based progress, follow-up closure,
-- export views for Local reporting, and drill-down from admin -> community -> VHV -> person.
-- JHCIS remains read-only. No citizen ID / phone / LINE ID is exposed by these views.

begin;

create or replace function private.field_period_start_v200()
returns date
language sql stable
set search_path=''
as $$
  select case
    when current_date < date '2026-10-01' then
      case when extract(month from current_date)>=10
        then make_date(extract(year from current_date)::integer,10,1)
        else make_date(extract(year from current_date)::integer-1,10,1)
      end
    else
      case when extract(month from current_date)>=10
        then greatest(make_date(extract(year from current_date)::integer,10,1),date '2026-10-01')
        else greatest(make_date(extract(year from current_date)::integer-1,10,1),date '2026-10-01')
      end
  end
$$;

revoke all on function private.field_period_start_v200() from public,anon,authenticated;

create or replace function private.field_period_mode_v200()
returns text
language sql stable
set search_path=''
as $$ select case when current_date < date '2026-10-01' then 'test' else 'production' end $$;

revoke all on function private.field_period_mode_v200() from public,anon,authenticated;

alter table public.screening_followups
  add column if not exists resolution_note text not null default '',
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists updated_at timestamptz not null default now();

-- One normalized row = one operational task for one person in the current work period.
create or replace view public.field_work_items_v200
with (security_invoker=true)
as
with cfg as (
  select private.field_period_start_v200() as period_start,
         private.field_period_mode_v200() as period_mode
), base as (
  select
    p.source_pcucode,p.source_pid,p.display_name,p.birth_date,
    extract(year from age(current_date,p.birth_date))::integer as age_years,
    ((extract(year from age(current_date,p.birth_date))::integer*12)+extract(month from age(current_date,p.birth_date))::integer) as age_months,
    h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
    p.has_ht,p.has_dm,p.service_population_eligible,p.ncd_base_eligible
  from public.health_persons p
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where p.active=true and p.service_population_eligible=true and p.birth_date is not null
), work as (
  -- Growth: operational completion only, not an official nutrition KPI.
  select b.*, 'growth'::text task_type,'เธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธ'::text task_label,'age_screening'::text task_group,
    case when g.id is not null then 'complete' else 'due' end::text as status,
    case when g.id is not null then 100 else 0 end::integer progress_percent,
    case when g.id is not null then 'normal' else 'yellow' end::text priority,
    g.screened_at as last_activity_at,g.screened_at as completed_at,
    cfg.period_start,cfg.period_mode
  from base b cross join cfg
  left join lateral (
    select x.id,x.screened_at from public.health_growth_screenings x
    where x.source_pcucode=b.source_pcucode and x.source_pid=b.source_pid
      and x.screened_at::date>=cfg.period_start
    order by x.screened_at desc limit 1
  ) g on true
  where b.age_years between 0 and 14

  union all

  -- Child development: operational completion if all 5 domains assessed in the latest record.
  select b.*, 'child_development'::text,'เธเธฑเธ’เธเธฒเธเธฒเธฃเน€เธ”เนเธ'::text,'age_screening'::text,
    case when d.id is null then 'due'
         when d.overall_status='incomplete' then 'partial'
         else 'complete' end::text,
    case when d.id is null then 0 else least(100,coalesce(d.assessed_domains,0)*20) end::integer,
    case when d.id is null then 'yellow'
         when d.overall_status='needs_further_assessment' then 'orange'
         when d.overall_status='incomplete' then 'yellow'
         else 'normal' end::text,
    d.screened_at,
    case when d.id is not null and d.overall_status<>'incomplete' then d.screened_at else null end,
    cfg.period_start,cfg.period_mode
  from base b cross join cfg
  left join lateral (
    select x.id,x.screened_at,x.overall_status,
      (select count(*)::integer from jsonb_each_text(coalesce(x.domains,'{}'::jsonb)) e where e.value in ('normal','observation')) as assessed_domains
    from public.child_development_screenings x
    where x.source_pcucode=b.source_pcucode and x.source_pid=b.source_pid
      and x.screened_at::date>=cfg.period_start
    order by x.screened_at desc limit 1
  ) d on true
  where b.age_years between 0 and 5

  union all

  -- NCD operational target follows synced J-Report/JHCIS eligibility.
  select b.*, 'ncd'::text,'เธเธฑเธ”เธเธฃเธญเธ NCD'::text,'ncd'::text,
    case when n.id is not null then 'complete' else 'due' end::text,
    case when n.id is not null then 100 else 0 end::integer,
    case when n.severity in ('urgent','alert') then 'red'
         when n.severity='risk' then 'yellow'
         when n.id is not null then 'normal'
         else 'yellow' end::text,
    n.recorded_at,
    case when n.id is not null then n.recorded_at else null end,
    cfg.period_start,cfg.period_mode
  from base b cross join cfg
  left join lateral (
    select x.id,x.recorded_at,x.severity
    from public.health_ncd_screenings x
    where x.source_pcucode=b.source_pcucode and x.source_pid=b.source_pid
      and x.screened_on>=cfg.period_start
      and (cfg.period_mode='test' or coalesce(x.record_mode,'production')='production')
    order by x.screened_on desc,x.recorded_at desc limit 1
  ) n on true
  where coalesce(b.ncd_base_eligible,(b.age_years>=35 and not (b.has_ht or b.has_dm)))=true

  union all

  -- Elderly 9 domains: complete only when all 9 domains are assessed.
  select b.*, 'elderly9'::text,'เธเธนเนเธชเธนเธเธญเธฒเธขเธธ 9 เธ”เนเธฒเธ'::text,'elderly'::text,
    case when es.id is null then 'due'
         when es.elderly9_status='complete' then 'complete'
         else 'partial' end::text,
    case when es.id is null then 0 else least(100,round(cardinality(coalesce(es.completed_domains,'{}'::text[]))*100.0/9)::integer) end,
    case when es.id is null then 'yellow'
         when coalesce(er.observations,0)>0 then 'orange'
         when es.elderly9_status='complete' then 'normal'
         else 'yellow' end::text,
    coalesce(er.last_assessed_at,es.updated_at),
    case when es.elderly9_status='complete' then coalesce(es.completed_at,es.updated_at) else null end,
    cfg.period_start,cfg.period_mode
  from base b cross join cfg
  left join lateral (
    select s.* from public.screening_sessions s
    where s.source_pcucode=b.source_pcucode and s.source_pid=b.source_pid
      and s.route='elderly_60_plus' and s.screening_date>=cfg.period_start
    order by s.screening_date desc,s.updated_at desc limit 1
  ) es on true
  left join lateral (
    select count(*) filter(where r.status='observation')::integer observations,
           max(r.assessed_at) last_assessed_at
    from public.elderly9_domain_results r
    where es.id is not null and r.session_id=es.id
  ) er on true
  where b.age_years>=60
)
select
  source_pcucode,source_pid,display_name,birth_date,age_years,age_months,
  hcode,house_no,moo,community,volunteer_pid,
  task_type,task_label,task_group,status,progress_percent,priority,
  last_activity_at,completed_at,period_start,period_mode
from work;

revoke all on table public.field_work_items_v200 from anon;

revoke insert,update,delete,truncate,references,trigger on table public.field_work_items_v200 from authenticated;

grant select on table public.field_work_items_v200 to authenticated;

-- Export projections. No CID, HN, phone, address or LINE ID.
create or replace view public.field_export_ncd_v200
with (security_invoker=true)
as
select s.id,s.screened_on,s.recorded_at,s.source_pcucode,s.source_pid,p.display_name,
       h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
       s.weight_kg,s.height_cm,s.waist_cm,s.bmi,s.sbp,s.dbp,s.glucose_mg_dl,s.glucose_type,
       s.ncd_status,s.severity,s.bp_status,s.glucose_status,
       s.mental_2q_status,s.mental_2q_result,s.cvd_risk_percent,s.cvd_risk_level,
       s.record_mode,s.calculation_version
from public.health_ncd_screenings s
join public.health_persons p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
join public.houses h on h.source_pcucode=s.house_pcucode and h.hcode=s.hcode;

grant select on public.field_export_ncd_v200 to authenticated;

create or replace view public.field_export_growth_v200
with (security_invoker=true)
as
select g.id,g.screened_at,g.source_pcucode,g.source_pid,p.display_name,
       h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
       g.age_months,g.weight_kg,g.height_cm,g.interpretation_code,g.reference_version
from public.health_growth_screenings g
join public.health_persons p on p.source_pcucode=g.source_pcucode and p.source_pid=g.source_pid
join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode;

grant select on public.field_export_growth_v200 to authenticated;

create or replace view public.field_export_child_dev_v200
with (security_invoker=true)
as
select d.id,d.screened_at,d.source_pcucode,d.source_pid,p.display_name,
       h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
       d.actual_age_months,d.reference_target_months,d.domains,d.overall_status,d.note
from public.child_development_screenings d
join public.health_persons p on p.source_pcucode=d.source_pcucode and p.source_pid=d.source_pid
join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode;

grant select on public.field_export_child_dev_v200 to authenticated;

create or replace view public.field_export_elderly9_v200
with (security_invoker=true)
as
select s.id as session_id,s.screening_date,s.source_pcucode,s.source_pid,p.display_name,
       h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
       s.ncd_status,s.elderly9_status,cardinality(coalesce(s.completed_domains,'{}'::text[])) as completed_domains,
       jsonb_object_agg(r.domain_code,r.status order by r.domain_code) filter(where r.domain_code is not null) as domains,
       count(*) filter(where r.status='observation')::integer as observations,
       max(r.assessed_at) as last_assessed_at
from public.screening_sessions s
join public.health_persons p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
left join public.elderly9_domain_results r on r.session_id=s.id
where s.route='elderly_60_plus'
group by s.id,s.screening_date,s.source_pcucode,s.source_pid,p.display_name,h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,s.ncd_status,s.elderly9_status,s.completed_domains;

grant select on public.field_export_elderly9_v200 to authenticated;

create or replace view public.field_export_followup_v200
with (security_invoker=true)
as
select f.id,f.created_at,f.updated_at,f.completed_at,f.source_pcucode,f.source_pid,p.display_name,
       h.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
       f.followup_type,f.domain_code,f.priority,f.status,f.summary,f.resolution_note
from public.screening_followups f
join public.health_persons p on p.source_pcucode=f.source_pcucode and p.source_pid=f.source_pid
join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode;

grant select on public.field_export_followup_v200 to authenticated;

-- Scoped dashboard: one contract for user / staff / admin.
create or replace function public.field_work_dashboard_v200(p_scope text default 'self')
returns jsonb
language plpgsql stable security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid(); v_role text; v_community text; v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self'))); v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,community,volunteer_pid into v_role,v_community,v_pid
  from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_role='admin' then v_scope:='all';
  elsif v_role='user' then v_scope:='self';
  elsif v_role='staff' and v_scope not in ('self','community') then v_scope:='self';
  end if;

  with scoped as (
    select w.* from public.field_work_items_v200 w
    where v_role='admin'
       or (v_scope='self' and v_pid is not null and w.volunteer_pid=v_pid)
       or (v_role='staff' and v_scope='community' and private.community_key(w.community)=private.community_key(v_community))
  ), base_summary as (
    select count(*)::bigint total,
           count(*) filter(where status='complete')::bigint complete,
           count(*) filter(where status='partial')::bigint partial,
           count(*) filter(where status='due')::bigint due,
           count(*) filter(where priority='red')::bigint red,
           count(*) filter(where priority='orange')::bigint orange
    from scoped
  ), task_rows as (
    select task_type,max(task_label) task_label,count(*)::bigint target,
           count(*) filter(where status='complete')::bigint complete,
           count(*) filter(where status='partial')::bigint partial,
           count(*) filter(where status='due')::bigint due
    from scoped group by task_type
  ), task_json as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'task_type',task_type,'task_label',task_label,'target',target,'complete',complete,'partial',partial,'due',due,
      'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
    ) order by task_type),'[]'::jsonb) value from task_rows
  ), person_keys as (
    select distinct source_pcucode,source_pid from scoped
  ), follow_stat as (
    select count(*) filter(where f.status in ('open','in_progress'))::bigint open_count,
           count(*) filter(where f.status='done')::bigint done_count,
           count(*) filter(where f.status in ('open','in_progress') and f.priority='red')::bigint red_count,
           count(*) filter(where f.status in ('open','in_progress') and f.priority='orange')::bigint orange_count
    from public.screening_followups f
    join person_keys p on p.source_pcucode=f.source_pcucode and p.source_pid=f.source_pid
  ), volunteer_rows as (
    select s.volunteer_pid,max(v.display_name) display_name,max(s.community) community,
           count(*)::bigint target,count(*) filter(where s.status='complete')::bigint complete,
           count(*) filter(where s.status='partial')::bigint partial,
           count(*) filter(where s.status='due')::bigint due
    from scoped s left join public.volunteers v on v.source_pid=s.volunteer_pid
    where s.volunteer_pid is not null group by s.volunteer_pid
  ), volunteer_json as (
    select case when v_role in ('staff','admin') then coalesce(jsonb_agg(jsonb_build_object(
      'volunteer_pid',volunteer_pid,'display_name',coalesce(display_name,'เนเธกเนเธฃเธฐเธเธธ'),'community',community,
      'target',target,'complete',complete,'partial',partial,'due',due,
      'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
    ) order by (case when target>0 then complete*100.0/target else 0 end),display_name),'[]'::jsonb) else '[]'::jsonb end value
    from volunteer_rows
  ), community_rows as (
    select community,count(*)::bigint target,count(*) filter(where status='complete')::bigint complete,
           count(*) filter(where status='partial')::bigint partial,count(*) filter(where status='due')::bigint due,
           count(distinct volunteer_pid) filter(where volunteer_pid is not null)::bigint volunteers
    from scoped group by community
  ), community_json as (
    select case when v_role='admin' then coalesce(jsonb_agg(jsonb_build_object(
      'community',community,'target',target,'complete',complete,'partial',partial,'due',due,'volunteers',volunteers,
      'percent',case when target>0 then round(complete*100.0/target,1) else 0 end
    ) order by (case when target>0 then complete*100.0/target else 0 end),community),'[]'::jsonb) else '[]'::jsonb end value
    from community_rows
  )
  select jsonb_build_object(
    'version','2.0.0','role',v_role,'scope',v_scope,
    'scope_label',case when v_role='admin' then 'เธ—เธธเธเธเธธเธกเธเธ'
      when v_role='staff' and v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      else 'เธเธฒเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' end,
    'period_start',private.field_period_start_v200(),'period_mode',private.field_period_mode_v200(),
    'target_tasks',coalesce(b.total,0),'complete_tasks',coalesce(b.complete,0),'partial_tasks',coalesce(b.partial,0),'due_tasks',coalesce(b.due,0),
    'coverage_percent',case when coalesce(b.total,0)>0 then round(b.complete*100.0/b.total,1) else 0 end,
    'red_tasks',coalesce(b.red,0),'orange_tasks',coalesce(b.orange,0),
    'followup_open',coalesce(f.open_count,0),'followup_done',coalesce(f.done_count,0),'followup_red',coalesce(f.red_count,0),'followup_orange',coalesce(f.orange_count,0),
    'tasks',t.value,'volunteers',vj.value,'communities',cj.value,
    'metric_note','เน€เธเธญเธฃเนเน€เธเนเธเธ•เนเธฃเธงเธกเน€เธเนเธ Operational Task Completion; เนเธกเนเนเธเนเนเธ—เธ KPI HDC เธ—เธฒเธเธเธฒเธฃ เนเธฅเธฐเธฃเธฒเธขเธเธฒเธฃเธ•เธดเธ”เธ•เธฒเธกเนเธกเนเธ–เธนเธเธเธณเธกเธฒเธซเธฑเธ Coverage'
  ) into v_result
  from base_summary b cross join task_json t cross join follow_stat f cross join volunteer_json vj cross join community_json cj;
  return v_result;
end;
$$;

revoke all on function public.field_work_dashboard_v200(text) from public,anon;

grant execute on function public.field_work_dashboard_v200(text) to authenticated;

create or replace function public.field_work_list_v200(
  p_scope text default 'self',p_task_type text default '',p_status text default '',p_volunteer_pid bigint default null,
  p_community text default '',p_limit integer default 100,p_offset integer default 0
)
returns table(
  source_pcucode text,source_pid bigint,display_name text,age_years integer,hcode text,house_no text,moo text,community text,volunteer_pid bigint,
  task_type text,task_label text,status text,progress_percent integer,priority text,last_activity_at timestamptz,completed_at timestamptz
)
language plpgsql stable security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid();v_role text;v_community text;v_pid bigint;v_scope text:=lower(btrim(coalesce(p_scope,'self')));
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select role,profiles.community,profiles.volunteer_pid into v_role,v_community,v_pid from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if v_role='admin' then v_scope:='all'; elsif v_role='user' then v_scope:='self'; elsif v_role='staff' and v_scope not in ('self','community') then v_scope:='self'; end if;
  return query
  select w.source_pcucode,w.source_pid,w.display_name,w.age_years,w.hcode,w.house_no,w.moo,w.community,w.volunteer_pid,
         w.task_type,w.task_label,w.status,w.progress_percent,w.priority,w.last_activity_at,w.completed_at
  from public.field_work_items_v200 w
  where (v_role='admin' or (v_scope='self' and v_pid is not null and w.volunteer_pid=v_pid)
        or (v_role='staff' and v_scope='community' and private.community_key(w.community)=private.community_key(v_community)))
    and (coalesce(btrim(p_task_type),'')='' or w.task_type=p_task_type)
    and (coalesce(btrim(p_status),'')='' or w.status=p_status)
    and (p_volunteer_pid is null or w.volunteer_pid=p_volunteer_pid)
    and (coalesce(btrim(p_community),'')='' or private.community_key(w.community)=private.community_key(p_community))
  order by case w.priority when 'red' then 0 when 'orange' then 1 when 'yellow' then 2 else 3 end,
           case w.status when 'due' then 0 when 'partial' then 1 else 2 end,w.community,w.house_no,w.display_name,w.task_type
  limit least(greatest(coalesce(p_limit,100),1),1000) offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on function public.field_work_list_v200(text,text,text,bigint,text,integer,integer) from public,anon;

grant execute on function public.field_work_list_v200(text,text,text,bigint,text,integer,integer) to authenticated;

create or replace function public.update_screening_followup_v200(p_id uuid,p_status text,p_resolution_note text default '')
returns jsonb language plpgsql security definer set search_path=''
as $$
declare f public.screening_followups%rowtype;v_status text:=lower(btrim(coalesce(p_status,'')));
begin
  if auth.uid() is null or private.current_role() not in ('staff','admin') then raise exception 'STAFF_OR_ADMIN_REQUIRED'; end if;
  if v_status not in ('open','in_progress','done','cancelled') then raise exception 'INVALID_FOLLOWUP_STATUS'; end if;
  select * into f from public.screening_followups where id=p_id for update;
  if not found then raise exception 'FOLLOWUP_NOT_FOUND'; end if;
  if private.current_role()<>'admin' and not private.health_can_access_person(f.source_pcucode,f.source_pid) then raise exception 'FOLLOWUP_OUT_OF_SCOPE'; end if;
  update public.screening_followups set status=v_status,resolution_note=left(btrim(coalesce(p_resolution_note,'')),500),updated_by=auth.uid(),updated_at=now(),
    completed_at=case when v_status='done' then coalesce(completed_at,now()) when v_status in ('open','in_progress') then null else completed_at end
  where id=p_id returning * into f;
  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,source_pid,severity,details)
  values(auth.uid(),'UPDATE','screening_followup',f.id::text,f.source_pcucode,f.source_pid,f.priority,
         jsonb_build_object('status',f.status,'resolution_note_set',coalesce(f.resolution_note,'')<>''));
  return jsonb_build_object('ok',true,'id',f.id,'status',f.status,'completed_at',f.completed_at);
end;
$$;

revoke all on function public.update_screening_followup_v200(uuid,text,text) from public,anon;

grant execute on function public.update_screening_followup_v200(uuid,text,text) to authenticated;

insert into public.app_settings(key,value)
values('field_work_reporting_v200',jsonb_build_object(
  'version','2.0.0','name','Field Work & Reporting Center','go_live_date','2026-10-01',
  'task_types',jsonb_build_array('growth','child_development','ncd','elderly9'),
  'overall_metric','operational_task_completion','followup_separate_from_coverage',true,
  'role_drilldown','admin -> community -> volunteer -> person; staff -> volunteer -> person; user -> own work',
  'exports','Local XLSX via privacy-scoped export views','jhcis_write_back',false,'citizen_id_exported',false
)) on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
