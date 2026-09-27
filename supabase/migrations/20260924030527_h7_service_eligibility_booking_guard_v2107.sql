-- H7.3: per-service eligibility is required in addition to the existing
-- event-level gate. These tables start empty; no clinical rule is inferred
-- from j-report test-history codes and no real booking is opened by migration.
create table if not exists public.h7_service_rules_v2107 (
  event_id uuid not null references public.cloud_announcements_v2083(id) on delete cascade,
  service_key text not null check (service_key in ('anti_hcv','hbsag')),
  rule_version integer not null check (rule_version > 0),
  signed_rule_reference text not null check (length(trim(signed_rule_reference)) > 0),
  approved_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (event_id,service_key)
);

create table if not exists public.h7_service_snapshots_v2107 (
  event_id uuid not null,
  source_pcucode text not null check (length(source_pcucode) between 1 and 30),
  source_pid bigint not null check (source_pid > 0),
  service_key text not null,
  event_rule_version integer not null check (event_rule_version > 0),
  service_rule_version integer not null check (service_rule_version > 0),
  signed_rule_reference text not null,
  status text not null check (status in ('preliminary_eligible','review_required','ineligible','stale')),
  reason_code text not null,
  source_checked_at timestamptz not null,
  expires_at timestamptz not null,
  synced_at timestamptz not null default now(),
  primary key (event_id,source_pcucode,source_pid,service_key),
  foreign key (event_id,service_key)
    references public.h7_service_rules_v2107(event_id,service_key) on delete cascade,
  check (expires_at > source_checked_at and expires_at <= source_checked_at + interval '24 hours')
);
create index if not exists h7_service_snapshots_v2107_event_status_idx
  on public.h7_service_snapshots_v2107(event_id,service_key,status,expires_at);

alter table public.h7_service_rules_v2107 enable row level security;
alter table public.h7_service_snapshots_v2107 enable row level security;
revoke all on public.h7_service_rules_v2107 from anon,authenticated;
revoke all on public.h7_service_snapshots_v2107 from anon,authenticated;
grant all on public.h7_service_rules_v2107 to service_role;
grant all on public.h7_service_snapshots_v2107 to service_role;

create or replace function private.h7_services_current_v2107(
  p_event uuid,p_pcucode text,p_pid bigint,p_hcv boolean,p_hbsag boolean
) returns boolean language sql stable security definer set search_path='' as $$
  select (p_hcv is true or p_hbsag is true)
    and not exists (
      select 1 from (values ('anti_hcv'::text,p_hcv),('hbsag'::text,p_hbsag)) requested(service_key,selected)
      where requested.selected is true and not exists (
        select 1 from public.h7_service_snapshots_v2107 s
        join public.h7_service_rules_v2107 sr
          on sr.event_id=s.event_id and sr.service_key=s.service_key
        join public.h7_event_rules_v2103 er on er.event_id=s.event_id
        join public.cloud_announcements_v2083 a on a.id=s.event_id
        where s.event_id=p_event and s.source_pcucode=p_pcucode and s.source_pid=p_pid
          and s.service_key=requested.service_key
          and s.status='preliminary_eligible'
          and s.event_rule_version=er.rule_version
          and s.service_rule_version=sr.rule_version
          and s.signed_rule_reference=sr.signed_rule_reference
          and sr.approved_at is not null and er.approved_at is not null
          and er.signed_rule_reference=a.pilot_target_rule_reference
          and a.pilot_target_confirmed_at is not null
          and s.source_checked_at<=now() and s.source_checked_at>=now()-interval '24 hours'
          and s.expires_at>now()
      )
    );
$$;
revoke all on function private.h7_services_current_v2107(uuid,text,bigint,boolean,boolean) from public,anon,authenticated;

-- The booking RPC inserts a booking and then its selected-service details in
-- one transaction. A BEFORE trigger on details closes the bypass path even if
-- an older client still calls that RPC without first checking eligibility UI.
create or replace function private.h7_booking_details_guard_v2107()
returns trigger language plpgsql security definer set search_path='' as $$
declare b public.cloud_event_bookings_v2085%rowtype;
begin
  select * into b from public.cloud_event_bookings_v2085 where id=new.booking_id;
  if not found or not private.h7_services_current_v2107(
      b.announcement_id,b.source_pcucode,b.source_pid,new.hcv_selected,new.hbsag_selected) then
    raise exception 'เธเธฅเธเธฃเธฐเน€เธกเธดเธเธฃเธฒเธขเธเธฃเธดเธเธฒเธฃเนเธกเนเธเธฃเธเธซเธฃเธทเธญเธซเธกเธ”เธญเธฒเธขเธธ เธเธฃเธธเธ“เธฒเธฃเธญเน€เธเนเธฒเธซเธเนเธฒเธ—เธตเนเธ•เธฃเธงเธเธชเธญเธ'
      using errcode='22023';
  end if;
  return new;
