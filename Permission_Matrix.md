# Permission Matrix — Phase 1

Concrete instantiation of the `role_permissions` table (default template seeded into every new organization at creation — org owners can customize from this baseline via Settings → Roles, since `role_permissions` is per-organization, not global).

**Modules in scope for Phase 1:** `organization` (org profile/settings), `team` (members/invitations), `roles` (role_permissions management), `billing` (subscription), `notifications`. Future-phase modules (`crm`, `inventory`, `accounting`, `payroll`, etc.) will each add a row per role following the identical pattern once built — not present yet because the underlying tables don't exist.

**Legend:** V = View, C = Create, E = Edit, D = Delete, X = Export

| Role | `organization` | `team` | `roles` | `billing` | `notifications` |
|---|---|---|---|---|---|
| **Owner** | V,C,E,D | V,C,E,D | V,C,E,D | V,C,E,D | V,E |
| **Admin** | V,E | V,C,E,D | V,C,E,D | V | V,E |
| **Manager** | V | V | V | — | V,E |
| **Accountant** | V | — | — | V | V,E |
| **Sales Rep** | V | — | — | — | V,E |
| **HR Manager** | V | V | — | — | V,E |
| **Inventory Staff** | V | — | — | — | V,E |
| **Support Agent** | V | — | — | — | V,E |
| **Read Only** | V | V | — | — | V |
| **Custom** | *(defined per-organization by Owner/Admin, no defaults)* | | | | |

**Notes on specific rows:**
- **Only Owner can delete the organization** (soft-delete, not even in Phase 1's scope — the column exists, the flow doesn't yet) or manage billing/subscription changes — Admins are trusted with day-to-day operation but not account-level/financial control.
- **Only Owner and Admin manage `roles`** — allowing Managers to edit permissions would let them grant themselves broader access, a privilege-escalation path that's closed by design.
- **`notifications` is universally V,E for every role** — every user manages their own notification read-state regardless of org role; this is enforced by the RLS policy (`user_id = auth.uid()`), not by `role_permissions`, since it's a personal, not organizational, permission.
- **Everyone can at least View `organization`** — needed so any member sees basic org context (name, plan tier limits) even without administrative rights.

**Implementation note (added Milestone 2):** the `billing` and `roles` columns each split into a *view* and a *manage* check in code (`lib/rbac/permissions.ts`: `canViewBilling`/`canManageBilling`, `canViewRoles`/`canManageRoles`), since the matrix above already implies different roles can view vs. edit (e.g. Accountant can view billing but not manage it). The Settings page's Billing and Roles tabs are only rendered at all for roles with view access; the underlying RLS policies enforce the same distinction independently.

## How This Maps to Enforcement

Two layers, both real, serving different purposes:

1. **Database (authoritative):** RLS policies (see `RLS_Policy_Reference.md`) check `user_role_in_org()` directly for the handful of hardcoded-sensitive operations (org update, member management, billing) — these don't consult `role_permissions` because they're structural, not customizable.
2. **Application (`role_permissions`-driven, authoritative for future domain modules):** Once Phase 2+ modules exist, their RLS policies **will** consult `role_permissions` dynamically (`exists (select 1 from role_permissions where organization_id = ... and role = user_role_in_org(...) and module = 'crm' and can_edit)`) rather than hardcoding role checks per table — this is what makes custom roles actually take effect for domain data without a schema change per module.

Phase 1's own modules (team, billing, roles) intentionally use the simpler hardcoded owner/admin check above, since these are structural platform capabilities, not business-configurable ones — an organization should never be able to grant a "Sales Rep" the ability to change billing, regardless of custom role configuration.
