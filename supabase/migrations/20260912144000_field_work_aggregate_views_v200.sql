-- OSM-PHC v2.0.0
-- Compact aggregate views for fast Cloud -> Local reporting.
-- These views contain counts only; detailed rows remain in the scoped export views.

begin;

create or replace view public.field_work_progress_v200
with (security_invoker=true)
as
select
  w.community,
  w.volunteer_pid,
  w.task_type,
  max(w.task_label) as task_label,
  min(w.period_start) as period_start,
  max(w.period_mode) as period_mode,
  count(*)::bigint as target,
  count(*) filter(where w.status='complete')::bigint as complete,
  count(*) filter(where w.status='partial')::bigint as partial,
  count(*) filter(where w.status='due')::bigint as due,
  count(*) filter(where w.priority='red')::bigint as red,
  count(*) filter(where w.priority='orange')::bigint as orange
from public.field_work_items_v200 w
group by w.community,w.volunteer_pid,w.task_type;

revoke all on public.field_work_progress_v200 from anon;

grant select on public.field_work_progress_v200 to authenticated,service_role;

create or replace view public.field_followup_progress_v200
with (security_invoker=true)
as
select
  x.community,
  x.volunteer_pid,
  x.status,
  x.priority,
  count(*)::bigint as total
from public.field_export_followup_v200 x
group by x.community,x.volunteer_pid,x.status,x.priority;

revoke all on public.field_followup_progress_v200 from anon;

grant select on public.field_followup_progress_v200 to authenticated,service_role;

commit;
