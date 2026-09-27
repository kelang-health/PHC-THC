begin;
set local lock_timeout='5s';
alter table public.houses drop constraint houses_verification_status_v2050;
alter table public.houses add constraint houses_verification_status_v2123
check (verification_status = any (array[
 'verified_jhcis','pending_jhcis_create','pending_jhcis_update',
 'review_required','superseded','rejected','removed_from_jhcis'
]));
commit;
