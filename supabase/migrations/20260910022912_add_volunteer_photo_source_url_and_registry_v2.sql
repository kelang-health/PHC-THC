alter table public.volunteer_profile_media add column if not exists photo_source_url text;

create or replace function public.volunteer_registry_profiles_v2()
returns table(
  source_pid bigint,
  display_name text,
  community text,
  moo text,
  anchor_status text,
  house_count bigint,
  pinned_count bigint,
  field_confirmed_count bigint,
  review_count bigint,
  outside_tambon_count bigint,
  outside_community_count bigint,
  missing_count bigint,
  issue_house_count bigint,
  ready_pct numeric,
  status_code text,
  status_label text,
  photo_object_path text,
  photo_source_url text,
  photo_alt text
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  p public.profiles%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into p from public.profiles where user_id=auth.uid() and active=true;
  if not found then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  return query
  with agg as (
    select
      v.source_pid,
      v.display_name,
      v.community,
      v.moo,
      v.anchor_status,
      count(h.id)::bigint as house_count,
      count(h.id) filter (where h.latitude is not null and h.longitude is not null)::bigint as pinned_count,
      count(h.id) filter (where h.coordinate_status like 'resolved_%')::bigint as field_confirmed_count,
      count(h.id) filter (where h.review_required=true)::bigint as review_count,
      count(h.id) filter (where h.inside_tambon=false)::bigint as outside_tambon_count,
      count(h.id) filter (where h.inside_community=false and coalesce(h.inside_tambon,true)=true)::bigint as outside_community_count,
      count(h.id) filter (where h.latitude is null or h.longitude is null)::bigint as missing_count,
      count(h.id) filter (
        where h.latitude is null or h.longitude is null
           or h.review_required=true
           or h.inside_tambon=false
           or (h.inside_community=false and coalesce(h.inside_tambon,true)=true)
      )::bigint as issue_house_count
    from public.volunteers v
    left join public.houses h on h.volunteer_pid=v.source_pid
    where v.active=true
      and (
        p.role='admin'
        or (p.role='staff' and btrim(coalesce(v.community,''))=btrim(coalesce(p.community,'')))
        or (p.role='user' and v.source_pid=p.volunteer_pid)
      )
    group by v.source_pid,v.display_name,v.community,v.moo,v.anchor_status
  ), scored as (
    select a.*,
      case when a.house_count=0 then 0::numeric
           else round(((a.house_count-a.issue_house_count)::numeric*100)/a.house_count,1)
      end as ready_pct,
      case when a.house_count=0 then 'yellow'
           when a.outside_tambon_count>0 or a.issue_house_count::numeric/nullif(a.house_count,0)>=0.30 then 'pink'
           when a.issue_house_count::numeric/nullif(a.house_count,0)>=0.15 then 'orange'
           when a.issue_house_count>0 or a.pinned_count::numeric/nullif(a.house_count,0)<0.90 then 'yellow'
           else 'green'
      end as status_code
    from agg a
  )
  select
    s.source_pid,s.display_name,s.community,s.moo,s.anchor_status,
    s.house_count,s.pinned_count,s.field_confirmed_count,s.review_count,
    s.outside_tambon_count,s.outside_community_count,s.missing_count,
    s.issue_house_count,s.ready_pct,s.status_code,
    case s.status_code
      when 'green' then 'เธเธฃเนเธญเธกเนเธเนเธเธฒเธ'
      when 'yellow' then 'เธ•เธดเธ”เธ•เธฒเธก'
      when 'orange' then 'เธเธงเธฃเธ•เธฃเธงเธ'
      else 'เน€เธฃเนเธเนเธเนเธเนเธญเธกเธนเธฅ'
    end,
    m.photo_object_path,m.photo_source_url,m.photo_alt
  from scored s
  left join public.volunteer_profile_media m on m.source_pid=s.source_pid
  order by s.display_name;
end;
$$;

revoke all on function public.volunteer_registry_profiles_v2() from public, anon;
grant execute on function public.volunteer_registry_profiles_v2() to authenticated;
