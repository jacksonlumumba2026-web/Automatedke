-- =============================================================================
-- Migration: CRITICAL FIX — log_audit_event() fails on every write to
-- organizations
--
-- log_audit_event() was written generically, assuming every audited
-- table has an organization_id column to derive the audit log's scope
-- from. That's true for organization_members, role_permissions,
-- invitations, and subscriptions — but NOT for organizations itself,
-- whose identity column is `id`. NEW.organization_id / OLD.organization_id
-- simply doesn't exist on that table's row type, so
-- trg_audit_organizations has failed on every INSERT/UPDATE/DELETE to
-- organizations since the very first migration — meaning every
-- organization creation (via create_organization_with_owner, which
-- inserts into organizations) and every organization edit (Settings ->
-- Organization) would have failed in production.
--
-- Caught by finally executing a real end-to-end organization-creation
-- call against the live database, immediately after fixing the
-- ambiguous-slug bug in the prior migration.
--
-- Fix: special-case organizations, using NEW.id/OLD.id (its own primary
-- key) as the audit scope instead of a nonexistent organization_id field.
-- =============================================================================

create or replace function log_audit_event()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if TG_TABLE_NAME = 'organizations' then
    -- The organizations table's own identity column IS the org id —
    -- there is no separate organization_id field on this one table.
    v_org_id := case when TG_OP = 'DELETE' then old.id else new.id end;
  else
    v_org_id := coalesce(
      (case when TG_OP = 'DELETE' then old.organization_id else new.organization_id end),
      null
    );
  end if;

  insert into audit_logs (organization_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (
    v_org_id,
    auth.uid(),
    lower(TG_OP),
    TG_TABLE_NAME,
    case when TG_OP = 'DELETE' then old.id else new.id end,
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('UPDATE','INSERT') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;
