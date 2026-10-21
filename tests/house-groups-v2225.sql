-- Run as the database owner. All test reads/audit inserts are rolled back.
begin;
create temp table house_group_test_results(test text,passed boolean);
do $$
declare v public.profiles; h public.houses; other_house uuid; a jsonb; notice jsonb; names jsonb; n int; denied boolean; school uuid;
begin
 for v in select distinct on(role) * from public.profiles where active and role in ('admin','staff','user')
   and (role='admin' or exists(select 1 from public.houses hx join public.health_persons p on p.house_pcucode=hx.source_pcucode and p.hcode=hx.hcode and p.jhcis_typelive=2
    where hx.superseded_by is null and hx.verification_status='verified_jhcis' and
     ((role='staff' and private.community_key(hx.community)=private.community_key(public.profiles.community)) or
      (role='user' and hx.volunteer_pid=public.profiles.volunteer_pid)))) order by role,user_id
 loop
  perform set_config('request.jwt.claim.sub',v.user_id::text,true);
  a:=public.house_groups_v2225();
  if exists(select 1 from jsonb_array_elements(a) r where r ? 'display_name' or r ? 'members') then raise exception 'NAME_LEAK'; end if;
  if (select count(*) from jsonb_array_elements(a))<>(select count(distinct r->>'id') from jsonb_array_elements(a) r) then raise exception 'DUPLICATE_GROUP'; end if;
  if exists(select 1 from jsonb_array_elements(a) r where r->>'house_group'='empty' and (r->>'target_count')::int<>0) then raise exception 'EMPTY_TARGET'; end if;
  if exists(select 1 from jsonb_array_elements(a) r join public.houses hx on hx.id=(r->>'id')::uuid
     where not private.health_can_access_house(hx.source_pcucode,hx.hcode)
      and not exists(select 1 from jsonb_array_elements(public.house_registration_review_cards_v2202()) q where q->>'id'=hx.id::text)) then raise exception 'SCOPE_LEAK'; end if;
  insert into house_group_test_results values(v.role||': groups unique, names absent, scope and zero empty targets',true);
  select hh.* into h from public.houses hh join public.health_persons p on p.house_pcucode=hh.source_pcucode and p.hcode=hh.hcode and p.jhcis_typelive=2
   where hh.superseded_by is null and hh.verification_status='verified_jhcis' and private.health_can_access_house(hh.source_pcucode,hh.hcode)
    and not private.house_is_school_only_v2225(hh) limit 1;
  if h.id is null then raise exception 'TYPE2_FIXTURE_MISSING'; end if;
  notice:=public.house_type2_notice_v2225(h.id);
  select count(*) into n from public.health_persons p where p.house_pcucode=h.source_pcucode and p.hcode=h.hcode and p.jhcis_typelive=2;
  if (notice->>'type2_count')::int<>n or (notice->>'counted_as_target')::boolean or notice ? 'display_name' then raise exception 'COUNT_WRONG'; end if;
  insert into house_group_test_results values(v.role||': count only, type2 excluded',true);
  if v.role='user' then
   denied:=false;
   begin perform public.house_type2_names_v2225(h.id); exception when others then if sqlerrm='STAFF_OR_ADMIN_REQUIRED' then denied:=true; else raise; end if; end;
   if not denied or (notice->>'can_view_names')::boolean then raise exception 'USER_NAMES_LEAK'; end if;
   insert into house_group_test_results values('user: direct names RPC denied',true);
  else
   names:=public.house_type2_names_v2225(h.id);
   if jsonb_array_length(names)<>n or not (notice->>'can_view_names')::boolean then raise exception 'NAMES_WRONG'; end if;
   if exists(select 1 from jsonb_array_elements(names) r where r ? 'source_pid' or r ? 'birth_date' or r ? 'gender' or (r->>'counted_as_target')::boolean) then raise exception 'EXCESS_DATA'; end if;
   if not exists(select 1 from public.health_audit_log l where l.entity='house_type2_registry' and l.entity_id=h.id::text and l.operator_id=v.user_id and l.action='READ') then raise exception 'AUDIT_MISSING'; end if;
   insert into house_group_test_results values(v.role||': explicit names minimal, audited, excluded',true);
  end if;
  if v.role<>'admin' then
   select hh.id into other_house from public.houses hh where hh.superseded_by is null and hh.verification_status='verified_jhcis' and not private.health_can_access_house(hh.source_pcucode,hh.hcode) limit 1;
   denied:=false;begin perform public.house_type2_notice_v2225(other_house); exception when others then if sqlerrm='HOUSE_OUT_OF_SCOPE' then denied:=true;else raise;end if;end;
   if not denied then raise exception 'OUTSIDE_COUNT_LEAK';end if;
   if v.role='staff' then
    denied:=false;begin perform public.house_type2_names_v2225(other_house); exception when others then if sqlerrm='HOUSE_OUT_OF_SCOPE' then denied:=true;else raise;end if;end;
    if not denied then raise exception 'OUTSIDE_NAMES_LEAK';end if;
   end if;
   insert into house_group_test_results values(v.role||': outside scope denied',true);
  else
   select hh.id into school from public.houses hh where hh.superseded_by is null and hh.verification_status='verified_jhcis' and private.house_is_school_only_v2225(hh) limit 1;
   notice:=public.house_type2_notice_v2225(school);
   if (notice->>'type2_count')::int<>0 or not (notice->>'school_house_only')::boolean then raise exception 'SCHOOL_EXPOSED';end if;
   if not exists(select 1 from jsonb_array_elements(a) r where r->>'id'=school::text and r->>'house_group'='special') then raise exception 'SCHOOL_GROUP_WRONG';end if;
   denied:=false;begin perform public.house_type2_names_v2225(school); exception when others then if sqlerrm='SCHOOL_HOUSE_ONLY' then denied:=true;else raise;end if;end;
   if not denied then raise exception 'SCHOOL_NAMES_LEAK';end if;
   insert into house_group_test_results values('school: separate, no names, no population targets',true);
  end if;
 end loop;
 if (select count(*) from house_group_test_results where test like '%count only%')<>3 then raise exception 'MISSING_ROLE';end if;
 perform set_config('request.jwt.claim.sub','',true);
 denied:=false;begin perform public.house_groups_v2225();exception when others then if sqlerrm='AUTH_REQUIRED' then denied:=true;else raise;end if;end;
 if not denied then raise exception 'ANON_LEAK';end if;
 insert into house_group_test_results values('signed out: denied',true);
 for v in select * from public.profiles where not active limit 1 loop
  perform set_config('request.jwt.claim.sub',v.user_id::text,true);
  denied:=false;begin perform public.house_groups_v2225();exception when others then if sqlerrm='AUTH_REQUIRED' then denied:=true;else raise;end if;end;
  if not denied then raise exception 'INACTIVE_LEAK';end if;
  insert into house_group_test_results values('inactive account: denied',true);
 end loop;
end $$;
select * from house_group_test_results;
rollback;
