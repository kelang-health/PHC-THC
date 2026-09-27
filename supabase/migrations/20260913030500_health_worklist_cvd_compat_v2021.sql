-- Cloud v2.0.21: repair CVD columns on health worklist and refresh PostgREST schema cache.
begin;

alter table public.health_persons
  add column if not exists has_cvd boolean not null default false,
  add column if not exists cvd_population_eligible boolean not null default false;

create or replace view public.health_person_worklist_active_v1847
with (security_invoker=true) as
select w.*, p.has_cvd, p.cvd_population_eligible
from public.health_person_worklist_active_v1841 w
join public.health_persons p
  on p.source_pcucode=w.source_pcucode
 and p.source_pid=w.source_pid;

revoke all on table public.health_person_worklist_active_v1847 from anon;

revoke insert,update,delete,truncate,references,trigger on table public.health_person_worklist_active_v1847 from authenticated;

grant select on table public.health_person_worklist_active_v1847 to authenticated;

comment on view public.health_person_worklist_active_v1847 is
  'Compatibility worklist for Cloud v2.0.21. Extends active v1.8.41 worklist with has_cvd and cvd_population_eligible.';

notify pgrst, 'reload schema';

commit;
