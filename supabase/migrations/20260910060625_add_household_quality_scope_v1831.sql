create or replace function public.community_scope_summary_v1831(
  p_community text default null,
  p_all_moo boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_own_moo text;
  v_target_moo text;
  v_target text := nullif(btrim(coalesce(p_community,'')),'');
  v_total bigint := 0;
  v_assigned bigint := 0;
  v_pinned bigint := 0;
  v_field bigint := 0;
  v_review bigint := 0;
  v_out_tambon bigint := 0;
  v_out_community bigint := 0;
  v_missing bigint := 0;
  v_missing_id11 bigint := 0;
  v_people bigint := 0;
  v_ncd_due bigint := 0;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo from public.communities c
    where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,'')) limit 1;
  end if;

  if v_target is not null then
    select c.moo into v_target_moo from public.communities c where c.active=true and btrim(c.name)=v_target limit 1;
    if v_target_moo is null then raise exception 'COMMUNITY_NOT_FOUND'; end if;
    if v_profile.role='staff' and v_target_moo is distinct from v_own_moo then raise exception 'COMMUNITY_OUT_OF_SCOPE'; end if;
    if v_profile.role='user' and v_target<>btrim(coalesce(v_profile.community,'')) then raise exception 'COMMUNITY_OUT_OF_SCOPE'; end if;
  end if;

  with scoped_houses as (
    select h.*
    from public.houses h
    join public.communities c on c.active=true and btrim(c.name)=btrim(h.community)
    where
      (v_profile.role='admin' and (v_target is null or btrim(c.name)=v_target))
      or
      (v_profile.role='staff' and (
        (coalesce(p_all_moo,false)=true and c.moo=v_own_moo)
        or (coalesce(p_all_moo,false)=false and btrim(c.name)=coalesce(v_target,btrim(v_profile.community)))
      ))
      or
      (v_profile.role='user' and btrim(c.name)=btrim(coalesce(v_profile.community,'')))
  )
  select
    count(sh.id),
    count(sh.id) filter (where sh.volunteer_pid is not null),
    count(sh.id) filter (where sh.latitude is not null and sh.longitude is not null),
    count(sh.id) filter (where sh.coordinate_status like 'resolved_%'),
    count(sh.id) filter (where sh.review_required=true),
    count(sh.id) filter (where sh.inside_tambon=false),
    count(sh.id) filter (where sh.inside_community=false and sh.inside_tambon is distinct from false),
    count(sh.id) filter (where sh.latitude is null or sh.longitude is null),
    count(sh.id) filter (where sh.house_id_11 is null or sh.house_id_11 !~ '^[0-9]{11}$')
  into v_total,v_assigned,v_pinned,v_field,v_review,v_out_tambon,v_out_community,v_missing,v_missing_id11
  from scoped_houses sh;

  if v_profile.role='admin' or (v_profile.role='staff' and coalesce(v_target,btrim(v_profile.community))=btrim(v_profile.community) and coalesce(p_all_moo,false)=false) then
    with scoped_hcodes as (
      select distinct h.source_pcucode,h.hcode
      from public.houses h
      where (v_profile.role='admin' and (v_target is null or btrim(h.community)=v_target))
         or (v_profile.role='staff' and btrim(h.community)=btrim(v_profile.community))
    )
    select count(*), count(*) filter (where w.ncd_target=true and coalesce(w.screened_current_fy,false)=false)
    into v_people,v_ncd_due
    from public.health_person_worklist w
    join scoped_hcodes s on s.source_pcucode=w.source_pcucode and s.hcode=w.hcode;
  end if;

  return jsonb_build_object(
    'role',v_profile.role,
    'own_community',v_profile.community,
    'own_moo',v_own_moo,
    'selected_community',coalesce(v_target,case when v_profile.role in ('staff','user') then v_profile.community else null end),
    'all_moo',coalesce(p_all_moo,false),
    'total_houses',v_total,
    'assigned_houses',v_assigned,
    'pinned_houses',v_pinned,
    'field_confirmed',v_field,
    'review_houses',v_review,
    'outside_tambon',v_out_tambon,
    'outside_community',v_out_community,
    'missing_coordinates',v_missing,
    'missing_house_id_11',v_missing_id11,
    'people',v_people,
    'ncd_due',v_ncd_due,
    'field_progress_pct',case when v_total>0 then round((v_field::numeric*100)/v_total,1) else 0 end
  );
end;
$$;

