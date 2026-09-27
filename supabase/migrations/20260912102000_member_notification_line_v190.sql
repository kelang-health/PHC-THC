-- OSM-PHC Cloud v1.9.0
-- Phase B-D: household member requests, central admin notifications/Telegram outbox,
-- and LINE linkage/messaging/appointments.
-- JHCIS remains read-only. No Cloud function writes back to JHCIS.

begin;

-- ---------------------------------------------------------------------------
-- Shared security helpers
-- ---------------------------------------------------------------------------
create table if not exists private.system_crypto_v190 (
  singleton boolean primary key default true check (singleton),
  secret_key text not null,
  created_at timestamptz not null default now()
);

revoke all on private.system_crypto_v190 from public,anon,authenticated;

insert into private.system_crypto_v190(singleton,secret_key)
values (true,encode(extensions.gen_random_bytes(32),'hex'))
on conflict (singleton) do nothing;

create or replace function private.crypto_key_v190()
returns text
language sql stable security definer
set search_path=''
as $$ select secret_key from private.system_crypto_v190 where singleton=true $$;

revoke all on function private.crypto_key_v190() from public,anon,authenticated;

create or replace function private.thai_cid_valid_v190(p_cid text)
returns boolean
language plpgsql immutable
set search_path=''
as $$
declare
  v text:=regexp_replace(coalesce(p_cid,''),'\s','','g');
  s integer:=0;
  i integer;
  check_digit integer;
begin
  if v !~ '^[0-9]{13}$' then return false; end if;
  for i in 1..12 loop
    s:=s+(substr(v,i,1)::integer*(14-i));
  end loop;
  check_digit:=(11-(s%11))%10;
  return check_digit=substr(v,13,1)::integer;
end;
$$;

revoke all on function private.thai_cid_valid_v190(text) from public,anon,authenticated;

drop function if exists private.cid_hash_v190(text);

create function private.cid_hash_v190(p_cid text)
returns text
language sql stable security definer
set search_path=''
as $$
  select encode(extensions.hmac(regexp_replace(coalesce(p_cid,''),'\s','','g'),private.crypto_key_v190(),'sha256'),'hex')
$$;

revoke all on function private.cid_hash_v190(text) from public,anon,authenticated;

create or replace function private.encrypt_text_v190(p_value text)
returns bytea
language sql stable security definer
set search_path=''
as $$
  select extensions.pgp_sym_encrypt(coalesce(p_value,''),private.crypto_key_v190(),'cipher-algo=aes256')
$$;

revoke all on function private.encrypt_text_v190(text) from public,anon,authenticated;

create or replace function private.decrypt_text_v190(p_value bytea)
returns text
language sql stable security definer
set search_path=''
as $$
  select extensions.pgp_sym_decrypt(p_value,private.crypto_key_v190())
$$;

revoke all on function private.decrypt_text_v190(bytea) from public,anon,authenticated;

-- Hash-only matching projection for future JHCIS sync. Raw CID is never added to health_persons.
alter table public.health_persons
  add column if not exists citizen_id_hash text,
  add column if not exists citizen_id_last4 text;

create index if not exists health_persons_cid_hash_v190_idx
  on public.health_persons(citizen_id_hash) where citizen_id_hash is not null;

-- ---------------------------------------------------------------------------
-- Central notifications. Safe summaries only; sensitive detail remains in app.
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default extensions.gen_random_uuid(),
  event_type text not null,
  severity text not null default 'info' check (severity in ('info','success','warning','alert','critical')),
  recipient_user_id uuid references auth.users(id) on delete cascade,
  admin_only boolean not null default false,
  title text not null,
  body text not null default '',
  action_path text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists notifications_admin_created_v190_idx on public.notifications(admin_only,created_at desc);

create index if not exists notifications_recipient_v190_idx on public.notifications(recipient_user_id,created_at desc);

alter table public.notifications enable row level security;

revoke all on public.notifications from public,anon,authenticated;

grant select,update(read_at) on public.notifications to authenticated;

drop policy if exists notifications_select_v190 on public.notifications;

create policy notifications_select_v190 on public.notifications
for select to authenticated using (
  recipient_user_id=auth.uid()
  or (admin_only=true and private.current_role()='admin')
);

drop policy if exists notifications_read_v190 on public.notifications;

