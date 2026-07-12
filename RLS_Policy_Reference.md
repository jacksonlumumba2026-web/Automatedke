# RLS Policy Reference — Phase 1

Companion to `database_schema.sql`, which contains the executable policies. This document is the readable reference for what each policy enforces and why — used in code review and onboarding, so a reviewer can check intent against implementation without parsing SQL line by line.

**Governing principle:** RLS is the authorization boundary, not the application layer. Every policy below is enforced by Postgres itself — a bug in a server action, an admin script, or a future API integration cannot bypass it. Application-layer permission checks (Section 8 companion, `lib/rbac/permissions.ts`) exist for UX (hiding buttons a user can't use), never as the actual security control.

**Two helper functions underpin every policy** (defined in `database_schema.sql`):
- `user_org_ids()` — the set of organizations the current authenticated user actively belongs to.
- `user_role_in_org(org_id)` — the current user's role within a specific organization.
Both are `SECURITY DEFINER`, which is what avoids infinite recursion when a policy on `organization_members` needs to check `organization_members` membership.

---

## Security Fix Log

**Fixed before first deployment:** an earlier draft of the `organization_members` INSERT policy included a bootstrap clause (`organization_id not in (select organization_id from organization_members)`) intended to let a brand-new user create their own first membership row. That subquery is itself RLS-filtered — a user who belongs to zero organizations sees zero rows from *any* organization via that query, making the "org has no members yet" check true for every organization, not just genuinely new ones. This would have let any authenticated user insert themselves as owner of an existing organization. **Fix:** the client-side policy now requires owner/admin for all inserts, with no exception; first-owner creation happens exclusively inside the `create-organization` Edge Function using the service-role client, which bypasses RLS by design and enforces `auth.uid() is not null` as its own authorization check. See `API_Specification.md`.

**Gap closed in Milestone 3:** Security Architecture (Blueprint Section 11) requires an immutable audit trail for financial and permission-change actions, but audit triggers were only attached to `organizations`, `organization_members`, and `role_permissions`. `invitations` (grants org access) and `subscriptions` (financial/plan data) were missed. Both now have audit triggers — see `supabase/migrations/20260709000003_phase1_extend_audit_coverage.sql`.

**Incident during first real deployment (Milestone 3):** running Supabase's security advisor against an actual deployed instance for the first time flagged `user_org_ids()` and `user_role_in_org()` as unintentionally-public RPC endpoints (Postgres grants `EXECUTE` to `PUBLIC` by default on function creation). The fix — revoking `EXECUTE` from `public`/`anon`/`authenticated` — **broke Row Level Security entirely**: every policy on `organizations`, `organization_members`, `teams`, `role_permissions`, `invitations`, and `subscriptions` calls one of these two functions inside its `USING`/`WITH CHECK` clause, and Postgres requires the *querying* role to hold `EXECUTE` on any function a policy calls, regardless of that function being `SECURITY DEFINER` — `SECURITY DEFINER` only changes whose privileges the function *body* runs with, not whether the caller may invoke it. This was caught immediately by a real functional test (`set role anon; select ... from organizations;`), not by static review, and fixed by restoring the grants (`supabase/migrations/20260709000008_phase1_fix_rls_helper_grants.sql`).

**Accepted tradeoff, not a residual bug:** the security advisor still flags both functions as callable via direct RPC. This is unavoidable given the above — they must remain callable by `authenticated`/`anon` for RLS to work — and it's harmless: both functions key off `auth.uid()`, so calling either directly only ever returns the caller's *own* memberships/role, information already available through normal app queries. Do not attempt to close this warning by revoking execute again; that reintroduces the outage above.

**Two critical PL/pgSQL bugs found by end-to-end execution testing, not static review (Milestone 3):** every prior test of `create_organization_with_owner` and `accept_invitation` had only exercised their auth-rejection paths (no live authenticated session was available until this milestone's real Supabase connection). Actually simulating an authenticated call end-to-end surfaced two identical-pattern bugs: both functions' `RETURNS TABLE (organization_id uuid, ...)` / `(..., slug text)` clauses implicitly declare `organization_id`/`slug` as PL/pgSQL variables in scope for the entire function body — which collided with bare (unqualified) references to the same-named table columns inside each function (`create_organization_with_owner`'s slug-uniqueness loop; `accept_invitation`'s idempotency check). Postgres correctly refused to guess and raised "column reference is ambiguous" on **every single call** — meaning organization creation and invitation acceptance would have failed for every user in production. Fixed by explicitly qualifying the column references (`organizations.slug`, `organization_members.organization_id`) — see `20260709000009` and `20260709000011`. Re-verified end-to-end afterward: full cascade (organization, membership, subscription, 28 seeded role_permissions rows, audit log entry) confirmed working for real.

**A third critical bug, same root cause, different function:** `log_audit_event()` (the generic trigger attached to every audited table) assumed every audited table has an `organization_id` column to key the audit entry's scope on. True for `organization_members`, `role_permissions`, `invitations`, `subscriptions` — **not** for `organizations` itself, whose own identity column is `id`. This meant `trg_audit_organizations` failed on every insert/update to `organizations` since the very first migration, silently breaking both organization creation and the Settings → Organization edit flow. Fixed by special-casing `organizations` to use `NEW.id`/`OLD.id` instead — see `20260709000010`.

**Known, deliberately-deferred issue (not fixed):** `audit_logs.organization_id` has `ON DELETE CASCADE` to `organizations(id)`, but the `AFTER DELETE` audit trigger on `organizations` tries to *insert* a new audit row referencing the org's id after that row is already gone mid-transaction, which violates the FK. In practice this is unreachable by the application today — there is deliberately no RLS `DELETE` policy on `organizations` at all (hard deletion is explicitly out of scope for Phase 1; see the original migration's comments on soft-delete-only). Documented here rather than patched blind, since the right fix depends on a real org-deletion design (e.g. should audit history survive org deletion via `SET NULL`?) that hasn't been made yet — revisit when a Phase 2+ admin deletion flow is actually designed.

## Policy Matrix

| Table | Operation | Who | Enforced Logic |
|---|---|---|---|
| `organizations` | SELECT | Any active member | `id in user_org_ids()` |
| `organizations` | INSERT | Any authenticated user | `auth.uid() is not null` — anyone can create a new org (becomes its owner via the onboarding flow) |
| `organizations` | UPDATE | Owner, Admin | Must be an active member **and** role in `('owner','admin')` |
| `organizations` | DELETE | *(no policy — blocked)* | Deliberate: org deletion is a soft-delete via `deleted_at`, handled through a dedicated admin-audited flow in a later phase, never a raw DELETE |
| `users` | SELECT | Self, or any co-member of a shared org | Self always visible; co-members visible so names/avatars render in member lists, activity feeds |
| `users` | UPDATE | Self only | `id = auth.uid()` |
| `organization_members` | SELECT | Any active member of that org | `organization_id in user_org_ids()` |
| `organization_members` | INSERT | Owner, Admin only (via normal client) | `user_role_in_org(organization_id) in ('owner','admin')`. **First-owner membership is never created this way** — see note below |
| `organization_members` | UPDATE | Owner, Admin | Role changes restricted to owner/admin |
| `organization_members` | DELETE | Owner, Admin | Removing a member restricted to owner/admin |
| `teams` / `team_members` | SELECT | Any active member | Scoped via `organization_id in user_org_ids()` |
| `teams` | ALL (write) | Owner, Admin, Manager | Managers can organize their own teams without needing full admin rights |
| `role_permissions` | SELECT | Any active member | Members can see what their role can/can't do (transparency, supports good UX for permission-denied states) |
| `role_permissions` | INSERT/UPDATE/DELETE | Owner, Admin | Only org leadership can redefine what a role is permitted to do |
| `invitations` | SELECT | Owner, Admin | Only leadership sees pending invitations for their org |
| `invitations` | INSERT | Owner, Admin | Only leadership can invite |
| `invitations` | UPDATE | Owner, Admin | Revocation only by leadership |
| `invitations` | *(token lookup)* | Handled outside RLS | Acceptance flow uses a `SECURITY DEFINER` function keyed by the invitation token itself — the token is the credential, not row-level org membership (the accepting user isn't a member yet) |
| `subscriptions` | SELECT | Any active member | Visible to all so non-owners understand plan limits in the UI |
| `subscriptions` | UPDATE | Owner only | Billing changes restricted to the single owner role, not admins |
| `notifications` | SELECT | Recipient only | `user_id = auth.uid()` — notifications are never org-visible, only to the intended recipient |
| `notifications` | UPDATE | Recipient only | Marking read/unread |
| `audit_logs` | SELECT | Owner, Admin | Only leadership can review the audit trail |
| `audit_logs` | INSERT/UPDATE/DELETE | *(no user-facing policy)* | Writes occur exclusively via the `SECURITY DEFINER` trigger function, which bypasses RLS entirely — this makes the log tamper-resistant to every role, including owner |

---

## Testing Requirement

Per coding standards, every policy above must have at least one automated test that:
1. Confirms a legitimate access pattern succeeds.
2. Confirms the equivalent cross-tenant access attempt (same query, different `organization_id` the user doesn't belong to) returns zero rows or is rejected — never returns another tenant's data.

This is tested directly against the database (e.g., via `pgTAP` or a script issuing queries as different authenticated roles), not only indirectly through the application UI.
