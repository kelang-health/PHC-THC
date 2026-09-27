CREATE OR REPLACE FUNCTION private.refresh_report_snapshots_v2031(p_reason text DEFAULT 'manual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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
        ('community'::text,nullif(private.community_key(h.community),'')),
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
      select w.source_pcucode,w.source_pid,w.life_stage,w.ncd_target,w.screened_current_fy,w.known_ncd,w.latest_severity,
        p.is_student,p.is_disabled,p.service_population_eligible,p.adl_group_code,
        h.community,h.volunteer_pid
      from public.health_person_worklist_active_v1847 w
      join public.health_persons p on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
      join public.houses h on h.source_pcucode=w.house_pcucode and h.hcode=w.hcode and h.superseded_by is null and h.verification_status='verified_jhcis'
    ), person_scoped as materialized (
      select s.scope_type,s.scope_key,p.*
      from person_base p
      cross join lateral (values
        ('all'::text,'*'::text),
        ('community'::text,nullif(private.community_key(p.community),'')),
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
        count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข')::bigint early_child,
        count(*) filter(where service_population_eligible and life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ')::bigint school_age,
        count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ')::bigint youth,
        count(*) filter(where service_population_eligible and life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ')::bigint working_age,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ')::bigint older_people,
        count(*) filter(where service_population_eligible and is_student)::bigint students,
        count(*) filter(where service_population_eligible and is_disabled)::bigint disabled_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code<>'')::bigint adl_assessed_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1280')::bigint social_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1281')::bigint homebound_people,
        count(*) filter(where service_population_eligible and life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' and adl_group_code='1B1282')::bigint bedridden_people,
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
        ('community'::text,nullif(private.community_key(w.community),'')),
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
        'volunteer_pid',volunteer_pid,'display_name',coalesce(display_name,'เนเธกเนเธฃเธฐเธเธธ'),'community',community,
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
        'community',community,'target',target,'complete',complete,'partial',partial,'due',due,'volunteers',volunteers,
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
      'metric_note','เน€เธเธญเธฃเนเน€เธเนเธเธ•เนเธฃเธงเธกเน€เธเนเธ Operational Task Completion; เนเธกเนเนเธเนเนเธ—เธ KPI HDC เธ—เธฒเธเธเธฒเธฃ เนเธฅเธฐเธฃเธฒเธขเธเธฒเธฃเธ•เธดเธ”เธ•เธฒเธกเนเธกเนเธ–เธนเธเธเธณเธกเธฒเธซเธฑเธ Coverage'
    ),clock_timestamp()
    from base_summary b
    left join task_json t using(scope_type,scope_key)
    left join follow_stat f using(scope_type,scope_key)
    left join volunteer_json v using(scope_type,scope_key)
    left join community_json c using(scope_type,scope_key);
    get diagnostics v_added=row_count; v_rows:=v_rows+v_added;

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
$function$;
