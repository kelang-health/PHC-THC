-- OSM-PHC Cloud v1.8.60
-- Role-linked care dashboard and inherited Staff/VHV scope.
-- Staff remains a VHV for own houses/people, with an additional own-community context.
-- Admin remains all-area. JHCIS is read-only; only derived flags are synced to Cloud.

begin;

alter table public.health_persons
  add column if not exists is_student boolean not null default false,
  add column if not exists is_disabled boolean not null default false,
  add column if not exists care_group_code text;

alter table public.health_persons
  drop constraint if exists health_persons_care_group_code_check;

alter table public.health_persons
  add constraint health_persons_care_group_code_check
  check (care_group_code is null or care_group_code in ('1','2','3'));

comment on column public.health_persons.is_student is
  'Derived read-only flag from JHCIS personstudent; no school identifier is uploaded.';

comment on column public.health_persons.is_disabled is
  'Derived read-only flag from JHCIS personunable.';

comment on column public.health_persons.care_group_code is
  'Raw JHCIS person.candobedhomesocial code: 1=social, 2=homebound, 3=bedridden. Used only as a care-group flag.';

create or replace function public.my_household_cards_v1860()
returns table (
  id uuid,
  hcode text,
  house_no text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  coordinate_source text,
  coordinate_status text,
  record_status text,
  review_required boolean,
  review_reason text,
  volunteer_pid bigint,
  house_id_11 text,
  entry_source text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_pid bigint;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  v_role := private.current_role();
  v_pid := private.current_volunteer_pid();
  if v_role not in ('user','staff') or v_pid is null then
    raise exception 'VHV_SCOPE_REQUIRED';
  end if;

  return query
  select h.id,h.hcode,h.house_no,h.moo,h.community,h.latitude,h.longitude,
         h.coordinate_source,h.coordinate_status,h.record_status,h.review_required,
         h.review_reason,h.volunteer_pid,h.house_id_11,h.entry_source
  from public.houses h
  where h.volunteer_pid=v_pid
  order by
    nullif(regexp_replace(coalesce(h.house_no,''), '[^0-9].*$', ''), '')::integer nulls last,
    h.house_no;
end;
$$;

revoke all on function public.my_household_cards_v1860() from public,anon;

grant execute on function public.my_household_cards_v1860() to authenticated;

create or replace function public.care_dashboard_v1860(p_scope text default 'self')
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

  with scoped_houses as (
    select h.*
    from public.houses h
    where
      v_role='admin'
      or (v_scope='self' and v_pid is not null and h.volunteer_pid=v_pid)
      or (v_role='staff' and v_scope='community'
          and private.community_key(h.community)=private.community_key(v_community))
  ), scoped_people as (
    select w.*,p.is_student,p.is_disabled,p.care_group_code
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
    where coalesce(s.record_mode,'production')='production'
    order by s.source_pcucode,s.source_pid,s.screened_on desc,s.recorded_at desc
  ), hstat as (
    select count(*)::bigint houses,
           count(*) filter(where latitude is not null and longitude is not null)::bigint mapped_houses,
           count(*) filter(where latitude is null or longitude is null)::bigint missing_coordinates,
           count(*) filter(where review_required=true)::bigint review_houses
    from scoped_houses
  ), pstat as (
    select count(*)::bigint people,
           count(*) filter(where ncd_target)::bigint ncd_targets,
           count(*) filter(where ncd_target and coalesce(screened_current_fy,false))::bigint ncd_done,
           count(*) filter(where ncd_target and not coalesce(screened_current_fy,false))::bigint ncd_due,
           count(*) filter(where known_ncd)::bigint known_ncd,
           count(*) filter(where life_stage='เน€เธ”เนเธเธเธเธกเธงเธฑเธข')::bigint early_child,
           count(*) filter(where life_stage='เน€เธ”เนเธเธงเธฑเธขเน€เธฃเธตเธขเธ')::bigint school_age,
           count(*) filter(where life_stage='เธงเธฑเธขเธฃเธธเนเธเนเธฅเธฐเน€เธขเธฒเธงเธเธ')::bigint youth,
           count(*) filter(where life_stage='เธงเธฑเธขเธ—เธณเธเธฒเธ')::bigint working_age,
           count(*) filter(where life_stage='เธเธนเนเธชเธนเธเธญเธฒเธขเธธ')::bigint older_people,
           count(*) filter(where is_disabled)::bigint disabled_people,
           count(*) filter(where care_group_code='2')::bigint homebound_people,
           count(*) filter(where care_group_code='3')::bigint bedridden_people,
           count(*) filter(where latest_severity in ('alert','urgent'))::bigint urgent_attention
    from scoped_people
  ), qstat as (
    select count(*) filter(where mental_2q_status='assessed')::bigint mental_2q_assessed,
           count(*) filter(where mental_2q_status='not_assessed')::bigint mental_2q_not_assessed,
           count(*) filter(where mental_2q_status='incomplete')::bigint mental_2q_incomplete,
           count(*) filter(where mental_2q_status='assessed' and mental_2q_result=true)::bigint mental_2q_positive
    from latest_2q
  )
  select jsonb_build_object(
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
    'people',coalesce(pstat.people,0),
    'ncd_targets',coalesce(pstat.ncd_targets,0),
    'ncd_done',coalesce(pstat.ncd_done,0),
    'ncd_due',coalesce(pstat.ncd_due,0),
    'known_ncd',coalesce(pstat.known_ncd,0),
    'early_child',coalesce(pstat.early_child,0),
    'school_age',coalesce(pstat.school_age,0),
    'youth',coalesce(pstat.youth,0),
    'working_age',coalesce(pstat.working_age,0),
    'older_people',coalesce(pstat.older_people,0),
    'disabled_people',coalesce(pstat.disabled_people,0),
    'homebound_people',coalesce(pstat.homebound_people,0),
    'bedridden_people',coalesce(pstat.bedridden_people,0),
    'urgent_attention',coalesce(pstat.urgent_attention,0),
    'mental_2q_assessed',coalesce(qstat.mental_2q_assessed,0),
    'mental_2q_not_assessed',coalesce(qstat.mental_2q_not_assessed,0),
    'mental_2q_incomplete',coalesce(qstat.mental_2q_incomplete,0),
    'mental_2q_positive',coalesce(qstat.mental_2q_positive,0)
  ) into v_result
  from hstat cross join pstat cross join qstat;

  return v_result;
end;
$$;

revoke all on function public.care_dashboard_v1860(text) from public,anon;

grant execute on function public.care_dashboard_v1860(text) to authenticated;

insert into public.app_settings(key,value)
values ('care_dashboard',jsonb_build_object(
  'version','1.8.60',
  'role_model','staff_inherits_vhv_personal_scope_plus_own_community_context',
  'user_scope','own_assigned_houses_people',
  'staff_scopes',jsonb_build_array('self','community'),
  'admin_scope','all',
  'life_stage_groups',jsonb_build_array('0-5','school_age','youth','working_age','older_people'),
  'special_groups',jsonb_build_array('disabled','homebound','bedridden'),
  'homebound_source','JHCIS person.candobedhomesocial=2',
  'bedridden_source','JHCIS person.candobedhomesocial=3',
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
