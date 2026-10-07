create table private.ncd_field_results_v2203(
 id uuid primary key default gen_random_uuid(),request_id uuid not null unique,
 source_screen_id uuid not null references public.health_ncd_screenings(id),kind text not null check(kind in('bp','dtx')),
 measured_on date not null,period text,sequence smallint,sbp integer,dbp integer,pulse integer,dtx integer,fasting boolean,
 recorded_by uuid not null,created_at timestamptz not null default now(),
 check((kind='bp' and sbp between 70 and 260 and dbp between 40 and 180 and sbp>dbp and pulse between 20 and 250 and period in('morning','evening') and sequence in(1,2) and dtx is null and fasting is null)
 or(kind='dtx' and dtx between 20 and 700 and fasting is not null and sbp is null and dbp is null and pulse is null and period is null and sequence is null))
);
create unique index ncd_field_bp_slot_v2203 on private.ncd_field_results_v2203(source_screen_id,measured_on,period,sequence) where kind='bp';
create unique index ncd_field_dtx_day_v2203 on private.ncd_field_results_v2203(source_screen_id,measured_on) where kind='dtx';
alter table private.ncd_field_results_v2203 enable row level security;
revoke all on private.ncd_field_results_v2203 from public,anon,authenticated;

create function private.ncd_field_cases_v2203() returns table(source_screen_id uuid,kind text,source_pcucode text,source_pid bigint,display_name text,house_no text,community text,screened_on date,sbp integer,dbp integer,glucose_mg_dl integer,glucose_type text)
language sql stable security definer set search_path='' as $$
 with actor as(select * from public.profiles where user_id=auth.uid() and active), candidates as(
 select s.id, k.kind,s.source_pcucode,s.source_pid,p.display_name,h.house_no,h.community,s.screened_on,s.sbp,s.dbp,s.glucose_mg_dl,s.glucose_type,
 row_number()over(partition by s.source_pcucode,s.source_pid,k.kind order by s.screened_on,s.recorded_at,s.id) rn
 from public.health_ncd_screenings s join public.health_persons p using(source_pcucode,source_pid)
 join public.houses h on h.source_pcucode=p.house_pcucode and h.hcode=p.hcode
 cross join actor a cross join(values('bp'),('dtx')) k(kind)
 where p.active and p.ncd_base_eligible and p.jhcis_typelive in(1,3) and h.superseded_by is null
 and s.screened_on>=make_date(extract(year from timezone('Asia/Bangkok',now()))::int-case when extract(month from timezone('Asia/Bangkok',now()))<10 then 1 else 0 end,10,1)
 and s.screened_on<=timezone('Asia/Bangkok',now())::date and p.birth_date<=s.screened_on-interval '35 years'
 and(a.role='admin' or(a.role='staff' and coalesce(btrim(a.community),'')<>'' and private.community_key(a.community)=private.community_key(h.community)) or(a.role='user' and h.volunteer_pid=a.volunteer_pid))
 and((k.kind='bp' and (not p.has_ht or exists(select 1 from private.ncd_field_results_v2203 m where m.source_screen_id=s.id and m.kind='bp')) and(s.sbp between 140 and 179 or s.dbp between 90 and 109) and s.sbp<180 and s.dbp<110)
 or(k.kind='dtx' and (not p.has_dm or exists(select 1 from private.ncd_field_results_v2203 m where m.source_screen_id=s.id and m.kind='dtx')) and((s.glucose_type='fasting' and s.glucose_mg_dl>=126)or(s.glucose_type='random' and s.glucose_mg_dl>=110))))
 )select id,kind,source_pcucode,source_pid,display_name,house_no,community,screened_on,sbp,dbp,glucose_mg_dl,glucose_type from candidates where rn=1;
$$;
revoke all on function private.ncd_field_cases_v2203() from public,anon,authenticated;

create function public.ncd_field_worklist_v2203() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.profiles where user_id=auth.uid() and active) then raise exception 'AUTH_REQUIRED';end if;
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('measurements',coalesce((select jsonb_agg(to_jsonb(m)-'recorded_by'-'request_id' order by m.measured_on,m.period,m.sequence) from private.ncd_field_results_v2203 m where m.source_screen_id=c.source_screen_id and m.kind=c.kind),'[]'::jsonb)) order by c.screened_on,c.display_name),'[]'::jsonb) into result from private.ncd_field_cases_v2203() c;
 return result;
end $$;
revoke all on function public.ncd_field_worklist_v2203() from public,anon;
grant execute on function public.ncd_field_worklist_v2203() to authenticated;

create function public.save_ncd_field_result_v2203(p_source_screen_id uuid,p_kind text,p_measured_on date,p_request_id uuid,p_sbp integer default null,p_dbp integer default null,p_pulse integer default null,p_period text default null,p_sequence smallint default null,p_dtx integer default null,p_fasting boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c record; result uuid;
begin
 select * into c from private.ncd_field_cases_v2203() where source_screen_id=p_source_screen_id and kind=p_kind;
 if c.source_screen_id is null then raise exception 'CASE_NOT_ALLOWED';end if;
 if p_measured_on is null or p_measured_on<=c.screened_on or p_measured_on>timezone('Asia/Bangkok',now())::date then raise exception 'FOLLOWUP_DATE_INVALID';end if;
 if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
 if p_kind='bp' and(p_sbp is null or p_dbp is null or p_pulse is null or p_period is null or p_sequence is null or p_sbp not between 70 and 260 or p_dbp not between 40 and 180 or p_sbp<=p_dbp or p_pulse not between 20 and 250 or p_period not in('morning','evening') or p_sequence not in(1,2) or p_dtx is not null or p_fasting is not null) then raise exception 'BP_FIELDS_INVALID';end if;
 if p_kind='dtx' and(p_dtx is null or p_dtx not between 20 and 700 or p_fasting is null or p_sbp is not null or p_dbp is not null or p_pulse is not null or p_period is not null or p_sequence is not null) then raise exception 'DTX_FIELDS_INVALID';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_source_screen_id::text||p_kind));
 select id into result from private.ncd_field_results_v2203 where request_id=p_request_id and source_screen_id=p_source_screen_id and kind=p_kind and recorded_by=auth.uid();
 if result is not null then return jsonb_build_object('ok',true,'id',result,'replayed',true);end if;
 insert into private.ncd_field_results_v2203(request_id,source_screen_id,kind,measured_on,sbp,dbp,pulse,period,sequence,dtx,fasting,recorded_by)
 values(p_request_id,p_source_screen_id,p_kind,p_measured_on,p_sbp,p_dbp,p_pulse,p_period,p_sequence,p_dtx,p_fasting,auth.uid()) returning id into result;
 return jsonb_build_object('ok',true,'id',result);
end $$;
revoke all on function public.save_ncd_field_result_v2203(uuid,text,date,uuid,integer,integer,integer,text,smallint,integer,boolean) from public,anon;
grant execute on function public.save_ncd_field_result_v2203(uuid,text,date,uuid,integer,integer,integer,text,smallint,integer,boolean) to authenticated;
