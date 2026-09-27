-- OSM-PHC Cloud / Local reconciliation v2.0.45
-- Local Admin may inspect Cloud field-created houses/member requests against JHCIS.
-- Raw CID is exposed only to service_role RPC and must remain in Local process memory.
-- No function in this migration writes back to JHCIS.

begin;

create or replace function public.service_cloud_jhcis_reconcile_queue_v2045()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_requests jsonb := '[]'::jsonb;
  v_houses jsonb := '[]'::jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'request_id',r.id,
    'house_id',r.house_id,
    'citizen_id',private.decrypt_text_v190(r.citizen_id_cipher),
    'cid_last4',r.citizen_id_last4,
    'full_name',r.full_name,
    'birth_date',r.birth_date,
    'request_status',r.status,
    'linked_person_pcucode',r.linked_person_pcucode,
    'linked_person_id',r.linked_person_id,
    'created_at',r.created_at,
    'house',jsonb_build_object(
      'source_pcucode',h.source_pcucode,
      'hcode',h.hcode,
      'house_id_11',h.house_id_11,
      'house_no',h.house_no,
      'moo',h.moo,
      'community',h.community,
      'entry_source',h.entry_source
    )
  ) order by r.created_at), '[]'::jsonb)
  into v_requests
  from public.household_member_requests r
  join public.houses h on h.id=r.house_id
  where r.status in ('pending','needs_correction','verified')
    and r.linked_person_id is null;

  select coalesce(jsonb_agg(jsonb_build_object(
    'house_id',h.id,
    'source_pcucode',h.source_pcucode,
    'hcode',h.hcode,
    'house_id_11',h.house_id_11,
    'house_no',h.house_no,
    'moo',h.moo,
    'community',h.community,
    'entry_source',h.entry_source,
    'record_status',h.record_status,
    'field_created_at',h.field_created_at
  ) order by h.field_created_at nulls last,h.house_no), '[]'::jsonb)
  into v_houses
  from public.houses h
  where h.entry_source='field';

  return jsonb_build_object(
    'requests',v_requests,
    'field_houses',v_houses,
    'policy',jsonb_build_object(
      'person_match','exact Thai CID 13 digits in Local process memory',
      'house_match','unique house_id_11 then verify house_no + moo + community',
      'jhcis_write_back',false,
      'raw_cid_browser_exposed',false
    )
  );
end;
$$;

revoke all on function public.service_cloud_jhcis_reconcile_queue_v2045() from public,anon,authenticated;

grant execute on function public.service_cloud_jhcis_reconcile_queue_v2045() to service_role;

create or replace function public.service_link_member_request_v2045(
  p_request_id uuid,
  p_source_pcucode text,
  p_source_pid bigint
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_req public.household_member_requests%rowtype;
  v_house public.houses%rowtype;
  v_person public.health_persons%rowtype;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  select * into v_req from public.household_member_requests where id=p_request_id for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  if v_req.linked_person_id is not null then
    return jsonb_build_object('ok',true,'already_linked',true,'request_id',v_req.id);
  end if;
  if v_req.status not in ('pending','needs_correction','verified') then
    raise exception 'REQUEST_NOT_LINKABLE';
  end if;

  select * into v_house from public.houses where id=v_req.house_id;
  if not found then raise exception 'HOUSE_NOT_FOUND'; end if;

  select * into v_person from public.health_persons
  where source_pcucode=p_source_pcucode and source_pid=p_source_pid and active=true;
  if not found then raise exception 'PERSON_NOT_SYNCED_TO_CLOUD'; end if;
  if coalesce(v_person.jhcis_typelive,0) not in (1,3)
     or coalesce(v_person.service_population_eligible,false)=false then
    raise exception 'PERSON_TYPE_NOT_SERVICE_ELIGIBLE';
  end if;
  if v_person.house_pcucode<>v_house.source_pcucode or v_person.hcode<>v_house.hcode then
    raise exception 'PERSON_HOUSE_MISMATCH_REQUIRES_SYNC';
  end if;
  if v_person.citizen_id_hash is not null and v_person.citizen_id_hash<>v_req.citizen_id_hash then
    raise exception 'CITIZEN_ID_HASH_MISMATCH';
  end if;

  update public.household_member_requests
     set status='verified',
         review_note='เธ•เธฃเธงเธเธชเธญเธเธขเนเธญเธเธเธฅเธฑเธเธเธฑเธ JHCIS เนเธฅเนเธงเนเธฅเธฐเน€เธเธทเนเธญเธก PID เธชเธณเน€เธฃเนเธ',
         reviewed_at=now(),
         linked_person_pcucode=v_person.source_pcucode,
         linked_person_id=v_person.source_pid,
         updated_at=now()
   where id=v_req.id;

  insert into public.health_audit_log(action,entity,entity_id,source_pcucode,source_pid,hcode,severity,details)
  values('SERVICE_LINK','household_member_request',v_req.id::text,v_person.source_pcucode,v_person.source_pid,v_person.hcode,'verified',
    jsonb_build_object('source','local_jhcis_reverse_reconcile','cid_logged',false,'jhcis_write_back',false));

  return jsonb_build_object('ok',true,'request_id',v_req.id,'linked_person_id',v_person.source_pid,'status','verified');
end;
$$;

revoke all on function public.service_link_member_request_v2045(uuid,text,bigint) from public,anon,authenticated;

grant execute on function public.service_link_member_request_v2045(uuid,text,bigint) to service_role;

insert into public.app_settings(key,value)
values('cloud_jhcis_reverse_reconcile_v2045',jsonb_build_object(
  'version','2.0.45',
  'person_key','CID13 exact match; raw value service-role/local-memory only',
  'house_key','house_id_11 exact unique + house_no/moo/community verification',
  'typelive_policy','1/3 eligible; 2/4 found but require JHCIS correction; never create duplicate',
  'jhcis_write_back',false,
  'browser_raw_cid',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
