-- v1.8.1 follow-up: choose the truly latest previous screening by date.
-- If JHCIS and OSM Plus have the same date, OSM Plus wins because it has
-- the richer behavior-frequency details captured by this application.
create or replace view public.health_person_worklist
with (security_invoker=true)
as
with base as (
  select p.*,h.house_no,h.moo,h.community,h.volunteer_pid,
    case when p.birth_date is null then null else extract(year from age(current_date,p.birth_date))::integer end as age_years
  from public.health_persons p
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where p.active=true
), latest as (
  select * from public.health_ncd_latest
), fy as (
  select case when extract(month from current_date)>=10
    then make_date(extract(year from current_date)::integer,10,1)
    else make_date(extract(year from current_date)::integer-1,10,1) end as fy_start
), ranked as (
  select b.*,l.screened_on as app_screened_on,l.ncd_status as app_ncd_status,l.severity as app_severity,
         l.weight_kg as app_weight_kg,l.height_cm as app_height_cm,l.waist_cm as app_waist_cm,
         l.sbp as app_sbp,l.dbp as app_dbp,l.glucose_mg_dl as app_glucose_mg_dl,l.bmi as app_bmi,
         l.smoker as app_smoker,l.alcohol_risk as app_alcohol_risk,l.exercise_sufficient as app_exercise_sufficient,
         l.smoking_frequency as app_smoking_frequency,l.alcohol_frequency as app_alcohol_frequency,l.exercise_frequency as app_exercise_frequency,
         case when l.screened_on is not null and (b.previous_screened_on is null or l.screened_on>=b.previous_screened_on) then true else false end as app_is_latest
  from base b
  left join latest l on l.source_pcucode=b.source_pcucode and l.source_pid=b.source_pid
)
select r.source_pcucode,r.source_pid,r.house_pcucode,r.hcode,r.house_no,r.moo,r.community,r.volunteer_pid,
  r.display_name,r.gender,r.birth_date,r.age_years,
  case when r.age_years is null then 'เนเธกเนเธ—เธฃเธฒเธ'
       when r.age_years<=5 then 'เน€เธ”เนเธเธเธเธกเธงเธฑเธข'
       when r.age_years<=14 then 'เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ'
       when r.age_years<=24 then 'เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ'
       when r.age_years<=59 then 'เธงเธฑเธขเธ—เธณเธเธฒเธ'
       else 'เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' end as life_stage,
  r.has_ht,r.has_dm,(r.has_ht or r.has_dm) as known_ncd,
  (r.age_years>=35 and not (r.has_ht or r.has_dm)) as ncd_target,
  case when r.app_is_latest then r.app_screened_on else r.previous_screened_on end as latest_screened_on,
  case when r.app_is_latest then r.app_ncd_status
       when r.previous_screened_on is not null then 'เธกเธตเธเธฃเธฐเธงเธฑเธ•เธดเธเธฑเธ”เธเธฃเธญเธเนเธ JHCIS'
       else null end as latest_ncd_status,
  case when r.app_is_latest then r.app_severity else null end as latest_severity,
  case when greatest(coalesce(r.app_screened_on,date '1900-01-01'),coalesce(r.previous_screened_on,date '1900-01-01'))>=fy.fy_start then true else false end as screened_current_fy,
  case when r.app_is_latest then r.app_screened_on else r.previous_screened_on end as previous_screened_on,
  case when r.app_is_latest then r.app_weight_kg else r.previous_weight_kg end as previous_weight_kg,
  case when r.app_is_latest then r.app_height_cm else r.previous_height_cm end as previous_height_cm,
  case when r.app_is_latest then r.app_waist_cm else r.previous_waist_cm end as previous_waist_cm,
  case when r.app_is_latest then r.app_sbp else r.previous_sbp end as previous_sbp,
  case when r.app_is_latest then r.app_dbp else r.previous_dbp end as previous_dbp,
  case when r.app_is_latest then r.app_glucose_mg_dl else r.previous_glucose_mg_dl end as previous_glucose_mg_dl,
  case when r.app_is_latest then r.app_bmi else r.previous_bmi end as previous_bmi,
  case when r.app_is_latest then 'เธญเธชเธก. เธเธฅเธฑเธช'
       when r.previous_screened_on is not null then coalesce(nullif(r.previous_source,''),'JHCIS') else '' end as previous_source,
  case when r.app_is_latest then coalesce(nullif(r.app_smoking_frequency,''),case when r.app_smoker then 'เธชเธนเธ' else 'เนเธกเนเธชเธนเธ' end) else '' end as previous_smoking,
  case when r.app_is_latest then coalesce(nullif(r.app_alcohol_frequency,''),case when r.app_alcohol_risk then 'เธ”เธทเนเธก' else 'เนเธกเนเธ”เธทเนเธก' end) else '' end as previous_alcohol,
  case when r.app_is_latest then coalesce(nullif(r.app_exercise_frequency,''),case when r.app_exercise_sufficient then 'เน€เธเธตเธขเธเธเธญ' else 'เนเธกเนเน€เธเธตเธขเธเธเธญ' end) else '' end as previous_exercise
from ranked r
cross join fy;

grant select on public.health_person_worklist to authenticated;
