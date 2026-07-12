# Authentication Specification — Phase 1

Formalizes Blueprint Section 11 and Phase1_Architecture.md Section 6 into an implementation-precise spec.

## 1. Identity Providers
- **Email/password** — Supabase Auth native.
- **Google OAuth** — standard OAuth 2.0 / OIDC via Supabase provider config.
- **Microsoft OAuth** — Azure AD (multi-tenant "common" endpoint, so any Microsoft account works, not just a specific org's tenant).

Both OAuth providers use the **Authorization Code flow with PKCE** — Supabase's default for browser clients — never the implicit flow.

## 2. Token Model
- **Access token:** JWT, 1-hour expiry, contains `sub` (user id) and standard claims. Never contains role/permission data directly — roles are looked up live against `organization_members`/`role_permissions` on every request, so a permission change takes effect immediately rather than waiting for token expiry.
- **Refresh token:** rotating, stored in an `httpOnly`, `Secure`, `SameSite=Lax` cookie — never accessible to client-side JavaScript (mitigates XSS token theft).
- **Session refresh:** `middleware.ts` refreshes the session on every request per Next.js/Supabase SSR requirements; a request with an expired access token but valid refresh token transparently gets a new access token without the user noticing.

## 3. Password Policy
- Minimum 10 characters, at least one number — enforced client-side (immediate feedback) and server-side (Supabase Auth config, authoritative).
- No maximum complexity theater (no forced special-character rules that push users toward predictable substitutions) — length is the strongest lever.
- Breached-password check via Supabase Auth's built-in HaveIBeenPwned integration if available in the project's Auth settings; otherwise deferred to Phase 6 hardening.

## 4. Email Verification
- Required for email/password signups before full product access — unverified users can complete onboarding but see a persistent, dismissable-but-recurring banner until verified.
- OAuth signups (Google/Microsoft) are treated as pre-verified — the provider has already confirmed the email.
- Verification link: single-use, 24-hour expiry.

## 5. Invitation Tokens
- 32 bytes, cryptographically random (`gen_random_bytes(32)`, hex-encoded), effectively unguessable.
- 7-day expiry, single-use (`status` transitions `pending → accepted|expired|revoked`, no reuse after any terminal state).
- Acceptance is a `SECURITY DEFINER` function — the accepting user is not yet an org member, so this intentionally operates outside normal RLS, scoped tightly to "given a valid, unexpired, pending token, create exactly one `organization_members` row and mark the invitation accepted."

## 6. Rate Limiting & Abuse Prevention
- Login attempts: rate-limited per email + per IP (Supabase Auth built-in throttling; Phase 6 adds application-level rate limiting on top if needed).
- Password reset requests: rate-limited per email to prevent email-bombing a target account.
- Signup: CAPTCHA/bot-protection evaluated for Phase 6 hardening if abuse patterns emerge — not a Phase 1 blocker, but the auth forms are built with a CAPTCHA slot reserved so it's a config change, not a redesign, when needed.

## 7. Session Termination
- **Logout:** revokes the current refresh token; access token remains valid until natural expiry (max 1 hour exposure window) — standard JWT tradeoff, acceptable given the short expiry.
- **Password change / reset:** invalidates all other active sessions for that user, not just the current one — closes the window where a compromised session survives a password reset.
- **Member removal from an org:** does not terminate the user's global session (they may belong to other orgs) — it removes their `organization_members` row, and RLS immediately blocks access to that org's data on their very next request, regardless of token validity.

## 8. Multi-Org Session Context
A single auth session can be "active" in multiple organizations (via the `OrgSwitcher`). The active `organization_id` is **not** encoded in the JWT — it's request-scoped, resolved from the URL's `orgSlug` and re-validated against `organization_members` on every request. This means a stale client-side "currently selected org" state can never grant access to data the server-side check wouldn't independently allow.

## 9. Failure Modes & User-Facing Behavior

| Scenario | Behavior |
|---|---|
| Expired access + valid refresh token | Silent refresh, no user-visible interruption |
| Expired refresh token | Redirect to `/login`, return-to URL preserved |
| Valid session, user removed from the org they're viewing | 403 on next request, redirected to org switcher (or onboarding if zero orgs remain) |
| Invitation token expired | Clear message + option to request the inviter resend, not a generic 404 |
| Invitation token already accepted | Redirect to login (likely the user is already a member and is reusing an old email link) |
| OAuth provider error/denial | Return to login with a specific, non-alarming message ("Sign-in was cancelled"), not a raw provider error dump |

## 10. Future (not Phase 1, scoped for later)
- **MFA (TOTP):** schema/config-ready in Supabase Auth, enabled as a Settings → Security toggle in Phase 6; mandatory at Enterprise tier per Monetization Strategy.
- **SSO (SAML/OIDC for Enterprise customers):** Phase 6+, evaluated based on actual Enterprise-tier demand rather than built speculatively.
