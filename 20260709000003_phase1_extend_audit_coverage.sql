-- =============================================================================
-- Migration: Extend audit logging coverage
--
-- Gap found during Milestone 3 review: Security Architecture (Blueprint
-- Section 11) requires "immutable audit trail for all financial, payroll,
-- and permission-change actions," but only organizations,
-- organization_members, and role_permissions had audit triggers attached.
--
-- invitations grants org access (a permission-change-adjacent action —
-- who was invited, as what role, by whom, and whether it was later
-- revoked) and subscriptions is financial data (plan changes). Both
-- belong in the audit trail. Reuses the existing log_audit_event()
-- function from the foundation migration — no new logic needed, just
-- attaching triggers to two more tables.
-- =============================================================================

create trigger trg_audit_invitations
  after insert or update or delete on invitations
  for each row execute function log_audit_event();

create trigger trg_audit_subscriptions
  after insert or update or delete on subscriptions
  for each row execute function log_audit_event();
