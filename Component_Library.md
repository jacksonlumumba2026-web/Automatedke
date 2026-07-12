# Component Library Documentation — Phase 1

Detailed reference for every primitive in `components/ui/` and layout component in `components/layout/`. This is the implementation contract — Phase 1 builds these signatures exactly; later phases consume them without modification. Companion to `design_system.md` (tokens/visual language).

---

## `<Button>`

```tsx
type ButtonProps = {
  variant?: 'primary' | 'secondary' | 'outline' | 'ghost' | 'destructive'; // default 'primary'
  size?: 'sm' | 'md' | 'lg';                                              // default 'md'
  loading?: boolean;
  disabled?: boolean;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
  onClick?: () => void;
  type?: 'button' | 'submit' | 'reset';
  children: React.ReactNode;
} & React.ButtonHTMLAttributes<HTMLButtonElement>;
```
**Behavior:** `loading` disables the button, replaces `children` with a spinner, and preserves the button's measured width (no layout shift). `destructive` variant is reserved for irreversible actions and pairs with a confirmation `<Modal>` — never a bare click-to-delete.

**Example:**
```tsx
<Button variant="destructive" loading={isRemoving} onClick={handleRemoveMember}>
  Remove member
</Button>
```

---

## `<Input>` / `<Textarea>`

```tsx
type InputProps = {
  label: string;                 // always required — no placeholder-as-label
  helperText?: string;
  error?: string;                // presence triggers error styling + aria-invalid
  prefixIcon?: React.ReactNode;
  suffixIcon?: React.ReactNode;
  required?: boolean;
} & React.InputHTMLAttributes<HTMLInputElement>;
```
**Accessibility:** `label` is always programmatically associated via `htmlFor`/`id` — never a visual-only label. `error` sets `aria-invalid="true"` and `aria-describedby` pointing at the error message.

---

## `<Select>` / `<Combobox>`

`Select` for short, fixed lists (e.g., role picker: owner/admin/manager/...). `Combobox` for long or searchable lists (deferred — first real usage is Phase 2's product/customer pickers, but the primitive ships in Phase 1 so the pattern exists before it's needed).

```tsx
type SelectProps<T> = {
  label: string;
  options: { value: T; label: string; disabled?: boolean }[];
  value: T;
  onChange: (value: T) => void;
  error?: string;
};
```

---

## `<Card>`

```tsx
type CardProps = {
  children: React.ReactNode;
  className?: string;
};
// Sub-components: Card.Header, Card.Body, Card.Footer
```
**Usage pattern:**
```tsx
<Card>
  <Card.Header>Organization Details</Card.Header>
  <Card.Body>{/* form fields */}</Card.Body>
  <Card.Footer><Button>Save changes</Button></Card.Footer>
</Card>
```

---

## `<Table>` (the highest-reuse component in the system)

**Status: implemented** (`components/ui/Table.tsx`), first used by the Team settings tab for the member and pending-invitation lists.

```tsx
type Column<T> = {
  key: keyof T | string;
  header: string;
  sortable?: boolean;
  render?: (row: T) => React.ReactNode;   // custom cell rendering (badges, actions, etc.)
  width?: string;
};

type TableProps<T> = {
  columns: Column<T>[];
  data: T[];
  loading?: boolean;             // renders Skeleton rows matching column count
  emptyState?: React.ReactNode;  // renders <EmptyState> when data.length === 0 and !loading
  onSort?: (key: string, direction: 'asc' | 'desc') => void;
  pagination?: { page: number; pageSize: number; total: number; onPageChange: (page: number) => void };
  rowKey: (row: T) => string;
};
```
**Why this shape:** every future domain module (customers list, product list, invoice list, employee list) is the same `Table` with different columns and a different data source — this is the component that makes 12 modules feel like one product rather than 12 differently-built list views.

---

## `<Modal>` / `<Dialog>`

**Status: implemented** (`components/ui/Modal.tsx`), first used by `InviteMemberModal`.

```tsx
type ModalProps = {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  size?: 'sm' | 'md' | 'lg';
  preventBackdropClose?: boolean;   // true for destructive confirmations
  children: React.ReactNode;
};
```
**Accessibility:** focus is trapped within the modal while open, focus returns to the triggering element on close, `Esc` closes unless `preventBackdropClose` is set (destructive actions require an explicit button click, not an accidental key press).

---

## `<Toast>` (notification system)

**Status: implemented** in Milestone 2's follow-up pass (`components/ui/Toast.tsx`), mounted once at the root layout via `<ToastProvider>`.

