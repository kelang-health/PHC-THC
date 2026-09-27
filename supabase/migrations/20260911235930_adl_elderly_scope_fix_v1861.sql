-- OSM-PHC v1.8.61 follow-up: HDC ADL grouping applies to elderly (60+) only.
-- Prevent younger historical SPECIALPP rows from inflating social/homebound/bedridden dashboard counts.
begin;

create or replace function public.care_dashboard_v1861(p_scope text default 'self')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_result jsonb;
  v_hdc jsonb:=null;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select p.role,p.community,p.volunteer_pid
    into v_role,v_community,v_pid
  from public.profiles p
  where p.user_id=v_uid and p.active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';
  elsif v_role='user' then v_scope:='self';
  elsif v_role='staff' and v_scope not in ('self','community') then v_scope:='self';
  end if;

  if v_role='admin' then
    select s.value into v_hdc
    from public.app_settings s
    where s.key='care_reference_hdc'
    limit 1;
  end if;

  with scoped_houses as (
    select h.*
    from public.houses h
    where
      v_role='admin'
      or (v_scope='self' and v_pid is not null and h.volunteer_pid=v_pid)
      or (v_role='staff' and v_scope='community'
          and private.community_key(h.community)=private.community_key(v_community))
  ), scoped_people as (
    select w.*,p.is_student,p.is_disabled,p.service_population_eligible,
           p.adl_group_code,p.adl_assessed_on
    from public.health_person_worklist_active_v1847 w
    join public.health_persons p
      on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
    join scoped_houses h
      on h.source_pcucode=w.house_pcucode and h.hcode=w.hcode
  ), latest_2q as (
    select distinct on (s.source_pcucode,s.source_pid)
           s.source_pcucode,s.source_pid,s.mental_2q_status,s.mental_2q_result
    from public.health_ncd_screenings s
    join scoped_people p
      on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
     and p.service_population_eligible=true
    where coalesce(s.record_mode,'production')='production'
    order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
  ), hstat as (
    select count(*)::bigint houses,
           count(*) filter(where latitude is not null and longitude is not null)::bigint mapped_houses,
           count(*) filter(where latitude is null or longitude is null)::bigint missing_coordinates,
           count(*) filter(where review_required=true)::bigint review_houses
    from scoped_houses
  ), pstat as (
    select count(*)::bigint household_people,
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
    from scoped_people
  ), qstat as (
    select count(*) filter(where mental_2q_status='assessed')::bigint mental_2q_assessed,
           count(*) filter(where mental_2q_status='not_assessed')::bigint mental_2q_not_assessed,
           count(*) filter(where mental_2q_status='incomplete')::bigint mental_2q_incomplete,
           count(*) filter(where mental_2q_status='assessed' and mental_2q_result=true)::bigint mental_2q_positive
    from latest_2q
  )
  select jsonb_build_object(
    'version','1.8.61',
    'role',v_role,
    'scope',v_scope,
    'scope_label',case
      when v_role='admin' then 'เธ—เธธเธเธเธทเนเธเธ—เธตเนเธ•เธฒเธกเธชเธดเธ—เธเธดเนเธเธนเนเธ”เธนเนเธฅเธฃเธฐเธเธ'
      when v_role='staff' and v_scope='community' then 'เธเธธเธกเธเธ '||coalesce(v_community,'')
      else 'เธเนเธฒเธเนเธฅเธฐเธเธฃเธฐเธเธฒเธเธเธ—เธตเนเธเธฑเธเธฃเธฑเธเธเธดเธ”เธเธญเธ'
    end,
    'community',coalesce(v_community,''),
    'has_personal_scope',(v_pid is not null),
    'houses',coalesce(hstat.houses,0),
    'mapped_houses',coalesce(hstat.mapped_houses,0),
    'missing_coordinates',coalesce(hstat.missing_coordinates,0),
    'review_houses',coalesce(hstat.review_houses,0),
    'household_people',coalesce(pstat.household_people,0),
    'people',coalesce(pstat.service_people,0),
    'service_people',coalesce(pstat.service_people,0),
    'ncd_targets',coalesce(pstat.ncd_targets,0),
    'ncd_done',coalesce(pstat.ncd_done,0),
    'ncd_due',coalesce(pstat.ncd_due,0),
    'known_ncd',coalesce(pstat.known_ncd,0),
    'early_child',coalesce(pstat.early_child,0),
    'school_age',coalesce(pstat.school_age,0),
    'youth',coalesce(pstat.youth,0),
    'working_age',coalesce(pstat.working_age,0),
    'older_people',coalesce(pstat.older_people,0),
    'students',coalesce(pstat.students,0),
    'disabled_people',coalesce(pstat.disabled_people,0),
    'adl_assessed_people',coalesce(pstat.adl_assessed_people,0),
    'social_people',coalesce(pstat.social_people,0),
    'homebound_people',coalesce(pstat.homebound_people,0),
    'bedridden_people',coalesce(pstat.bedridden_people,0),
    'urgent_attention',coalesce(pstat.urgent_attention,0),
    'mental_2q_assessed',coalesce(qstat.mental_2q_assessed,0),
    'mental_2q_not_assessed',coalesce(qstat.mental_2q_not_assessed,0),
    'mental_2q_incomplete',coalesce(qstat.mental_2q_incomplete,0),
    'mental_2q_positive',coalesce(qstat.mental_2q_positive,0),
    'metric_sources',jsonb_build_object(
      'person_level','JHCIS read-only / J-Report operational definition',
      'service_population','typelive 1,3 + nation 99 + alive + non-00 village',
      'ncd','J-Report operational worklist; official HDC DM/HT denominators are separate',
      'adl','latest JHCIS f43specialpp 1B1280/1B1281/1B1282',
      'official_comparator','MoPH Open Data via hdc-app; aggregate only'
    ),
    'hdc_reference',case when v_role='admin' then v_hdc else null end
  ) into v_result
  from hstat cross join pstat cross join qstat;

  return v_result;
end;
$$;

comment on function public.care_dashboard_v1861(text) is
  'Role-scoped care dashboard v1.8.61. ADL social/homebound/bedridden counts are service-population elderly only and use latest SPECIALPP 1B1280/1B1281/1B1282.';

commit;
