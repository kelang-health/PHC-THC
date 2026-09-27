-- Cloud v2.0.57 corrective performance + parity:
-- one normalized join, both legacy exact-name and v1854 normalized contracts.
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
  communities as materialized (
    select
      c.name::text as community,
      c.moo::text as moo,
      btrim(c.name)::text as community_trim,
      private.community_key(c.name)::text as community_key
    from public.communities c
    where c.active=true
  ),
  houses as materialized (
    select
      h.id,h.volunteer_pid,h.latitude,h.longitude,h.coordinate_status,
      h.review_required,h.inside_tambon,h.inside_community,h.house_id_11,
      btrim(h.community)::text as community_trim,
      private.community_key(h.community)::text as community_key
    from public.houses h
    where h.superseded_by is null
      and h.verification_status='verified_jhcis'
  ),
  joined as materialized (
    select
      c.community,c.moo,c.community_trim,c.community_key,
      h.*,
      (h.id is not null and h.community_trim=c.community_trim) as exact_match
    from communities c
    left join houses h on h.community_key=c.community_key
  ),
  stats as materialized (
    select
      community,moo,

      count(id) filter (where exact_match)::bigint as houses,
      count(id) filter (where exact_match and volunteer_pid is not null)::bigint as assigned_houses,
      count(id) filter (where exact_match and latitude is not null and longitude is not null)::bigint as pinned_houses,
      count(id) filter (where exact_match and coordinate_status like 'resolved_%')::bigint as field_confirmed,
      count(id) filter (where exact_match and review_required=true)::bigint as review_houses,
      count(id) filter (where exact_match and inside_tambon=false)::bigint as outside_tambon,
      count(id) filter (
        where exact_match and inside_community=false
          and inside_tambon is distinct from false
      )::bigint as outside_community,
      count(id) filter (where exact_match and (latitude is null or longitude is null))::bigint as missing_coordinates,
      count(id) filter (
        where exact_match and (house_id_11 is null or house_id_11 !~ '^[0-9]{11}$')
      )::bigint as missing_house_id_11,
      count(distinct volunteer_pid) filter (where exact_match and volunteer_pid is not null)::bigint as volunteers,

      count(id)::bigint as v1854_houses,
      count(id) filter (where volunteer_pid is not null)::bigint as v1854_assigned_houses,
      count(id) filter (where latitude is not null and longitude is not null)::bigint as v1854_pinned_houses,
      count(id) filter (where review_required=true)::bigint as v1854_review_houses,
      count(id) filter (where inside_tambon=false)::bigint as v1854_outside_tambon,
      count(id) filter (where inside_community=false)::bigint as v1854_outside_community,
      count(id) filter (where latitude is null or longitude is null)::bigint as v1854_missing_coordinates,
      count(distinct volunteer_pid) filter (where volunteer_pid is not null)::bigint as v1854_volunteers
    from joined
    group by community,moo
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
        'volunteers',s.v1854_volunteers,'houses',s.v1854_houses,
        'pinned_houses',s.v1854_pinned_houses,'review_houses',s.v1854_review_houses,
        'assigned_houses',s.v1854_assigned_houses,
        'outside_tambon',s.v1854_outside_tambon,
        'outside_community',s.v1854_outside_community,
        'missing_coordinates',s.v1854_missing_coordinates,
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
