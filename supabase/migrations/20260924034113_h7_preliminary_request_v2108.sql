-- H7.1 preliminary requests are NOT confirmed bookings and reserve no seats.
-- No patient history, lab result, risk group, phone, or name is stored here.
create table if not exists public.h7_preliminary_requests_v2108 (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.cloud_announcements_v2083(id),
  slot_id uuid not null references public.cloud_event_slots_v2085(id),
  source_pcucode text not null check (length(source_pcucode) between 1 and 30),
  source_pid bigint not null check (source_pid > 0),
  requested_by uuid not null references auth.users(id),
  anti_hcv_requested boolean not null default false,
  hbsag_requested boolean not null default false,
  status text not null default 'pending_local' check (status in
    ('pending_local','local_candidate','needs_review','not_in_cohort','cancelled')),
  reason_code text not null default 'awaiting_local',
  policy_version text,
  evaluated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (anti_hcv_requested or hbsag_requested)
);
create unique index if not exists h7_preliminary_requests_v2108_active_person_idx
  on public.h7_preliminary_requests_v2108(event_id,source_pcucode,source_pid)
  where status <> 'cancelled';
create index if not exists h7_preliminary_requests_v2108_queue_idx
  on public.h7_preliminary_requests_v2108(status,created_at,id);
alter table public.h7_preliminary_requests_v2108 enable row level security;
revoke all on public.h7_preliminary_requests_v2108 from anon,authenticated;
grant select,insert,update on public.h7_preliminary_requests_v2108 to service_role;

