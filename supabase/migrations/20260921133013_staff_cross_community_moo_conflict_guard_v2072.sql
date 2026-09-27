do $migration$
declare v_definition text;v_old text;v_new text;
begin
 select pg_get_functiondef('public.staff_household_cards_v2072(text)'::regprocedure) into v_definition;
 v_old:=' v_is_own:=private.community_key(v_target.name)=private.community_key(v_own.name);';
 v_new:=' v_is_own:=private.community_key(v_target.name)=private.community_key(v_own.name);
 if not v_is_own and exists (
   select 1 from public.houses h
   where h.superseded_by is null
     and h.verification_status=''verified_jhcis''
     and private.community_key(h.community)=private.community_key(v_target.name)
     and btrim(coalesce(h.moo,''''))<>btrim(v_target.moo)
 ) then
   raise exception ''COMMUNITY_MOO_CONFLICT_REQUIRES_ADMIN_REVIEW'';
 end if;';
 if position(v_old in v_definition)=0 then raise exception 'STAFF_SCOPE_GUARD_ANCHOR_MISSING'; end if;
 execute replace(v_definition,v_old,v_new);
end $migration$;
