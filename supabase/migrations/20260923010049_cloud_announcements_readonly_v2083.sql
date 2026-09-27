-- Phase 4 read-only Cloud announcements; publishing will be implemented separately in phase 3.
create table if not exists public.cloud_announcements_v2083 (
  id uuid primary key default gen_random_uuid(),
  local_draft_id bigint unique,
  kind text not null default 'news' check (kind in ('news','status','event')),
  title text not null check (char_length(title) between 1 and 140),
  summary text not null default '' check (char_length(summary)<=220),
  body text not null default '' check (char_length(body)<=4000),
  audience text not null default 'all' check (audience in ('all','admin','staff','user')),
  target_community text,
  image_path text check (image_path is null or (char_length(image_path)<=300 and image_path ~ '^announcements/[a-zA-Z0-9_./-]+$' and image_path !~ '/\.\./')),
  starts_at timestamptz,
  ends_at timestamptz,
  home_featured boolean not null default false,
  priority integer not null default 0 check (priority between -100 and 100),
  status text not null default 'draft' check (status in ('draft','published','hidden','archived')),
  version integer not null default 1 check (version>0),
  published_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint cloud_announcements_v2083_date_chk check (starts_at is null or ends_at is null or starts_at<=ends_at)
);
create index if not exists cloud_announcements_v2083_visible_idx
on public.cloud_announcements_v2083 (priority desc, published_at desc)
where status='published';
alter table public.cloud_announcements_v2083 enable row level security;
revoke all on table public.cloud_announcements_v2083 from public,anon,authenticated;
grant select on public.cloud_announcements_v2083 to authenticated;
grant all on public.cloud_announcements_v2083 to service_role;
drop policy if exists cloud_announcements_v2083_reader on public.cloud_announcements_v2083;
create policy cloud_announcements_v2083_reader on public.cloud_announcements_v2083
for select to authenticated
using (
  status='published'
  and (starts_at is null or starts_at<=now())
  and (ends_at is null or ends_at>=now())
  and exists (
    select 1 from public.profiles p
    where p.user_id=(select auth.uid()) and p.active is true
      and (cloud_announcements_v2083.audience='all' or cloud_announcements_v2083.audience=p.role)
      and (cloud_announcements_v2083.target_community is null
        or p.role='admin'
        or cloud_announcements_v2083.target_community=p.community)
  )
);
comment on table public.cloud_announcements_v2083 is 'Phase 4 Cloud read-only published public-health notices; only service role may publish, separate Local phase 3 pipeline pending.';
