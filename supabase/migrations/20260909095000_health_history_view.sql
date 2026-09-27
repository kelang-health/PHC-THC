-- v1.8 follow-up: user-facing NCD history with scoped person/house labels.
create or replace view public.health_ncd_history
with (security_invoker=true)
as
select
  s.id,s.screened_on,s.source_pcucode,s.source_pid,
  p.display_name,p.gender,p.birth_date,
  s.hcode,h.house_no,h.moo,h.community,
  s.ncd_status,s.severity,s.bp_status,s.glucose_status,s.advice,s.recorded_at
from public.health_ncd_screenings s
join public.health_persons p
  on p.source_pcucode=s.source_pcucode and p.source_pid=s.source_pid
join public.houses h
  on h.source_pcucode=s.house_pcucode and h.hcode=s.hcode;

grant select on public.health_ncd_history to authenticated;
