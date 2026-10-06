-- Keep historical elderly 9-domain records editable. The new same-day gate
-- applies to sessions created from the v2140 rollout date onward.
create or replace function private.require_elderly9_basic_health_v2140()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.screening_sessions%rowtype;
  both_diseases boolean;
begin
  select * into s from public.screening_sessions where id=new.session_id;
  if not found then raise exception 'SESSION_NOT_FOUND'; end if;

  select coalesce(p.has_dm,false) and coalesce(p.has_ht,false)
    into both_diseases
  from public.health_persons p
  where p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid;

  if s.screening_date>=date '2026-10-06'
     and coalesce(both_diseases,false) and not exists (
    select 1 from public.elderly9_basic_health_checks_v2140 b
    where b.session_id=s.id
      and b.source_pcucode=s.source_pcucode
      and b.source_pid=s.source_pid
      and b.measured_on=s.screening_date
  ) then
    raise exception 'ELDERLY_BASIC_HEALTH_REQUIRED_FIRST';
  end if;
  return new;
end;
$$;

revoke all on function private.require_elderly9_basic_health_v2140() from public, anon, authenticated;
