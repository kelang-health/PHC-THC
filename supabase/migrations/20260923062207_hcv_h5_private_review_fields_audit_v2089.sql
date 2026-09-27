-- H5: private review/service-tracking fields. They are not clinical test results.
alter table private.hcv_booking_details_v2087
 add column if not exists hcv_performed boolean not null default false,
 add column if not exists hbsag_performed boolean not null default false,
 add column if not exists reviewed_by text,
 add column if not exists reviewed_at timestamptz;
alter table private.hcv_booking_details_v2087
 drop constraint if exists hcv_booking_performed_selected_chk;
alter table private.hcv_booking_details_v2087
 add constraint hcv_booking_performed_selected_chk
 check ((not hcv_performed or hcv_selected) and (not hbsag_performed or hbsag_selected));
create table if not exists private.hcv_booking_review_audit_v2089 (
 id bigint generated always as identity primary key,
 booking_id uuid not null references public.cloud_event_bookings_v2085(id) on delete restrict,
 actor text not null check (char_length(actor) between 1 and 100),
 previous_status text not null,
 new_status text not null,
 previous_hcv_performed boolean not null,
 new_hcv_performed boolean not null,
 previous_hbsag_performed boolean not null,
 new_hbsag_performed boolean not null,
 changed_at timestamptz not null default now()
);
alter table private.hcv_booking_review_audit_v2089 enable row level security;
revoke all on private.hcv_booking_review_audit_v2089 from public,anon,authenticated;
grant all on private.hcv_booking_review_audit_v2089 to service_role;
create index if not exists hcv_review_audit_booking_time_v2089
 on private.hcv_booking_review_audit_v2089(booking_id,changed_at desc);
comment on column private.hcv_booking_details_v2087.hcv_performed is 'Manual service-delivery check only; not a clinical laboratory test result; no JHCIS write.';
comment on column private.hcv_booking_details_v2087.hbsag_performed is 'Manual service-delivery check only; not a clinical laboratory test result; no JHCIS write.';
