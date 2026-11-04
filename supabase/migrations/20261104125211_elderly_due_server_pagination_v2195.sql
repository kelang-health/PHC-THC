-- Reuse the existing authenticated worklist and apply the elderly filter
-- before pagination. Keep scope, assignment rules and row shape intact.
do $migration$
declare
  old_path regprocedure := 'public.health_worklist_assignment_json_v2033(text,text,text,text,text,text,bigint,integer,integer)'::regprocedure;
  fast_path regprocedure := 'public.health_worklist_assignment_json_v2054(text,text,text,text,text,text,bigint,integer,integer)'::regprocedure;
  target regprocedure;
  definition text;
  original text;
  scope_anchor constant text := 'and (v_stage is null or c.life_stage=v_stage)';
  result_anchor constant text := 'return v_result;';
  elderly_clause constant text := $clause$
        and (v_filter <> 'elderly_due' or (
          c.screening_route = 'elderly_60_plus'
          and not coalesce(c.elderly9_completed_current_fy, false)
          and coalesce(c.elderly9_status_current_fy, '') <> 'complete'
        ))$clause$;
  expected integer;
begin
  foreach target in array array[old_path,fast_path] loop
    original := pg_get_functiondef(target);
    expected := case when target=fast_path then 2 else 1 end;
    if (length(original)-length(replace(original,scope_anchor,'')))/length(scope_anchor) <> expected then
      raise exception 'ELDERLY_DUE_SCOPE_ANCHOR_MISMATCH: %',target;
    end if;
    definition := replace(original,scope_anchor,scope_anchor||elderly_clause||E'\n        ');
    if target=old_path then
      if strpos(original,$old$if v_filter not in ('field_targets','due','targets','known','all')$old$)=0
         or strpos(original,$old$if v_filter='field_targets' then$old$)=0 then
        raise exception 'ELDERLY_DUE_LEGACY_BRANCH_MISMATCH';
      end if;
      definition := replace(definition,$old$if v_filter not in ('field_targets','due','targets','known','all')$old$,
        $new$if v_filter not in ('field_targets','elderly_due','due','targets','known','all')$new$);
      definition := replace(definition,$old$if v_filter='field_targets' then$old$,
        $new$if v_filter in ('field_targets','elderly_due') then$new$);
    else
      if strpos(original,$old$if v_filter<>'field_targets' then$old$)=0 then
        raise exception 'ELDERLY_DUE_FAST_BRANCH_MISMATCH';
      end if;
      definition := replace(definition,$old$if v_filter<>'field_targets' then$old$,
        $new$if v_filter not in ('field_targets','elderly_due') then$new$);
    end if;
    if strpos(original,result_anchor)=0 then
      raise exception 'ELDERLY_DUE_RESULT_ANCHOR_MISMATCH: %',target;
    end if;
    definition := replace(definition,result_anchor,$result$return case when v_filter='elderly_due'
      then v_result||jsonb_build_object('filter',v_filter) else v_result end;$result$);
    execute definition;
  end loop;
end;
$migration$;
