# CLAUDE.md — Automated KE 2.0

This file is the permanent instruction set for any AI assistant (or engineer) working in this repository. It reflects decisions already approved in `/docs` — it does not introduce new ones. When in doubt, the documents in `/docs` are the source of truth; this file is the condensed, operational version of them.

---

## 1. What This Project Is

Automated KE 2.0 is a multi-tenant business automation platform (CRM, ERP, AI assistants, accounting, inventory, HR, marketing) for Kenyan SMEs, expanding to East Africa. Full context: `docs/Product_Blueprint.md`.

**Current phase:** Phase 1 (Project Setup, Authentication, Dashboard, Database) — see `docs/Phase1_Architecture.md` and `docs/Deployment_Architecture.md` for the full roadmap and implementation plan.

---

## 2. Stack — Do Not Substitute Without Explicit Approval

- **Frontend:** Next.js (App Router) + React + TypeScript (`strict: true`) + Tailwind CSS
- **Backend:** Supabase (Postgres + Auth + Edge Functions + Storage)
- **Monorepo:** pnpm workspaces + Turborepo (`apps/web`, `packages/config`, `packages/types`)
- **Hosting:** Vercel (app), Supabase managed (backend) — see `docs/Deployment_Architecture.md`

If a task seems to require a different library or service than what's already in `package.json`, stop and flag it rather than adding a new dependency silently.

---

## 3. Non-Negotiable Rules

These are not preferences — violating them is a blocked PR, not a style nit.

