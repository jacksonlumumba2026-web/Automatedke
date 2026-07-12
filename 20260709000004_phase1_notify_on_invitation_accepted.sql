-- =============================================================================
-- Migration: Notify the inviter when their invitation is accepted
--
-- Gap found during Milestone 3 review: the notifications table and the
-- Topbar's notification bell both exist, but nothing anywhere ever
-- inserted a row into notifications — the "Notifications foundation"
-- roadmap item (Phase1_Architecture.md Step 8) was a shell with no real
-- event feeding it. This is the first real notification-generating
-- event: the person who sent an invitation is notified when it's
-- accepted, so team growth is visible without requiring someone to
-- manually check the Team settings tab.
--
-- Uses CREATE OR REPLACE on the existing accept_invitation function
-- (defined in 20260709000002) rather than editing that migration file —
-- consistent with the append-only discipline: function bodies are
-- versioned forward, not rewritten in place, once a migration exists.
-- =============================================================================

create or replace function accept_invitation(p_token text)
returns table (organization_id uuid, organization_slug text, role org_role)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_user_email text;
  v_user_name text;
  v_invitation invitations%rowtype;
  v_org_slug text;
  v_org_name text;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED: must be authenticated to accept an invitation';
  end if;

  select email into v_user_email from auth.users where id = v_user_id;
  select full_name into v_user_name from users where id = v_user_id;

  select * into v_invitation from invitations where token = p_token;

  if not found then
    raise exception 'INVITATION_NOT_FOUND: this invitation link is invalid';
  end if;

  if v_invitation.status = 'accepted' then
    raise exception 'INVITATION_ALREADY_ACCEPTED: this invitation has already been used';
  end if;

  if v_invitation.status = 'revoked' then
    raise exception 'INVITATION_REVOKED: this invitation has been revoked';
  end if;

  if v_invitation.status = 'expired' or v_invitation.expires_at < now() then
    update invitations set status = 'expired' where id = v_invitation.id and status = 'pending';
    raise exception 'INVITATION_EXPIRED: this invitation link has expired';
  end if;

  if lower(v_user_email) is distinct from lower(v_invitation.email) then
    raise exception 'EMAIL_MISMATCH: sign in with the email this invitation was sent to';
  end if;

  select slug, name into v_org_slug, v_org_name from organizations where id = v_invitation.organization_id;

  -- Already a member (re-clicking an old link) — idempotent success,
  -- no duplicate notification.
  if exists (
    select 1 from organization_members
    where organization_id = v_invitation.organization_id and user_id = v_user_id
  ) then
    update invitations set status = 'accepted' where id = v_invitation.id;
    return query select v_invitation.organization_id, v_org_slug, v_invitation.role;
    return;
  end if;

  insert into organization_members (organization_id, user_id, role, status, invited_by)
  values (v_invitation.organization_id, v_user_id, v_invitation.role, 'active', v_invitation.invited_by);

  update invitations set status = 'accepted' where id = v_invitation.id;

  -- Notify the inviter. invited_by is NOT NULL on invitations, but guard
  -- anyway — a failed notification insert must never roll back a
  -- successful invitation acceptance, so this is best-effort.
  if v_invitation.invited_by is not null then
    insert into notifications (organization_id, user_id, type, title, body)
    values (
      v_invitation.organization_id,
      v_invitation.invited_by,
      'invitation_accepted',
      'New team member joined',
      coalesce(v_user_name, v_user_email) || ' accepted your invitation to join ' || v_org_name || '.'
    );
  end if;

  return query select v_invitation.organization_id, v_org_slug, v_invitation.role;
end;
$$;

grant execute on function accept_invitation(text) to authenticated;
