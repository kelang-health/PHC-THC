CREATE OR REPLACE FUNCTION public.my_household_cards_v1860()
RETURNS TABLE(id uuid,hcode text,house_no text,moo text,community text,latitude double precision,longitude double precision,coordinate_source text,coordinate_status text,record_status text,review_required boolean,review_reason text,volunteer_pid bigint,house_id_11 text,entry_source text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
declare v_role text; v_pid bigint;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 v_role:=private.current_role();
 v_pid:=private.current_volunteer_pid();
 if v_role not in ('user','staff') or v_pid is null then raise exception 'VHV_SCOPE_REQUIRED'; end if;
 return query
 select h.id,h.hcode,h.house_no,h.moo,h.community,h.latitude,h.longitude,
        h.coordinate_source,h.coordinate_status,h.record_status,h.review_required,
        h.review_reason,h.volunteer_pid,h.house_id_11,h.entry_source
 from public.houses h
 where h.superseded_by is null and h.verification_status='verified_jhcis' and h.volunteer_pid=v_pid
 order by nullif(regexp_replace(coalesce(h.house_no,''),'[^0-9].*$',''),'')::numeric nulls last,
          h.house_no,h.id;
end;
$function$;
