-- OSM-PHC Cloud v2.0.9
-- Service-role only export for secure Cloud -> Local LINE linkage replication.
-- Raw LINE user ID is decrypted only inside this RPC over the authenticated server-to-server channel.
-- Browser/authenticated users cannot execute this function.

begin;

create or replace function public.local_line_link_export_v209()
returns table(
  app_user_id uuid,
  display_name text,
  role text,
  community text,
  volunteer_pid bigint,
  profile_active boolean,
  line_connected boolean,
  line_user_hash text,
  line_user_id text,
  linked_at timestamptz,
  line_updated_at timestamptz
)
language plpgsql stable security definer
set search_path=''
as $$
begin
  if auth.role()<>'service_role' then raise exception 'SERVICE_ROLE_REQUIRED'; end if;
  return query
  select p.user_id,p.display_name,p.role,p.community,p.volunteer_pid,p.active,
         coalesce(l.active,false),coalesce(l.line_user_hash,''),
         case when l.line_user_cipher is null then '' else private.decrypt_text_v190(l.line_user_cipher) end,
         l.linked_at,l.updated_at
  from public.profiles p
  left join public.user_line_links l on l.app_user_id=p.user_id
  where p.role in ('admin','staff','user')
  order by p.display_name,p.user_id;
end;
$$;

revoke all on function public.local_line_link_export_v209() from public,anon,authenticated;

grant execute on function public.local_line_link_export_v209() to service_role;

insert into public.app_settings(key,value)
values('line_link_local_export_v209',jsonb_build_object(
  'version','2.0.9',
  'source_of_truth','public.user_line_links',
  'consumer','OSM-PHC Local server only',
  'service_role_only',true,
  'raw_line_user_id_browser_exposed',false,
  'local_storage','encrypted with Local Fernet key',
  'purpose','LINE linkage status and future server-side messaging integration'
))
on conflict(key) do update set value=excluded.value,updated_at=now();

commit;
