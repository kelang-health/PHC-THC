
alter table public.daily_system_summary
  add column if not exists telegram_sent_at timestamptz,
  add column if not exists telegram_send_status text not null default 'pending';

create index if not exists daily_system_summary_generated_at_idx
  on public.daily_system_summary(generated_at desc);
