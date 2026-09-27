-- Cloud v2.0.57 corrective performance: preserve both card contracts
-- while scanning verified houses only once.
begin;

create or replace function public.admin_community_fast_bundle_v2057()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_result jsonb;
begin
  if auth.uid() is null or private.current_role()<>'admin' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  with ctx as materialized (
    select private.current_community()::text as own_community
  ),
  stats as materialized (
    select
      c.name::text as community,
      c.moo::text as moo,
      count(h.id)::bigint as houses,
      count(h.id) filter (where h.volunteer_pid is not null)::bigint as assigned_houses,
      count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint as pinned_houses,
      count(h.id) filter (where h.coordinate_status like 'resolved_%')::bigint as field_confirmed,
      count(h.id) filter (where h.review_required=true)::bigint as review_houses,
      count(h.id) filter (where h.inside_tambon=false)::bigint as outside_tambon,
      count(h.id) filter (
        where h.inside_community=false
          and h.inside_tambon is distinct from false
      )::bigint as outside_community,
      count(h.id) filter (where h.inside_community=false)::bigint as outside_community_v1854,
      count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint as missing_coordinates,
      count(h.id) filter (where h.house_id_11 is null or h.house_id_11 !~ '^[0-9]{11}$')::bigint as missing_house_id_11,
      count(distinct h.volunteer_pid) filter (where h.volunteer_pid is not null)::bigint as volunteers
    from public.communities c
    left join public.houses h
      on btrim(h.community)=btrim(c.name)
     and h.superseded_by is null
     and h.verification_status='verified_jhcis'
    where c.active=true
    group by c.name,c.moo
  ),
  totals as (
    select
      coalesce(sum(houses),0)::bigint as total_houses,
      coalesce(sum(assigned_houses),0)::bigint as assigned_houses,
      coalesce(sum(pinned_houses),0)::bigint as pinned_houses,
      coalesce(sum(field_confirmed),0)::bigint as field_confirmed,
      coalesce(sum(review_houses),0)::bigint as review_houses,
      coalesce(sum(outside_tambon),0)::bigint as outside_tambon,
      coalesce(sum(outside_community),0)::bigint as outside_community,
      coalesce(sum(missing_coordinates),0)::bigint as missing_coordinates,
      coalesce(sum(missing_house_id_11),0)::bigint as missing_house_id_11
    from stats
  )
  select jsonb_build_object(
    'version','2.0.57',
    'scope','admin_all',
    'dashboard',jsonb_build_object(
      'role','admin',
      'community',coalesce((select own_community from ctx),''),
      'moo',null,
      'total_houses',t.total_houses,
      'assigned_houses',t.assigned_houses,
      'pinned_houses',t.pinned_houses,
      'field_confirmed',t.field_confirmed,
      'review_houses',t.review_houses,
      'outside_tambon',t.outside_tambon,
      'outside_community',t.outside_community,
      'outside_any',t.outside_tambon+t.outside_community,
      'missing_coordinates',t.missing_coordinates,
      'missing_house_id_11',t.missing_house_id_11,
      'field_progress_pct',
        case when t.total_houses>0
          then round((t.field_confirmed::numeric*100.0)/t.total_houses,1)
          else 0 end
    ),
    'cards',coalesce((
      select jsonb_agg(jsonb_build_object(
        'community',s.community,'moo',s.moo,
        'houses',s.houses,'assigned_houses',s.assigned_houses,
        'pinned_houses',s.pinned_houses,'field_confirmed',s.field_confirmed,
        'review_houses',s.review_houses,'outside_tambon',s.outside_tambon,
        'outside_community',s.outside_community,'missing_coordinates',s.missing_coordinates,
        'volunteers',s.volunteers,'access_mode','manage',
        'is_assigned',btrim(s.community)=btrim(coalesce((select own_community from ctx),''))
      ) order by nullif(s.moo,'')::int nulls last,s.community)
      from stats s
    ),'[]'::jsonb),
    'cards_v1854',coalesce((
      select jsonb_agg(jsonb_build_object(
        'community',s.community,'moo',s.moo,
        'volunteers',s.volunteers,'houses',s.houses,
        'pinned_houses',s.pinned_houses,'review_houses',s.review_houses,
        'assigned_houses',s.assigned_houses,'outside_tambon',s.outside_tambon,
        'outside_community',s.outside_community_v1854,
        'missing_coordinates',s.missing_coordinates,
        'is_assigned',private.community_key(s.community)=private.community_key(coalesce((select own_community from ctx),'')),
        'access_mode','manage'
      ) order by nullif(s.moo,'')::int nulls last,s.community)
      from stats s
    ),'[]'::jsonb)
  )
  into v_result
  from totals t;

  return v_result;
end;
$$;

revoke all on function public.admin_community_fast_bundle_v2057() from public,anon;

grant execute on function public.admin_community_fast_bundle_v2057() to authenticated;

notify pgrst,'reload schema';

commit;
