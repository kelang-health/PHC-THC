-- The case source already applies the existing admin, staff and volunteer scope.
create function public.ncd_field_worklist_page_v2196(
  p_kind text default 'all', p_search text default '', p_offset integer default 0
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  v_result jsonb;
  v_offset integer := greatest(coalesce(p_offset,0),0);
begin
  if not exists(select 1 from public.profiles where user_id=auth.uid() and active) then
    raise exception 'AUTH_REQUIRED';
  end if;

  with matches as materialized (
    select c.source_screen_id,c.kind,c.display_name,c.house_no,c.community,
           c.screened_on,c.sbp,c.dbp,c.glucose_mg_dl,c.glucose_type
    from private.ncd_field_cases_v2203() c
    where (p_kind='all' or c.kind=p_kind)
      and strpos(
        lower(coalesce(c.display_name,'')||' '||coalesce(c.house_no,'')||' '||coalesce(c.community,'')),
        lower(left(coalesce(p_search,''),160))
      )>0
  ), page as (
    select * from matches order by screened_on,display_name,source_screen_id,kind
    limit 50 offset v_offset
  ), summaries as (
    select p.*, history.measurement_count, coalesce(streak.consecutive,0) as bp_days_consecutive
    from page p
    cross join lateral (
      select count(*) as measurement_count
      from private.ncd_field_results_v2203 m
      where m.source_screen_id=p.source_screen_id and m.kind=p.kind
    ) history
    left join lateral (
      select max(run.days) as consecutive
      from (
        select count(*) as days
        from (
          select m.measured_on, m.measured_on - row_number() over(order by m.measured_on)::integer as streak
          from private.ncd_field_results_v2203 m
          where m.source_screen_id=p.source_screen_id and m.kind='bp'
          group by m.measured_on
          having count(distinct (m.period,m.sequence)) filter (
            where m.period in ('morning','evening') and m.sequence in (1,2)
          )=4
        ) complete_days
        group by complete_days.streak
      ) run
    ) streak on p.kind='bp'
  )
  select jsonb_build_object(
    'items',coalesce((select jsonb_agg(to_jsonb(s) order by s.screened_on,s.display_name,s.source_screen_id,s.kind) from summaries s),'[]'::jsonb),
    'total',(select count(*) from matches)
  ) into v_result;
  return v_result;
end;
$$;

create function public.ncd_field_case_history_v2196(p_source_screen_id uuid,p_kind text)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not exists (
    select 1 from private.ncd_field_cases_v2203() c
    where c.source_screen_id=p_source_screen_id and c.kind=p_kind
  ) then
    raise exception 'CASE_NOT_ALLOWED';
  end if;

  select coalesce(jsonb_agg(to_jsonb(m) order by m.measured_on,m.period,m.sequence),'[]'::jsonb)
  into v_result
  from (
    select measured_on,kind,period,sequence,sbp,dbp,pulse,dtx,fasting
    from private.ncd_field_results_v2203
    where source_screen_id=p_source_screen_id and kind=p_kind
  ) m;
  return v_result;
end;
$$;

revoke all on function public.ncd_field_worklist_page_v2196(text,text,integer),
  public.ncd_field_case_history_v2196(uuid,text) from public,anon,authenticated;
grant execute on function public.ncd_field_worklist_page_v2196(text,text,integer),
  public.ncd_field_case_history_v2196(uuid,text) to authenticated;
