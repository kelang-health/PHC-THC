-- Run as database owner. No permanent changes; all test state rolls back.
begin;
create temp table staff_direct_baseline(user_id uuid,role text,volunteer_pid bigint,cards jsonb);
do $$ declare p public.profiles; begin
 for p in select * from public.profiles where active and role='staff'
  union all (select * from public.profiles where active and role='admin' limit 1)
  union all (select * from public.profiles where active and role='user' limit 1)
 loop
  perform set_config('request.jwt.claim.sub',p.user_id::text,true);
  insert into staff_direct_baseline values(p.user_id,p.role,p.volunteer_pid,public.house_groups_v2225());
 end loop;
end $$;

create temp table staff_direct_results(role text,before_care int,after_care int,other_groups_unchanged boolean);
do $$ declare b record; actual jsonb; expected jsonb; old_count int; new_count int; begin
 for b in select * from staff_direct_baseline loop
  perform set_config('request.jwt.claim.sub',b.user_id::text,true);
  actual:=public.house_groups_v2225();
  select coalesce(jsonb_agg(r order by ord),'[]'::jsonb) into expected
  from jsonb_array_elements(b.cards) with ordinality q(r,ord)
  where b.role<>'staff' or r->>'house_group'<>'care' or exists(
   select 1 from public.houses h where h.id=(r->>'id')::uuid and b.volunteer_pid is not null and h.volunteer_pid=b.volunteer_pid);
  if actual<>expected then raise exception 'GROUP_DELTA_MISMATCH: %',b.role;end if;
  if b.role='staff' and exists(select 1 from jsonb_array_elements(actual) r join public.houses h on h.id=(r->>'id')::uuid
   where r->>'house_group'='care' and (b.volunteer_pid is null or h.volunteer_pid is distinct from b.volunteer_pid)) then raise exception 'STAFF_OTHER_OWNER_LEAK';end if;
  select count(*) into old_count from jsonb_array_elements(b.cards) r where r->>'house_group'='care';
  select count(*) into new_count from jsonb_array_elements(actual) r where r->>'house_group'='care';
  insert into staff_direct_results values(b.role,old_count,new_count,true);
 end loop;
 if (select count(*) from staff_direct_results where role='staff')<>(select count(*) from public.profiles where active and role='staff') then raise exception 'MISSING_STAFF_TEST';end if;
end $$;
select role,count(*) accounts_tested,min(before_care) min_before,max(before_care) max_before,min(after_care) min_after,max(after_care) max_after,bool_and(other_groups_unchanged) other_groups_unchanged from staff_direct_results group by role order by role;

rollback;
