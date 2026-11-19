begin;
create function public.child_quarter_result_v208(p_pcu text,p_pid bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 today date := (now() at time zone 'Asia/Bangkok')::date;
 start_day date := date_trunc('quarter',today)::date;
 p public.health_persons%rowtype;
 g jsonb;
 d jsonb;
begin
 if auth.uid() is null or not coalesce(private.health_can_access_person(p_pcu,p_pid),false) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
 select * into p from public.health_persons where source_pcucode=p_pcu and source_pid=p_pid;
 select jsonb_build_object('id',x.id,'day',s.screening_date,'weight_kg',x.weight_kg,'height_cm',x.height_cm,'nutrition',x.nutrition_result,'source','Cloud') into g
 from public.health_growth_screenings x join public.screening_sessions s on s.id=x.session_id
 where x.source_pcucode=p_pcu and x.source_pid=p_pid and s.route='child_0_5' and s.screening_date between start_day and today
 order by s.screening_date desc,x.screened_at desc,x.id desc limit 1;
 if g is null and p.growth_previous_on between start_day and today and p.growth_previous_weight_kg>0 and p.growth_previous_height_cm>0 then
 g:=jsonb_build_object('day',p.growth_previous_on,'weight_kg',p.growth_previous_weight_kg,'height_cm',p.growth_previous_height_cm,'source','JHCIS',
 'nutrition',private.growth_interpret_v204((extract(year from age(p.growth_previous_on,p.birth_date))*12+extract(month from age(p.growth_previous_on,p.birth_date)))::integer,p.gender,p.growth_previous_weight_kg,p.growth_previous_height_cm));
 end if;
 select jsonb_build_object('id',x.id,'day',s.screening_date,'domains',x.domains,'status',x.overall_status,'note',x.note) into d
 from public.child_development_screenings x join public.screening_sessions s on s.id=x.session_id
 where x.source_pcucode=p_pcu and x.source_pid=p_pid and s.route='child_0_5' and s.screening_date between start_day and today
 order by s.screening_date desc,x.screened_at desc,x.id desc limit 1;
 return jsonb_build_object('start',start_day,'growth',g,'development',d,'complete',g is not null and coalesce(d->>'status' in ('preliminary_normal','needs_further_assessment'),false)
 and not exists(select 1 from unnest(array['gross_motor','fine_motor_intelligence','receptive_language','expressive_language','personal_social']) k where coalesce(d->'domains'->>k,'') not in ('normal','observation')));
end $$;
create function public.save_child_quarter_v208(p_session uuid,p_weight numeric,p_height numeric,p_domains jsonb,p_note text,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.screening_sessions%rowtype;
begin
 select * into s from public.screening_sessions where id=p_session;
 if not found or s.route<>'child_0_5' or auth.uid() is null or not coalesce(private.health_can_access_person(s.source_pcucode,s.source_pid),false) then raise exception 'SESSION_OUT_OF_SCOPE'; end if;
 if s.screening_date <> (now() at time zone 'Asia/Bangkok')::date then raise exception 'CHILD_SESSION_DATE_CHANGED'; end if;
 perform pg_advisory_xact_lock(hashtextextended('child-quarter:'||s.source_pcucode||':'||s.source_pid,0));
 if public.child_quarter_result_v208(s.source_pcucode,s.source_pid) is distinct from p_expected then raise exception 'CHILD_QUARTER_CHANGED'; end if;
 if exists(select 1 from unnest(array['gross_motor','fine_motor_intelligence','receptive_language','expressive_language','personal_social']) k where coalesce(p_domains->>k,'') not in ('normal','observation')) then raise exception 'CHILD_DOMAINS_INCOMPLETE'; end if;
 if p_expected->'growth'='null'::jsonb or (p_weight,p_height) is distinct from ((p_expected->'growth'->>'weight_kg')::numeric,(p_expected->'growth'->>'height_cm')::numeric) then
 perform public.save_growth_screening_v190(p_session,p_weight,p_height);
 end if;
 perform public.save_child_development_v190(p_session,p_domains,p_note);
 return public.child_quarter_result_v208(s.source_pcucode,s.source_pid);
end $$;
revoke all on function public.child_quarter_result_v208(text,bigint),public.save_child_quarter_v208(uuid,numeric,numeric,jsonb,text,jsonb) from public,anon;
grant execute on function public.child_quarter_result_v208(text,bigint),public.save_child_quarter_v208(uuid,numeric,numeric,jsonb,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
