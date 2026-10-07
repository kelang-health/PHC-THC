create or replace function public.ncd_field_local_report_v2204(p_pcucode text,p_mode text,p_community text default '',p_volunteer_pid bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'SERVICE_ONLY';end if;
if p_mode not in('all','community','self') or p_mode is null or coalesce(p_pcucode,'')='' then raise exception 'SCOPE_REQUIRED';end if;
with cases as (with actor as(select p_mode role,p_community community,p_volunteer_pid volunteer_pid), candidates as(
 select s.id, k.kind,s.source_pcucode,s.source_pid,p.display_name,h.house_no,h.community,s.screened_on,s.sbp,s.dbp,s.glucose_mg_dl,s.glucose_type,
 row_number()over(partition by s.source_pcucode,s.source_pid,k.kind order by s.screened_on,s.recorded_at,s.id) rn
 from public.health_ncd_screenings s join public.health_persons p using(source_pcucode,source_pid)
 join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
 cross join actor a cross join(values('bp'),('dtx')) k(kind)
 where s.source_pcucode=p_pcucode and p.active and p.ncd_base_eligible and p.jhcis_typelive in(1,3) and h.superseded_by is null
 and s.screened_on>=make_date(extract(year from timezone('Asia/Bangkok',now()))::int-case when extract(month from timezone('Asia/Bangkok',now()))<10 then 1 else 0 end,10,1)
 and s.screened_on<=timezone('Asia/Bangkok',now())::date and p.birth_date<=s.screened_on-interval '35 years'
 and(a.role='all' or(a.role='community' and coalesce(btrim(a.community),'')<>'' and private.community_key(a.community)=private.community_key(h.community)) or(a.role='self' and h.volunteer_pid=a.volunteer_pid))
 and((k.kind='bp' and (not p.has_ht or exists(select 1 from private.ncd_field_results_v2203 m where m.source_screen_id=s.id and m.kind='bp')) and(s.sbp between 140 and 179 or s.dbp between 90 and 109) and s.sbp<180 and s.dbp<110)
 or(k.kind='dtx' and (not p.has_dm or exists(select 1 from private.ncd_field_results_v2203 m where m.source_screen_id=s.id and m.kind='dtx')) and((s.glucose_type='fasting' and s.glucose_mg_dl>=126)or(s.glucose_type='random' and s.glucose_mg_dl>=110))))
 )select id source_screen_id,kind,source_pcucode,source_pid,display_name,house_no,community,screened_on,sbp,dbp,glucose_mg_dl,glucose_type from candidates where rn=1)
select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('measurements',coalesce((select jsonb_agg(to_jsonb(m)-'recorded_by'-'request_id' order by m.measured_on,m.period,m.sequence) from private.ncd_field_results_v2203 m where m.source_screen_id=c.source_screen_id and m.kind=c.kind),'[]'::jsonb))),'[]'::jsonb) into result from cases c;
return result;
end $$;
revoke all on function public.ncd_field_local_report_v2204(text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.ncd_field_local_report_v2204(text,text,text,bigint) to service_role;
notify pgrst,'reload schema';
