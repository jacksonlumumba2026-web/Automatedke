# Automated KE 2.0 — Phase 1 Architecture
**Scope:** Project Setup, Authentication, Dashboard, Database (per Development Roadmap, Section 14 of the Blueprint)
**Status:** Planning — pending approval before implementation begins

---

## 1. Technical Review — Changes Recommended Before Implementation

The blueprint's stack (Next.js + React + TypeScript + Tailwind, Supabase/Postgres/Edge Functions, modular monolith) stands. Before writing code, eight adjustments will save significant rework later:

1. **Monorepo from day one (pnpm + Turborepo), not a single Next.js app.**
   The blueprint mentions Files, mobile-responsiveness, and eventual scale across modules. A monorepo (`apps/web`, `packages/ui`, `packages/types`, `packages/config`) costs almost nothing now and avoids a painful extraction later when a mobile app or admin panel is needed. Shared Tailwind/ESLint/TS config and Supabase-generated types live in `packages/` and are consumed by every app.

2. **Path-based multi-tenancy for v1, not subdomains.**
   `app.automatedke.com/[orgSlug]/dashboard` instead of `orgslug.automatedke.com`. Subdomains require wildcard DNS/SSL and complicate local development for no v1 benefit. Path-based tenancy is simpler to build and secure correctly, and can be migrated to subdomains later without a data-model change — the `organization_id` scoping is identical either way.

3. **Role-permission table, not hardcoded role enums.**
   Section 6 of the blueprint calls for custom, granular roles ("org admins can compose granular permissions per module"). Building this as hardcoded enum checks in Phase 1 means rebuilding it in Phase 3+. Instead, Phase 1 ships a `role_permissions` table now (module × action × role, per organization) even though only a few roles are used initially — the mechanism is right from the start.

4. **Module activation on the organization record, from Phase 1.**
   The blueprint's IA (Section 5) says orgs only see modules relevant to their business (a school skips POS). This must be a data-driven `enabled_modules` field on `organizations`, not a per-module `if` scattered through the frontend, or every future phase will need to retrofit it.

5. **Database-enforced audit logging via triggers, not application-layer logging.**
   Section 11 requires immutable audit trails on financial/HR data. If audit logging lives in application code, any direct DB write (migration, admin script, bug) bypasses it. Postgres triggers writing to `audit_logs` guarantee nothing is missed, regardless of write path.

6. **SECURITY DEFINER helper functions for RLS on the membership table.**
   A common Supabase pitfall: an RLS policy on `organization_members` that queries `organization_members` to check membership creates infinite recursion. Phase 1 defines a `SECURITY DEFINER` function (`user_org_ids()`) once, used by every policy — avoids this class of bug entirely rather than debugging it per-table later.

7. **Migration-first workflow, Supabase Studio dashboard never used for schema changes.**
   Every schema change is a versioned SQL file in `supabase/migrations/`, applied via CLI/CI. This is a coding-standards item (Section 10) but has architectural weight: it's the only way multi-environment (local/staging/prod) parity survives past week one.

8. **Type generation from the live schema, not hand-written types.**
   `supabase gen types typescript` runs in CI and on local schema changes, output committed to `packages/types`. This keeps frontend/backend in sync automatically and is cheap to set up now versus expensive to retrofit once hand-written types have drifted.

None of these change the blueprint's strategic direction — they're implementation-order decisions that prevent Phase 2–6 rework.

---

## 2. Complete Folder Structure

