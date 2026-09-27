-- Cloud v2.0.55 Phase 2H: User/Staff fast path only.
-- Login/PIN/LINE Login/OAuth/Auth flow intentionally unchanged.
begin;

create or replace function public.staff_community_fast_bundle_v2055()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
with ctx as (
  select
    private.current_role() as role,
    private.current_community() as own_community,
    private.current_moo() as own_moo
),
allowed as materialized (
  select
    c.name as community,
    c.moo,
    private.community_key(c.name)=private.community_key(ctx.own_community) as is_assigned
  from public.communities c, ctx
  where c.active=true
    and ctx.role='staff'
    and coalesce(btrim(ctx.own_moo),'')<>''
    and btrim(c.moo)=btrim(ctx.own_moo)
),
stats as materialized (
  select
    a.community,
    a.moo,
    a.is_assigned,
    count(distinct h.volunteer_pid) filter (where h.volunteer_pid is not null)::bigint as volunteers,
    count(h.id)::bigint as houses,
    count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint as pinned_houses,
    count(h.id) filter (where h.review_required=true)::bigint as review_houses,
    count(h.id) filter (where h.volunteer_pid is not null)::bigint as assigned_houses,
    count(h.id) filter (where h.inside_tambon=false)::bigint as outside_tambon,
    count(h.id) filter (where h.inside_community=false)::bigint as outside_community,
    count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint as missing_coordinates,
    count(h.id) filter (where h.coordinate_status like 'resolved_%')::bigint as field_confirmed
  from allowed a
  left join public.houses h
    on private.community_key(h.community)=private.community_key(a.community)
   and h.superseded_by is null
   and h.verification_status='verified_jhcis'
  group by a.community,a.moo,a.is_assigned
),
cards as (
  select
    s.community,s.moo,s.volunteers,s.houses,s.pinned_houses,s.review_houses,
    s.assigned_houses,s.outside_tambon,s.outside_community,s.missing_coordinates,
    s.is_assigned,
    case when s.is_assigned then 'manage' else 'view' end::text as access_mode
  from stats s
  order by s.is_assigned desc,s.moo,s.community
),
own as (
  select * from stats where is_assigned limit 1
)
select jsonb_build_object(
  'version','2.0.55',
  'scope','staff_same_moo',
  'dashboard',jsonb_build_object(
    'role','staff',
    'scope_community',coalesce((select own_community from ctx),''),
    'total_houses',coalesce((select houses from own),0),
    'pinned_houses',coalesce((select pinned_houses from own),0),
    'missing_coordinates',coalesce((select missing_coordinates from own),0),
    'review_houses',coalesce((select review_houses from own),0),
    'field_confirmed',coalesce((select field_confirmed from own),0),
    'outside_tambon',coalesce((select outside_tambon from own),0),
    'outside_community',coalesce((select outside_community from own),0)
  ),
  'cards',coalesce((select jsonb_agg(to_jsonb(c) order by c.is_assigned desc,c.moo,c.community) from cards c),'[]'::jsonb)
)
from ctx
where role='staff';
$$;

revoke all on function public.staff_community_fast_bundle_v2055() from public,anon;

grant execute on function public.staff_community_fast_bundle_v2055() to authenticated;

insert into public.app_settings(key,value)
values('phase2h_user_staff_fastpath_v2055',jsonb_build_object(
  'version','2.0.55',
  'scope',jsonb_build_array('user','staff'),
  'staff_community_bundle','single_rpc_single_house_aggregation',
  'house_primary_first','my_household_cards_v1860',
  'pending_house_loading','idle_after_primary',
  'house_quota_loading','on_add_house_action',
  'stable_cache_seconds',300,
  'auth_login_unchanged',true,
  'line_login_unchanged',true,
  'jhcis_write_back',false
))
on conflict(key) do update set value=excluded.value,updated_at=now();

notify pgrst,'reload schema';

commit;
