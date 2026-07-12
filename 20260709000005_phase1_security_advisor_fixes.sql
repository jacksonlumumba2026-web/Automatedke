-- =============================================================================
-- Migration: Security advisor fixes
--
-- Found by running `supabase get_advisors` (security) against a real
-- deployed instance for the first time in Milestone 3 — static code
-- review couldn't catch these:
--
-- 1. set_updated_at() and slugify() were missing `set search_path`,
--    unlike every other function in the schema. A mutable search_path
--    is a privilege-escalation vector (a malicious search_path could
--    redirect an unqualified function/table reference elsewhere).
--
-- 2. Postgres grants EXECUTE to PUBLIC by default on function creation.
--    user_org_ids(), user_role_in_org(), handle_new_user(), and
--    log_audit_event() were only ever meant to be called internally (by
--    RLS policies and triggers) but were consequently callable directly
--    via /rest/v1/rpc/... by anon and authenticated clients. Revoking
--    that default, explicit-grant-only from here on.
--
-- create_organization_with_owner() and accept_invitation() ARE meant to
-- be called via RPC by authenticated users — that grant already exists
-- and is intentional. This migration additionally revokes anon access to
-- them for defense in depth: both already reject unauthenticated callers
-- internally (auth.uid() is not null check), but there's no reason to
-- leave the anon role able to reach the endpoint at all.
-- =============================================================================

-- --- Fix 1: missing search_path ---------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function slugify(p_input text)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(both '-' from regexp_replace(lower(trim(p_input)), '[^a-z0-9]+', '-', 'g'));
$$;

-- --- Fix 2: lock down internal-only helper functions ------------------------
revoke execute on function user_org_ids() from public, anon, authenticated;
revoke execute on function user_role_in_org(uuid) from public, anon, authenticated;
revoke execute on function handle_new_user() from public, anon, authenticated;
revoke execute on function log_audit_event() from public, anon, authenticated;

-- These are still callable by the functions/triggers that use them
-- internally (RLS policies, the auth.users trigger) since Postgres
-- function-body calls execute as the defining/session role's
-- privileges for SECURITY DEFINER functions, not through the REST API
-- grant system — revoking PUBLIC/anon/authenticated EXECUTE only closes
-- the direct /rest/v1/rpc/... path, not internal usage.

-- --- Defense in depth: anon should never reach the two legitimate RPCs -----
revoke execute on function create_organization_with_owner(text, text, text) from anon;
revoke execute on function accept_invitation(text) from anon;