create policy notifications_read_v190 on public.notifications
for update to authenticated using (
  recipient_user_id=auth.uid()
  or (admin_only=true and private.current_role()='admin')
) with check (
  recipient_user_id=auth.uid()
  or (admin_only=true and private.current_role()='admin')
);

create table if not exists private.notification_outbox_v190 (
  id bigint generated always as identity primary key,
  notification_id uuid not null references public.notifications(id) on delete cascade,
  channel text not null check (channel in ('telegram','line')),
  status text not null default 'queued' check (status in ('queued','sending','sent','failed','cancelled')),
  attempt_count integer not null default 0,
  last_error text not null default '',
  next_attempt_at timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique(notification_id,channel)
);

revoke all on private.notification_outbox_v190 from public,anon,authenticated;

create or replace function private.safe_notification_text_v190(p_value text)
returns boolean
language sql immutable
set search_path=''
as $$
  select coalesce(p_value,'') !~ '[0-9]{13}'
     and lower(coalesce(p_value,'')) !~ '(password|api[ _-]?key|service[ _-]?role|bot[ _-]?token|secret)\s*[:=]'
$$;

revoke all on function private.safe_notification_text_v190(text) from public,anon,authenticated;

create or replace function private.emit_admin_notification_v190(
  p_event_type text,
  p_severity text,
  p_title text,
  p_body text,
  p_action_path text default '',
  p_metadata jsonb default '{}'::jsonb,
  p_telegram boolean default true
) returns uuid
language plpgsql security definer
set search_path=''
as $$
declare v_id uuid;
begin
  if not private.safe_notification_text_v190(p_title) or not private.safe_notification_text_v190(p_body) then
    raise exception 'UNSAFE_NOTIFICATION_CONTENT';
  end if;
  insert into public.notifications(event_type,severity,admin_only,title,body,action_path,metadata)
  values(left(coalesce(p_event_type,'system.event'),80),
         case when p_severity in ('info','success','warning','alert','critical') then p_severity else 'warning' end,
         true,left(coalesce(p_title,'OSM-PHC'),160),left(coalesce(p_body,''),500),
         left(coalesce(p_action_path,''),300),coalesce(p_metadata,'{}'::jsonb))
  returning id into v_id;
  if coalesce(p_telegram,true) then
    insert into private.notification_outbox_v190(notification_id,channel)
    values(v_id,'telegram') on conflict do nothing;
  end if;
  return v_id;
end;
$$;

revoke all on function private.emit_admin_notification_v190(text,text,text,text,text,jsonb,boolean) from public,anon,authenticated;

create or replace function public.admin_notification_center_v190(p_limit integer default 50)
returns table(id uuid,event_type text,severity text,title text,body text,action_path text,created_at timestamptz,read_at timestamptz)
language plpgsql stable security definer
set search_path=''
as $$
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  return query select n.id,n.event_type,n.severity,n.title,n.body,n.action_path,n.created_at,n.read_at
  from public.notifications n where n.admin_only=true order by n.created_at desc limit least(greatest(coalesce(p_limit,50),1),200);
end;
$$;

revoke all on function public.admin_notification_center_v190(integer) from public,anon;

grant execute on function public.admin_notification_center_v190(integer) to authenticated;

create or replace function public.emit_system_event_v190(
  p_event_type text,p_severity text,p_title text,p_body text,p_action_path text default ''
) returns uuid
language plpgsql security definer
set search_path=''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if p_event_type not in ('sync.failed','sync.recovered','database.timeout','security.alert','coordinate.review','hdc.reference_stale') then
    raise exception 'EVENT_NOT_ALLOWED';
  end if;
  return private.emit_admin_notification_v190(p_event_type,p_severity,p_title,p_body,p_action_path,'{}'::jsonb,true);
end;
$$;

revoke all on function public.emit_system_event_v190(text,text,text,text,text) from public,anon,authenticated;

grant execute on function public.emit_system_event_v190(text,text,text,text,text) to service_role;

create or replace function public.telegram_outbox_claim_v190(p_limit integer default 20)
returns table(outbox_id bigint,notification_id uuid,event_type text,severity text,title text,body text,action_path text)
language plpgsql security definer
set search_path=''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  return query
  with picked as (
    select o.id from private.notification_outbox_v190 o
    where o.channel='telegram' and o.status in ('queued','failed') and o.next_attempt_at<=now() and o.attempt_count<5
    order by o.created_at for update skip locked limit least(greatest(coalesce(p_limit,20),1),50)
  ), updated as (
    update private.notification_outbox_v190 o set status='sending',attempt_count=attempt_count+1
    from picked p where o.id=p.id returning o.*
  )
  select u.id,n.id,n.event_type,n.severity,n.title,n.body,n.action_path
  from updated u join public.notifications n on n.id=u.notification_id;
