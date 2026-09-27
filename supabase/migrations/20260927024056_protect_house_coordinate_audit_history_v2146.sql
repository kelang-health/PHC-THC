
alter table public.house_coordinate_audit
  drop constraint if exists house_coordinate_audit_house_id_fkey;

alter table public.house_coordinate_audit
  add constraint house_coordinate_audit_house_id_fkey
  foreign key (house_id) references public.houses(id) on delete restrict;
