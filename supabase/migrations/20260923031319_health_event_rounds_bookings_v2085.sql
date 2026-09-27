-- Phase 5: configurable activity rounds and scoped, capacity-safe bookings.
alter table public.cloud_announcements_v2083
 add column if not exists booking_enabled boolean not null default false,
 add column if not exists booking_opens_at timestamptz,
 add column if not exists booking_closes_at timestamptz;
alter table public.cloud_announcements_v2083
 drop constraint if exists cloud_announcements_v2083_booking_window_chk;
alter table public.cloud_announcements_v2083
 add constraint cloud_announcements_v2083_booking_window_chk
 check (booking_opens_at is null or booking_closes_at is null or booking_opens_at<=booking_closes_at);

create table if not exists public.cloud_event_slots_v2085(
 id uuid primary key default gen_random_uuid(),
 announcement_id uuid not null references public.cloud_announcements_v2083(id) on delete restrict,
 local_slot_key uuid not null,
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 location text not null check(char_length(location) between 1 and 220),
 capacity integer not null check(capacity between 1 and 10000),
 status text not null default 'open' check(status in('open','closed')),
 updated_at timestamptz not null default now(),
 unique(announcement_id,local_slot_key),
 constraint event_slot_time_chk check(ends_at>starts_at)
);
create index if not exists cloud_event_slots_v2085_event_idx on public.cloud_event_slots_v2085(announcement_id,starts_at);
alter table public.cloud_event_slots_v2085 enable row level security;
revoke all on public.cloud_event_slots_v2085 from public,anon,authenticated;
grant select on public.cloud_event_slots_v2085 to authenticated;
grant all on public.cloud_event_slots_v2085 to service_role;
drop policy if exists cloud_event_slots_v2085_reader on public.cloud_event_slots_v2085;
create policy cloud_event_slots_v2085_reader on public.cloud_event_slots_v2085
for select to authenticated using (
 exists(select 1 from public.cloud_announcements_v2083 a where a.id=announcement_id)
);
create table if not exists public.cloud_event_bookings_v2085(
 id uuid primary key default gen_random_uuid(),
 announcement_id uuid not null references public.cloud_announcements_v2083(id) on delete restrict,
 slot_id uuid not null references public.cloud_event_slots_v2085(id) on delete restrict,
 source_pcucode text not null,
 source_pid bigint not null,
 booked_by uuid not null,
 status text not null default 'booked' check(status in ('booked','cancelled')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists cloud_event_bookings_v2085_unique_active
on public.cloud_event_bookings_v2085(announcement_id,source_pcucode,source_pid) where status='booked';
create index if not exists cloud_event_bookings_v2085_slot_idx
on public.cloud_event_bookings_v2085(slot_id,status);
alter table public.cloud_event_bookings_v2085 enable row level security;
revoke all on public.cloud_event_bookings_v2085 from public,anon,authenticated;
grant select on public.cloud_event_bookings_v2085 to authenticated;
grant all on public.cloud_event_bookings_v2085 to service_role;
drop policy if exists cloud_event_bookings_v2085_reader on public.cloud_event_bookings_v2085;
create policy cloud_event_bookings_v2085_reader on public.cloud_event_bookings_v2085
for select to authenticated using (
 exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.active is true)
 and exists(select 1 from public.health_persons hp where hp.source_pcucode=source_pcucode and hp.source_pid=source_pid and hp.active is true and private.health_can_access_house(hp.house_pcucode,hp.hcode))
);
-- Capacity and duplicate protection both happen inside one transaction.
create or replace function public.book_health_event_v2085(
 p_slot uuid,p_pcucode text,p_pid bigint
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.cloud_event_slots_v2085%rowtype;
 a public.cloud_announcements_v2083%rowtype;
 existing uuid; fresh uuid; occupied integer;
begin
 if auth.uid() is null then raise exception 'เธเธฃเธธเธ“เธฒเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ' using errcode='42501'; end if;
 if p_pid is null or p_pcucode is null or length(p_pcucode)>30 then
   raise exception 'เธเนเธญเธกเธนเธฅเธเธธเธเธเธฅเนเธกเนเธ–เธนเธเธ•เนเธญเธ' using errcode='22023';
 end if;
 if not exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.active is true) then
   raise exception 'เธเธฑเธเธเธตเนเธกเนเธกเธตเธชเธดเธ—เธเธดเน' using errcode='42501';
 end if;
 if not exists(select 1 from public.health_persons hp
   where hp.source_pcucode=p_pcucode and hp.source_pid=p_pid and hp.active is true
     and private.health_can_access_house(hp.house_pcucode,hp.hcode)) then
   raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเน€เธฅเธทเธญเธเธเธธเธเธเธฅเธเธตเน' using errcode='42501';
 end if;
 select * into s from public.cloud_event_slots_v2085 where id=p_slot for update;
 if not found then raise exception 'เนเธกเนเธเธเธฃเธญเธเธเธดเธเธเธฃเธฃเธก' using errcode='22023'; end if;
 select * into a from public.cloud_announcements_v2083 where id=s.announcement_id;
 if a.status<>'published' or a.kind<>'event' or not a.booking_enabled
    or (a.starts_at is not null and a.starts_at>now())
    or (a.ends_at is not null and a.ends_at<now())
    or (a.booking_opens_at is not null and a.booking_opens_at>now())
    or (a.booking_closes_at is not null and a.booking_closes_at<now())
    or s.status<>'open' or s.starts_at<=now() then
   raise exception 'เธเธดเธเธเธฃเธฃเธกเธซเธฃเธทเธญเธฃเธญเธเธเธตเนเธเธดเธ”เธฃเธฑเธเธเธญเธเนเธฅเนเธง' using errcode='22023';
 end if;
 select b.id into existing from public.cloud_event_bookings_v2085 b
 where b.announcement_id=a.id and b.source_pcucode=p_pcucode and b.source_pid=p_pid and b.status='booked'
 limit 1;
 if existing is not null then return jsonb_build_object('status','already_booked','booking_id',existing); end if;
 select count(*) into occupied from public.cloud_event_bookings_v2085 b
 where b.slot_id=s.id and b.status='booked';
 if occupied>=s.capacity then raise exception 'เธฃเธญเธเธเธตเนเน€เธ•เนเธกเนเธฅเนเธง' using errcode='22023'; end if;
 insert into public.cloud_event_bookings_v2085(announcement_id,slot_id,source_pcucode,source_pid,booked_by)
 values(a.id,s.id,p_pcucode,p_pid,auth.uid()) returning id into fresh;
 return jsonb_build_object('status','booked','booking_id',fresh,'remaining',s.capacity-occupied-1);
end $$;
revoke all on function public.book_health_event_v2085(uuid,text,bigint) from public,anon;
grant execute on function public.book_health_event_v2085(uuid,text,bigint) to authenticated;

create or replace function public.cancel_health_event_booking_v2085(p_booking uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.cloud_event_bookings_v2085%rowtype;
begin
 if auth.uid() is null then raise exception 'เธเธฃเธธเธ“เธฒเน€เธเนเธฒเธชเธนเนเธฃเธฐเธเธ' using errcode='42501'; end if;
 select * into b from public.cloud_event_bookings_v2085 where id=p_booking for update;
 if not found then raise exception 'เนเธกเนเธเธเธเธฒเธฃเธเธญเธ' using errcode='22023'; end if;
 if not exists(select 1 from public.profiles p where p.user_id=auth.uid() and p.active is true) or
    not exists(select 1 from public.health_persons hp
       where hp.source_pcucode=b.source_pcucode and hp.source_pid=b.source_pid and hp.active is true
        and private.health_can_access_house(hp.house_pcucode,hp.hcode)) then
   raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเธขเธเน€เธฅเธดเธเธเธฒเธฃเธเธญเธเธเธตเน' using errcode='42501';
 end if;
 if b.status='cancelled' then return jsonb_build_object('status','already_cancelled','booking_id',b.id); end if;
 update public.cloud_event_bookings_v2085 set status='cancelled',updated_at=now() where id=b.id;
 return jsonb_build_object('status','cancelled','booking_id',b.id);
end $$;
revoke all on function public.cancel_health_event_booking_v2085(uuid) from public,anon;
grant execute on function public.cancel_health_event_booking_v2085(uuid) to authenticated;
