begin;
set local statement_timeout='100s';
-- Staff care tab lists only directly assigned houses. Other tabs, community access, targets and person permissions remain unchanged.
create or replace function private.house_groups_v2225()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v public.profiles; v_review jsonb; result jsonb;
begin
 select * into v from public.profiles where user_id=auth.uid() and active;
 if v.user_id is null or v.role not in ('admin','staff','user') then raise exception 'AUTH_REQUIRED'; end if;
 v_review:=public.house_registration_review_cards_v2202();
 with review as (
   select r from jsonb_array_elements(v_review) r
 ), scoped as (
   select h.*, private.house_is_school_only_v2225(h) is_school, (select r from review where r->>'id'=h.id::text) audit
   from public.houses h
   where h.superseded_by is null and h.verification_status='verified_jhcis'
   and (private.health_can_access_house(h.source_pcucode,h.hcode)
        or exists(select 1 from review where r->>'id'=h.id::text))
 ), counts as (
   select h.id,
    count(p.source_pid) registered_count,
    count(p.source_pid) filter(where p.jhcis_typelive=2) type2_count,
    count(p.source_pid) filter(where p.active and p.service_population_eligible and p.jhcis_typelive in (1,3)
      and coalesce(rs.service_target_active,true)) target_count,
    count(p.source_pid) filter(where p.jhcis_typelive is distinct from 2) other_count
   from scoped h left join public.health_persons p on p.house_pcucode=h.source_pcucode and p.hcode=h.hcode
   left join public.health_person_residence_status rs on rs.source_pcucode=p.source_pcucode and rs.source_pid=p.source_pid
   group by h.id
 ), cards as (
  select h.*,c.type2_count,c.target_count,c.registered_count,
   case when h.is_school then 'special'
    when h.audit is not null or h.volunteer_pid is null or coalesce(btrim(h.community),'')='' then 'review'
    when c.target_count>0 then 'care'
    when c.other_count>0 then 'review'
    else 'empty' end house_group
  from scoped h join counts c using(id)
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'house_no',house_no,'moo',moo,'community',community,'hcode',hcode,
  'house_group',house_group,'type2_count',case when house_group='special' then 0 else type2_count end,
  'target_count',case when house_group='special' then 0 else target_count end,
  'review',audit,'review_required',review_required,'review_reason',review_reason,
  'latitude',latitude,'longitude',longitude,
  'reason',case when house_group='special' then 'โรงเรียน · เก็บเฉพาะทะเบียนบ้าน ไม่นับเป็นเป้าหมาย'
    when audit is not null then 'รอตรวจสอบทะเบียนบ้าน'
    when volunteer_pid is null or coalesce(btrim(community),'')='' then 'รอมอบหมายชุมชนหรือผู้รับผิดชอบ'
    when target_count>0 then 'มีเป้าหมายดูแลสุขภาพ'
    when type2_count>0 and house_group='empty' then 'มีชื่อทะเบียน type 2 แต่ไม่อยู่ในพื้นที่ · ไม่นับเป็นเป้าหมาย'
    when registered_count>0 then 'ยังไม่มีเป้าหมายสุขภาพ · รอตรวจสอบสถานะผู้พักอาศัย'
    else 'ไม่พบรายชื่อเป้าหมายในทะเบียน Cloud · ยังไม่ยืนยันสภาพการพักอาศัย' end
 ) order by nullif(regexp_replace(coalesce(house_no,''),'[^0-9].*$',''),'')::numeric nulls last,house_no,id),'[]'::jsonb)
 into result from cards
 where v.role<>'staff' or house_group<>'care'
    or (v.volunteer_pid is not null and volunteer_pid=v.volunteer_pid);
 return result;
end $$;

create temp table fast_baseline(user_id uuid, role text, payload jsonb, old_ms numeric);
do $$ declare v record; t timestamptz; a jsonb; begin
 for v in (select user_id,role from public.profiles where active and role='admin' order by user_id limit 1)
 union all (select user_id,role from public.profiles where active and role='staff' order by volunteer_pid nulls first,user_id limit 3)
 union all (select user_id,role from public.profiles where active and role='user' order by user_id limit 3)
 loop
  perform set_config('request.jwt.claim.sub',v.user_id::text,true);
  t:=clock_timestamp(); a:=public.house_groups_v2225();
  insert into fast_baseline values(v.user_id,v.role,a,extract(epoch from clock_timestamp()-t)*1000);
 end loop;
