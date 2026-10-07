alter table private.house_id11_review_v2202 add column original_id11 text;
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
 'house_id_11',h.house_id_11,'original_id11',r.original_id11,'updated_at',h.updated_at,
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
end $function$
;
notify pgrst,'reload schema';
