# API Specification — Phase 1

## 1. Architecture Overview

Automated KE uses a **two-layer API model**, per Blueprint Section 10:

1. **Internal data access** — Next.js server components, server actions, and route handlers talk to Supabase directly via the generated client (PostgREST under the hood), with **Row Level Security as the authorization layer**. This is not a hand-rolled REST API; it's the Supabase auto-API, security-enforced at the database. This is how the product itself operates — fast to build, and every query is safe by construction.

2. **Public/partner API** (`/api/v1/...`) — a deliberately thin, versioned, documented REST surface for third-party integrations (Business/Enterprise tier add-on, Blueprint Section 13). **Not built in Phase 1** — there is no meaningful external integration surface until domain data (customers, invoices, products) exists in Phase 2+. This document defines the standard now so Phase 2 onward implements against an agreed contract rather than improvising one per module.

**Phase 1 custom logic** that doesn't map cleanly to a direct table read/write is implemented as **Supabase Edge Functions**, called from server actions — never exposed directly to the browser with elevated privileges.

---

## 2. Phase 1 Server-Side Operations

**Architecture note (revised during Milestone 2 implementation):** `create-organization` is implemented as a `SECURITY DEFINER` Postgres RPC function (`create_organization_with_owner`, in `supabase/migrations/20260709000001_phase1_org_creation_function.sql`), not an Edge Function as originally sketched. A multi-step Edge Function issuing separate REST calls (insert org, insert membership, insert subscription, seed permissions) is not atomic — a failure partway through leaves a half-created organization. A single Postgres function call is one transaction by construction. The function checks `auth.uid() is not null` itself, which is the authorization boundary for this trusted path (same pattern as `user_org_ids()`/`user_role_in_org()`), and is called directly via `supabase.rpc()` from the Next.js server action using the normal (non-service-role) server client. This removes an unnecessary network hop and avoids the service-role key touching this flow at all.

Remaining Phase 1 operations below are still implemented as thin server actions calling Supabase directly (no dedicated Edge Function needed — they're single-table operations RLS already secures correctly):

| Operation | Implementation | Auth | Purpose |
|---|---|---|---|
| `create_organization_with_owner` | Postgres RPC (`SECURITY DEFINER`) | Authenticated user (checked inside the function) | Atomically creates `organizations`, `organization_members` (owner), `subscriptions` (free), and default `role_permissions`. **Execution-verified end-to-end** against a live Supabase instance in Milestone 3 (two critical bugs found and fixed in the process — see `RLS_Policy_Reference.md`'s incident log). |
| `accept_invitation` | Postgres RPC (`SECURITY DEFINER`) | Authenticated user (email must match the invited address — checked inside the function) | Same reasoning as org creation: the accepting user has no `organization_members` row yet, so a normal RLS-scoped insert can't succeed. Validates token existence, expiry, and status; idempotent if already a member. **Execution-verified end-to-end**, including the notification side-effect — see `Authentication_Specification.md` Section 5 and `RLS_Policy_Reference.md`'s incident log. |
| Send/revoke invitation | Server actions (`lib/invitations/actions.ts`) + direct table access (RLS-secured) | Owner/Admin, enforced by both the action and RLS | **Implemented** in Milestone 2. Email delivery (transactional provider) is still deferred to Phase 5 per `Phase1_Architecture.md` Step 8 — the invitation row, token, and accept flow are fully functional via direct link in the meantime. |
| `switch-active-org` | No server call needed | — | Active org is resolved from the URL's `orgSlug` on every request (see Section 7 of `Phase1_Architecture.md`), not a server-side "switch" operation to persist |

### Request/Response shape (standardized across all functions)

**Request:**
```json
{
  "organization_name": "Nakuru Hardware Ltd",
  "industry": "retail",
  "country": "KE"
}
```

**Success response (200):**
```json
{
  "data": {
    "organization_id": "uuid",
    "slug": "nakuru-hardware-ltd"
  },
  "error": null
}
```

**Error response (4xx/5xx)** — shape matches the Error Handling Standards document:
```json
{
  "data": null,
  "error": {
    "code": "ORG_SLUG_TAKEN",
    "message": "An organization with a similar name already exists.",
    "details": null
  }
}
```

---

## 3. Direct Data Access Patterns (internal — via Supabase client, RLS-enforced)

These aren't "endpoints" in the REST sense but are documented as the standard access patterns Phase 1 screens use, since they're the actual API surface of the app:

| Screen | Table(s) | Operation | RLS-enforced by |
|---|---|---|---|
| Dashboard | `organizations`, `notifications`, `audit_logs` | SELECT | `user_org_ids()` |
| Settings → Organization | `organizations` | SELECT/UPDATE | owner/admin role check |
| Settings → Team | `organization_members`, `users` | SELECT, and INSERT/UPDATE/DELETE via Edge Functions above | owner/admin role check |
| Settings → Roles | `role_permissions` | SELECT/UPDATE | owner/admin role check |
| Settings → Billing | `subscriptions` | SELECT/UPDATE | owner-only for update |
| Notification bell | `notifications` | SELECT/UPDATE (mark read) | recipient-only |

**Standard for all list queries:** pagination via `.range()`, default page size 25, max 100; sortable columns explicitly allow-listed per screen (never accept an arbitrary client-supplied column name for `ORDER BY` — injection surface).

---

## 4. Public API Standard (defined now, implemented Phase 2+)

Per Blueprint Section 10, when the public API ships:

- **Versioned:** `/api/v1/...`, breaking changes require a new version, never an in-place breaking change to `v1`.
- **Auth:** API keys scoped to an organization and a role, generated in Settings → Integrations (not user session tokens — API keys are long-lived and independently revocable).
- **Rate limiting:** per API key, tiered by subscription plan (ties to Monetization Strategy — API access is itself a paid feature at Business tier+).
- **Pagination:** cursor-based (`?after=<cursor>`) for stability under concurrent writes, not offset-based.
- **Errors:** identical `{ data, error: { code, message, details } }` shape as internal functions — one error contract across the whole platform.
- **Documentation:** auto-generated OpenAPI spec from route handler schemas (Zod → OpenAPI), published at `/api/v1/docs`.
- **Webhooks (outbound):** organizations can register a URL to receive events (`order.created`, `invoice.paid`, `stock.low`) — this is the mechanism that makes the Workflow Builder (Phase 4) and third-party automation (Zapier-style) possible without a bespoke integration per partner.

No public API routes exist in the Phase 1 codebase — this section is a contract for later phases to implement against, so the shape doesn't drift module to module.
