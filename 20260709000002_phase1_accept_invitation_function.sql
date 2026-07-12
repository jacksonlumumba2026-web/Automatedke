-- =============================================================================
-- Migration: Invitation acceptance function
-- The accepting user has no organization_members row for the target org
-- yet, so a normal RLS-scoped INSERT can't succeed (and per the Security
-- Fix Log in RLS_Policy_Reference.md, must never be special-cased to
-- pretend otherwise). This function is the trusted, narrow path: given a
-- valid, unexpired, pending token, it creates exactly one membership row
-- and marks the invitation accepted. Matches
-- Authentication_Specification.md Section 5 exactly.
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
  v_invitation invitations%rowtype;
  v_org_slug text;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED: must be authenticated to accept an invitation';
  end if;

  select email into v_user_email from auth.users where id = v_user_id;

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

  -- Defense in depth: the invitation was issued to a specific email.
  -- Accepting with a different account would let anyone who guesses/
  -- intercepts a token join under their own identity instead of the
  -- invited person's — the token grants "join as the invited email,"
  -- not "join as whoever holds this link."
  if lower(v_user_email) is distinct from lower(v_invitation.email) then
    raise exception 'EMAIL_MISMATCH: sign in with the email this invitation was sent to';
  end if;

  -- Already a member (e.g. re-clicking an old link after joining another
  -- way) — treat as idempotent success rather than an error.
  if exists (
    select 1 from organization_members
    where organization_id = v_invitation.organization_id and user_id = v_user_id
  ) then
    update invitations set status = 'accepted' where id = v_invitation.id;
    select slug into v_org_slug from organizations where id = v_invitation.organization_id;
    return query select v_invitation.organization_id, v_org_slug, v_invitation.role;
    return;
  end if;

  insert into organization_members (organization_id, user_id, role, status, invited_by)
  values (v_invitation.organization_id, v_user_id, v_invitation.role, 'active', v_invitation.invited_by);

  update invitations set status = 'accepted' where id = v_invitation.id;

  select slug into v_org_slug from organizations where id = v_invitation.organization_id;

  return query select v_invitation.organization_id, v_org_slug, v_invitation.role;
end;
$$;

grant execute on function accept_invitation(text) to authenticated;