```
automated-ke/
├── apps/
│   └── web/                              # Next.js 14+ App Router application
│       ├── app/
│       │   ├── (marketing)/              # public site — landing, pricing (SEO-optimized, SSR)
│       │   │   ├── page.tsx
│       │   │   ├── pricing/
│       │   │   └── layout.tsx
│       │   ├── (auth)/                   # unauthenticated flows
│       │   │   ├── login/page.tsx
│       │   │   ├── signup/page.tsx
│       │   │   ├── forgot-password/page.tsx
│       │   │   ├── reset-password/page.tsx
│       │   │   ├── verify-email/page.tsx
│       │   │   ├── accept-invite/[token]/page.tsx
│       │   │   └── layout.tsx
│       │   ├── onboarding/               # post-signup org creation flow
│       │   │   ├── create-organization/page.tsx
│       │   │   └── layout.tsx
│       │   ├── (app)/
│       │   │   └── [orgSlug]/            # org-scoped, tenant-isolated routes
│       │   │       ├── dashboard/page.tsx
│       │   │       ├── settings/
│       │   │       │   ├── organization/page.tsx
│       │   │       │   ├── team/page.tsx
│       │   │       │   ├── roles/page.tsx
│       │   │       │   ├── billing/page.tsx
│       │   │       │   └── security/page.tsx
│       │   │       ├── notifications/page.tsx
│       │   │       └── layout.tsx        # org context provider, sidebar shell
│       │   ├── api/
│       │   │   ├── webhooks/             # e.g. auth events, future payment webhooks
│       │   │   └── health/route.ts
│       │   ├── layout.tsx                # root layout (fonts, theme provider)
│       │   ├── globals.css
│       │   └── not-found.tsx
│       ├── components/
│       │   ├── ui/                       # design-system primitives (Section 9)
│       │   ├── layout/                   # Sidebar, Topbar, OrgSwitcher, AppShell
│       │   ├── auth/                     # LoginForm, SignupForm, OAuthButtons
│       │   ├── onboarding/
│       │   ├── dashboard/
│       │   └── shared/                   # cross-module composites (EmptyState, DataTable)
│       ├── lib/
│       │   ├── supabase/
│       │   │   ├── client.ts             # browser client
│       │   │   ├── server.ts             # server component / route handler client
│       │   │   ├── middleware.ts         # session refresh helper
│       │   │   └── admin.ts              # service-role client (server-only, never bundled to client)
│       │   ├── auth/
│       │   │   ├── session.ts
│       │   │   └── guards.ts             # requireAuth(), requireOrgRole()
│       │   ├── rbac/
│       │   │   ├── permissions.ts        # can(user, module, action)
│       │   │   └── constants.ts
│       │   ├── validators/               # zod schemas, shared client+server
│       │   ├── email/                    # transactional email templates/senders
│       │   └── utils/
│       ├── hooks/
│       │   ├── use-organization.ts
│       │   ├── use-permissions.ts
│       │   └── use-toast.ts
│       ├── types/
│       │   └── database.ts               # re-exported from packages/types (generated)
│       ├── middleware.ts                 # auth session refresh + route protection
│       ├── next.config.ts
│       ├── tailwind.config.ts
│       └── package.json
├── packages/
│   ├── ui/                               # (Phase 2+) extractable shared component package
│   ├── config/                           # shared eslint-config, tsconfig, tailwind-preset
│   └── types/
│       └── database.types.ts             # auto-generated from Supabase schema, committed
├── supabase/
│   ├── migrations/                       # timestamped, sequential, never edited after merge
│   │   └── 20260709000000_phase1_foundation.sql
│   ├── seed.sql                          # local dev seed data only
│   └── config.toml
├── docs/
│   ├── blueprint/                        # Section-by-section blueprint (source of truth)
│   └── architecture/                     # this document and future phase docs
├── .env.example
├── .github/workflows/                    # CI: lint, typecheck, test, migration-diff check
├── pnpm-workspace.yaml
├── turbo.json
└── package.json
```

**Rationale for key decisions:**
- Route groups `(marketing)`, `(auth)`, `(app)` separate concerns that have different rendering strategies (SSR/SEO for marketing, minimal shell for auth, fully authenticated app shell for the product) without affecting the URL structure.
- `[orgSlug]` as a dynamic segment is the single point where tenant context is established for every nested route — the layout at that level is where org membership is verified before anything renders.
- `lib/supabase/admin.ts` is isolated deliberately: the service-role key must never be importable from a client component, and keeping it in one file makes that boundary auditable.

---

## 6. Authentication Flows

**Providers:** Email/password, Google OAuth, Microsoft OAuth (per Technical Architecture, Section 8).

### 6.1 Sign-up
1. User submits email/password, or completes Google/Microsoft OAuth.
2. Supabase Auth creates the `auth.users` record.
3. A database trigger (`handle_new_user`) inserts a corresponding row into public `users` (profile table) — keeps `auth.users` (managed by Supabase) separate from our extensible profile data.
4. Email/password users receive a verification email; OAuth users are considered verified via the provider.
5. Redirect to `/onboarding/create-organization` — **a user with zero organizations always lands here**, never on a dashboard.

### 6.2 Organization creation (onboarding)
1. New user provides organization name, industry (drives default `enabled_modules`), and country (defaults to Kenya).
2. Server action creates the `organizations` row, an `organization_members` row for the creator with role `owner`, and a `subscriptions` row on the Free tier.
3. Redirect to `/{orgSlug}/dashboard`.