end;
$$;

revoke all on function public.telegram_outbox_claim_v190(integer) from public,anon,authenticated;

grant execute on function public.telegram_outbox_claim_v190(integer) to service_role;

create or replace function public.notification_outbox_finish_v190(p_outbox_id bigint,p_ok boolean,p_error text default '')
returns void
language plpgsql security definer
set search_path=''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  update private.notification_outbox_v190
  set status=case when p_ok then 'sent' else 'failed' end,
      sent_at=case when p_ok then now() else null end,
      last_error=left(coalesce(p_error,''),500),
      next_attempt_at=case when p_ok then next_attempt_at else now()+interval '10 minutes' end
  where id=p_outbox_id;
end;
$$;

revoke all on function public.notification_outbox_finish_v190(bigint,boolean,text) from public,anon,authenticated;

grant execute on function public.notification_outbox_finish_v190(bigint,boolean,text) to service_role;

-- ---------------------------------------------------------------------------
-- Phase B: household member request workflow
-- ---------------------------------------------------------------------------
create table if not exists public.household_member_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  house_id uuid not null references public.houses(id) on delete restrict,
  submitted_by uuid not null references auth.users(id),
  citizen_id_cipher bytea not null,
  citizen_id_hash text not null,
  citizen_id_last4 text not null check (citizen_id_last4 ~ '^[0-9]{4}$'),
  full_name text not null,
  birth_date date not null,
  status text not null default 'pending' check (status in ('pending','verified','needs_correction','rejected')),
  review_note text not null default '',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  linked_person_pcucode text,
  linked_person_id bigint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint member_request_link_pair_v190 check ((linked_person_pcucode is null)=(linked_person_id is null)),
  foreign key (linked_person_pcucode,linked_person_id) references public.health_persons(source_pcucode,source_pid)
);

create index if not exists member_request_house_v190_idx on public.household_member_requests(house_id,created_at desc);

create index if not exists member_request_status_v190_idx on public.household_member_requests(status,created_at desc);

create index if not exists member_request_cid_v190_idx on public.household_member_requests(citizen_id_hash,status);

alter table public.household_member_requests enable row level security;

revoke all on public.household_member_requests from public,anon,authenticated;

-- No direct authenticated table grants: sensitive ciphertext is RPC-only.

create or replace function private.can_access_house_id_v190(p_house_id uuid)
returns boolean
language sql stable security definer
set search_path=''
as $$
  select exists(select 1 from public.houses h where h.id=p_house_id and private.health_can_access_house(h.source_pcucode,h.hcode))
$$;

revoke all on function private.can_access_house_id_v190(uuid) from public,anon,authenticated;

