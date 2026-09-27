-- Cloud v2.0.56 โ€” Child 0-14 JHCIS growth history bridge.
-- JHCIS remains read-only; only a latest measurement snapshot is replicated to Cloud.
begin;

alter table public.health_persons
  add column if not exists growth_previous_on date,
  add column if not exists growth_previous_weight_kg numeric(5,2),
  add column if not exists growth_previous_height_cm numeric(5,2),
  add column if not exists growth_previous_source text;

create or replace function public.growth_timeline_v204(p_source_pcucode text,p_source_pid bigint)
returns table(
  id uuid,
  screened_at timestamptz,
  age_months integer,
  weight_kg numeric,
  height_cm numeric,
  interpretation_code text,
  interpretation_label text,
  reference_version text,
  nutrition_result jsonb
)
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.uid() is null or not private.health_can_access_person(p_source_pcucode,p_source_pid) then
    raise exception 'PERSON_OUT_OF_SCOPE';
  end if;

  return query
  with timeline as (
    select
      g.id,
      g.screened_at,
      g.age_months,
      g.weight_kg::numeric as weight_kg,
      g.height_cm::numeric as height_cm,
      g.interpretation_code,
      g.interpretation_label,
      g.reference_version,
      g.nutrition_result
    from public.health_growth_screenings g
    where g.source_pcucode=p_source_pcucode and g.source_pid=p_source_pid

    union all

    select
      null::uuid as id,
      (hp.growth_previous_on::timestamp at time zone 'Asia/Bangkok') as screened_at,
      case
        when hp.birth_date is null then null::integer
        else greatest(0,
          (extract(year from age(hp.growth_previous_on,hp.birth_date))::integer * 12)
          + extract(month from age(hp.growth_previous_on,hp.birth_date))::integer
        )
      end as age_months,
      hp.growth_previous_weight_kg::numeric as weight_kg,
      hp.growth_previous_height_cm::numeric as height_cm,
      'jhcis_history'::text as interpretation_code,
      'เธเธฃเธฐเธงเธฑเธ•เธดเธเนเธณเธซเธเธฑเธ/เธชเนเธงเธเธชเธนเธเน€เธ”เธดเธกเธเธฒเธ JHCIS'::text as interpretation_label,
      coalesce(nullif(hp.growth_previous_source,''),'JHCIS')::text as reference_version,
      null::jsonb as nutrition_result
    from public.health_persons hp
    where hp.source_pcucode=p_source_pcucode
      and hp.source_pid=p_source_pid
      and hp.active=true
      and hp.growth_previous_on is not null
      and hp.growth_previous_weight_kg is not null
      and hp.growth_previous_height_cm is not null
  )
  select t.id,t.screened_at,t.age_months,t.weight_kg,t.height_cm,
         t.interpretation_code,t.interpretation_label,t.reference_version,t.nutrition_result
  from timeline t
  order by t.screened_at desc nulls last
  limit 50;
end;
$$;

revoke all on function public.growth_timeline_v204(text,bigint) from public,anon;

grant execute on function public.growth_timeline_v204(text,bigint) to authenticated;

insert into public.app_settings(key,value)
values('child_growth_jhcis_history_v2056',jsonb_build_object(
  'version','2.0.56',
  'age_range','0-14',
  'jhcis_source_priority',jsonb_build_array('visitnutrition','studenthealthnutrition','visit'),
  'cloud_snapshot_columns',jsonb_build_array('growth_previous_on','growth_previous_weight_kg','growth_previous_height_cm','growth_previous_source'),
  'timeline','cloud_growth_plus_latest_jhcis_snapshot',
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
