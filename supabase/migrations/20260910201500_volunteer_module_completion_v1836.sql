-- OSM-PHC Cloud v1.8.36
-- Complete volunteer profile module: training history + scoped read RPCs.
-- No citizen ID, phone, address, HN, email or LINE ID is stored here.
begin;

create table if not exists public.volunteer_training_history (
  source_pcucode text not null default '',
  volunteer_pid bigint not null,
  event_id bigint not null,
  course_name text not null default '',
  category text not null default '',
  event_date date not null,
  budget_year integer,
  hours double precision not null default 0,
  attendance_status text not null default '',
  result text not null default '',
  certificate_no text not null default '',
  event_status text not null default 'active',
  sync_token text,
  updated_at timestamptz not null default now(),
  primary key (source_pcucode, volunteer_pid, event_id)
);

create index if not exists idx_volunteer_training_pid
  on public.volunteer_training_history(source_pcucode, volunteer_pid);

create index if not exists idx_volunteer_training_date
  on public.volunteer_training_history(event_date desc);

alter table public.volunteer_training_history enable row level security;

drop policy if exists volunteer_training_select on public.volunteer_training_history;

create policy volunteer_training_select on public.volunteer_training_history
for select to authenticated
using (
  exists (
    select 1
    from public.volunteers v
    where v.source_pcucode = volunteer_training_history.source_pcucode
      and v.source_pid = volunteer_training_history.volunteer_pid
      and (
        private.current_role() = 'admin'
        or (
          private.current_role() = 'staff'
          and coalesce(btrim(private.current_community()), '') <> ''
          and btrim(v.community) = btrim(private.current_community())
        )
        or (
          private.current_role() = 'user'
          and v.source_pid = private.current_volunteer_pid()
        )
      )
  )
);

grant select on public.volunteer_training_history to authenticated;

create or replace function public.volunteer_training_profile(p_source_pid bigint)
returns table(
  source_pcucode text,
  volunteer_pid bigint,
  event_id bigint,
  course_name text,
  category text,
  event_date date,
  budget_year integer,
  hours double precision,
  attendance_status text,
  result text,
  certificate_no text,
  event_status text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    t.source_pcucode,t.volunteer_pid,t.event_id,t.course_name,t.category,t.event_date,
    t.budget_year,t.hours,t.attendance_status,t.result,t.certificate_no,t.event_status
  from public.volunteer_training_history t
  where t.volunteer_pid = p_source_pid
  order by t.event_date desc, t.event_id desc
  limit 100
$$;

grant execute on function public.volunteer_training_profile(bigint) to authenticated;

create or replace view public.volunteer_training_summary
with (security_invoker = true)
as
select
  source_pcucode,
  volunteer_pid,
  count(*) filter (where event_status <> 'cancelled')::bigint as training_count,
  coalesce(sum(hours) filter (where event_status <> 'cancelled'),0)::double precision as training_hours,
  max(event_date) filter (where event_status <> 'cancelled') as last_training_date
from public.volunteer_training_history
group by source_pcucode,volunteer_pid;

grant select on public.volunteer_training_summary to authenticated;

insert into public.app_settings(key,value)
values ('volunteer_module',jsonb_build_object(
  'version','1.8.36',
  'profile','360',
  'training_history',true,
  'photo_storage','private_signed_url',
  'source_of_truth','local_osm_phc_and_jhcis_read_only',
  'cloud_edit_registry',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
