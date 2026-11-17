-- Disposable PostgreSQL/PostgREST fixture. Synthetic moo/community/volunteer labels only.
-- Mirrors product intent; real app derives roles from profiles, NOT these synthetic JWT claims.
CREATE TABLE public.phase4_moo_communities (
 moo integer NOT NULL, name text NOT NULL UNIQUE, PRIMARY KEY(moo,name)
);
INSERT INTO public.phase4_moo_communities(moo,name)
 SELECT moo,'moo-'||moo||'-community-'||part
 FROM generate_series(1,8) moo CROSS JOIN generate_series(1,2) part;
GRANT SELECT ON public.phase4_moo_communities TO authenticated,service_role;
CREATE TABLE public.phase4_moo_houses (
 id text PRIMARY KEY, moo integer NOT NULL CHECK (moo BETWEEN 1 AND 8),
 community text NOT NULL, volunteer_pid text, house_no text NOT NULL
);
ALTER TABLE public.phase4_moo_houses ENABLE ROW LEVEL SECURITY;
CREATE POLICY phase4_moo_house_select ON public.phase4_moo_houses
 FOR SELECT TO authenticated USING (
  COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'app_role'='admin'
  OR (
   COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'app_role'='staff'
   AND moo::text=COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'moo'
   AND EXISTS (
    SELECT 1 FROM public.phase4_moo_communities c
    WHERE c.name=COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'community'
      AND c.moo::text=COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'moo'
   )
  )
  OR (
   COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'app_role'='user'
   AND volunteer_pid IS NOT NULL
   AND volunteer_pid=COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'volunteer_pid'
  )
);
-- A staff member may update houses in OWN community only, never sibling community in same moo.
CREATE POLICY phase4_moo_house_staff_update ON public.phase4_moo_houses
 FOR UPDATE TO authenticated
 USING (
  COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'app_role'='staff'
  AND community=COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'community'
  AND moo::text=COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'moo'
 ) WITH CHECK (
  COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'app_role'='staff'
  AND community=COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'community'
  AND moo::text=COALESCE(current_setting('request.jwt.claims',true),'{}')::jsonb->>'moo'
);
GRANT SELECT,UPDATE ON public.phase4_moo_houses TO authenticated;
GRANT SELECT,UPDATE ON public.phase4_moo_houses TO service_role;
INSERT INTO public.phase4_moo_houses(id,moo,community,volunteer_pid,house_no)
 SELECT 'h-'||moo||'-'||part||'-'||h,moo,
        'moo-'||moo||'-community-'||part,
        CASE WHEN h=1 THEN 'vol-'||moo||'-'||part ELSE NULL END,
        'TEST-'||moo||'-'||part||'-'||h
 FROM generate_series(1,8) moo CROSS JOIN generate_series(1,2) part
 CROSS JOIN generate_series(1,2) h;
CREATE TABLE public.phase4_moo_members (
 id text PRIMARY KEY, house_id text NOT NULL REFERENCES public.phase4_moo_houses(id) ON DELETE RESTRICT,
 display_name text NOT NULL, stale_community text
);
ALTER TABLE public.phase4_moo_members ENABLE ROW LEVEL SECURITY;
-- The member must follow the referenced house's RLS, even if its stale community suggests otherwise.
CREATE POLICY phase4_moo_member_select ON public.phase4_moo_members
 FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.phase4_moo_houses h WHERE h.id=house_id)
);
GRANT SELECT ON public.phase4_moo_members TO authenticated,service_role;
INSERT INTO public.phase4_moo_members(id,house_id,display_name,stale_community)
 SELECT 'member-'||h.id||'-'||i,h.id,'SYNTHETIC ONLY',h.community
 FROM public.phase4_moo_houses h CROSS JOIN generate_series(1,2) i;
UPDATE public.phase4_moo_members
 SET stale_community='moo-1-community-1'
 WHERE id='member-h-2-1-1-1';
SELECT 'PASS: isolated 8-moo/16-community/32-house/64-member fixture only' AS result;
