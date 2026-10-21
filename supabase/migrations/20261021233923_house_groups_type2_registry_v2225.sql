-- Read-only presentation of existing registration data; never activates type 2.
-- SECURITY DEFINER is needed only to count inactive rows hidden by person RLS.
-- Every public entry checks an active profile and the existing house scope.
create or replace function private.house_is_school_only_v2225(h public.houses)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(h.house_id_11='52010046170' or
   (h.hcode in ('2360','2587') and btrim(h.moo)='6' and btrim(h.house_no)='84'),false)
$$;
revoke all on function private.house_is_school_only_v2225(public.houses) from public,anon,authenticated;

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
 into result from cards;
 return result;
end $$;
revoke all on function private.house_groups_v2225() from public,anon;
grant execute on function private.house_groups_v2225() to authenticated;

create or replace function private.house_type2_notice_v2225(p_house_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v public.profiles; h public.houses; n bigint;
begin
 select * into v from public.profiles where user_id=auth.uid() and active;
 if v.user_id is null or v.role not in ('admin','staff','user') then raise exception 'AUTH_REQUIRED'; end if;
 select * into h from public.houses where id=p_house_id and superseded_by is null and verification_status='verified_jhcis';
 if h.id is null or not private.health_can_access_house(h.source_pcucode,h.hcode) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
 if private.house_is_school_only_v2225(h) then n:=0;
 else select count(*) into n from public.health_persons p where p.house_pcucode=h.source_pcucode and p.hcode=h.hcode and p.jhcis_typelive=2; end if;
 return jsonb_build_object('house_id',h.id,'house_no',h.house_no,'moo',h.moo,'community',h.community,
  'type2_count',n,'can_view_names',v.role in ('admin','staff') and n>0,'counted_as_target',false,
  'school_house_only',private.house_is_school_only_v2225(h));
end $$;
revoke all on function private.house_type2_notice_v2225(uuid) from public,anon;
grant execute on function private.house_type2_notice_v2225(uuid) to authenticated;

create or replace function private.house_type2_names_v2225(p_house_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.profiles; h public.houses; names jsonb;
begin
 select * into v from public.profiles where user_id=auth.uid() and active;
 if v.user_id is null or v.role not in ('admin','staff') then raise exception 'STAFF_OR_ADMIN_REQUIRED'; end if;
 select * into h from public.houses where id=p_house_id and superseded_by is null and verification_status='verified_jhcis';
 if h.id is null or not private.health_can_access_house(h.source_pcucode,h.hcode) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
 if private.house_is_school_only_v2225(h) then raise exception 'SCHOOL_HOUSE_ONLY'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('display_name',p.display_name,'jhcis_typelive',2,
   'counted_as_target',false) order by p.display_name),'[]'::jsonb) into names
 from public.health_persons p where p.house_pcucode=h.source_pcucode and p.hcode=h.hcode and p.jhcis_typelive=2;
 insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,hcode,severity,details)
 values(auth.uid(),'READ','house_type2_registry',h.id::text,h.source_pcucode,h.hcode,'info',
   jsonb_build_object('count',jsonb_array_length(names),'counted_as_target',false));
 return names;
end $$;
revoke all on function private.house_type2_names_v2225(uuid) from public,anon;
grant execute on function private.house_type2_names_v2225(uuid) to authenticated;

create or replace function public.house_groups_v2225() returns jsonb
language sql stable security invoker set search_path='' as $$
 select private.house_groups_v2225()
$$;
revoke all on function public.house_groups_v2225() from public,anon;
grant execute on function public.house_groups_v2225() to authenticated;

create or replace function public.house_type2_notice_v2225(p_house_id uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select private.house_type2_notice_v2225(p_house_id)
$$;
revoke all on function public.house_type2_notice_v2225(uuid) from public,anon;
grant execute on function public.house_type2_notice_v2225(uuid) to authenticated;

create or replace function public.house_type2_names_v2225(p_house_id uuid) returns jsonb
language sql volatile security invoker set search_path='' as $$
 select private.house_type2_names_v2225(p_house_id)
$$;
revoke all on function public.house_type2_names_v2225(uuid) from public,anon;
grant execute on function public.house_type2_names_v2225(uuid) to authenticated;
