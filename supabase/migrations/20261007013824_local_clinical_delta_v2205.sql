create function public.service_clinical_delta_v2205(p_pcucode text,p_dataset text,p_after timestamptz default '1970-01-01',p_after_id text default '',p_until timestamptz default now(),p_limit integer default 500)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if coalesce(auth.jwt()->>'role','')<>'service_role' then raise exception 'SERVICE_ONLY';end if;
 if coalesce(p_pcucode,'')='' or p_dataset not in('ncd_field','elderly_vitals') or p_dataset is null or p_limit not between 1 and 500 then raise exception 'INVALID_REQUEST';end if;
 with source as(
 select m.id::text source_id,m.created_at changed_at,to_jsonb(m)-'recorded_by'-'request_id'||jsonb_build_object('source_pcucode',s.source_pcucode,'source_pid',s.source_pid) payload
 from private.ncd_field_results_v2203 m join public.health_ncd_screenings s on s.id=m.source_screen_id
 where p_dataset='ncd_field' and s.source_pcucode=p_pcucode
 union all
 select v.session_id::text,v.updated_at,to_jsonb(v)-'measured_by' from public.elderly9_basic_health_checks_v2140 v
 where p_dataset='elderly_vitals' and v.source_pcucode=p_pcucode
 ), page as(select * from source where (changed_at,source_id)>(p_after,p_after_id) and changed_at<=p_until order by changed_at,source_id limit p_limit)
 select coalesce(jsonb_agg(jsonb_build_object('source_id',source_id,'changed_at',changed_at,'payload',payload) order by changed_at,source_id),'[]'::jsonb) into result from page;
 return result;
end $$;
revoke all on function public.service_clinical_delta_v2205(text,text,timestamptz,text,timestamptz,integer) from public,anon,authenticated;
grant execute on function public.service_clinical_delta_v2205(text,text,timestamptz,text,timestamptz,integer) to service_role;
notify pgrst,'reload schema';
