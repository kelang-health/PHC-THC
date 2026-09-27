-- Cloud v2.0.30b: direct-table implementation for concurrent screening targets.
-- The previous RPC still touched a security_invoker view, so authenticated RLS work could remain.
begin;

create or replace function public.my_screening_targets_v2030(
  p_scope text default 'self',
  p_stage text default null,
  p_search text default null,
  p_community text default null,
  p_limit integer default 300
)
returns setof public.health_screening_target_worklist_v2026
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_community text;
  v_pid bigint;
  v_scope text:=lower(btrim(coalesce(p_scope,'self')));
  v_stage text:=nullif(btrim(coalesce(p_stage,'')),'');
  v_search text:=left(nullif(btrim(coalesce(p_search,'')),''),60);
  v_filter_community text:=nullif(btrim(coalesce(p_community,'')),'');
  v_limit integer:=greatest(1,least(coalesce(p_limit,300),300));
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;

  select pr.role,pr.community,pr.volunteer_pid
    into v_role,v_community,v_pid
  from public.profiles pr
  where pr.user_id=v_uid and pr.active=true
  limit 1;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_role='admin' then v_scope:='all';
  elsif v_role='user' then v_scope:='self';
  elsif v_role='staff' then
    if v_scope not in ('self','community') then v_scope:='self'; end if;
  else raise exception 'ROLE_NOT_ALLOWED';
  end if;

  return query
  select
    p.source_pcucode,p.source_pid,p.hcode,h.house_no,h.moo,h.community,h.volunteer_pid,
    p.display_name,p.gender,p.birth_date,pl.age_years,
    case when pl.age_years<=5 then 'เน€เธ”เนเธเธเธเธกเธงเธฑเธข'
         when pl.age_years<=14 then 'เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ'
         when pl.age_years<=24 then 'เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ'
         when pl.age_years<=59 then 'เธงเธฑเธขเธ—เธณเธเธฒเธ'
         else 'เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' end::text as life_stage,
    p.has_ht,p.has_dm,(p.has_ht or p.has_dm) as known_ncd,
    (pl.age_years>=35 and not (p.has_ht or p.has_dm)) as ncd_target,
    p.previous_screened_on as latest_screened_on,
    case when p.previous_screened_on is not null then 'เธกเธตเธเธฃเธฐเธงเธฑเธ•เธดเธเธฑเธ”เธเธฃเธญเธเน€เธ”เธดเธก' else null end::text as latest_ncd_status,
    null::text as latest_severity,
    false::boolean as screened_current_fy,
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
    and pl.target_enabled=true
    and coalesce(rs.service_target_active,true)=true
    and (
      v_role='admin'
      or (v_scope='self' and v_pid is not null and h.volunteer_pid=v_pid)
      or (
        v_role='staff' and v_scope='community'
        and private.community_key(h.community)=private.community_key(v_community)
      )
    )
    and (
      v_filter_community is null
      or private.community_key(h.community)=private.community_key(v_filter_community)
    )
    and (
      v_stage is null
      or (case when pl.age_years<=5 then 'เน€เธ”เนเธเธเธเธกเธงเธฑเธข'
               when pl.age_years<=14 then 'เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ'
               when pl.age_years<=24 then 'เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ'
               when pl.age_years<=59 then 'เธงเธฑเธขเธ—เธณเธเธฒเธ'
               else 'เธเธนเนเธชเธนเธเธญเธฒเธขเธธ' end)=v_stage
    )
    and (v_search is null or p.display_name ilike ('%'||v_search||'%'))
  order by h.community,p.hcode,p.display_name
  limit v_limit;
end;
$$;

revoke all on function public.my_screening_targets_v2030(text,text,text,text,integer) from public,anon;

grant execute on function public.my_screening_targets_v2030(text,text,text,text,integer) to authenticated;

update public.app_settings
set value=value || jsonb_build_object(
  'implementation','direct_tables_explicit_scope',
  'security_invoker_view_in_rpc',false,
  'updated_for_concurrency',true
),updated_at=now()
where key='screening_target_runtime_v2030';

notify pgrst,'reload schema';

commit;