create or replace function public.community_household_cards_v1831(p_community text)
returns table(
  id uuid,
  house_no text,
  hcode text,
  house_id_11 text,
  moo text,
  community text,
  latitude double precision,
  longitude double precision,
  volunteer_pid bigint,
  volunteer_name text,
  spatial_status text,
  can_edit boolean,
  health_access boolean,
  member_count bigint,
  older_count bigint,
  age35plus_count bigint,
  ncd_target_count bigint,
  ncd_due_count bigint,
  known_ncd_count bigint,
  latest_screened_on date,
  quality_code text,
  quality_label text
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_target text := btrim(coalesce(p_community,''));
  v_target_moo text;
  v_own_moo text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  select c.moo into v_target_moo from public.communities c where c.active=true and btrim(c.name)=v_target limit 1;
  if v_target_moo is null then raise exception 'COMMUNITY_NOT_FOUND'; end if;
  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo from public.communities c where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,'')) limit 1;
  end if;
  if not (
    v_profile.role='admin'
    or (v_profile.role='staff' and v_target_moo=v_own_moo)
    or (v_profile.role='user' and v_target=btrim(coalesce(v_profile.community,'')))
  ) then raise exception 'COMMUNITY_OUT_OF_SCOPE'; end if;

  return query
  with base as (
    select h.*,
      coalesce(v.display_name,'เธขเธฑเธเนเธกเนเนเธ”เนเธกเธญเธเธซเธกเธฒเธข')::text as vname,
      case
        when v_profile.role='admin' then true
        when v_profile.role='staff' then v_target=btrim(coalesce(v_profile.community,''))
        when v_profile.role='user' then h.volunteer_pid is not null and h.volunteer_pid=v_profile.volunteer_pid
        else false
      end as h_access,
      case
        when v_profile.role='admin' then true
        when v_profile.role='staff' then v_target=btrim(coalesce(v_profile.community,''))
        when v_profile.role='user' then h.volunteer_pid is not null and h.volunteer_pid=v_profile.volunteer_pid
        else false
      end as editable,
      case
        when h.latitude is null or h.longitude is null then 'missing'
        when h.inside_tambon=false then 'outside_tambon'
        when h.inside_community=false then 'outside_community'
        when h.review_required=true then 'review'
        when h.coordinate_status like 'resolved_%' then 'field_confirmed'
        else 'pinned'
      end::text as s_status
    from public.houses h
    left join public.volunteers v on v.source_pid=h.volunteer_pid and v.active=true
    where btrim(h.community)=v_target
  ), scored as (
    select b.*,
      case when b.h_access then coalesce(x.member_count,0) else null end as m_count,
      case when b.h_access then coalesce(x.older_count,0) else null end as o_count,
      case when b.h_access then coalesce(x.age35plus_count,0) else null end as a35_count,
      case when b.h_access then coalesce(x.ncd_target_count,0) else null end as nt_count,
      case when b.h_access then coalesce(x.ncd_due_count,0) else null end as nd_count,
      case when b.h_access then coalesce(x.known_ncd_count,0) else null end as kn_count,
      case when b.h_access then x.latest_screened_on else null end as last_screen
    from base b
    left join lateral (
      select
        count(*)::bigint as member_count,
        count(*) filter (where w.age_years>=60)::bigint as older_count,
        count(*) filter (where w.age_years>=35)::bigint as age35plus_count,
        count(*) filter (where w.ncd_target=true)::bigint as ncd_target_count,
        count(*) filter (where w.ncd_target=true and coalesce(w.screened_current_fy,false)=false)::bigint as ncd_due_count,
        count(*) filter (where w.known_ncd=true)::bigint as known_ncd_count,
        max(w.latest_screened_on)::date as latest_screened_on
      from public.health_person_worklist w
      where w.source_pcucode=b.source_pcucode and w.hcode=b.hcode
    ) x on true
  )
  select
    s.id,s.house_no,s.hcode,s.house_id_11,s.moo,s.community,s.latitude,s.longitude,
    s.volunteer_pid,s.vname,s.s_status,s.editable,s.h_access,
    s.m_count,s.o_count,s.a35_count,s.nt_count,s.nd_count,s.kn_count,s.last_screen,
    case
      when not s.h_access then 'spatial'
      when s.inside_tambon=false then 'pink'
      when s.s_status in ('missing','outside_community','review') then 'orange'
      when coalesce(s.nd_count,0)>=2 then 'orange'
      when coalesce(s.nd_count,0)=1 or coalesce(s.m_count,0)=0 then 'yellow'
      else 'green'
    end::text,
    case
      when not s.h_access then 'เธ”เธนเธเนเธญเธกเธนเธฅเธเธทเนเธเธ—เธตเน'
      when s.inside_tambon=false then 'เธ•เธฃเธงเธเธเธทเนเธเธ—เธตเนเน€เธฃเนเธเธ”เนเธงเธ'
      when s.s_status in ('missing','outside_community','review') then 'เธเธงเธฃเธ•เธฃเธงเธเธเนเธญเธกเธนเธฅเธเนเธฒเธ'
      when coalesce(s.nd_count,0)>=2 then 'เธกเธตเธเธฒเธเธชเธธเธเธ เธฒเธเธเธงเธฃเธ•เธดเธ”เธ•เธฒเธก'
      when coalesce(s.nd_count,0)=1 then 'เธกเธตเธเธฒเธเธ•เธดเธ”เธ•เธฒเธก'
      when coalesce(s.m_count,0)=0 then 'เธขเธฑเธเนเธกเนเธเธเธชเธกเธฒเธเธดเธเน€เธเธทเนเธญเธกเธเนเธฒเธ'
      else 'เธเนเธญเธกเธนเธฅเธเธฃเนเธญเธกเนเธเนเธเธฒเธ'
    end::text
  from scored s
  order by s.house_no collate "C";
