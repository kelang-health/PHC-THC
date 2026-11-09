-- Preserve all measurements in history; only fasting DTX completes the community step.
create or replace function public.ncd_field_worklist_page_v2196(
  p_kind text default 'all', p_search text default '', p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not exists(select 1 from public.profiles where user_id=auth.uid() and active) then raise exception 'AUTH_REQUIRED'; end if;
  with matches as materialized (
    select * from private.ncd_main_cases_v2201() c
    where (p_kind='all' or c.kind=p_kind)
      and strpos(lower(concat_ws(' ',c.display_name,c.house_no,c.community)),lower(left(coalesce(p_search,''),160)))>0
  ), page as (
    select * from matches order by due_on,display_name,source_screen_id
    limit 50 offset greatest(coalesce(p_offset,0),0)
  ), summaries as (
    select p.*, history.measurement_count, history.fasting_dtx_count, coalesce(streak.consecutive,0) as bp_days_consecutive
    from page p
    cross join lateral (
      select count(*) as measurement_count,
             count(*) filter (where m.kind='dtx' and m.fasting is true) as fasting_dtx_count
      from private.ncd_field_results_v2203 m
      where m.main_target_id=p.source_screen_id and m.kind=p.kind
    ) history
    left join lateral (
      select max(run.days) as consecutive
      from (
        select count(*) as days from (
          select m.measured_on,m.measured_on-row_number() over(order by m.measured_on)::integer as streak
          from private.ncd_field_results_v2203 m
          where m.main_target_id=p.source_screen_id and m.kind='bp'
          group by m.measured_on having count(distinct (m.period,m.sequence))=4
        ) complete_days group by complete_days.streak
      ) run
    ) streak on p.kind='bp'
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(s) order by s.due_on,s.display_name,s.source_screen_id) from summaries s),'[]'::jsonb),
    'total',(select count(*) from matches)) into v_result;
  return v_result;
end;
$$;

notify pgrst,'reload schema';
