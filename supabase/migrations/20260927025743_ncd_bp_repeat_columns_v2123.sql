alter table public.health_ncd_screenings
  add column if not exists sbp_first integer,
  add column if not exists dbp_first integer,
  add column if not exists sbp_repeat integer,
  add column if not exists dbp_repeat integer,
  add column if not exists bp_measurement_count smallint not null default 1;

update public.health_ncd_screenings
set sbp_first=coalesce(sbp_first,sbp),
    dbp_first=coalesce(dbp_first,dbp),
    bp_measurement_count=case when sbp_repeat is not null and dbp_repeat is not null then 2 else 1 end
where sbp_first is null or dbp_first is null;

alter table public.health_ncd_screenings
  add constraint health_ncd_screenings_bp_repeat_pair_v2123
    check ((sbp_repeat is null and dbp_repeat is null)
        or (sbp_repeat is not null and dbp_repeat is not null));

alter table public.health_ncd_screenings
  add constraint health_ncd_screenings_bp_repeat_range_v2123
    check ((sbp_repeat is null and dbp_repeat is null)
        or (sbp_repeat between 70 and 260 and dbp_repeat between 40 and 180 and sbp_repeat>dbp_repeat));