```tsx
type ToastVariant = 'success' | 'error' | 'info' | 'warning';
function useToast(): {
  toast: (message: string, variant?: ToastVariant, options?: { duration?: number }) => void;
};
```
**Standard:** every mutation (create/update/delete) triggers exactly one toast — success or error, never both, never silent. Error toasts derive their message from the standardized error shape (see Error Handling Standards).

**Post-redirect success feedback:** a toast fired on a page that's about to unmount (e.g. right before `router.push()` after creating an organization or resetting a password) would never be seen — the root layout persists across client-side navigation in App Router, so a mount-only effect on it would also miss these. The fix is `lib/toast/pending.ts`: call `setPendingToast(message, variant)` immediately before the redirect; `<PendingToastConsumer>` (mounted at the root, keyed off `usePathname()`) picks it up and fires it on the page landed on, then clears it. Use this pattern for any mutation that redirects; use `useToast()` directly for any mutation that doesn't.

---

## `<Badge>`

```tsx
type BadgeProps = {
  variant: 'default' | 'success' | 'warning' | 'danger' | 'info';
  children: React.ReactNode;
};
```
**Mapping convention (enforced, not per-instance choice):** active/paid/completed → `success`; pending/trial → `warning`; suspended/overdue/failed → `danger`; role labels → `default`. This mapping is centralized in `lib/rbac/constants.ts` and status-mapping utilities so a given status always renders the same color everywhere in the product.

---

## `<Avatar>`

```tsx
type AvatarProps = {
  src?: string;
  name: string;          // used to generate initials fallback
  size?: 'sm' | 'md' | 'lg';
};
```

---

## `<Tabs>`

**Status: implemented** (`components/ui/Tabs.tsx`), used for the Settings page's Organization/Team/Roles/Billing sub-navigation — arrow-key navigation between tabs included, per WCAG's tabs pattern.

```tsx
type TabsProps = {
  tabs: { key: string; label: string; content: React.ReactNode }[];
  defaultTab?: string;
};
```
Used for settings sub-navigation (Organization / Team / Roles / Billing / Security) in Phase 1.

---

## `<Skeleton>`

```tsx
type SkeletonProps = { variant: 'text' | 'card' | 'table-row' | 'stat-card'; count?: number };
```
**Rule:** any component with an async data dependency ships its matching `Skeleton` variant in the same PR — a `loading` prop that just shows a spinner over blank space is not acceptable for content areas (Table, Card, StatCard).

---

## `<EmptyState>`

```tsx
type EmptyStateProps = {
  icon?: React.ReactNode;
  title: string;
  description?: string;
  action?: { label: string; onClick: () => void };
};
```
Heavily used in Phase 1 since most screens start with zero data (no team members beyond the owner, no notifications yet).

---

## `<StatCard>`

```tsx
type StatCardProps = {
  label: string;
  value: string | number;
  delta?: { value: number; direction: 'up' | 'down'; period: string };  // e.g. "+12% vs last month"
  icon?: React.ReactNode;
  loading?: boolean;
};
```
`delta.direction` maps to `accent` (up, generally good) or `danger` (down) — **except** for metrics where down is good (e.g., "overdue invoices"), which pass an explicit `invertColor` flag rather than relying on direction alone.

---

## Layout Components

### `<AppShell>`
Composes `<Sidebar>` + `<Topbar>` + content area. Responsive breakpoint collapses `<Sidebar>` to a bottom drawer below `md`. This is the single root layout component for every authenticated screen — no module renders outside it.

### `<Sidebar>`
```tsx
type SidebarProps = {
  enabledModules: string[];   // from organizations.enabled_modules
  activeModule: string;
};
```
Renders nav items driven entirely by data, not a hardcoded list per organization type — a hospital and a retail shop run the identical `Sidebar` component with different `enabledModules` arrays.

**Settings is a single nav entry, not one per section:** an earlier draft linked directly to `/settings/team` and `/settings/billing` before those routes existed (a dead-link bug caught in Milestone 2's review). Fixed by consolidating to one `/settings` entry whose sub-navigation is handled by `<Tabs>` (Organization/Team/Roles/Billing) — matching how `<Tabs>` was already documented above, rather than growing the sidebar by one link per settings section as more get built.

### `<OrgSwitcher>`
Renders only when the current user has `organization_members` rows in more than one org; otherwise renders nothing (no empty dropdown for the common single-org case).

### `<Topbar>`
Composes `<OrgSwitcher>`, notification bell (badge count from unread `notifications`), and user menu (profile, logout).
