-- Cloud v2.0.31: cover the current-generation foreign key used by snapshot state checks.
begin;
create index if not exists report_snapshot_state_generation_v2031_idx
  on public.report_snapshot_state_v2031(current_generation);
commit;
