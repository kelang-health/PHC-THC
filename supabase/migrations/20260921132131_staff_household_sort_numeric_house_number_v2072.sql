do $$
declare v_def text;
begin
 select pg_get_functiondef('public.staff_household_cards_v2072(text)'::regprocedure) into v_def;
 if position('::integer nulls last' in v_def)=0 then raise exception 'EXPECTED_SORT_CAST_MISSING'; end if;
 execute replace(v_def,'::integer nulls last','::numeric nulls last');
end $$;