-- Deliberately separate from the real booking RPC. This does not reserve a slot.
create or replace function private.h7_submit_preliminary_v2108(
  p_event uuid,p_slot uuid,p_pcucode text,p_pid bigint,p_hcv boolean,p_hbsag boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid; v_volunteer_pid bigint; v_community text;
        v_birth date; v_id uuid; v_slot public.cloud_event_slots_v2085%rowtype;
        v_event public.cloud_announcements_v2083%rowtype;
begin
  v_user:=auth.uid();
  if v_user is null then raise exception 'เธเธฃเธธเธ“เธฒเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ' using errcode='42501'; end if;
  select volunteer_pid,community into v_volunteer_pid,v_community from public.profiles
    where user_id=v_user and active is true and role in ('user','staff');
  if v_volunteer_pid is null then raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธชเนเธเธเธณเธเธญ' using errcode='42501'; end if;
  if p_pcucode is null or length(p_pcucode) not between 1 and 30 or p_pid is null or p_pid<=0
     or (p_hcv is not true and p_hbsag is not true) then
    raise exception 'เธเนเธญเธกเธนเธฅเธเธณเธเธญเนเธกเนเธเธฃเธ' using errcode='22023';
  end if;
  select hp.birth_date into v_birth from public.health_persons hp
    join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
    where hp.source_pcucode=p_pcucode and hp.source_pid=p_pid
      and hp.active is true and hp.service_population_eligible is true
      and h.superseded_by is null and h.verification_status='verified_jhcis'
      and h.volunteer_pid=v_volunteer_pid
      and private.health_can_access_house(hp.house_pcucode,hp.hcode);
  if not found then raise exception 'เธเธธเธเธเธฅเธเธตเนเนเธกเนเธญเธขเธนเนเนเธเธเธงเธฒเธกเธฃเธฑเธเธเธดเธ”เธเธญเธ' using errcode='42501'; end if;
  if v_birth is null or v_birth>=date '1992-01-01' then
    raise exception 'เธเธณเธเธญเนเธเธเธเธตเน€เธเธดเธ”เธเธตเนเนเธกเนเธเธฃเธญเธเธเธฅเธธเธก เธเธฃเธธเธ“เธฒเนเธซเนเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธ•เธฃเธงเธเธเนเธญเธเนเธเธเธตเนเธญเธทเนเธ'
      using errcode='22023';
  end if;
  select * into v_slot from public.cloud_event_slots_v2085 where id=p_slot;
  if not found or v_slot.announcement_id<>p_event or v_slot.status<>'open'
      or v_slot.starts_at<=now() then
    raise exception 'เธฃเธญเธเธเธฃเธดเธเธฒเธฃเนเธกเนเธเธฃเนเธญเธกเธฃเธฑเธเธเธณเธเธญ' using errcode='22023';
  end if;
  select * into v_event from public.cloud_announcements_v2083 where id=p_event;
  if not found or v_event.kind<>'event' or v_event.event_subtype<>'hcv_hbsag'
      or v_event.status<>'published' or v_event.audience<>'user'
      or v_event.booking_enabled is not true or v_event.is_demo is true
      or v_event.pilot_mode is not true or v_event.pilot_approved_at is null
      or not private.hcv_pilot_can_access_v2095(v_event.id)
      or v_slot.capacity>5
      or (v_event.target_community is not null and v_event.target_community<>v_community)
      or (p_hcv is true and v_event.hcv_enabled is not true)
      or (p_hbsag is true and v_event.hbsag_enabled is not true)
      or (v_event.booking_opens_at is not null and v_event.booking_opens_at>now())
      or (v_event.booking_closes_at is not null and v_event.booking_closes_at<now()) then
    raise exception 'เธเธดเธเธเธฃเธฃเธกเธขเธฑเธเนเธกเนเน€เธเธดเธ”เธฃเธฑเธเธเธณเธเธญ' using errcode='22023';
  end if;
  if exists (select 1 from public.cloud_event_bookings_v2085 b where
      b.announcement_id=p_event and b.source_pcucode=p_pcucode
      and b.source_pid=p_pid and b.status='booked') then
    raise exception 'เธเธธเธเธเธฅเธเธตเนเธกเธตเธเธฑเธ”เธญเธขเธนเนเนเธฅเนเธง' using errcode='22023';
  end if;
  select id into v_id from public.h7_preliminary_requests_v2108
    where event_id=p_event and source_pcucode=p_pcucode and source_pid=p_pid
      and status<>'cancelled' limit 1;
  if v_id is not null then
    return jsonb_build_object('status','already_requested','request_id',v_id,
      'seat_reserved',false);
  end if;
  begin
    insert into public.h7_preliminary_requests_v2108
      (event_id,slot_id,source_pcucode,source_pid,requested_by,
       anti_hcv_requested,hbsag_requested)
    values(p_event,p_slot,p_pcucode,p_pid,v_user,p_hcv is true,p_hbsag is true)
    returning id into v_id;
  exception when unique_violation then
    select id into v_id from public.h7_preliminary_requests_v2108
      where event_id=p_event and source_pcucode=p_pcucode and source_pid=p_pid
        and status<>'cancelled' limit 1;
    if v_id is null then raise; end if;
    return jsonb_build_object('status','already_requested','request_id',v_id,
      'seat_reserved',false);
  end;
  return jsonb_build_object('status','pending_local','request_id',v_id,
    'seat_reserved',false);
end;
$$;
revoke all on function private.h7_submit_preliminary_v2108(uuid,uuid,text,bigint,boolean,boolean)
  from public,anon,authenticated;
grant usage on schema private to authenticated;
grant execute on function private.h7_submit_preliminary_v2108(uuid,uuid,text,bigint,boolean,boolean)
  to authenticated;
create or replace function public.h7_submit_preliminary_v2108(
  p_event uuid,p_slot uuid,p_pcucode text,p_pid bigint,p_hcv boolean,p_hbsag boolean
) returns jsonb language sql volatile security invoker set search_path='' as $$
  select private.h7_submit_preliminary_v2108(p_event,p_slot,p_pcucode,p_pid,p_hcv,p_hbsag)
$$;
revoke all on function public.h7_submit_preliminary_v2108(uuid,uuid,text,bigint,boolean,boolean)
  from public,anon;
grant execute on function public.h7_submit_preliminary_v2108(uuid,uuid,text,bigint,boolean,boolean)
  to authenticated;

create or replace function private.h7_my_preliminary_v2108(p_request uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_user uuid; v_pid bigint; v_row public.h7_preliminary_requests_v2108%rowtype;
begin
  v_user:=auth.uid();
  select volunteer_pid into v_pid from public.profiles where user_id=v_user
    and active is true and role in ('user','staff');
  if v_user is null or v_pid is null then
    raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธ”เธนเธเธณเธเธญ' using errcode='42501';
  end if;
  select * into v_row from public.h7_preliminary_requests_v2108 where id=p_request;
  if not found or v_row.requested_by<>v_user or not exists (
    select 1 from public.health_persons hp
    join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
    where hp.source_pcucode=v_row.source_pcucode and hp.source_pid=v_row.source_pid
      and hp.active is true and h.superseded_by is null
      and h.verification_status='verified_jhcis' and h.volunteer_pid=v_pid
      and private.health_can_access_house(hp.house_pcucode,hp.hcode)
  ) then raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธ”เธนเธเธณเธเธญ' using errcode='42501'; end if;
  return jsonb_build_object('request_id',v_row.id,'status',v_row.status,
    'reason_code',v_row.reason_code,'evaluated_at',v_row.evaluated_at,
    'seat_reserved',false);
end;
$$;
revoke all on function private.h7_my_preliminary_v2108(uuid) from public,anon,authenticated;
grant execute on function private.h7_my_preliminary_v2108(uuid) to authenticated;
create or replace function public.h7_my_preliminary_v2108(p_request uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.h7_my_preliminary_v2108(p_request)
$$;
revoke all on function public.h7_my_preliminary_v2108(uuid) from public,anon;
grant execute on function public.h7_my_preliminary_v2108(uuid) to authenticated;
