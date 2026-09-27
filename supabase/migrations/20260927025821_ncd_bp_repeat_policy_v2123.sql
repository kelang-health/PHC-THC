insert into public.app_settings(key,value)
values(
  'ncd_bp_repeat_v2123',
  jsonb_build_object(
    'version','2.0.123',
    'trigger','first SBP >=140 OR first DBP >=90',
    'normal_first_reading','no repeat UI and no repeat payload',
    'repeat_interval_guidance','at least 1 minute using same arm and position',
    'effective_value','rounded mean of first and repeat',
    'grade3_safety','any reading >=180 SBP or >=110 DBP remains urgent'
  )
)
on conflict(key) do update set value=excluded.value,updated_at=now();
