
create or replace function private.preserve_cloud_house_coordinates_from_service_sync_v2161()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_request_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true),''),
    coalesce(auth.jwt()->>'role','')
  );
begin
  -- Cloud is the coordinate authority. Local/JHCIS service-role sync may
  -- reconcile registry fields, ownership and verification, but must never
  -- change the coordinate state of an existing Cloud house.
  if current_user = 'service_role' or v_request_role = 'service_role' then
    new.latitude := old.latitude;
    new.longitude := old.longitude;
    new.geom := old.geom;
    new.coordinate_source := old.coordinate_source;
    new.coordinate_status := old.coordinate_status;
    new.coordinate_distance_m := old.coordinate_distance_m;
    new.inside_tambon := old.inside_tambon;
    new.inside_community := old.inside_community;
  end if;
  return new;
end;
$function$;

revoke all on function private.preserve_cloud_house_coordinates_from_service_sync_v2161() from public, anon, authenticated;

drop trigger if exists trg_00_preserve_cloud_house_coordinates_service_v2161 on public.houses;
create trigger trg_00_preserve_cloud_house_coordinates_service_v2161
before update on public.houses
for each row execute function private.preserve_cloud_house_coordinates_from_service_sync_v2161();

-- Restore three field coordinates that were preserved in Cloud audit evidence
-- but were cleared by the previous Local house reconciliation.
with restore(id,latitude,longitude,coordinate_source,coordinate_status) as (
  values
    ('be5d8908-d28a-458e-a50c-c153ddadd39d'::uuid,18.2306557016794::double precision,99.5635986328125::double precision,'gps'::text,'resolved_by_community'::text),
    ('89f617b1-f784-4f74-a8f1-ef553b3a8570'::uuid,18.2546320791594::double precision,99.4961303472519::double precision,'map'::text,'resolved_by_community'::text),
    ('a340b8c9-c912-4c9b-a824-1eb60c63d4d1'::uuid,18.2447313518734::double precision,99.5106867531782::double precision,'gps'::text,'resolved_by_community'::text)
),
checked as (
  select r.*,h.community,public.check_house_location_v1858(r.latitude,r.longitude,h.community) as loc
  from restore r
  join public.houses h on h.id=r.id
  where h.superseded_by is null
)
update public.houses h
set latitude=c.latitude,
    longitude=c.longitude,
    coordinate_source=c.coordinate_source,
    coordinate_status=c.coordinate_status,
    coordinate_distance_m=null,
    inside_tambon=coalesce((c.loc->>'inside_tambon')::boolean,false),
    inside_community=coalesce((c.loc->>'inside_community')::boolean,false),
    updated_at=clock_timestamp()
from checked c
where h.id=c.id
  and coalesce((c.loc->>'allowed')::boolean,false)=true;

insert into public.app_settings(key,value)
values(
  'cloud_coordinate_authority_v2161',
  jsonb_build_object(
    'enabled',true,
    'policy','Cloud field coordinates are authoritative; Local/JHCIS service-role updates cannot modify coordinates of existing Cloud houses',
    'protected_fields',jsonb_build_array(
      'latitude','longitude','geom','coordinate_source','coordinate_status',
      'coordinate_distance_m','inside_tambon','inside_community'
    ),
    'cloud_field_rpc_allowed',true,
    'jhcis_coordinate_writeback','explicit admin only; Cloud to JHCIS xgis/ygis',
    'restored_from_audit_houses',3,
    'version','2.1.61',
    'updated_at',now()
  )
)
on conflict(key) do update set value=excluded.value,updated_at=now();
