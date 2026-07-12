# Engineering Standards — Error Handling, Logging, Monitoring

## Part 1 — Error Handling Standards

### 1.1 Standard Error Shape
Every error — from an Edge Function, server action, or client-caught exception — normalizes to:
```json
{
  "code": "ORG_SLUG_TAKEN",
  "message": "An organization with a similar name already exists.",
  "details": null
}
```
- `code`: `SCREAMING_SNAKE_CASE`, stable, machine-matchable — client code branches on `code`, never on parsing `message` text.
- `message`: human-readable, safe to show a non-technical user directly — never a raw database or stack trace string.
- `details`: optional structured data (e.g., field-level Zod validation errors) for form-level error display.

### 1.2 Error Categories & HTTP/Status Mapping

| Category | Example codes | Status | Client behavior |
|---|---|---|---|
| Validation | `INVALID_EMAIL`, `REQUIRED_FIELD` | 400 | Inline field error, from `details` |
| Authentication | `SESSION_EXPIRED`, `INVALID_CREDENTIALS` | 401 | Redirect to login (session expired) or inline form error (bad credentials) |
| Authorization | `INSUFFICIENT_PERMISSIONS`, `NOT_ORG_MEMBER` | 403 | Toast + block action; never expose *why* in more detail than necessary (don't reveal whether a resource exists to a user who can't access it) |
| Not Found | `ORG_NOT_FOUND`, `INVITATION_NOT_FOUND` | 404 | Friendly empty/not-found state, not a raw 404 page for in-app resources |
| Conflict | `ORG_SLUG_TAKEN`, `INVITATION_ALREADY_ACCEPTED` | 409 | Inline error, often with a suggested resolution |
| Rate Limited | `TOO_MANY_ATTEMPTS` | 429 | Toast with retry-after guidance |
| Server | `INTERNAL_ERROR` | 500 | Generic "something went wrong, try again" — never leak internals |

### 1.3 Client-Side Handling
- **Form/mutation errors:** surfaced inline (field-level) or via a single `Toast` — never both for the same error, never a silent failure.
- **Render-time errors:** React Error Boundaries wrap each major route segment (`(app)/[orgSlug]/layout.tsx` and below) so one module's failure doesn't blank the entire app shell — the sidebar and org context remain usable.
- **Network/transient errors:** automatic retry (exponential backoff, max 3 attempts) only for idempotent reads (SELECT queries); mutations are never auto-retried silently — a failed invitation-send is surfaced, not silently reattempted, to avoid duplicate side effects.

### 1.4 Server-Side Handling
- Every Edge Function and server action wraps its logic in a top-level try/catch that guarantees the standard error shape is returned even for unexpected exceptions — a raw stack trace is never returned to the client.
- Zod validation failures are caught before any database call and mapped to `details` with per-field messages.
- Postgres errors (constraint violations, RLS denials) are caught and translated to the taxonomy above — a raw Postgres error code/message never reaches the client (both a security and a UX concern).

---

## Part 2 — Logging Strategy

### 2.1 Format
Structured JSON logs, one event per line, minimum fields:
```json
{
  "timestamp": "2026-07-09T10:22:31Z",
  "level": "info",
  "message": "organization created",
  "request_id": "uuid",
  "user_id": "uuid",
  "organization_id": "uuid",
  "context": { "slug": "nakuru-hardware-ltd" }
}
```
`request_id` is generated at the edge (middleware) and threaded through every log line for a single request — this is what makes tracing a single user action across client → server action → Edge Function → database possible.

### 2.2 Levels
- `debug` — local development only, stripped in production builds.
- `info` — normal business events (org created, invitation sent, member role changed) — these double as a lightweight operational view of platform activity, distinct from the immutable `audit_logs` table (which is the compliance record; application logs are the operational/debugging record).
- `warn` — recoverable anomalies (validation rejected, rate limit hit, retried transient failure).
- `error` — caught exceptions that resulted in a failed user action.
- `fatal` — unrecoverable startup/config failures.

### 2.3 What Is Never Logged
- Passwords, tokens (access/refresh/invitation), API keys — never, at any log level, even truncated.
- Full national ID numbers, full M-Pesa numbers, or other PII beyond what's needed for debugging — where an identifier is needed in logs, use the internal UUID, not the human-readable PII field.
- This is a hard rule enforced by a lint rule / log-wrapper convention (`logger.info()` never receives a raw `req.body`, only an explicitly allow-listed context object) — not left to developer discretion per call site.

### 2.4 Where Logs Go
- **Application logs:** Vercel's built-in log stream during Phase 1, exported to a log aggregation service (e.g., Axiom or Better Stack) once volume justifies it — deferred, not a Phase 1 blocker, but the structured-JSON convention above means the migration is a pipe change, not a rewrite.
- **Database logs:** Supabase's built-in Postgres/Auth/API logs (query performance, auth events, RLS denials) — reviewed as part of the monitoring strategy below.
- **Audit trail:** `audit_logs` table (Section 9 of `database_schema.sql`) — distinct from operational logs, immutable, queried by org owners/admins, retained indefinitely (compliance record, not a debugging tool).

### 2.5 Retention
- Application logs: 30 days (Phase 1 default via hosting provider).
- Database/auth logs: per Supabase plan retention.
- Audit logs: indefinite — this is business/legal record, not operational telemetry.

---

## Part 3 — Monitoring Strategy

### 3.1 Uptime & Availability
- External uptime check (e.g., a simple `/api/health` endpoint polled every 60s) against both the Next.js app and Supabase project — alerts on consecutive failures, not single blips (avoids alert fatigue from transient network hiccups).

### 3.2 Error Tracking
- Client and server exceptions reported to an error-tracking service (e.g., Sentry) with `request_id` attached for cross-referencing against structured logs — every unhandled exception is visible, grouped, and trending, not just whatever a user happens to report.
- Error tracking respects the same PII rules as logging (Section 2.3) — source maps uploaded for readable stack traces without exposing them publicly.

### 3.3 Performance
- **Frontend:** Core Web Vitals (LCP, INP, CLS) tracked via Vercel Analytics (or equivalent) — directly relevant to the mobile-first, sometimes-low-connectivity target user (Blueprint Section 2/16).
- **Backend/database:** Supabase's built-in query performance dashboard, watched for slow queries (especially as domain tables grow in Phase 2+) — a query regression is caught before it's a user-visible complaint.

### 3.4 Security-Relevant Monitoring
- **RLS denial spikes:** an unusual increase in policy-denied queries from a given user/IP is a signal worth alerting on — it's either a bug (a legitimate feature querying incorrectly) or a probing attempt, and both deserve investigation.
- **Auth anomalies:** failed login spikes per account or per IP, unusual OAuth error rates.
- **Audit log review:** owners/admins have visibility into their own org's `audit_logs`; platform-level anomaly review (e.g., unusual cross-org patterns, which shouldn't be structurally possible given RLS but are worth monitoring for defense-in-depth) is a periodic manual/automated review, formalized further in Phase 6 hardening.

### 3.5 Alerting
- Critical (uptime down, error rate spike, RLS denial spike): immediate notification (e.g., Slack/PagerDuty channel).
- Warning (slow query trend, elevated 4xx rate): daily digest, reviewed but not paged.
- Thresholds are intentionally not over-specified here — they'll be calibrated against real Phase 1 traffic rather than guessed in advance; this document defines the categories and channels, not premature numeric thresholds that would need immediate revision.
