-- =============================================================================
-- Migration: Security advisor fixes, round 2
--
-- The prior migration revoked EXECUTE from `anon` on
-- create_organization_with_owner()/accept_invitation(), but the advisor
-- still flagged them as anon-callable on re-check. Reason: Postgres
-- grants EXECUTE to PUBLIC by default on function creation, and every
-- role — including anon — implicitly includes PUBLIC. Revoking from
-- `anon` specifically does nothing while the broader PUBLIC grant still
-- stands. Revoking from PUBLIC directly is what actually closes it; the
-- explicit `grant execute ... to authenticated` from the original
-- migrations remains in effect and is unaffected by this.
-- =============================================================================

revoke execute on function create_organization_with_owner(text, text, text) from public;
revoke execute on function accept_invitation(text) from public;
