# Automated KE 2.0 — Design System (Phase 1 Foundation)

This is the shared visual and component language every module — Phase 1 through Phase 6 — builds on. It exists so a 12-module product feels like one coherent app, per Blueprint Section 15.

---

## 1. Design Tokens

### Color
Brand guidelines call for trust, innovation, simplicity, speed, professionalism — a premium SaaS feel with dark/light modes. Proposed palette (adjustable, but internally consistent):

| Token | Light | Dark | Use |
|---|---|---|---|
| `primary` | `#3730A3` (indigo-700) | `#818CF8` (indigo-400) | Primary actions, active nav, links |
| `primary-hover` | `#312E81` | `#6366F1` | Hover state |
| `accent` | `#059669` (emerald-600) | `#34D399` | Success, money-positive states (ties to M-Pesa/growth association). **Only 3.77:1 on white — use for large text/icons/borders, not small body text.** |
| `accent-strong` | `#047857` (emerald-700) | `#34D399` | WCAG AA-safe (5.48:1) variant — use whenever accent color appears as small text (labels, inline status text) |
| `warning` | `#D97706` | `#FBBF24` | Low stock, pending approvals. **Only 3.19:1 on white — use for large text/icons/borders, not small body text.** |
| `warning-strong` | `#B45309` (amber-700) | `#FBBF24` | WCAG AA-safe (5.02:1) variant — use whenever warning color appears as small text |
| `danger` | `#DC2626` | `#F87171` | Destructive actions, overdue invoices |
| `background` | `#FAFAFA` | `#0B0F19` | App background |
| `surface` | `#FFFFFF` | `#111827` | Cards, panels |
| `border` | `#E5E7EB` | `#1F2937` | Dividers, input borders |
| `ink-primary` | `#111827` | `#F9FAFB` | Headings, primary text (renamed from `text-primary` to avoid colliding with `text-primary`, the brand-color-as-text-color utility — see Milestone 2 code quality review) |
| `ink-secondary` | `#6B7280` | `#9CA3AF` | Secondary/meta text |

**Rationale:** Indigo reads as trustworthy/technical without the overused "SaaS blue" sameness; emerald as the accent ties naturally to financial/growth contexts (money in, stock healthy, task complete) which recur constantly across CRM, Accounting, and Inventory modules.

### Typography
- **Font:** Inter (self-hosted via `next/font`) — excellent legibility at small sizes for dense data tables, wide weight range for strong headline hierarchy, free of licensing friction.
- **Scale:** `text-xs` (12px, meta/labels) → `text-sm` (14px, body/table data) → `text-base` (16px, default body) → `text-lg`/`text-xl` (section headers) → `text-2xl`–`text-4xl` (page titles, dashboard stat headlines).
- **Weight usage:** 400 body, 500 emphasis/labels, 600 headings, 700 reserved for hero/stat numbers — restraint keeps the dense, data-heavy screens (Inventory, Accounting) from feeling noisy.

### Spacing
4px base unit (Tailwind default scale). Component-internal padding: 12–16px. Card padding: 24px. Section gaps in-app: 32–48px (deliberately tighter than the marketing site's 120px — an operational dashboard prioritizes information density over breathing room, unlike the public site).

### Radius & Elevation
- Radius: `rounded-lg` (8px) for cards/inputs, `rounded-full` for avatars/badges — consistent throughout, no mixing of sharp and rounded styles.
- Elevation: flat surfaces by default (`border` token, not shadow) for in-app UI — shadows reserved for transient/overlay elements (modals, dropdowns, toasts) where they communicate "floating above the page," not for static cards where they'd add visual noise across a data-dense dashboard.

### Motion
- Standard transition: 150–200ms ease-out for hover/focus states.
- Page/panel transitions: 250ms, used for meaningful state changes only (a workflow firing, a record saving) — never decorative, per Blueprint Section 15.

---

## 2. Core Components (`components/ui/`)

Each is a single-responsibility, fully-typed, accessible primitive. All are built once in Phase 1 and reused unmodified across every future module.

| Component | Variants / Notes |
|---|---|
| **Button** | `primary`, `secondary`, `outline`, `ghost`, `destructive` × `sm`/`md`/`lg`; loading state built in (spinner replaces label, button disabled, width preserved to prevent layout shift) |
| **Input / Textarea** | Label, helper text, error state (red border + message, `aria-invalid`), prefix/suffix icon slot |
| **Select / Combobox** | Keyboard-navigable, searchable variant for long lists (e.g., product pickers in later phases) |
| **Checkbox / Radio / Switch** | Consistent focus ring, label always click-target-linked |
| **Card** | `header`/`body`/`footer` slots; used for dashboard stat cards, settings panels, list items |
| **Table / DataTable** | Sortable headers, sticky header on scroll, row hover, empty state slot, pagination footer, loading skeleton rows — this is the single most reused component across every future domain module (customers, products, invoices, employees) |
| **Modal / Dialog** | Focus-trapped, `Esc` to close, backdrop click configurable per use (destructive confirmations disable backdrop-dismiss) |
| **Dropdown Menu** | For row actions, user menu, org switcher |
| **Toast / Notification** | Success/error/info variants, auto-dismiss with pause-on-hover |
| **Badge** | Status indicators (role badges, subscription tier, invoice status) — color mapped to semantic token, not arbitrary per-instance color |
| **Avatar** | Image with initials fallback, used for users and org logos |
| **Tabs** | Underline style for settings sub-navigation |
| **Skeleton** | Loading placeholders matching the shape of Card/Table/Stat components — used everywhere data is async-loaded, never a generic spinner-only state for content areas |
| **EmptyState** | Icon + message + optional CTA — used extensively in Phase 1 since most modules start empty (no customers yet, no invoices yet) |
| **StatCard** | Dashboard KPI display: label, value, delta indicator (up/down %, colored via `accent`/`danger`) |

**Layout components (`components/layout/`):**
- **AppShell** — sidebar + topbar + content area, responsive (sidebar collapses to bottom nav/drawer on mobile — mobile-first per Blueprint Section 15).
- **Sidebar** — module navigation, driven by `organizations.enabled_modules`; active-state highlighting.
- **Topbar** — org switcher, search (future), notification bell, user menu.
- **OrgSwitcher** — dropdown of the user's organizations, only rendered if membership count > 1.

---

## 3. Component Build Standard

Every component in `components/ui/`:
1. Fully typed props, no `any`, sensible defaults.
2. Forwards `ref` where DOM access is meaningful (inputs, buttons).
3. Accepts `className` for one-off composition without breaking the base design (uses `cn()`/`clsx` merge utility, never full style overrides).
4. Keyboard-operable and screen-reader-labeled by default — accessibility is not an opt-in variant.
5. Has both light and dark styling defined at creation, not retrofitted.
6. Ships with a loading and empty/error state where applicable — a `Table` isn't "done" without its skeleton and empty-state variants.

---

## 4. Dashboard Shell (Phase 1 deliverable)

The Phase 1 dashboard is intentionally sparse — it's the shell future modules populate, not a feature in itself:
- **StatCard row** — placeholder KPIs (will populate with real data starting Phase 2: sales, customers, low stock, etc.)
- **Recent activity feed** — powered by `audit_logs`/`notifications`, gives immediate visible proof the system is tracking real actions from day one.
- **EmptyState modules** — for each `enabled_modules` entry not yet built, a clearly labeled "Coming in a future phase" card rather than a broken/missing nav item — keeps the product feeling intentional, not incomplete, during incremental rollout.

This shell is what every subsequent phase's module screens slot into — no future phase touches the shell itself, only adds new routes and sidebar entries.