end;
$$;

create or replace function public.community_household_detail_v1831(p_house_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
  v_house public.houses%rowtype;
  v_own_moo text;
  v_house_moo text;
  v_spatial_allowed boolean := false;
  v_health_allowed boolean := false;
  v_members jsonb := '[]'::jsonb;
  v_summary jsonb := '{}'::jsonb;
  v_timeline jsonb := '[]'::jsonb;
  v_volunteer_name text;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.profiles where user_id=v_uid and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  select * into v_house from public.houses where id=p_house_id;
  if not found then raise exception 'HOUSE_NOT_FOUND'; end if;

  select c.moo into v_house_moo from public.communities c where c.active=true and btrim(c.name)=btrim(v_house.community) limit 1;
  if v_profile.role in ('staff','user') then
    select c.moo into v_own_moo from public.communities c where c.active=true and btrim(c.name)=btrim(coalesce(v_profile.community,'')) limit 1;
  end if;

  v_spatial_allowed := coalesce(
    v_profile.role='admin'
    or (v_profile.role='staff' and v_house_moo=v_own_moo)
    or (v_profile.role='user' and btrim(v_house.community)=btrim(coalesce(v_profile.community,''))),false);
  if not v_spatial_allowed then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;

  v_health_allowed := coalesce(
    v_profile.role='admin'
    or (v_profile.role='staff' and btrim(v_house.community)=btrim(coalesce(v_profile.community,'')))
    or (v_profile.role='user' and v_house.volunteer_pid is not null and v_house.volunteer_pid=v_profile.volunteer_pid),false);

  select coalesce(v.display_name,'เธขเธฑเธเนเธกเนเนเธ”เนเธกเธญเธเธซเธกเธฒเธข') into v_volunteer_name
  from (select 1) z left join public.volunteers v on v.source_pid=v_house.volunteer_pid and v.active=true limit 1;

  if v_health_allowed then
    select jsonb_build_object(
      'members',count(*),
      'older_people',count(*) filter (where w.age_years>=60),
      'age35plus',count(*) filter (where w.age_years>=35),
      'ncd_targets',count(*) filter (where w.ncd_target=true),
      'ncd_due',count(*) filter (where w.ncd_target=true and coalesce(w.screened_current_fy,false)=false),
      'known_ncd',count(*) filter (where w.known_ncd=true),
      'latest_screened_on',max(w.latest_screened_on)
    ) into v_summary
    from public.health_person_worklist w
    where w.source_pcucode=v_house.source_pcucode and w.hcode=v_house.hcode;

    select coalesce(jsonb_agg(jsonb_build_object(
      'source_pid',w.source_pid,
      'display_name',w.display_name,
      'gender',w.gender,
      'age_years',w.age_years,
      'life_stage',w.life_stage,
      'known_ncd',w.known_ncd,
      'ncd_target',w.ncd_target,
      'screened_current_fy',w.screened_current_fy,
      'latest_screened_on',w.latest_screened_on,
      'latest_ncd_status',w.latest_ncd_status,
      'latest_severity',w.latest_severity,
      'task_label',case
        when w.ncd_target=true and coalesce(w.screened_current_fy,false)=false then 'NCD เธขเธฑเธเธกเธตเธเธฒเธเธเธฑเธ”เธเธฃเธญเธเธ•เธฒเธกเธฃเธฒเธขเธเธฒเธฃเธฃเธฐเธเธ'
        when w.known_ncd=true then 'เธกเธต DM/HT เน€เธ”เธดเธกเนเธเธเนเธญเธกเธนเธฅเธฃเธฐเธเธ'
        else 'เนเธกเนเธกเธตเธเธฒเธ NCD เธเนเธฒเธเธ—เธตเนเธฃเธฐเธเธเธฃเธฐเธเธธ'
      end,
      'mental_2q_status',q.mental_2q_status,
      'mental_2q_result',q.mental_2q_result
    ) order by w.age_years desc nulls last,w.display_name),'[]'::jsonb)
    into v_members
    from public.health_person_worklist w
    left join lateral (
      select s.mental_2q_status,s.mental_2q_result
      from public.health_ncd_screenings s
      where s.source_pcucode=w.source_pcucode and s.source_pid=w.source_pid and s.record_mode='production'
      order by s.screened_on desc,s.recorded_at desc limit 1
    ) q on true
    where w.source_pcucode=v_house.source_pcucode and w.hcode=v_house.hcode;

    with events as (
      select s.recorded_at as event_at,
             'health'::text as event_type,
             'เธเธฑเธ”เธเธฃเธญเธ NCD'::text as title,
             coalesce(w.display_name,'เธเธฃเธฐเธเธฒเธเธเนเธเธเนเธฒเธ')::text as detail
      from public.health_ncd_screenings s
      left join public.health_person_worklist w on w.source_pcucode=s.source_pcucode and w.source_pid=s.source_pid
      where s.source_pcucode=v_house.source_pcucode and s.hcode=v_house.hcode and s.record_mode='production'
      union all
      select a.created_at,'coordinate','เธเธฃเธฑเธเธเธดเธเธฑเธ”เธเนเธฒเธ',case when a.source='gps' then 'เธเธฑเธเธ—เธถเธเธเธฒเธ GPS' else 'เธเธฃเธฑเธเธเธฒเธเนเธเธเธ—เธตเน' end
      from public.house_coordinate_audit a where a.house_id=v_house.id
    )
    select coalesce(jsonb_agg(jsonb_build_object('event_at',event_at,'event_type',event_type,'title',title,'detail',detail) order by event_at desc),'[]'::jsonb)
    into v_timeline from (select * from events order by event_at desc limit 12) e;
  else
    with events as (
      select a.created_at as event_at,'coordinate'::text as event_type,'เธเธฃเธฑเธเธเธดเธเธฑเธ”เธเนเธฒเธ'::text as title,
             case when a.source='gps' then 'เธเธฑเธเธ—เธถเธเธเธฒเธ GPS' else 'เธเธฃเธฑเธเธเธฒเธเนเธเธเธ—เธตเน' end::text as detail
      from public.house_coordinate_audit a where a.house_id=v_house.id
      order by a.created_at desc limit 8
    )
    select coalesce(jsonb_agg(jsonb_build_object('event_at',event_at,'event_type',event_type,'title',title,'detail',detail) order by event_at desc),'[]'::jsonb)
    into v_timeline from events;
  end if;

  return jsonb_build_object(
    'health_access',v_health_allowed,
    'house',jsonb_build_object(
      'id',v_house.id,'house_no',v_house.house_no,'hcode',v_house.hcode,'house_id_11',v_house.house_id_11,
      'moo',v_house.moo,'community',v_house.community,'latitude',v_house.latitude,'longitude',v_house.longitude,
      'coordinate_status',v_house.coordinate_status,'review_required',v_house.review_required,
      'inside_tambon',v_house.inside_tambon,'inside_community',v_house.inside_community,
      'volunteer_pid',v_house.volunteer_pid,'volunteer_name',v_volunteer_name
    ),
    'summary',case when v_health_allowed then v_summary else null end,
    'members',case when v_health_allowed then v_members else '[]'::jsonb end,
    'timeline',v_timeline,
    'scope_note',case when v_health_allowed then 'เธ”เธนเธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธชเธกเธฒเธเธดเธเนเธฅเธฐเธเธฒเธเธชเธธเธเธ เธฒเธเนเธ”เนเธ•เธฒเธกเธเธญเธเน€เธเธ•เธชเธดเธ—เธเธดเน' else 'เธเธธเธกเธเธเธเธตเนเน€เธเธดเธ”เธ”เธนเน€เธเธดเธเธเธทเนเธเธ—เธตเนเนเธ”เน เนเธ•เนเธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธชเธกเธฒเธเธดเธเนเธฅเธฐเธเนเธญเธกเธนเธฅเธชเธธเธเธ เธฒเธเธ–เธนเธเธเธณเธเธฑเธ”เธ•เธฒเธกเธชเธดเธ—เธเธดเน' end
  );
end;
$$;

revoke all on function public.community_scope_summary_v1831(text,boolean) from public,anon;
revoke all on function public.community_household_cards_v1831(text) from public,anon;
revoke all on function public.community_household_detail_v1831(uuid) from public,anon;
grant execute on function public.community_scope_summary_v1831(text,boolean) to authenticated;
grant execute on function public.community_household_cards_v1831(text) to authenticated;
grant execute on function public.community_household_detail_v1831(uuid) to authenticated;
