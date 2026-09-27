CREATE TABLE IF NOT EXISTS private.hcv_demo_bookings_v2094(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 event_id uuid NOT NULL REFERENCES public.cloud_announcements_v2083(id) ON DELETE RESTRICT,
 source_pcucode text NOT NULL,
 source_pid bigint NOT NULL,
 booked_by uuid NOT NULL,
 slot_key text NOT NULL CHECK(slot_key IN ('A','B')),
 hcv_selected boolean NOT NULL DEFAULT false,
 hbsag_selected boolean NOT NULL DEFAULT false,
 status text NOT NULL DEFAULT 'booked' CHECK(status IN ('booked','cancelled')),
 verification_status text NOT NULL DEFAULT 'pending_review' CHECK(verification_status IN ('pending_review','appointment_confirmed','needs_follow_up','ineligible')),
 hcv_performed boolean NOT NULL DEFAULT false,
 hbsag_performed boolean NOT NULL DEFAULT false,
 reviewed_by text,
 reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT hcv_demo_one_test_chk CHECK(hcv_selected OR hbsag_selected),
 CONSTRAINT hcv_demo_performed_selected_chk CHECK((NOT hcv_performed OR hcv_selected) AND (NOT hbsag_performed OR hbsag_selected)),
 CONSTRAINT hcv_demo_confirmed_service_chk CHECK((NOT hcv_performed AND NOT hbsag_performed) OR verification_status='appointment_confirmed')
);
CREATE UNIQUE INDEX IF NOT EXISTS hcv_demo_active_person_uq_v2094
 ON private.hcv_demo_bookings_v2094(event_id,source_pcucode,source_pid) WHERE status='booked';
CREATE INDEX IF NOT EXISTS hcv_demo_event_slot_status_idx_v2094
 ON private.hcv_demo_bookings_v2094(event_id,slot_key,status);
CREATE TABLE IF NOT EXISTS private.hcv_demo_review_audit_v2094(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 event_id uuid NOT NULL REFERENCES public.cloud_announcements_v2083(id) ON DELETE RESTRICT,
 booking_id uuid NOT NULL REFERENCES private.hcv_demo_bookings_v2094(id) ON DELETE CASCADE,
 actor text NOT NULL,
 before_status text NOT NULL,
 after_status text NOT NULL,
 before_hcv_performed boolean NOT NULL,
 after_hcv_performed boolean NOT NULL,
 before_hbsag_performed boolean NOT NULL,
 after_hbsag_performed boolean NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.hcv_demo_bookings_v2094 ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.hcv_demo_review_audit_v2094 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.hcv_demo_bookings_v2094 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON private.hcv_demo_review_audit_v2094 FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON private.hcv_demo_bookings_v2094 TO service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON private.hcv_demo_review_audit_v2094 TO service_role;
GRANT USAGE,SELECT ON SEQUENCE private.hcv_demo_review_audit_v2094_id_seq TO service_role;
COMMENT ON TABLE private.hcv_demo_bookings_v2094 IS 'ISOLATED TEST ONLY: real assigned household identifiers, no patient contact or clinical results, resettable independently of production bookings/JHCIS';
