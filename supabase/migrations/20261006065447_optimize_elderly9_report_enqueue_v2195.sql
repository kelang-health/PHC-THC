drop trigger if exists report_snapshot_dirty_v2031 on public.elderly9_domain_results;
create trigger report_snapshot_dirty_v2031
after delete on public.elderly9_domain_results
for each statement execute function private.queue_report_snapshot_refresh_v2031();

drop trigger if exists report_snapshot_dirty_v2031 on public.screening_followups;
create trigger report_snapshot_dirty_v2031
after insert or delete or update of status, priority on public.screening_followups
for each statement execute function private.queue_report_snapshot_refresh_v2031();

comment on trigger report_snapshot_dirty_v2031 on public.elderly9_domain_results is
'Report snapshot refresh is queued only for DELETE. Normal elderly 9-domain INSERT/UPDATE already updates screening_sessions in the same save flow, avoiding duplicate enqueue work.';

comment on trigger report_snapshot_dirty_v2031 on public.screening_followups is
'Refresh report snapshots only when follow-up membership/status/priority can change report aggregates.';
