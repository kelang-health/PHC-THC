-- TEST ONLY: synthetic booking table on disposable PostgreSQL 17.
-- There is already a production cloud_event_bookings_v2085 table.
-- Do NOT migrate this fixture to production or enable paused Cloud booking.
CREATE TABLE public.phase4_booking_fixture (
  id text PRIMARY KEY,
  slot_id text NOT NULL,
  subject_ref text NOT NULL,
  owner_id text NOT NULL,
  community_id text NOT NULL,
  booking_status text NOT NULL DEFAULT 'reserved'
    CHECK (booking_status IN ('reserved','cancelled')),
  UNIQUE (slot_id, subject_ref)
);
ALTER TABLE public.phase4_booking_fixture ENABLE ROW LEVEL SECURITY;
CREATE POLICY fixture_booking_scoped_read ON public.phase4_booking_fixture
  FOR SELECT TO authenticated
  USING (
    COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'app_role','')='admin'
    OR (
      COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'app_role','')='staff'
      AND community_id=COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'community_id','')
    )
    OR (
      COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'app_role','')='user'
      AND owner_id=COALESCE(NULLIF(current_setting('request.jwt.claims',true),'')::jsonb->>'sub','')
    )
  );
GRANT SELECT ON public.phase4_booking_fixture TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.phase4_booking_fixture TO service_role;
-- Only the fixture/backend may create bookings while the real Cloud feature is paused.
INSERT INTO public.phase4_booking_fixture
 (id,slot_id,subject_ref,owner_id,community_id)
VALUES
 ('booking-a','slot-a','synthetic-person-a','test-user-a','community-a'),
 ('booking-b','slot-b','synthetic-person-b','test-user-b','community-a'),
 ('booking-c','slot-c','synthetic-person-c','test-user-c','community-b');

DO $assert$ BEGIN
 IF has_table_privilege('anon','public.phase4_booking_fixture','SELECT')
 OR has_table_privilege('authenticated','public.phase4_booking_fixture','INSERT')
 OR has_table_privilege('authenticated','public.phase4_booking_fixture','UPDATE')
 OR has_table_privilege('authenticated','public.phase4_booking_fixture','DELETE') THEN
   RAISE EXCEPTION 'Fixture leaked anonymous booking access or enabled direct client booking writes';
 END IF;
 BEGIN
  INSERT INTO public.phase4_booking_fixture
   (id,slot_id,subject_ref,owner_id,community_id)
  VALUES ('booking-duplicate','slot-a','synthetic-person-a','test-user-a','community-a');
  RAISE EXCEPTION 'Duplicate slot/person booking was not rejected';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
END $assert$;
SELECT 'PASS: synthetic booking table, scoped RLS, explicit grants and duplicate rejection' AS result;
