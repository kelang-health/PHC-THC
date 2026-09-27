create table if not exists public.volunteer_profile_media (
  source_pid bigint primary key,
  photo_object_path text,
  photo_alt text,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

alter table public.volunteer_profile_media enable row level security;
revoke all on table public.volunteer_profile_media from anon, authenticated;

drop policy if exists volunteer_profile_media_deny_clients on public.volunteer_profile_media;
create policy volunteer_profile_media_deny_clients
on public.volunteer_profile_media
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('volunteer-profiles','volunteer-profiles',false,2097152,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

create or replace function private.can_view_volunteer_photo(p_source_pid bigint)
returns boolean
language plpgsql
stable
security definer
set search_path = public, private
as $$
declare
  p public.profiles%rowtype;
begin
  if auth.uid() is null then return false; end if;
  select * into p from public.profiles where user_id=auth.uid() and active=true;
  if not found then return false; end if;
  if p.role='admin' then return true; end if;
  if p.role='user' then return p.volunteer_pid=p_source_pid; end if;
  if p.role='staff' then
    return exists(
      select 1 from public.volunteers v
      where v.source_pid=p_source_pid
        and v.active=true
        and btrim(coalesce(v.community,''))=btrim(coalesce(p.community,''))
    );
  end if;
  return false;
end;
$$;

create or replace function private.can_manage_volunteer_photo()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists(
    select 1 from public.profiles p
    where p.user_id=auth.uid() and p.active=true and p.role='admin'
  );
$$;

revoke all on function private.can_view_volunteer_photo(bigint) from public;
revoke all on function private.can_manage_volunteer_photo() from public;
grant usage on schema private to authenticated;
grant execute on function private.can_view_volunteer_photo(bigint) to authenticated;
grant execute on function private.can_manage_volunteer_photo() to authenticated;

drop policy if exists volunteer_profiles_read_scoped on storage.objects;
create policy volunteer_profiles_read_scoped
on storage.objects
for select
to authenticated
using (
  bucket_id='volunteer-profiles'
  and split_part(name,'/',1) ~ '^[0-9]+$'
  and private.can_view_volunteer_photo(split_part(name,'/',1)::bigint)
);

drop policy if exists volunteer_profiles_admin_insert on storage.objects;
create policy volunteer_profiles_admin_insert
on storage.objects
for insert
to authenticated
with check (bucket_id='volunteer-profiles' and private.can_manage_volunteer_photo());

drop policy if exists volunteer_profiles_admin_update on storage.objects;
create policy volunteer_profiles_admin_update
on storage.objects
for update
to authenticated
using (bucket_id='volunteer-profiles' and private.can_manage_volunteer_photo())
with check (bucket_id='volunteer-profiles' and private.can_manage_volunteer_photo());

drop policy if exists volunteer_profiles_admin_delete on storage.objects;
create policy volunteer_profiles_admin_delete
on storage.objects
for delete
to authenticated
using (bucket_id='volunteer-profiles' and private.can_manage_volunteer_photo());

create or replace function public.volunteer_registry_profiles()
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
    m.photo_object_path,m.photo_alt
  from scored s
  left join public.volunteer_profile_media m on m.source_pid=s.source_pid
  order by s.display_name;
end;
$$;

revoke all on function public.volunteer_registry_profiles() from public, anon;
grant execute on function public.volunteer_registry_profiles() to authenticated;
