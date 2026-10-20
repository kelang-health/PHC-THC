-- Preserve the existing caller RLS boundary when replacing the worklist view.
alter view public.health_person_worklist set (security_invoker=true);
