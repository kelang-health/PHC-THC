
begin;

create or replace view public.health_person_worklist_active_v1841 as
select
  w.source_pcucode,w.source_pid,w.house_pcucode,w.hcode,w.house_no,w.moo,w.community,w.volunteer_pid,
  w.display_name,w.gender,w.birth_date,w.age_years,w.life_stage,w.has_ht,w.has_dm,w.known_ncd,w.ncd_target,
  w.latest_screened_on,w.latest_ncd_status,w.latest_severity,w.screened_current_fy,
  w.previous_screened_on,w.previous_weight_kg,w.previous_height_cm,w.previous_waist_cm,
  w.previous_sbp,w.previous_dbp,w.previous_glucose_mg_dl,w.previous_bmi,w.previous_source,
  w.previous_smoking,w.previous_alcohol,w.previous_exercise,
  p.jhcis_typelive,
  coalesce(s.field_status,'unverified'::text) as residence_status,
  coalesce(s.review_state,'none'::text) as residence_review_state,
  coalesce(s.service_target_active,true) as service_target_active
from public.health_person_worklist w
join public.health_persons p
  on p.source_pcucode=w.source_pcucode and p.source_pid=w.source_pid
left join public.health_person_residence_status s
  on s.source_pcucode=w.source_pcucode and s.source_pid=w.source_pid
where p.service_population_eligible=true;

create or replace view public.health_screening_target_worklist_v2026 as
select
  p.source_pcucode,p.source_pid,p.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
  p.display_name,p.gender,p.birth_date,pl.age_years,
  case
    when pl.age_years<=5 then 'เน€เธ”เนเธเธเธเธกเธงเธฑเธข'::text
    when pl.age_years<=14 then 'เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ'::text
    when pl.age_years<=24 then 'เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ'::text
    when pl.age_years<=59 then 'เธงเธฑเธขเธ—เธณเธเธฒเธ'::text
    else 'เธเธนเนเธชเธนเธเธญเธฒเธขเธธ'::text
  end as life_stage,
  p.has_ht,p.has_dm,(p.has_ht or p.has_dm) as known_ncd,
  (pl.age_years>=35 and not (p.has_ht or p.has_dm)) as ncd_target,
  p.previous_screened_on as latest_screened_on,
  case when p.previous_screened_on is not null then 'เธกเธตเธเธฃเธฐเธงเธฑเธ•เธดเธเธฑเธ”เธเธฃเธญเธเน€เธ”เธดเธก'::text else null::text end as latest_ncd_status,
  null::text as latest_severity,
  false as screened_current_fy,
  p.previous_screened_on,p.previous_weight_kg,p.previous_height_cm,p.previous_waist_cm,
  p.previous_sbp,p.previous_dbp,p.previous_glucose_mg_dl,p.previous_bmi,p.previous_source,
  ''::text as previous_smoking,''::text as previous_alcohol,''::text as previous_exercise,
  p.has_cvd,p.cvd_population_eligible,
  pl.plan_date as screening_plan_date,pl.age_months as screening_age_months,
  pl.route as screening_route,pl.route_label as screening_route_label,
  pl.dspm_target_months as screening_dspm_target_months,
  pl.target_enabled as field_target_enabled,pl.updated_at as screening_plan_updated_at
from public.health_screening_plan_v2023 pl
join public.health_persons p
  on p.source_pcucode=pl.source_pcucode and p.source_pid=pl.source_pid
join public.houses h
  on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
left join public.health_person_residence_status rs
  on rs.source_pcucode=p.source_pcucode and rs.source_pid=p.source_pid
where p.active=true
  and p.service_population_eligible=true
  and pl.target_enabled=true;

insert into public.app_settings(key,value)
values(
  'jhcis_authoritative_population_policy_v2118',
  jsonb_build_object(
    'version','2.0.118',
    'rule','Cloud screening population follows active JHCIS typelive 1/3 + Thai service population; field residence reports remain review metadata until JHCIS is changed and synced',
    'residence_service_target_active_affects_worklist',false,
    'source_of_truth','jhcisdb'
  )
)
on conflict(key) do update set value=excluded.value,updated_at=now();

select public.refresh_screening_target_cache_v2030();
notify pgrst,'reload schema';
commit;