end;
$$;
revoke all on function private.h7_booking_details_guard_v2107() from public,anon,authenticated;
drop trigger if exists h7_booking_details_guard_v2107 on private.hcv_booking_details_v2087;
create trigger h7_booking_details_guard_v2107
  before insert or update of hcv_selected,hbsag_selected
  on private.hcv_booking_details_v2087
  for each row execute function private.h7_booking_details_guard_v2107();

-- Scoped, read-only status for the currently signed-in volunteer. Missing or
-- mismatched results are stale; no raw lab result or sensitive identifiers leak.
create or replace function public.h7_my_services_v2107(
  p_event uuid,p_pcucode text,p_pid bigint
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_user uuid; v_volunteer_pid bigint; v_result jsonb;
begin
  v_user:=auth.uid();
  if v_user is null then raise exception 'เธเธฃเธธเธ“เธฒเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ' using errcode='42501'; end if;
  select volunteer_pid into v_volunteer_pid from public.profiles
    where user_id=v_user and active is true and role in ('user','staff');
  if v_volunteer_pid is null then
    raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธ”เธนเธเนเธญเธกเธนเธฅเธเธธเธเธเธฅ' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.health_persons hp
    join public.houses h on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
    where hp.source_pcucode=p_pcucode and hp.source_pid=p_pid
      and hp.active is true and hp.service_population_eligible is true
      and h.superseded_by is null and h.verification_status='verified_jhcis'
      and h.volunteer_pid=v_volunteer_pid
      and private.health_can_access_house(hp.house_pcucode,hp.hcode)
  ) then raise exception 'เธเธธเธเธเธฅเธเธตเนเนเธกเนเธญเธขเธนเนเนเธเธเธงเธฒเธกเธฃเธฑเธเธเธดเธ”เธเธญเธ' using errcode='42501'; end if;
  if not exists (
    select 1 from public.cloud_announcements_v2083 a
    where a.id=p_event and a.kind='event' and a.event_subtype='hcv_hbsag'
      and a.status='published' and a.is_demo is false and a.pilot_mode is true
      and a.pilot_approved_at is not null and a.pilot_target_confirmed_at is not null
      and private.hcv_pilot_can_access_v2095(a.id)
  ) then raise exception 'เธเธดเธเธเธฃเธฃเธกเธเธตเนเนเธกเนเธญเธขเธนเนเนเธเธเธญเธเน€เธเธ•เธเธณเธฃเนเธญเธ' using errcode='42501'; end if;
  select jsonb_object_agg(requested.service_key,
    jsonb_build_object(
      'status',case when s.event_id is null or s.expires_at<=now()
          or s.source_checked_at>now() or s.source_checked_at<now()-interval '24 hours'
          or s.event_rule_version is distinct from er.rule_version
          or s.service_rule_version is distinct from sr.rule_version
          or s.signed_rule_reference is distinct from sr.signed_rule_reference
          or sr.approved_at is null or er.approved_at is null
          or er.signed_rule_reference is distinct from a.pilot_target_rule_reference
          then 'stale' else s.status end,
      'reason_code',case when s.event_id is null or s.expires_at<=now()
          then 'data_stale' else s.reason_code end,
      'eligible_to_request',coalesce(private.h7_services_current_v2107(
          p_event,p_pcucode,p_pid,requested.service_key='anti_hcv',
          requested.service_key='hbsag'),false),
      'source_checked_at',s.source_checked_at,'expires_at',s.expires_at
    )) into v_result
  from (values ('anti_hcv'::text),('hbsag'::text)) requested(service_key)
  join public.cloud_announcements_v2083 a on a.id=p_event
  left join public.h7_service_snapshots_v2107 s on s.event_id=p_event
    and s.source_pcucode=p_pcucode and s.source_pid=p_pid
    and s.service_key=requested.service_key
  left join public.h7_service_rules_v2107 sr on sr.event_id=p_event
    and sr.service_key=requested.service_key
  left join public.h7_event_rules_v2103 er on er.event_id=p_event;
  return coalesce(v_result,'{}'::jsonb);
end;
$$;
revoke all on function public.h7_my_services_v2107(uuid,text,bigint) from public,anon;
grant execute on function public.h7_my_services_v2107(uuid,text,bigint) to authenticated;
