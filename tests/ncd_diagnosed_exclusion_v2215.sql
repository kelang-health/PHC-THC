-- Regression test: always roll back the simulated diagnosis and field results.
begin;
DO $test$
DECLARE actor_id uuid; c record; k text; history_id uuid; was_blocked boolean;
BEGIN
 select user_id into actor_id from public.profiles where active and role='admin' limit 1;
 if actor_id is null then raise exception 'TEST_ADMIN_REQUIRED'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor_id,'role','authenticated')::text,true);
 FOR k IN SELECT unnest(array['bp','dtx']) LOOP
  select * into c from private.ncd_field_cases_v2203() where kind=k and screened_on<timezone('Asia/Bangkok',now())::date limit 1;
  if c.source_screen_id is null then raise exception 'TEST_CASE_REQUIRED_%',k; end if;
  insert into private.ncd_field_results_v2203(request_id,source_screen_id,kind,measured_on,period,sequence,sbp,dbp,pulse,dtx,fasting,recorded_by)
  values(gen_random_uuid(),c.source_screen_id,k,c.screened_on+1,case when k='bp' then 'morning' end,case when k='bp' then 1 end,case when k='bp' then 145 end,case when k='bp' then 95 end,case when k='bp' then 80 end,case when k='dtx' then 130 end,case when k='dtx' then true end,actor_id) returning id into history_id;
  if not exists(select 1 from jsonb_array_elements(public.ncd_field_worklist_v2203()) j where j->>'source_screen_id'=c.source_screen_id::text and j->>'kind'=k) then raise exception 'ELIGIBLE_HISTORY_MISSING';end if;
  update public.health_persons set has_ht=case when k='bp' then true else has_ht end,has_dm=case when k='dtx' then true else has_dm end where source_pcucode=c.source_pcucode and source_pid=c.source_pid;
  if exists(select 1 from private.ncd_field_cases_v2203() x where x.source_pcucode=c.source_pcucode and x.source_pid=c.source_pid and x.kind=k) then raise exception 'DIAGNOSED_CASE_LEAK';end if;
  if exists(select 1 from jsonb_array_elements(public.ncd_field_worklist_v2203()) j where j->>'source_pcucode'=c.source_pcucode and (j->>'source_pid')::bigint=c.source_pid and j->>'kind'=k) then raise exception 'WORKLIST_LEAK';end if;
  was_blocked:=false;
  begin
   perform public.save_ncd_field_result_v2203(c.source_screen_id,k,c.screened_on+1,gen_random_uuid(),145,95,80,'morning',2::smallint,null,null);
  exception when others then
   if sqlerrm='CASE_NOT_ALLOWED' then was_blocked:=true;else raise;end if;
  end;
  if not was_blocked then raise exception 'SAVE_NOT_BLOCKED';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor_id,'role','service_role')::text,true);
  if exists(select 1 from jsonb_array_elements(public.ncd_field_local_report_v2204(c.source_pcucode,'all')) j where (j->>'source_pid')::bigint=c.source_pid and j->>'kind'=k) then raise exception 'REPORT_LEAK';end if;
  if not exists(select 1 from private.ncd_field_results_v2203 where id=history_id) then raise exception 'HISTORY_REMOVED';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor_id,'role','authenticated')::text,true);
 END LOOP;
END $test$;
select 'PASS: BP and DTX diagnosis exclusions, existing history retained, saves blocked, reports excluded' result;
rollback;
