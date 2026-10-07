CREATE OR REPLACE FUNCTION public.correct_audited_house_id11_v2202(p_house_id uuid, p_id11 text, p_expected_updated_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; h public.houses; v text:=btrim(p_id11);
begin
 select * into p from public.profiles where user_id=auth.uid() and active;
 if p.user_id is null then raise exception 'AUTH_REQUIRED'; end if;
 if v is null or v !~ '^[0-9]{11}$' then raise exception 'HOUSE_ID11_INVALID'; end if;
 select * into h from public.houses where id=p_house_id and superseded_by is null and verification_status='verified_jhcis' for update;
 if h.id is null or not exists(select 1 from private.house_id11_review_v2202 where house_id=h.id) then raise exception 'NOT_IN_AUDIT_COHORT'; end if;
 if not (p.role='admin' or (p.role='user' and h.volunteer_pid=p.volunteer_pid)) then raise exception 'HOUSE_OUT_OF_SCOPE'; end if;
 if h.updated_at is distinct from p_expected_updated_at then raise exception 'HOUSE_CHANGED_RELOAD'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('house11:'||v));
 if exists(select 1 from public.houses where id<>h.id and superseded_by is null and house_id_11=v) then raise exception 'HOUSE_ID11_DUPLICATE'; end if;
 update private.house_id11_review_v2202 set corrected_id11=v,corrected_by=p.user_id,corrected_at=now() where house_id=h.id;
 update public.houses set house_id_11=v,updated_at=now() where id=h.id;
 insert into public.house_registration_audit(house_id,user_id,role,volunteer_pid,action,before_data,after_data)
 values(h.id,p.user_id,p.role,p.volunteer_pid,'update',jsonb_build_object('house_id_11',h.house_id_11),jsonb_build_object('house_id_11',v,'source','id11_audit_v2202','pending_main',true));
 return jsonb_build_object('ok',true,'house_id',h.id,'house_id_11',v);
end $function$;

CREATE OR REPLACE FUNCTION public.house_registration_review_cards_v2202()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where user_id=auth.uid() and active;
 if p.user_id is null then raise exception 'AUTH_REQUIRED'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',h.id,'hcode',h.hcode,'house_no',h.house_no,'moo',h.moo,'community',h.community,
 'house_id_11',h.house_id_11,'updated_at',h.updated_at,
 'needs_id11',r.house_id is not null and coalesce(h.house_id_11,'') !~ '^[0-9]{11}$',
 'unassigned_village',coalesce(btrim(h.community),'')='' and h.volunteer_pid is null,
 'can_edit',(p.role='admin' or (p.role='user' and h.volunteer_pid=p.volunteer_pid)),
 'pending_main',r.corrected_id11 is not null
 ) order by h.moo,h.house_no),'[]'::jsonb) into result
 from public.houses h left join private.house_id11_review_v2202 r on r.house_id=h.id
 where h.superseded_by is null and h.verification_status='verified_jhcis'
 and ((r.house_id is not null and coalesce(h.house_id_11,'') !~ '^[0-9]{11}$')
 or (coalesce(btrim(h.community),'')='' and h.volunteer_pid is null))
 and (p.role='admin'
 or (p.role='staff' and (
 (coalesce(btrim(p.community),'')<>'' and private.community_key(p.community)=private.community_key(h.community))
 or (coalesce(btrim(h.community),'')='' and h.volunteer_pid is null and exists(
 select 1 from public.communities c where c.active and private.community_key(c.name)=private.community_key(p.community)
 and btrim(c.moo)=btrim(h.moo)))))
 or (p.role='user' and h.volunteer_pid=p.volunteer_pid));
 return result;
end $function$;
notify pgrst,'reload schema';