1. **Every tenant-owned table has `organization_id` and Row Level Security enabled, with a policy.** A table with RLS enabled and no policy (fully locked) is the safe default if a policy isn't ready yet. A table with RLS *disabled* is never acceptable for tenant data.
2. **RLS is the authorization boundary, not the application layer.** Application-side permission checks (`lib/rbac/`) exist only for UX (hiding buttons), never as the actual security control. Never write a query that relies on the frontend to filter by `organization_id` — the database must enforce it.
3. **Migrations are append-only.** Never edit a migration file that has been merged to `main`. Fix mistakes with a new migration. CI enforces this (`scripts/check-migration-diff.js`) — don't work around it.
4. **No schema changes via Supabase Studio** in any shared environment. Every schema change is a versioned file in `supabase/migrations/`.
5. **The service-role Supabase client (`lib/supabase/admin.ts` once it exists) never runs in a client-reachable code path without an independent authorization check**, and is never imported into a `"use client"` file. This is enforced by an ESLint rule — do not disable it to make something "work."
6. **No `any` in TypeScript** without an inline comment justifying it. Database types are always generated (`pnpm db:types`), never hand-written, except the documented Phase 1 placeholder in `packages/types/database.types.ts` (which must be replaced once a live Supabase project exists — see the comment at the top of that file).
7. **Every server action / route handler / Edge Function starts with an auth + permission check before any data access.** No exceptions, no "add it later."
8. **Accessibility is enforced at build time, not reviewed after the fact.** `jsx-a11y` lint rules are set to `error`. Any new color token must be checked against WCAG AA (4.5:1 for normal text, 3:1 for large text/UI) before use — see the contrast notes in `docs/design_system.md`.
9. **No placeholder implementations.** If something can't be finished in a given pass, it's flagged explicitly, not stubbed out silently and left looking done.
10. **Never revoke `EXECUTE` on a function without checking whether an RLS policy calls it first.** `SECURITY DEFINER` controls whose privileges a function's body runs with — it does not waive the requirement that the querying role hold `EXECUTE` to invoke the function at all. A function referenced inside any policy's `USING`/`WITH CHECK` clause must keep `EXECUTE` granted to every role that queries the table(s) it protects, even if a security scan flags it as "publicly callable." This broke RLS platform-wide once already (see `RLS_Policy_Reference.md`'s incident log) — grep every RLS policy for a function's name before touching its grants.
11. **In any `plpgsql` function with `RETURNS TABLE (col_name ...)`, every output column name is an implicit variable in scope for the entire function body — qualify every bare reference to a real table column of the same name**, even inside a `WHERE`/`EXISTS` clause that looks unambiguous at a glance. This caused two separate "column reference is ambiguous" failures — on every single call — in `create_organization_with_owner` (`slug`) and `accept_invitation` (`organization_id`), both invisible until real end-to-end execution testing (see `RLS_Policy_Reference.md`'s incident log). Any new `RETURNS TABLE` function must be execution-tested for its actual success path, not just its auth-rejection path, before being considered done.
12. **A generic trigger function attached to multiple tables must not assume every table shares the same column name for the same concept.** `log_audit_event()` assumed every audited table has an `organization_id` column; `organizations` itself uses `id` for that role, which broke every write to that one table silently since the first migration. When writing a shared trigger/function for several tables, explicitly verify the assumption holds for every table it's attached to — don't infer it from the majority case.

---

## 4. Workflow Rules for This Project

- **Follow the implementation plan in `docs/Phase1_Architecture.md` Section 11 in order.** Don't jump ahead to a later milestone's work while an earlier one is incomplete.
- **After every milestone:** run an architecture review, a security review, a performance review, and an accessibility review before moving on. Fix what's found; don't defer known issues without saying so explicitly.
- **This sandbox/dev environment may not have network access.** `pnpm install`, `pnpm build`, `supabase` CLI commands, and live testing may need to be verified in a real environment. Say so explicitly rather than claiming something was run when it wasn't — static review (syntax validation, config sanity checks, manual tracing) is not a substitute for a real install/build, and should be labeled as such.
- **Reference the engineering docs, don't restate or contradict them.** If new work seems to require deviating from `docs/`, flag the conflict and ask, rather than quietly diverging.

---

## 5. Folder Structure Reference

```
apps/web/app/(marketing)   Public site
apps/web/app/(auth)        Login, signup, password reset, invite acceptance
apps/web/app/onboarding    Post-signup organization creation
apps/web/app/(app)/[orgSlug]   Authenticated, tenant-scoped app
apps/web/components/ui     Design-system primitives — see docs/Component_Library.md
apps/web/lib/supabase      client.ts (browser), server.ts (SSR), admin.ts (service-role, server-only)
apps/web/lib/rbac          Permission-check helpers (UX layer only — see Rule 2 above)
supabase/migrations        Append-only, timestamped SQL migrations
packages/types              Generated Supabase types — never hand-edited (see Rule 6)
docs/                        Full engineering reference (blueprint, schema, RLS, API, security, deployment)
```

Full rationale for this structure: `docs/Phase1_Architecture.md`, Section 2.

---

## 6. Common Commands

| Command | Purpose |
|---|---|
| `pnpm dev` | Run the web app locally |
| `pnpm lint` / `pnpm typecheck` / `pnpm test` | Quality gates — all three must pass before a milestone is "done" |
| `pnpm db:types` | Regenerate `packages/types/database.types.ts` from the live schema |
| `pnpm db:migrate:local` | Reset local DB, reapply all migrations |
| `supabase db push` | Apply migrations to a remote project (CI does this for production — see `docs/Deployment_Architecture.md`) |

---

## 7. Where to Look Before Asking

| Question | Document |
|---|---|
| "What does this table/column mean?" | `docs/database_schema.sql`, `docs/Database_ERD.md` |
| "Who can do what?" | `docs/Permission_Matrix.md`, `docs/RLS_Policy_Reference.md` |
| "What should this error look like?" | `docs/Engineering_Standards.md` (Part 1) |
| "What color/spacing/component do I use?" | `docs/design_system.md`, `docs/Component_Library.md` |
| "How does login/invite/session work?" | `docs/Authentication_Specification.md` |
| "How does this get deployed?" | `docs/Deployment_Architecture.md` |
| "What's the overall plan?" | `docs/Phase1_Architecture.md`, `docs/Product_Blueprint.md` |

---

## 8. Market Context (affects product decisions, not just marketing copy)

Kenya-first, phased expansion to East Africa. Pricing, currency (KES default), and payment integration (M-Pesa-first) decisions should assume this posture unless a task explicitly says otherwise — see `docs/Product_Blueprint.md`, Section 2 and 13.

---

## 9. Definition of Done

A task is complete only when:

- Code is production-ready.
- Tests pass.
- Security review passes.
- Performance review passes.
- Accessibility review passes.
- Documentation is updated.
- No placeholder implementations remain.

This applies at the same granularity as Section 4's per-milestone reviews — a milestone isn't "done" because code was written for every item on the list, it's done when every item above is true for that code.

---

## 10. UI Standards

Every screen must:

- Be mobile-first.
- Support dark and light themes.
- Use the design system (`docs/design_system.md`, `docs/Component_Library.md`) — no one-off colors, spacing, or components.
- Include loading states.
- Include empty states.
- Include error states.
- Include success feedback.
- Be keyboard accessible.
- Meet WCAG AA accessibility.

A screen missing any of these is not production-ready, regardless of how complete the "happy path" looks.

---

## 11. AI Coding Principles

- Never sacrifice quality for speed.
- Prefer maintainable architecture.
- Refactor duplicated code immediately — don't let a second copy of the same logic ship "to be cleaned up later."
- Explain major architectural decisions.
- Do not invent APIs or database fields.
- Verify against project documentation before implementing — if `/docs` doesn't cover it, flag the gap rather than guessing.

---

*This file should be updated whenever an approved architectural decision changes — not left to drift from `/docs`. If you update this file, update the corresponding source document in `/docs` in the same change.*
