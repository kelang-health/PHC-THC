begin;
create table private.ncd_external_diagnoses (
 source_pcucode text not null,
 source_pid bigint not null,
 kind text not null check (kind in ('bp','dtx')),
 target_id uuid not null references private.ncd_main_targets_v2201(id),
 treatment_site text not null check (char_length(btrim(treatment_site)) between 1 and 200),
 recorded_by uuid not null,
 recorded_at timestamptz not null default now(),
 primary key (source_pcucode,source_pid)
);
alter table private.ncd_external_diagnoses enable row level security;
revoke all on private.ncd_external_diagnoses from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.ncd_main_cases_v2201()
 RETURNS TABLE(source_screen_id uuid, kind text, source_pcucode text, source_pid bigint, display_name text, house_no text, community text, screened_on date, due_on date, sbp numeric, dbp numeric, glucose_mg_dl numeric, glucose_type text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select t.id,t.kind,t.source_pcucode,t.source_pid,p.display_name,h.house_no,t.community,t.screened_on,t.due_on,
         t.sbp,t.dbp,t.glucose_mg_dl,t.glucose_type
  from private.ncd_main_targets_v2201 t
  join public.health_persons p on p.source_pcucode=t.source_pcucode and p.source_pid=t.source_pid
  join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode and h.hcode=t.hcode
  join public.profiles a on a.user_id=auth.uid() and a.active
  where not exists (select 1 from private.ncd_external_diagnoses d where d.source_pcucode=t.source_pcucode and d.source_pid=t.source_pid)
    and t.active and t.due_on>=timezone('Asia/Bangkok',now())::date
    and p.active and p.service_population_eligible and p.jhcis_typelive in (1,3)
    and h.superseded_by is null and h.verification_status='verified_jhcis'
    and coalesce(h.house_id_11,'')<>'52010046170'
    and (a.role='admin'
      or (a.role='staff' and nullif(btrim(a.community),'') is not null
          and private.community_key(a.community)=private.community_key(t.community)
          and private.community_key(t.community)=private.community_key(h.community))
      or (a.role='user' and t.owner_pid=a.volunteer_pid and h.volunteer_pid=t.owner_pid));
$function$
;
create function public.close_ncd_external_diagnosis(p_target_id uuid,p_kind text,p_treatment_site text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c record;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if coalesce(char_length(btrim(p_treatment_site)),0) not between 1 and 200 then raise exception 'TREATMENT_SITE_REQUIRED'; end if;
 perform pg_catalog.pg_advisory_xact_lock(2201,6116);
 if exists(select 1 from private.ncd_external_diagnoses d where d.target_id=p_target_id and d.kind=p_kind and d.recorded_by=auth.uid() and d.treatment_site=btrim(p_treatment_site)) then
   return jsonb_build_object('ok',true);
 end if;
 select * into c from private.ncd_main_cases_v2201() where source_screen_id=p_target_id and kind=p_kind;
 if not found then raise exception 'CASE_NOT_ALLOWED'; end if;
 insert into private.ncd_external_diagnoses(source_pcucode,source_pid,kind,target_id,treatment_site,recorded_by)
 values(c.source_pcucode,c.source_pid,c.kind,c.source_screen_id,btrim(p_treatment_site),auth.uid());
 return jsonb_build_object('ok',true);
end;
$$;
revoke all on function public.close_ncd_external_diagnosis(uuid,text,text) from public,anon;
grant execute on function public.close_ncd_external_diagnosis(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
