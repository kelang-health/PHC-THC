-- H3: schema-only, backwards compatible. HCV publication remains blocked by Local H2.
alter table public.cloud_announcements_v2083
 add column if not exists event_subtype text not null default 'general',
 add column if not exists hcv_enabled boolean not null default false,
 add column if not exists hbsag_enabled boolean not null default false,
 add column if not exists event_contact_phone text not null default '',
 add column if not exists eligibility_notice text not null default '',
 add column if not exists preparation_notice text not null default '';
alter table public.cloud_announcements_v2083
 drop constraint if exists cloud_announcements_v2083_hcv_settings_chk;
alter table public.cloud_announcements_v2083
 add constraint cloud_announcements_v2083_hcv_settings_chk check (
  (event_subtype='general' and not hcv_enabled and not hbsag_enabled)
  or (event_subtype='hcv_hbsag' and kind='event' and audience='user' and (hcv_enabled or hbsag_enabled)
      and char_length(event_contact_phone)<=20 and char_length(eligibility_notice)<=1200
      and char_length(preparation_notice)<=1200)
 );
comment on column public.cloud_announcements_v2083.event_subtype is 'general remains unchanged; hcv_hbsag is disabled for publication until H4/H6 acceptance.';
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;
create table if not exists private.hcv_booking_details_v2087 (
 booking_id uuid primary key references public.cloud_event_bookings_v2085(id) on delete restrict,
 hcv_selected boolean not null default false,
 hbsag_selected boolean not null default false,
 contact_phone text not null,
 verification_status text not null default 'pending_review'
   check (verification_status in ('pending_review','appointment_confirmed','needs_follow_up','ineligible')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint hcv_booking_test_selection_chk check (hcv_selected or hbsag_selected),
 constraint hcv_booking_contact_phone_chk check (contact_phone ~ '^0[0-9]{8,9}$')
);
alter table private.hcv_booking_details_v2087 enable row level security;
revoke all on private.hcv_booking_details_v2087 from public,anon,authenticated;
grant usage on schema private to service_role;
grant all on private.hcv_booking_details_v2087 to service_role;
create index if not exists hcv_booking_details_status_idx on private.hcv_booking_details_v2087 (verification_status,created_at desc);
comment on table private.hcv_booking_details_v2087 is 'HCV/HBsAg booking contact and selected tests; no direct API access to authenticated/anon, exposed only via narrowly scoped RPCs.';