create or replace function public.submit_household_member_request_v190(
  p_house_id uuid,p_citizen_id text,p_full_name text,p_birth_date date
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v_cid text:=regexp_replace(coalesce(p_citizen_id,''),'\s','','g');
  v_name text:=regexp_replace(btrim(coalesce(p_full_name,'')),'\s+',' ','g');
  v_hash text;
  v_id uuid;
  v_house public.houses%rowtype;
  v_existing bigint;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_house from public.houses where id=p_house_id;
  if not found then raise exception 'HOUSE_NOT_FOUND'; end if;
  if not private.health_can_access_house(v_house.source_pcucode,v_house.hcode) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
  if not private.thai_cid_valid_v190(v_cid) then raise exception 'INVALID_THAI_CITIZEN_ID'; end if;
  if char_length(v_name)<2 then raise exception 'NAME_REQUIRED'; end if;
  if p_birth_date is null or p_birth_date>current_date or p_birth_date<current_date-interval '120 years' then raise exception 'INVALID_BIRTH_DATE'; end if;
  v_hash:=private.cid_hash_v190(v_cid);
  select count(*) into v_existing from public.household_member_requests r
  where r.citizen_id_hash=v_hash and r.status in ('pending','needs_correction');
  if v_existing>0 then raise exception 'DUPLICATE_MEMBER_REQUEST'; end if;
  if exists(select 1 from public.health_persons p where p.citizen_id_hash=v_hash and p.active=true) then
    raise exception 'PERSON_ALREADY_EXISTS_REVIEW_LINK';
  end if;
  insert into public.household_member_requests(
    house_id,submitted_by,citizen_id_cipher,citizen_id_hash,citizen_id_last4,full_name,birth_date
  ) values (
    p_house_id,auth.uid(),private.encrypt_text_v190(v_cid),v_hash,right(v_cid,4),v_name,p_birth_date
  ) returning id into v_id;
  perform private.emit_admin_notification_v190(
    'member_request.created','warning','OSM-PHC: เธกเธตเธเธณเธเธญเน€เธเธดเนเธกเธชเธกเธฒเธเธดเธเนเธซเธกเน',
    'เธกเธตเธเธณเธเธญเน€เธเธดเนเธกเธชเธกเธฒเธเธดเธเธเนเธฒเธเนเธซเธกเน 1 เธฃเธฒเธข เธเธฃเธธเธ“เธฒเธ•เธฃเธงเธเธชเธญเธเนเธเธฃเธฐเธเธ','?panel=admin-member-requests',
    jsonb_build_object('request_id',v_id,'community',v_house.community),true
  );
  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,hcode,severity,details)
  values(auth.uid(),'CREATE','household_member_request',v_id::text,v_house.source_pcucode,v_house.hcode,'pending',jsonb_build_object('house_id',p_house_id,'cid_last4',right(v_cid,4)));
  return jsonb_build_object('ok',true,'id',v_id,'status','pending','masked_citizen_id','โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||right(v_cid,4));
end;
$$;

revoke all on function public.submit_household_member_request_v190(uuid,text,text,date) from public,anon;

grant execute on function public.submit_household_member_request_v190(uuid,text,text,date) to authenticated;

create or replace function public.household_member_requests_v190(p_house_id uuid)
returns table(id uuid,full_name text,birth_date date,masked_citizen_id text,status text,review_note text,linked boolean,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not private.can_access_house_id_v190(p_house_id) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
  return query select r.id,r.full_name,r.birth_date,'โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||r.citizen_id_last4,r.status,
    case when r.status='needs_correction' then r.review_note else '' end,
    r.linked_person_id is not null,r.created_at,r.updated_at
  from public.household_member_requests r where r.house_id=p_house_id order by r.created_at desc;
end;
$$;

revoke all on function public.household_member_requests_v190(uuid) from public,anon;

grant execute on function public.household_member_requests_v190(uuid) to authenticated;

create or replace function public.admin_member_request_queue_v190(p_status text default 'pending')
returns table(id uuid,house_id uuid,house_no text,moo text,community text,full_name text,birth_date date,masked_citizen_id text,status text,review_note text,created_at timestamptz,submitted_by uuid)
language plpgsql stable security definer
set search_path=''
as $$
declare v_status text:=lower(btrim(coalesce(p_status,'pending')));
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  return query select r.id,r.house_id,h.house_no,h.moo,h.community,r.full_name,r.birth_date,
    'โ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ขโ€ข'||r.citizen_id_last4,r.status,r.review_note,r.created_at,r.submitted_by
  from public.household_member_requests r join public.houses h on h.id=r.house_id
  where v_status='all' or r.status=v_status order by r.created_at desc;
end;
$$;

revoke all on function public.admin_member_request_queue_v190(text) from public,anon;

grant execute on function public.admin_member_request_queue_v190(text) to authenticated;

create or replace function public.admin_member_request_sensitive_v190(p_request_id uuid)
returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare v public.household_member_requests%rowtype; v_cid text;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  select * into v from public.household_member_requests where id=p_request_id;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  v_cid:=private.decrypt_text_v190(v.citizen_id_cipher);
  insert into public.health_audit_log(operator_id,action,entity,entity_id,severity,details)
  values(auth.uid(),'READ_SENSITIVE','household_member_request',v.id::text,'audit',jsonb_build_object('purpose','admin_review'));
  return jsonb_build_object('id',v.id,'citizen_id',v_cid,'full_name',v.full_name,'birth_date',v.birth_date,'status',v.status);
end;
$$;

revoke all on function public.admin_member_request_sensitive_v190(uuid) from public,anon;

grant execute on function public.admin_member_request_sensitive_v190(uuid) to authenticated;

create or replace function public.review_household_member_request_v190(
  p_request_id uuid,p_decision text,p_note text default '',p_link_pcucode text default null,p_link_pid bigint default null
) returns jsonb
language plpgsql security definer
set search_path=''
as $$
declare
  v public.household_member_requests%rowtype;
  h public.houses%rowtype;
  p public.health_persons%rowtype;
  d text:=lower(btrim(coalesce(p_decision,'')));
  v_status text;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  if d not in ('verify','needs_correction','reject') then raise exception 'INVALID_DECISION'; end if;
  select * into v from public.household_member_requests where id=p_request_id for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  if v.status not in ('pending','needs_correction') then raise exception 'REQUEST_ALREADY_REVIEWED'; end if;
  select * into h from public.houses where id=v.house_id;
  if d='verify' then
    if p_link_pcucode is not null or p_link_pid is not null then
      if p_link_pcucode is null or p_link_pid is null then raise exception 'LINK_PERSON_PAIR_REQUIRED'; end if;
      select * into p from public.health_persons where source_pcucode=p_link_pcucode and source_pid=p_link_pid and active=true;
      if not found then raise exception 'LINK_PERSON_NOT_FOUND'; end if;
      if p.house_pcucode<>h.source_pcucode or p.hcode<>h.hcode then raise exception 'LINK_PERSON_HOUSE_MISMATCH_REQUIRES_JHCIS_SYNC'; end if;
      if p.citizen_id_hash is not null and p.citizen_id_hash<>v.citizen_id_hash then raise exception 'CITIZEN_ID_HASH_MISMATCH'; end if;
    end if;
    v_status:='verified';
  elsif d='needs_correction' then v_status:='needs_correction';
  else v_status:='rejected'; end if;
  update public.household_member_requests set status=v_status,review_note=left(btrim(coalesce(p_note,'')),500),reviewed_by=auth.uid(),reviewed_at=now(),
    linked_person_pcucode=case when d='verify' then p_link_pcucode else null end,
    linked_person_id=case when d='verify' then p_link_pid else null end,updated_at=now()
  where id=p_request_id;
  insert into public.health_audit_log(operator_id,action,entity,entity_id,source_pcucode,source_pid,hcode,severity,details)
  values(auth.uid(),'REVIEW','household_member_request',v.id::text,h.source_pcucode,p_link_pid,h.hcode,v_status,jsonb_build_object('decision',d,'linked',p_link_pid is not null));
  return jsonb_build_object('ok',true,'status',v_status,'linked',p_link_pid is not null,
    'population_effective',d='verify' and p_link_pid is not null,
    'message',case when d='verify' and p_link_pid is null then 'เธ•เธฃเธงเธเธชเธญเธเธเธณเธเธญเนเธฅเนเธง เธฃเธญเน€เธเธทเนเธญเธกเธเธธเธเธเธฅเธเธฒเธ JHCIS Sync เธเธถเธเธเธฐเธเธฑเธเน€เธเนเธเธชเธกเธฒเธเธดเธเธเธฃเธดเธ' else '' end);
end;
$$;

revoke all on function public.review_household_member_request_v190(uuid,text,text,text,bigint) from public,anon;

grant execute on function public.review_household_member_request_v190(uuid,text,text,text,bigint) to authenticated;

-- Service-only sync helper: hashes CID server-side; never persists raw CID.
create or replace function public.sync_health_person_cid_hash_v190(p_source_pcucode text,p_source_pid bigint,p_citizen_id text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_cid text:=regexp_replace(coalesce(p_citizen_id,''),'\s','','g');
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if not private.thai_cid_valid_v190(v_cid) then raise exception 'INVALID_THAI_CITIZEN_ID'; end if;
  update public.health_persons set citizen_id_hash=private.cid_hash_v190(v_cid),citizen_id_last4=right(v_cid,4)
  where source_pcucode=p_source_pcucode and source_pid=p_source_pid;
end;
$$;

revoke all on function public.sync_health_person_cid_hash_v190(text,bigint,text) from public,anon,authenticated;

grant execute on function public.sync_health_person_cid_hash_v190(text,bigint,text) to service_role;

-- Automatically queue admin alert for urgent NCD results. Message contains no person identifier.
create or replace function private.notify_urgent_ncd_v190()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.severity in ('alert','urgent') then
    perform private.emit_admin_notification_v190('health.urgent',case when new.severity='urgent' then 'critical' else 'alert' end,
      'OSM-PHC: เธเธเธเธฅเธเธฑเธ”เธเธฃเธญเธเธ—เธตเนเธ•เนเธญเธเธ•เธดเธ”เธ•เธฒเธก','เธกเธตเธเธฅเธเธฑเธ”เธเธฃเธญเธเธ—เธตเนเธ•เนเธญเธเธ•เธดเธ”เธ•เธฒเธกเนเธเธเธทเนเธเธ—เธตเน เธเธฃเธธเธ“เธฒเน€เธเธดเธ”เธฃเธฐเธเธเน€เธเธทเนเธญเธ”เธนเธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”','?panel=health',
      jsonb_build_object('screening_id',new.id,'severity',new.severity),true);
  end if;
  return new;
end;
$$;

revoke all on function private.notify_urgent_ncd_v190() from public,anon,authenticated;

drop trigger if exists trg_notify_urgent_ncd_v190 on public.health_ncd_screenings;

create trigger trg_notify_urgent_ncd_v190 after insert on public.health_ncd_screenings
for each row execute function private.notify_urgent_ncd_v190();

-- ---------------------------------------------------------------------------
-- Phase D: LINE linkage and communication. LINE is a channel, never auth DB.
-- ---------------------------------------------------------------------------
create table if not exists public.user_line_links (
  app_user_id uuid primary key references auth.users(id) on delete cascade,
  line_user_hash text not null unique,
  line_user_cipher bytea not null,
  active boolean not null default true,
  linked_at timestamptz not null default now(),
  unlinked_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists private.line_link_tokens_v190 (
  id uuid primary key default extensions.gen_random_uuid(),
  app_user_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

revoke all on private.line_link_tokens_v190 from public,anon,authenticated;

create table if not exists public.line_messages (
  id uuid primary key default extensions.gen_random_uuid(),
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  message_type text not null default 'notice' check (message_type in ('notice','appointment','urgent_task','system')),
  body text not null,
  action_path text not null default '',
  status text not null default 'queued' check (status in ('queued','sending','sent','failed','cancelled')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  last_error text not null default ''
);

create index if not exists line_messages_recipient_v190_idx on public.line_messages(recipient_user_id,created_at desc);

create table if not exists public.appointments (
  id uuid primary key default extensions.gen_random_uuid(),
  app_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  appointment_at timestamptz not null,
  location_text text not null default '',
  note text not null default '',
  status text not null default 'scheduled' check (status in ('scheduled','cancelled','completed')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.appointment_responses (
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  app_user_id uuid not null references auth.users(id) on delete cascade,
  response text not null check (response in ('accepted','declined','acknowledged')),
  responded_at timestamptz not null default now(),
  primary key(appointment_id,app_user_id)
);

alter table public.user_line_links enable row level security;

alter table public.line_messages enable row level security;

alter table public.appointments enable row level security;

alter table public.appointment_responses enable row level security;

revoke all on public.user_line_links,public.line_messages,public.appointments,public.appointment_responses from public,anon,authenticated;

grant select on public.appointments,public.appointment_responses to authenticated;

drop policy if exists appointments_select_v190 on public.appointments;

create policy appointments_select_v190 on public.appointments for select to authenticated using (app_user_id=auth.uid() or private.current_role()='admin');

drop policy if exists appointment_responses_select_v190 on public.appointment_responses;

create policy appointment_responses_select_v190 on public.appointment_responses for select to authenticated using (app_user_id=auth.uid() or private.current_role()='admin');

create or replace function public.my_line_status_v190()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v public.user_line_links%rowtype; v_next public.appointments%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v from public.user_line_links where app_user_id=auth.uid() and active=true;
  select * into v_next from public.appointments where app_user_id=auth.uid() and status='scheduled' and appointment_at>=now() order by appointment_at limit 1;
  return jsonb_build_object('connected',found or exists(select 1 from public.user_line_links l where l.app_user_id=auth.uid() and l.active=true),
    'linked_at',(select linked_at from public.user_line_links where app_user_id=auth.uid() and active=true),
    'next_appointment',case when v_next.id is null then null else jsonb_build_object('id',v_next.id,'title',v_next.title,'appointment_at',v_next.appointment_at,'location',v_next.location_text) end);
end;
$$;

revoke all on function public.my_line_status_v190() from public,anon;

grant execute on function public.my_line_status_v190() to authenticated;

create or replace function public.create_line_link_code_v190()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_code text; v_hash text; v_id uuid;
begin
  if auth.uid() is null or private.current_role() not in ('user','staff','admin') then raise exception 'AUTH_REQUIRED'; end if;
  delete from private.line_link_tokens_v190 where app_user_id=auth.uid() and used_at is null;
  v_code:=upper(substr(replace(extensions.gen_random_uuid()::text,'-',''),1,8));
  v_hash:=private.cid_hash_v190('LINE:'||v_code);
  insert into private.line_link_tokens_v190(app_user_id,token_hash,expires_at) values(auth.uid(),v_hash,now()+interval '10 minutes') returning id into v_id;
  return jsonb_build_object('code',v_code,'expires_at',now()+interval '10 minutes');
end;
$$;

revoke all on function public.create_line_link_code_v190() from public,anon;

grant execute on function public.create_line_link_code_v190() to authenticated;

create or replace function public.consume_line_link_code_v190(p_code text,p_line_user_id text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_token private.line_link_tokens_v190%rowtype; v_hash text; v_line_hash text;
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  if coalesce(length(btrim(p_line_user_id)),0)<5 then raise exception 'INVALID_LINE_USER_ID'; end if;
  v_hash:=private.cid_hash_v190('LINE:'||upper(btrim(p_code)));
  select * into v_token from private.line_link_tokens_v190 where token_hash=v_hash and used_at is null and expires_at>now() for update;
  if not found then raise exception 'LINK_CODE_INVALID_OR_EXPIRED'; end if;
  v_line_hash:=private.cid_hash_v190('LINEID:'||btrim(p_line_user_id));
  if exists(select 1 from public.user_line_links where line_user_hash=v_line_hash and app_user_id<>v_token.app_user_id and active=true) then raise exception 'LINE_ALREADY_LINKED'; end if;
  insert into public.user_line_links(app_user_id,line_user_hash,line_user_cipher,active,linked_at,updated_at)
  values(v_token.app_user_id,v_line_hash,private.encrypt_text_v190(btrim(p_line_user_id)),true,now(),now())
  on conflict(app_user_id) do update set line_user_hash=excluded.line_user_hash,line_user_cipher=excluded.line_user_cipher,active=true,linked_at=now(),unlinked_at=null,updated_at=now();
  update private.line_link_tokens_v190 set used_at=now() where id=v_token.id;
  return jsonb_build_object('ok',true,'app_user_id',v_token.app_user_id);
end;
$$;

revoke all on function public.consume_line_link_code_v190(text,text) from public,anon,authenticated;

grant execute on function public.consume_line_link_code_v190(text,text) to service_role;

create or replace function public.unlink_my_line_v190()
returns void language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 update public.user_line_links set active=false,unlinked_at=now(),updated_at=now() where app_user_id=auth.uid();
end;
$$;

revoke all on function public.unlink_my_line_v190() from public,anon;

grant execute on function public.unlink_my_line_v190() to authenticated;

create or replace function public.admin_line_overview_v190()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  return jsonb_build_object(
    'users_total',(select count(*) from public.profiles where active=true and role in ('user','staff','admin')),
    'line_connected',(select count(*) from public.user_line_links where active=true),
    'line_not_connected',(select count(*) from public.profiles p where p.active=true and p.role in ('user','staff','admin') and not exists(select 1 from public.user_line_links l where l.app_user_id=p.user_id and l.active=true)),
    'upcoming_appointments',(select count(*) from public.appointments where status='scheduled' and appointment_at>=now()),
    'message_failed',(select count(*) from public.line_messages where status='failed')
  );
end;
$$;

revoke all on function public.admin_line_overview_v190() from public,anon;

grant execute on function public.admin_line_overview_v190() to authenticated;

create or replace function public.admin_queue_line_message_v190(
  p_recipient_user_id uuid,p_body text,p_action_path text default '',p_message_type text default 'notice'
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  if not private.safe_notification_text_v190(p_body) then raise exception 'UNSAFE_MESSAGE_CONTENT'; end if;
  if not exists(select 1 from public.profiles where user_id=p_recipient_user_id and active=true) then raise exception 'RECIPIENT_NOT_ACTIVE'; end if;
  if not exists(select 1 from public.user_line_links where app_user_id=p_recipient_user_id and active=true) then raise exception 'LINE_NOT_CONNECTED'; end if;
  insert into public.line_messages(recipient_user_id,message_type,body,action_path,created_by)
  values(p_recipient_user_id,case when p_message_type in ('notice','appointment','urgent_task','system') then p_message_type else 'notice' end,left(p_body,500),left(coalesce(p_action_path,''),300),auth.uid()) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.admin_queue_line_message_v190(uuid,text,text,text) from public,anon;

grant execute on function public.admin_queue_line_message_v190(uuid,text,text,text) to authenticated;

create or replace function public.line_outbox_claim_v190(p_limit integer default 20)
returns table(message_id uuid,line_user_id text,body text,action_path text)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  return query
  with picked as (
    select m.id from public.line_messages m join public.user_line_links l on l.app_user_id=m.recipient_user_id and l.active=true
    where m.status in ('queued','failed') order by m.created_at for update of m skip locked limit least(greatest(coalesce(p_limit,20),1),50)
  ), u as (
    update public.line_messages m set status='sending' from picked p where m.id=p.id returning m.*
  )
  select u.id,private.decrypt_text_v190(l.line_user_cipher),u.body,u.action_path from u join public.user_line_links l on l.app_user_id=u.recipient_user_id and l.active=true;
end;
$$;

revoke all on function public.line_outbox_claim_v190(integer) from public,anon,authenticated;

grant execute on function public.line_outbox_claim_v190(integer) to service_role;

create or replace function public.line_message_finish_v190(p_message_id uuid,p_ok boolean,p_error text default '')
returns void language plpgsql security definer set search_path=''
as $$
begin
 if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
 update public.line_messages set status=case when p_ok then 'sent' else 'failed' end,sent_at=case when p_ok then now() else null end,last_error=left(coalesce(p_error,''),500) where id=p_message_id;
end;
$$;

revoke all on function public.line_message_finish_v190(uuid,boolean,text) from public,anon,authenticated;

grant execute on function public.line_message_finish_v190(uuid,boolean,text) to service_role;

create or replace function public.admin_create_appointment_v190(p_app_user_id uuid,p_title text,p_appointment_at timestamptz,p_location text default '',p_note text default '')
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if auth.uid() is null or private.current_role()<>'admin' then raise exception 'ADMIN_REQUIRED'; end if;
  if p_appointment_at is null or p_appointment_at<now()-interval '5 minutes' then raise exception 'INVALID_APPOINTMENT_TIME'; end if;
  insert into public.appointments(app_user_id,title,appointment_at,location_text,note,created_by)
  values(p_app_user_id,left(btrim(p_title),160),p_appointment_at,left(btrim(coalesce(p_location,'')),240),left(btrim(coalesce(p_note,'')),500),auth.uid()) returning id into v_id;
  if exists(select 1 from public.user_line_links where app_user_id=p_app_user_id and active=true) then
    insert into public.line_messages(recipient_user_id,message_type,body,action_path,created_by)
    values(p_app_user_id,'appointment','เธกเธตเธเธฑเธ”เธซเธกเธฒเธขเนเธซเธกเน เธเธฃเธธเธ“เธฒเน€เธเธดเธ” OSM-PHC เน€เธเธทเนเธญเธ”เธนเธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”','?panel=overview',auth.uid());
  end if;
  return v_id;
end;
$$;

revoke all on function public.admin_create_appointment_v190(uuid,text,timestamptz,text,text) from public,anon;

grant execute on function public.admin_create_appointment_v190(uuid,text,timestamptz,text,text) to authenticated;

create or replace function public.respond_appointment_v190(p_appointment_id uuid,p_response text)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_response not in ('accepted','declined','acknowledged') then raise exception 'INVALID_RESPONSE'; end if;
  if not exists(select 1 from public.appointments a where a.id=p_appointment_id and a.app_user_id=auth.uid()) then raise exception 'APPOINTMENT_OUT_OF_SCOPE'; end if;
  insert into public.appointment_responses(appointment_id,app_user_id,response) values(p_appointment_id,auth.uid(),p_response)
  on conflict(appointment_id,app_user_id) do update set response=excluded.response,responded_at=now();
end;
$$;

revoke all on function public.respond_appointment_v190(uuid,text) from public,anon;

grant execute on function public.respond_appointment_v190(uuid,text) to authenticated;

insert into public.app_settings(key,value)
values ('five_features_v190',jsonb_build_object(
  'version','1.9.0','member_requests',true,'telegram_admin_only',true,'line_linked_users_only',true,
  'jhcis_write_back',false,'citizen_id_storage','AES256 ciphertext in request + keyed hash/last4; never list/log raw CID',
  'telegram_secret_location','Supabase server secret only','line_secret_location','Supabase server secret only'
)) on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
