CREATE OR REPLACE FUNCTION public.attach_ncd_to_screening_session_v190(p_session_id uuid, p_ncd_screening_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.screening_sessions%rowtype; n public.health_ncd_screenings%rowtype; v_mode text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into s from public.screening_sessions where id=p_session_id for update;
  if not found or not private.health_can_access_person(s.source_pcucode,s.source_pid) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
  if s.route not in ('ncd_35_59','elderly_60_plus') then raise exception 'NCD_NOT_REQUIRED_FOR_ROUTE'; end if;
  v_mode:=private.screening_record_mode_v208(s.screening_date);
  if p_ncd_screening_id is null then
    select * into n from public.health_ncd_screenings x
    where x.source_pcucode=s.source_pcucode and x.source_pid=s.source_pid and (x.screened_on=s.screening_date or (s.route='elderly_60_plus' and s.age_years>=60 and x.screened_on<=s.screening_date))
      and coalesce(x.record_mode,'production')=v_mode
    order by x.screened_on desc,x.recorded_at desc limit 1;
  else
    select * into n from public.health_ncd_screenings x
    where x.id=p_ncd_screening_id and x.source_pcucode=s.source_pcucode and x.source_pid=s.source_pid and (x.screened_on=s.screening_date or (s.route='elderly_60_plus' and s.age_years>=60 and x.screened_on<=s.screening_date))
      and coalesce(x.record_mode,'production')=v_mode;
  end if;
  if not found then raise exception 'NCD_SCREENING_REQUIRED_FIRST'; end if;
  update public.screening_sessions set ncd_screening_id=n.id,ncd_status='complete',elderly9_status=case when route='elderly_60_plus' and elderly9_status='blocked_by_ncd' then 'in_progress' else elderly9_status end,updated_at=now() where id=s.id returning * into s;
  return jsonb_build_object('ok',true,'ncd_status',s.ncd_status,'elderly9_status',s.elderly9_status,'ncd_screening_id',s.ncd_screening_id,'record_mode',v_mode,'ncd_reference_date',n.screened_on);
end;
$function$;

CREATE OR REPLACE FUNCTION private.require_elderly9_basic_health_v2140()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
     and coalesce(both_diseases,false) and not exists (select 1 from public.health_ncd_screenings n where n.id=s.ncd_screening_id and n.source_pcucode=s.source_pcucode and n.source_pid=s.source_pid and n.screened_on<=s.screening_date and coalesce(n.record_mode,'production')=private.screening_record_mode_v208(s.screening_date)) and not exists (
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
$function$
;

create function public.elderly_ncd_reference_v2206(p_source_pcucode text,p_source_pid bigint,p_day date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not private.health_can_access_person(p_source_pcucode,p_source_pid) then raise exception 'PERSON_OUT_OF_SCOPE';end if;
 if p_day is null or p_day>timezone('Asia/Bangkok',now())::date then raise exception 'INVALID_DATE';end if;
 if not exists(select 1 from public.health_persons p where p.source_pcucode=p_source_pcucode and p.source_pid=p_source_pid and p.birth_date<=p_day-interval '60 years') then return '{}'::jsonb;end if;
 select jsonb_build_object('ncd_screening_id',n.id,'ncd_reference_date',n.screened_on) into result from public.health_ncd_screenings n where n.source_pcucode=p_source_pcucode and n.source_pid=p_source_pid and n.screened_on<=p_day and coalesce(n.record_mode,'production')=private.screening_record_mode_v208(p_day) order by n.screened_on desc,n.recorded_at desc limit 1;
 return coalesce(result,'{}'::jsonb);
end $$;
revoke all on function public.elderly_ncd_reference_v2206(text,bigint,date) from public,anon;
grant execute on function public.elderly_ncd_reference_v2206(text,bigint,date) to authenticated;
notify pgrst,'reload schema';

