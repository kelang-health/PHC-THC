
ALTER TABLE private.nightly_snapshot_outcomes_v2077 DROP CONSTRAINT nightly_snapshot_outcomes_v2077_status_check;
ALTER TABLE private.nightly_snapshot_outcomes_v2077
 ADD CONSTRAINT nightly_snapshot_outcomes_v2077_status_check
 CHECK (status IN ('success','failed','busy','unverified'));
ALTER TABLE private.nightly_snapshot_watch_v2068 DROP CONSTRAINT nightly_snapshot_watch_v2068_status_check;
ALTER TABLE private.nightly_snapshot_watch_v2068
 ADD CONSTRAINT nightly_snapshot_watch_v2068_status_check
 CHECK (status IN ('alert','ok','unverified'));
