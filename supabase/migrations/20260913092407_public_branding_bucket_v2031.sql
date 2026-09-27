-- Cloud v2.0.31: public system branding asset written only by Local service role.
begin;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'osm-public-assets',
  'osm-public-assets',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp','image/svg+xml']::text[]
)
on conflict(id) do update set
  public=excluded.public,
  file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

-- No storage.objects write policy is added. Browser roles cannot upload/update/delete;
-- Local uses the existing server-only service role during an explicit Cloud sync.
commit;