end $$;
-- Equivalent scope using the active profile loaded once. No person/target writes.
-- Staff care tab lists only directly assigned houses. Other tabs, community access, targets and person permissions remain unchanged.
create or replace function private.house_groups_v2225()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v public.profiles; v_review jsonb; result jsonb; v_community text;
begin
 select * into v from public.profiles where user_id=auth.uid() and active;
 if v.user_id is null or v.role not in ('admin','staff','user') then raise exception 'AUTH_REQUIRED'; end if;
 v_community:=private.community_key(v.community);
 v_review:=public.house_registration_review_cards_v2202();
 with review as (
   select r, r->>'id' house_id from jsonb_array_elements(v_review) r
 ), scoped as (
   select h.*, private.house_is_school_only_v2225(h) is_school, review.r audit
   from public.houses h left join review on review.house_id=h.id::text
   where h.superseded_by is null and h.verification_status='verified_jhcis'
   and (v.role='admin'
        or (v.role='staff' and v_community<>'' and private.community_key(h.community)=v_community)
        or (v.role='user' and h.volunteer_pid=v.volunteer_pid)
        or review.house_id is not null)
 ), counts as (
   select h.id,
    count(p.source_pid) registered_count,
    count(p.source_pid) filter(where p.jhcis_typelive=2) type2_count,
    count(p.source_pid) filter(where p.active and p.service_population_eligible and p.jhcis_typelive in (1,3)
      and coalesce(rs.service_target_active,true)) target_count,
    count(p.source_pid) filter(where p.jhcis_typelive is distinct from 2) other_count
   from scoped h left join public.health_persons p on p.house_pcucode=h.source_pcucode and p.hcode=h.hcode
   left join public.health_person_residence_status rs on rs.source_pcucode=p.source_pcucode and rs.source_pid=p.source_pid
   group by h.id
 ), cards as (
  select h.*,c.type2_count,c.target_count,c.registered_count,
   case when h.is_school then 'special'
    when h.audit is not null or h.volunteer_pid is null or coalesce(btrim(h.community),'')='' then 'review'
    when c.target_count>0 then 'care'
    when c.other_count>0 then 'review'
    else 'empty' end house_group
  from scoped h join counts c using(id)
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',id,'house_no',house_no,'moo',moo,'community',community,'hcode',hcode,
  'house_group',house_group,'type2_count',case when house_group='special' then 0 else type2_count end,
  'target_count',case when house_group='special' then 0 else target_count end,
  'review',audit,'review_required',review_required,'review_reason',review_reason,
  'latitude',latitude,'longitude',longitude,
  'reason',case when house_group='special' then 'โรงเรียน · เก็บเฉพาะทะเบียนบ้าน ไม่นับเป็นเป้าหมาย'
    when audit is not null then 'รอตรวจสอบทะเบียนบ้าน'
    when volunteer_pid is null or coalesce(btrim(community),'')='' then 'รอมอบหมายชุมชนหรือผู้รับผิดชอบ'
    when target_count>0 then 'มีเป้าหมายดูแลสุขภาพ'
    when type2_count>0 and house_group='empty' then 'มีชื่อทะเบียน type 2 แต่ไม่อยู่ในพื้นที่ · ไม่นับเป็นเป้าหมาย'
    when registered_count>0 then 'ยังไม่มีเป้าหมายสุขภาพ · รอตรวจสอบสถานะผู้พักอาศัย'
    else 'ไม่พบรายชื่อเป้าหมายในทะเบียน Cloud · ยังไม่ยืนยันสภาพการพักอาศัย' end
 ) order by nullif(regexp_replace(coalesce(house_no,''),'[^0-9].*$',''),'')::numeric nulls last,house_no,id),'[]'::jsonb)
 into result from cards
 where v.role<>'staff' or house_group<>'care'
    or (v.volunteer_pid is not null and volunteer_pid=v.volunteer_pid);
 return result;
end $$;

revoke all on function private.house_groups_v2225() from public,anon;
grant execute on function private.house_groups_v2225() to authenticated;

create temp table fast_results(role text, houses int, old_ms numeric, new_ms numeric, identical boolean);
do $$ declare v record; t timestamptz; a jsonb; ms numeric; begin
 for v in select * from fast_baseline loop
  perform set_config('request.jwt.claim.sub',v.user_id::text,true);
  t:=clock_timestamp(); a:=public.house_groups_v2225(); ms:=extract(epoch from clock_timestamp()-t)*1000;
  if a is distinct from v.payload then raise exception 'PAYLOAD_CHANGED for role %',v.role; end if;
  insert into fast_results values(v.role,jsonb_array_length(a),v.old_ms,ms,a=v.payload);
 end loop;
end $$;
select jsonb_agg(to_jsonb(r) order by role,houses) result from fast_results r;
rollback;
