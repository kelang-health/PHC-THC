-- OSM-PHC v1.8.4 โ€” Legacy Smart NCD Care D integration
-- Preserves useful screening history and rule metadata without restoring the
-- legacy plaintext user/password model. JHCIS remains read-only.
begin;

create table if not exists public.health_screening_rules (
  id bigint primary key,
  category text not null,
  code text not null unique,
  min_value numeric not null,
  max_value numeric not null,
  result text not null,
  risk_level text not null default '',
  color text not null default '',
  followup_month integer,
  refer_recommended boolean not null default false,
  priority text not null default '',
  advice text not null default '',
  source text not null default 'Smart NCD Care D legacy',
  active boolean not null default true,
  use_for_calculation boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.health_screening_rules enable row level security;

revoke all on public.health_screening_rules from public,anon,authenticated;

grant select on public.health_screening_rules to authenticated;

drop policy if exists health_screening_rules_select on public.health_screening_rules;

create policy health_screening_rules_select on public.health_screening_rules
for select to authenticated using (active=true);

insert into public.health_screening_rules
(id,category,code,min_value,max_value,result,risk_level,color,followup_month,refer_recommended,priority,advice,use_for_calculation)
values
(1,'BMI','BMI01',0,18.5,'เธเธญเธกเน€เธเธดเธเนเธ','เธ•เนเธณ','primary',6,false,'Low','เธเนเธณเธซเธเธฑเธเธเนเธญเธขเธเธงเนเธฒเธเธเธ•เธด เธเธงเธฃเธฃเธฑเธเธเธฃเธฐเธ—เธฒเธเธญเธฒเธซเธฒเธฃเธเธฃเธ 5 เธซเธกเธนเน เน€เธเธดเนเธกเนเธเธฃเธ•เธตเธ เนเธฅเธฐเธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธขเน€เธชเธฃเธดเธกเธชเธฃเนเธฒเธเธเธฅเนเธฒเธกเน€เธเธทเนเธญ',true),
(2,'BMI','BMI02',18.51,22.9,'เธเนเธณเธซเธเธฑเธเธเธเธ•เธด','เธเธเธ•เธด','success',12,false,'Low','เธเนเธณเธซเธเธฑเธเน€เธซเธกเธฒเธฐเธชเธก เธเธงเธฃเธฃเธฑเธเธฉเธฒเธเธคเธ•เธดเธเธฃเธฃเธกเธชเธธเธเธ เธฒเธเธ—เธตเนเธ”เธต',true),
(3,'BMI','BMI03',23,24.9,'เธเนเธณเธซเธเธฑเธเน€เธเธดเธ','เน€เธชเธตเนเธขเธ','warning',6,false,'Medium','เธเธงเธเธเธธเธกเธญเธฒเธซเธฒเธฃเนเธฅเธฐเน€เธเธดเนเธกเธเธดเธเธเธฃเธฃเธกเธ—เธฒเธเธเธฒเธข',true),
(4,'BMI','BMI04',25,29.9,'เธญเนเธงเธ','เธชเธนเธ','danger',3,false,'High','เธฅเธ”เธเนเธณเธซเธเธฑเธ เธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธขเธชเธกเนเธณเน€เธชเธกเธญ',true),
(5,'BMI','BMI05',30,99,'เธญเนเธงเธเธกเธฒเธ','เธชเธนเธเธกเธฒเธ','danger',1,true,'High','เธเธงเธฃเธเธฃเธถเธเธฉเธฒเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธชเธฒเธเธฒเธฃเธ“เธชเธธเธ',true),
(6,'WAIST_MALE','WM01',0,90,'เธฃเธญเธเน€เธญเธงเธเธเธ•เธด','เธเธเธ•เธด','success',12,false,'Low','เธฃเธฑเธเธเธฃเธฐเธ—เธฒเธเธญเธฒเธซเธฒเธฃเน€เธซเธกเธฒเธฐเธชเธก เธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธขเธญเธขเนเธฒเธเธเนเธญเธข 30 เธเธฒเธ—เธตเธ•เนเธญเธงเธฑเธ',true),
(7,'WAIST_MALE','WM02',90.01,999,'เธฃเธญเธเน€เธญเธงเน€เธเธดเธ','เธชเธนเธ','danger',3,false,'High','เธเธงเธเธเธธเธกเธญเธฒเธซเธฒเธฃ เธฅเธ”เนเธเธกเธฑเธ เธฅเธ”เธเนเธณเธ•เธฒเธฅ เนเธฅเธฐเธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธข',true),
(8,'WAIST_FEMALE','WF01',0,80,'เธฃเธญเธเน€เธญเธงเธเธเธ•เธด','เธเธเธ•เธด','success',12,false,'Low','เธฃเธฑเธเธเธฃเธฐเธ—เธฒเธเธญเธฒเธซเธฒเธฃเน€เธซเธกเธฒเธฐเธชเธก เธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธขเธญเธขเนเธฒเธเธเนเธญเธข 30 เธเธฒเธ—เธตเธ•เนเธญเธงเธฑเธ',true),
(9,'WAIST_FEMALE','WF02',80.01,999,'เธฃเธญเธเน€เธญเธงเน€เธเธดเธ','เธชเธนเธ','danger',3,false,'High','เธเธงเธเธเธธเธกเธญเธฒเธซเธฒเธฃ เธฅเธ”เนเธเธกเธฑเธ เธฅเธ”เธเนเธณเธ•เธฒเธฅ เนเธฅเธฐเธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธข',true),
(10,'WHtR','WH01',0,0.39,'เธเนเธญเธเธเนเธฒเธเธเธญเธก','เธ•เนเธณ','primary',12,false,'Low','เนเธกเนเธกเธตเธ เธฒเธงเธฐเธญเนเธงเธเธฅเธเธเธธเธ',true),
(11,'WHtR','WH02',0.4,0.49,'เธชเธกเธชเนเธงเธ','เธเธเธ•เธด','success',12,false,'Low','เธฃเธฑเธเธฉเธฒเธเธคเธ•เธดเธเธฃเธฃเธกเธชเธธเธเธ เธฒเธเธ—เธตเนเธ”เธต',true),
(12,'WHtR','WH03',0.5,0.59,'เธญเนเธงเธเธฅเธเธเธธเธ','เธชเธนเธ','warning',3,false,'Medium','เธเธงเธเธเธธเธกเธญเธฒเธซเธฒเธฃเนเธฅเธฐเธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธข',true),
(13,'WHtR','WH04',0.6,9,'เธญเนเธงเธเธฅเธเธเธธเธเธเธฑเธ”เน€เธเธ','เธชเธนเธเธกเธฒเธ','danger',1,true,'High','เธกเธตเธเธงเธฒเธกเน€เธชเธตเนเธขเธเนเธฃเธ NCD เธชเธนเธ',true),
(14,'FBS','FBS01',0,99,'เธเธเธ•เธด','เธเธเธ•เธด','success',12,false,'Low','เธเธงเธเธเธธเธกเธญเธฒเธซเธฒเธฃ เธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธข เธ•เธฃเธงเธเธชเธธเธเธ เธฒเธเธเธตเธฅเธฐ 1 เธเธฃเธฑเนเธ',true),
(15,'FBS','FBS02',100,125,'เธเนเธญเธเธเนเธฒเธเธชเธนเธ','เน€เธชเธตเนเธขเธเน€เธเธฒเธซเธงเธฒเธ','warning',6,false,'Medium','เธฅเธ”เธซเธงเธฒเธ เธเธงเธเธเธธเธกเธเนเธณเธซเธเธฑเธ เธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธข',true),
(16,'FBS','FBS03',126,999,'เธชเธนเธ','เธชเธเธชเธฑเธขเน€เธเธฒเธซเธงเธฒเธ','danger',1,true,'High','เธเธงเธฃเธ•เธฃเธงเธเธขเธทเธเธขเธฑเธเนเธฅเธฐเธ•เธดเธ”เธ•เธฒเธกเธฃเธฑเธเธฉเธฒ',true),
(17,'BP','BP01',0,119,'เธเธเธ•เธด','เธเธเธ•เธด','success',12,false,'Low','เธฅเธ”เน€เธเนเธก เธญเธญเธเธเธณเธฅเธฑเธเธเธฒเธข เธ•เธฃเธงเธเธชเธธเธเธ เธฒเธเธเธฃเธฐเธเธณเธเธต',true),
(18,'BP','BP02',120,139,'เธเนเธญเธเธเนเธฒเธเธชเธนเธ','เน€เธชเธตเนเธขเธ HT','warning',6,false,'Medium','เธฅเธ”เน€เธเนเธก เธฅเธ”เธเนเธณเธซเธเธฑเธ เธ•เธดเธ”เธ•เธฒเธกเธเธงเธฒเธกเธ”เธฑเธ',true),
(19,'BP','BP03',140,159,'เธชเธนเธ','เธชเธเธชเธฑเธข HT','danger',1,true,'High','เธ•เธฃเธงเธเธเนเธณเนเธฅเธฐเธ•เธดเธ”เธ•เธฒเธกเนเธ”เธขเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเน',true),
(20,'BP','BP04',160,300,'เธชเธนเธเธญเธฑเธเธ•เธฃเธฒเธข','HT เธฃเธฐเธ”เธฑเธเธญเธฑเธเธ•เธฃเธฒเธข','danger',1,true,'Critical','เธเธเนเธเธ—เธขเนเนเธ”เธขเน€เธฃเนเธง',true),
(21,'CVD','CVD01',0,4,'เธเธงเธฒเธกเน€เธชเธตเนเธขเธเธ•เนเธณ','เธ•เนเธณ','success',12,false,'Low','เธฃเธฑเธเธฉเธฒเธเธคเธ•เธดเธเธฃเธฃเธกเธชเธธเธเธ เธฒเธ',false),
(22,'CVD','CVD02',5,9,'เธเธงเธฒเธกเน€เธชเธตเนเธขเธเธเธฒเธเธเธฅเธฒเธ','เธเธฒเธเธเธฅเธฒเธ','warning',6,false,'Medium','เธเธงเธเธเธธเธกเธเธฑเธเธเธฑเธขเน€เธชเธตเนเธขเธ',false),
(23,'CVD','CVD03',10,19,'เธเธงเธฒเธกเน€เธชเธตเนเธขเธเธชเธนเธ','เธชเธนเธ','danger',3,true,'High','เธ•เธดเธ”เธ•เธฒเธกเนเธเธฅเนเธเธดเธ”',false),
(24,'CVD','CVD04',20,100,'เธเธงเธฒเธกเน€เธชเธตเนเธขเธเธชเธนเธเธกเธฒเธ','เธชเธนเธเธกเธฒเธ','danger',1,true,'Critical','เธเธเนเธเธ—เธขเนเนเธฅเธฐเธงเธฒเธเนเธเธเธฃเธฑเธเธฉเธฒ',false),
(25,'SUMMARY','SUM01',0,1,'เธเธงเธฒเธกเน€เธชเธตเนเธขเธเธ•เนเธณ','เธ•เนเธณ','success',12,false,'Low','เธฃเธฑเธเธฉเธฒเธชเธธเธเธ เธฒเธเธ•เนเธญเน€เธเธทเนเธญเธ',false),
(26,'SUMMARY','SUM02',2,3,'เธเธงเธฒเธกเน€เธชเธตเนเธขเธเธเธฒเธเธเธฅเธฒเธ','เธเธฒเธเธเธฅเธฒเธ','warning',6,false,'Medium','เธเธฃเธฑเธเน€เธเธฅเธตเนเธขเธเธเธคเธ•เธดเธเธฃเธฃเธกเธชเธธเธเธ เธฒเธ',false),
(27,'SUMMARY','SUM03',4,10,'เธเธงเธฒเธกเน€เธชเธตเนเธขเธเธชเธนเธ','เธชเธนเธ','danger',3,true,'High','เธเธงเธฃเธ•เธดเธ”เธ•เธฒเธกเนเธฅเธฐเธเธฃเธฐเน€เธกเธดเธเน€เธเธดเนเธกเน€เธ•เธดเธก',false)
on conflict(code) do update set
  category=excluded.category,min_value=excluded.min_value,max_value=excluded.max_value,
  result=excluded.result,risk_level=excluded.risk_level,color=excluded.color,
  followup_month=excluded.followup_month,refer_recommended=excluded.refer_recommended,
  priority=excluded.priority,advice=excluded.advice,
  use_for_calculation=excluded.use_for_calculation,updated_at=now();

create table if not exists public.health_ncd_legacy_screenings (
  legacy_id text primary key,
  source_pcucode text not null,
  source_pid bigint not null check(source_pid>0),
  screened_on date not null,
  age_years integer,
  gender text not null default '',
  weight_kg numeric(7,2),
  height_cm numeric(7,2),
  waist_cm numeric(9,2),
  legacy_bmi numeric(9,2),
  calculated_bmi numeric(7,2),
  whtr numeric(7,4),
  sbp integer,
  dbp integer,
  glucose_mg_dl integer,
  legacy_bp_status text not null default '',
  legacy_glucose_status text not null default '',
  smoking_frequency text not null default '',
  alcohol_frequency text not null default '',
  exercise_frequency text not null default '',
  legacy_cvd_risk text not null default '',
  legacy_ncd_status text not null default '',
  operator_volunteer_pid bigint,
  quality_valid boolean not null default false,
  quality_issues text[] not null default '{}'::text[],
  source_file text not null default 'screening_rows.sql',
  imported_at timestamptz not null default now(),
  foreign key(source_pcucode,source_pid)
    references public.health_persons(source_pcucode,source_pid)
);

create index if not exists health_ncd_legacy_person_date_idx
  on public.health_ncd_legacy_screenings(source_pcucode,source_pid,screened_on desc);

create index if not exists health_ncd_legacy_quality_idx
  on public.health_ncd_legacy_screenings(quality_valid,screened_on desc);

alter table public.health_ncd_legacy_screenings enable row level security;

revoke all on public.health_ncd_legacy_screenings from public,anon,authenticated;

grant select on public.health_ncd_legacy_screenings to authenticated;

drop policy if exists health_ncd_legacy_select on public.health_ncd_legacy_screenings;

create policy health_ncd_legacy_select on public.health_ncd_legacy_screenings
for select to authenticated
using (private.health_can_access_person(source_pcucode,source_pid));

create or replace view public.health_ncd_legacy_latest_valid
with (security_invoker=true)
as
select distinct on (source_pcucode,source_pid) *
from public.health_ncd_legacy_screenings
where quality_valid=true
order by source_pcucode,source_pid,screened_on desc,legacy_id desc;

grant select on public.health_ncd_legacy_latest_valid to authenticated;

-- Worklist: latest source priority is OSM Plus > valid Smart NCD legacy > JHCIS.
-- This makes old Smart NCD behavior frequency visible without trusting invalid measurements.
create or replace view public.health_person_worklist
with (security_invoker=true)
as
with fy as (
  select case when extract(month from current_date)>=10
    then make_date(extract(year from current_date)::integer,10,1)
    else make_date(extract(year from current_date)::integer-1,10,1) end as fy_start
), base as (
  select p.*,h.house_no,h.moo,h.community,h.volunteer_pid,
    case when p.birth_date is null then null else extract(year from age(current_date,p.birth_date))::integer end as age_years
  from public.health_persons p
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
  where p.active=true
), app_latest as (
  select * from public.health_ncd_latest
), legacy_latest as (
  select * from public.health_ncd_legacy_latest_valid
), ranked as (
  select b.*,
    a.screened_on as app_screened_on,a.ncd_status as app_ncd_status,a.severity as app_severity,
    a.weight_kg as app_weight_kg,a.height_cm as app_height_cm,a.waist_cm as app_waist_cm,
    a.sbp as app_sbp,a.dbp as app_dbp,a.glucose_mg_dl as app_glucose_mg_dl,a.bmi as app_bmi,
    a.smoker as app_smoker,a.alcohol_risk as app_alcohol_risk,a.exercise_sufficient as app_exercise_sufficient,
    a.smoking_frequency as app_smoking_frequency,a.alcohol_frequency as app_alcohol_frequency,a.exercise_frequency as app_exercise_frequency,
    g.screened_on as legacy_screened_on,g.legacy_ncd_status,g.weight_kg as legacy_weight_kg,
    g.height_cm as legacy_height_cm,g.waist_cm as legacy_waist_cm,g.sbp as legacy_sbp,g.dbp as legacy_dbp,
    g.glucose_mg_dl as legacy_glucose_mg_dl,g.calculated_bmi as legacy_calculated_bmi,
    g.smoking_frequency as legacy_smoking_frequency,g.alcohol_frequency as legacy_alcohol_frequency,
    g.exercise_frequency as legacy_exercise_frequency,
    (a.screened_on is not null
      and a.screened_on>=coalesce(g.screened_on,date '0001-01-01')
      and a.screened_on>=coalesce(b.previous_screened_on,date '0001-01-01')) as app_is_latest,
    (g.screened_on is not null
      and (a.screened_on is null or g.screened_on>a.screened_on)
      and g.screened_on>=coalesce(b.previous_screened_on,date '0001-01-01')) as legacy_is_latest
  from base b
  left join app_latest a on a.source_pcucode=b.source_pcucode and a.source_pid=b.source_pid
  left join legacy_latest g on g.source_pcucode=b.source_pcucode and g.source_pid=b.source_pid
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
  (r.ncd_base_eligible and r.birth_date is not null
    and extract(year from age(fy.fy_start,r.birth_date))::integer>=35
    and not (r.has_ht or r.has_dm)) as ncd_target,
  case when r.app_is_latest then r.app_screened_on
       when r.legacy_is_latest then r.legacy_screened_on
       else r.previous_screened_on end as latest_screened_on,
  case when r.app_is_latest then r.app_ncd_status
       when r.legacy_is_latest then nullif(r.legacy_ncd_status,'')
       when r.previous_screened_on is not null then 'เธกเธตเธเธฃเธฐเธงเธฑเธ•เธดเธเธฑเธ”เธเธฃเธญเธเนเธ JHCIS'
       else null end as latest_ncd_status,
  case when r.app_is_latest then r.app_severity
       when r.legacy_is_latest then case
         when r.legacy_ncd_status like '%เธชเธตเนเธ”เธ%' then 'alert'
         when r.legacy_ncd_status like '%เธชเธตเน€เธซเธฅเธทเธญเธ%' then 'risk'
         when r.legacy_ncd_status like '%เธชเธตเน€เธเธตเธขเธง%' then 'normal'
         else null end
       else null end as latest_severity,
  case when (case when r.app_is_latest then r.app_screened_on when r.legacy_is_latest then r.legacy_screened_on else r.previous_screened_on end)
       between fy.fy_start and current_date then true else false end as screened_current_fy,
  case when r.app_is_latest then r.app_screened_on when r.legacy_is_latest then r.legacy_screened_on else r.previous_screened_on end as previous_screened_on,
  (case when r.app_is_latest then r.app_weight_kg when r.legacy_is_latest then r.legacy_weight_kg else r.previous_weight_kg end)::numeric(5,2) as previous_weight_kg,
  (case when r.app_is_latest then r.app_height_cm when r.legacy_is_latest then r.legacy_height_cm else r.previous_height_cm end)::numeric(5,2) as previous_height_cm,
  (case when r.app_is_latest then r.app_waist_cm when r.legacy_is_latest then r.legacy_waist_cm else r.previous_waist_cm end)::numeric(5,2) as previous_waist_cm,
  case when r.app_is_latest then r.app_sbp when r.legacy_is_latest then r.legacy_sbp else r.previous_sbp end as previous_sbp,
  case when r.app_is_latest then r.app_dbp when r.legacy_is_latest then r.legacy_dbp else r.previous_dbp end as previous_dbp,
  case when r.app_is_latest then r.app_glucose_mg_dl when r.legacy_is_latest then r.legacy_glucose_mg_dl else r.previous_glucose_mg_dl end as previous_glucose_mg_dl,
  (case when r.app_is_latest then r.app_bmi when r.legacy_is_latest then r.legacy_calculated_bmi else r.previous_bmi end)::numeric(5,2) as previous_bmi,
  case when r.app_is_latest then 'เธญเธชเธก. เธเธฅเธฑเธช'
       when r.legacy_is_latest then 'Smart NCD Care D (เน€เธ”เธดเธก)'
       when r.previous_screened_on is not null then coalesce(nullif(r.previous_source,''),'JHCIS / j-report NCD Export')
       else '' end as previous_source,
  case when r.app_is_latest then coalesce(nullif(r.app_smoking_frequency,''),case when r.app_smoker then 'เธชเธนเธ' else 'เนเธกเนเธชเธนเธ' end)
       when r.legacy_is_latest then r.legacy_smoking_frequency else '' end as previous_smoking,
  case when r.app_is_latest then coalesce(nullif(r.app_alcohol_frequency,''),case when r.app_alcohol_risk then 'เธ”เธทเนเธก' else 'เนเธกเนเธ”เธทเนเธก' end)
       when r.legacy_is_latest then r.legacy_alcohol_frequency else '' end as previous_alcohol,
  case when r.app_is_latest then coalesce(nullif(r.app_exercise_frequency,''),case when r.app_exercise_sufficient then 'เน€เธเธตเธขเธเธเธญ' else 'เนเธกเนเน€เธเธตเธขเธเธเธญ' end)
       when r.legacy_is_latest then r.legacy_exercise_frequency else '' end as previous_exercise
from ranked r
cross join fy;

grant select on public.health_person_worklist to authenticated;

-- Unified history preserves all legacy rows, including invalid ones, but clearly flags quality.
drop view if exists public.health_ncd_history;

create view public.health_ncd_history
with (security_invoker=true)
as
select
  s.id::text as id,s.screened_on,s.source_pcucode,s.source_pid,
  p.display_name,p.gender,p.birth_date,
  s.hcode,h.house_no,h.moo,h.community,
  s.weight_kg,s.height_cm,s.waist_cm,s.bmi,s.sbp,s.dbp,s.glucose_mg_dl,s.glucose_type,
  s.smoking_frequency,s.alcohol_frequency,s.exercise_frequency,
  s.ncd_status,s.severity,s.bp_status,s.glucose_status,s.advice,
  'เธญเธชเธก. เธเธฅเธฑเธช'::text as source_label,true as quality_valid,'{}'::text[] as quality_issues,
  ''::text as legacy_cvd_risk,s.recorded_at
from public.health_ncd_screenings s
join public.health_persons p on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
join public.houses h on h.source_pcucode=s.house_pcucode and h.hcode=s.hcode
union all
select
  g.legacy_id,g.screened_on,g.source_pcucode,g.source_pid,
  p.display_name,p.gender,p.birth_date,
  p.hcode,h.house_no,h.moo,h.community,
  g.weight_kg,g.height_cm,g.waist_cm,g.calculated_bmi,g.sbp,g.dbp,g.glucose_mg_dl,'legacy_fbs'::text,
  g.smoking_frequency,g.alcohol_frequency,g.exercise_frequency,
  g.legacy_ncd_status,
  case when g.legacy_ncd_status like '%เธชเธตเนเธ”เธ%' then 'alert'
       when g.legacy_ncd_status like '%เธชเธตเน€เธซเธฅเธทเธญเธ%' then 'risk'
       when g.legacy_ncd_status like '%เธชเธตเน€เธเธตเธขเธง%' then 'normal'
       else null end as severity,
  g.legacy_bp_status,g.legacy_glucose_status,
  'เธเธฃเธฐเธงเธฑเธ•เธดเธเธฒเธ Smart NCD Care D เน€เธ”เธดเธก เนเธเนเน€เธเธทเนเธญเธญเนเธฒเธเธญเธดเธเธขเนเธญเธเธซเธฅเธฑเธ'::text,
  'Smart NCD Care D (เน€เธ”เธดเธก)'::text,g.quality_valid,g.quality_issues,g.legacy_cvd_risk,
  (g.screened_on::timestamp at time zone 'Asia/Bangkok') as recorded_at
from public.health_ncd_legacy_screenings g
join public.health_persons p on p.source_pcucode=g.source_pcucode and p.source_pid=g.source_pid
join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode;

grant select on public.health_ncd_history to authenticated;

insert into public.app_settings(key,value)
values ('legacy_smart_ncd',jsonb_build_object(
  'version','1.8.4',
  'source','Smart NCD Care D SQL dumps',
  'data_rows','registry reference only; current health_persons remains JHCIS read-only source',
  'screening_rows','imported into health_ncd_legacy_screenings with quality flags',
  'rules_rows','27 rules preserved in health_screening_rules',
  'users_rows','role/community reference only; plaintext passwords are never imported',
  'history_priority',jsonb_build_array('osm_plus','smart_ncd_legacy_valid','jhcis'),
  'legacy_cvd','archive only; not used for new calculations',
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
