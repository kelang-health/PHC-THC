insert into public.app_settings(key,value,updated_at)
values ('community_gis_policy',jsonb_build_object('version','1.8.18','map_engine','leaflet_1_9_4','house_search',true,'house_selection',true,'gps_capture',true,'map_tap_coordinate',true,'draggable_draft_pin',true,'double_confirm_save',true,'elderly_friendly_controls',true,'minimum_touch_target_px',60,'audit_coordinates',true),now())
on conflict (key) do update set value=excluded.value,updated_at=now();
