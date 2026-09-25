-- ONLY for disposable PostgreSQL 17/PostgREST CI fixture; NOT a production migration.
-- Fake community and volunteer identifiers; no CID/PID from real JHCIS.
CREATE TABLE public.phase4_card_houses(
 id text PRIMARY KEY,house_no text NOT NULL,community text NOT NULL,volunteer_pid text NOT NULL
);
ALTER TABLE public.phase4_card_houses ENABLE ROW LEVEL SECURITY;
CREATE POLICY synthetic_house_card_scope ON public.phase4_card_houses
 FOR SELECT TO authenticated USING (
  COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'app_role'='admin'
  OR (COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'app_role'='staff'
       AND community=COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'community')
  OR (COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'app_role'='user'
       AND volunteer_pid=COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'volunteer_pid')
 );
GRANT SELECT ON public.phase4_card_houses TO authenticated,service_role;
INSERT INTO public.phase4_card_houses(id,house_no,community,volunteer_pid)
 SELECT 'house-'||i::text,'TEST-'||i::text,
        'community-'||((i-1)%16)::text,'vol-'||((i-1)%8)::text
 FROM generate_series(1,48) i;

CREATE TABLE public.phase4_card_people(
 id text PRIMARY KEY,house_id text NOT NULL REFERENCES public.phase4_card_houses(id) ON DELETE RESTRICT,
 source_pid bigint NOT NULL,community text NOT NULL,volunteer_pid text NOT NULL,
 display_name text NOT NULL,active boolean NOT NULL DEFAULT true
);
ALTER TABLE public.phase4_card_people ENABLE ROW LEVEL SECURITY;
CREATE POLICY synthetic_member_card_scope ON public.phase4_card_people
 FOR SELECT TO authenticated USING (
  COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'app_role'='admin'
  OR (COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'app_role'='staff'
       AND community=COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'community')
  OR (COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'app_role'='user'
       AND volunteer_pid=COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'volunteer_pid')
 );
GRANT SELECT ON public.phase4_card_people TO authenticated,service_role;
INSERT INTO public.phase4_card_people(id,house_id,source_pid,community,volunteer_pid,display_name)
 SELECT 'member-'||h.id||'-'||n::text,h.id,
        (ROW_NUMBER() OVER(ORDER BY h.id,n))::bigint,
        h.community,h.volunteer_pid,'SYNTHETIC MEMBER'
 FROM public.phase4_card_houses h CROSS JOIN generate_series(1,3) n;
SELECT 'PASS: disposable 48-house/144-member scoped Data API fixture created' AS result;
