-- H3: search within currently assigned verified households only. No risk or clinical history is returned.
create or replace function public.search_hcv_event_people_v2087(
 p_event uuid, p_query text, p_limit integer default 20
) returns table(source_pcucode text,source_pid bigint,display_name text,birth_date date,house_no text,community text)
language plpgsql security definer set search_path='' as $$
declare v_pid bigint; v_query text;
begin
 select p.volunteer_pid into v_pid from public.profiles p
 where p.user_id=auth.uid() and p.active is true and p.role='user';
 if not found or v_pid is null then
   raise exception 'เน€เธเธเธฒเธฐเธเธฑเธเธเธต เธญเธชเธก. เธ—เธตเนเธกเธตเธเนเธฒเธเธฃเธฑเธเธเธดเธ”เธเธญเธ' using errcode='42501';
 end if;
 if not exists(select 1 from public.cloud_announcements_v2083 a
   where a.id=p_event and a.kind='event' and a.event_subtype='hcv_hbsag'
   and a.status='published' and a.audience='user'
   and (a.target_community is null or a.target_community =
      (select p.community from public.profiles p where p.user_id=auth.uid()))) then
   raise exception 'เนเธกเนเธกเธตเธชเธดเธ—เธเธดเนเน€เธเนเธฒเธ–เธถเธเธเธดเธเธเธฃเธฃเธก' using errcode='42501';
 end if;
 v_query:=trim(coalesce(p_query,''));
 if char_length(v_query)<2 or char_length(v_query)>70 then return; end if;
 return query
 select hp.source_pcucode,hp.source_pid,hp.display_name,hp.birth_date,h.house_no,h.community
 from public.health_persons hp join public.houses h
  on h.source_pcucode=hp.house_pcucode and h.hcode=hp.hcode
 where hp.active is true and hp.service_population_eligible is true
   and h.superseded_by is null and h.verification_status='verified_jhcis'
   and h.volunteer_pid=v_pid
   and private.health_can_access_house(hp.house_pcucode,hp.hcode)
   and hp.display_name ilike ('%'||replace(replace(replace(v_query,'\','\\'),'%','\%'),'_','\_')||'%') escape '\'
 order by hp.display_name,hp.source_pid
 limit least(greatest(coalesce(p_limit,20),1),20);
end $$;
revoke all on function public.search_hcv_event_people_v2087(uuid,text,integer) from public,anon;
grant execute on function public.search_hcv_event_people_v2087(uuid,text,integer) to authenticated;