### 6.3 Invitations (joining an existing organization)
1. An `owner`/`admin` invites a user by email + role from Settings → Team.
2. An `invitations` row is created with a signed, expiring token; an email is sent with `/accept-invite/[token]`.
3. On acceptance: if the email matches an existing account, the user logs in and an `organization_members` row is created; if not, they complete signup first, then the invite is consumed.
4. Invitations expire after 7 days and are single-use.

### 6.4 Login
1. Email/password or OAuth.
2. Supabase issues a JWT (access + refresh token) containing the `sub` (user id).
3. `middleware.ts` refreshes the session on every request and attaches it to server components.
4. If the user belongs to exactly one organization, they're routed straight to `/{orgSlug}/dashboard`; if multiple, an org switcher screen is shown; if zero, back to onboarding.

### 6.5 Password reset
Standard Supabase flow: request → emailed link with short-lived token → `/reset-password` → new password set → all other sessions for that user invalidated.

### 6.6 Session & route protection
- `middleware.ts` refreshes the Supabase session cookie on every request (required for SSR auth to work correctly with Next.js).
- Every route under `(app)/[orgSlug]/...` is guarded server-side by `requireOrgRole()` in the layout — checked against `organization_members`, never trusted from client state alone.
- Role/permission checks happen **twice**: server-side (authoritative, blocks rendering/data access) and client-side (UX only, hides buttons the user can't use) — the client check is never the security boundary.

### 6.7 Multi-factor authentication
Not required in Phase 1 build, but the schema and Supabase Auth configuration support enabling TOTP MFA per the blueprint's tier structure (optional Professional+, mandatory Enterprise) — this is a configuration toggle in Phase 6 hardening, not a schema change.

---

## 7. Organization & Multi-Tenant Architecture

**Isolation model:** Single Postgres database, single schema, every tenant-owned table carries `organization_id`, enforced by Row Level Security (Section 4/5 of this doc's companion `database_schema.sql`) — not just filtered in application queries. This is the single most important security decision in the platform: **a bug in frontend query-building cannot leak another organization's data**, because the database itself refuses the row.

**Tenant resolution:**
1. URL contains `orgSlug` (e.g., `/nakuru-hardware/dashboard`).
2. The `(app)/[orgSlug]/layout.tsx` server component resolves `orgSlug` → `organization_id`, and verifies the current authenticated user has a row in `organization_members` for that org.
3. On success, `organization_id` is placed in a request-scoped context (React context on the client, passed explicitly to server actions/queries on the server) — **every subsequent query is scoped by this id**, and RLS enforces it is scoped correctly even if application code forgets.
4. If the user is not a member of that org: 403, not a redirect that leaks whether the org exists.

**A user belonging to multiple organizations** (e.g., an accountant serving several SME clients) simply has multiple `organization_members` rows — the org switcher (Section 2 folder structure, `layout/OrgSwitcher`) lets them move between tenant contexts; there is no cross-org data merging anywhere in the product.

**Module activation:** `organizations.enabled_modules` (jsonb array, e.g., `["crm","inventory","pos"]`) is set from an industry-based default at creation and editable in Settings. The dashboard, sidebar, and RBAC layer all read this — a hospital never sees a POS nav item, a freelancer never sees Payroll.

**Extensibility to future phases:** Every domain table added in Phase 2+ (customers, products, invoices, etc.) follows the identical pattern established here — `organization_id` FK, RLS policy using the same `user_org_ids()` helper function, and an entry in `role_permissions` for the relevant module. Phase 1 is deliberately building the **pattern**, not just the Phase 1 tables.

---

## 10. Coding Standards

**Language & type safety**
- TypeScript `strict: true`, no `any` without an explicit `// eslint-disable-next-line` and a comment justifying it.
- Database types are generated (`supabase gen types typescript`), never hand-written — the generated file is the source of truth for table shapes throughout the app.
- All external input (form submissions, API route bodies, server action arguments) validated with Zod at the boundary before touching the database — validated types, not just TypeScript compile-time types, since compile-time checks don't protect against malformed runtime input.

**Component conventions**
- Server Components by default; `"use client"` only when interactivity (state, effects, browser APIs) requires it — keeps bundle size down and matches Next.js App Router's intended model.
- One component per file, colocated with its own types; shared primitives live in `components/ui/`, never duplicated per feature.
- No inline business logic in JSX — data fetching and mutations live in `lib/` or server actions, components stay presentational.

**Naming**
- Files: `kebab-case.tsx` for components, `camelCase.ts` for utilities.
- Components: `PascalCase`. Hooks: `useCamelCase`. Database tables/columns: `snake_case` (Postgres convention).
- Branches: `phase-1/feature-name`. Commits: Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`) — enables automated changelog generation later.

**Database & migrations**
- Every schema change is a new file in `supabase/migrations/`, applied via CLI — never edited via Supabase Studio's table editor in any shared environment.
- Every tenant-owned table: `organization_id` FK (indexed), RLS enabled before the migration is considered complete, `created_at`/`updated_at` (auto-managed via trigger), `deleted_at` for soft-deletable entities.
- No migration ships without a corresponding RLS policy — a table with RLS enabled and no policy is fully locked (safe default); a table without RLS enabled at all is a blocked PR.

**Security**
- Service-role Supabase client (`lib/supabase/admin.ts`) is used only in trusted server contexts (webhooks, admin scripts) — never in a code path reachable from client input without independent authorization checks.
- Every server action/route handler starts with an auth + permission check before any data access — no exceptions, no "I'll add it later."
- Secrets only in environment variables, never committed; `.env.example` documents required keys with no real values.

**Testing (Phase 1 baseline)**
- Unit tests for `lib/rbac/permissions.ts` and all validators (these are security-relevant and cheap to test exhaustively).
- Integration test for the full auth + onboarding flow (signup → org creation → dashboard access) before Phase 1 is marked complete.
- RLS policies tested directly against the database (not just through the app) — a policy that "works" only because the app never sends the malicious query isn't tested.

**Accessibility & performance**
- Semantic HTML first; ARIA attributes only where semantic HTML is insufficient.
- All interactive elements keyboard-navigable; focus states never removed via CSS.
- Images use Next.js `<Image>`; fonts self-hosted via `next/font` (no render-blocking external font requests).

---

## 11. Phase 1 Implementation Plan

Sequenced so each step is independently testable before the next begins.

**Step 1 — Repository & tooling setup**
pnpm workspace + Turborepo scaffold, shared ESLint/TS/Tailwind config in `packages/config`, CI pipeline (lint, typecheck, migration-diff check) on every PR.

**Step 2 — Supabase project & foundational schema**
Local Supabase instance via CLI, `supabase/migrations/..._phase1_foundation.sql` applied (see companion `database_schema.sql`), type generation wired into CI.

**Step 3 — Authentication**
Email/password + Google + Microsoft OAuth configured in Supabase Auth, `handle_new_user` trigger, login/signup/password-reset pages, `middleware.ts` session handling.

**Step 4 — Onboarding & organization creation**
`create-organization` flow, `organization_members`/`subscriptions` row creation, org-slug uniqueness validation, redirect logic for zero/one/many-org users.

**Step 5 — Multi-tenant routing & RBAC enforcement**
`[orgSlug]` layout with membership verification, `requireOrgRole()` guard, `role_permissions` seed data for default roles, org switcher UI.

**Step 6 — Invitations**
Invite creation (Settings → Team), email delivery, accept-invite flow, expiry/single-use enforcement.

**Step 7 — Dashboard shell & design system components**
`AppShell` (sidebar + topbar), core `components/ui/` primitives (see companion `design_system.md`), empty-state dashboard scaffolded for Phase 2 modules to populate.

**Step 8 — Notifications foundation**
`notifications` table + basic in-app notification bell (no external channels yet — email/SMS/WhatsApp notification delivery arrives with Phase 5 Marketing/Automation infrastructure).

**Step 9 — Audit logging verification**
Confirm triggers fire correctly on `organizations`, `organization_members`, and `role_permissions` changes; manual review of `audit_logs` output.

**Step 10 — Testing & review**
Unit + integration tests per Section 10, manual RLS penetration check (attempt cross-org reads/writes as a low-privilege authenticated user), accessibility pass on all Phase 1 screens.

**Definition of done for Phase 1:** A new user can sign up, verify email or complete OAuth, create an organization, invite a teammate with a specific role, have that role correctly restrict their access, and land on a dashboard shell — with every action attributable in the audit log and every cross-tenant access attempt provably blocked at the database layer.
