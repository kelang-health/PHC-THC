
CREATE TABLE IF NOT EXISTS private.nightly_snapshot_outcomes_v2077 (
 day_bkk date PRIMARY KEY,
 status text NOT NULL CHECK(status IN ('success','failed','busy')),
 started_at timestamptz NOT NULL,
 finished_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 generation uuid,
 cache_rows bigint,
 error_message text,
 checked_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX IF NOT EXISTS nightly_snapshot_outcomes_checked_v2077 ON private.nightly_snapshot_outcomes_v2077(checked_at DESC);
REVOKE ALL ON private.nightly_snapshot_outcomes_v2077 FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE private.nightly_snapshot_outcomes_v2077 IS 'Durable daily result independent of the four-generation derived report cache; no patient data.';
