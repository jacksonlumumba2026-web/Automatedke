-- =============================================================================
-- Automated KE 2.0 — Phase 1 Foundational Schema
-- Scope: Identity, Organizations, Multi-Tenancy, RBAC, Audit, Notifications
-- Domain tables (CRM, Inventory, Accounting, HR, etc.) are added in their
-- respective phases, following the identical organization_id + RLS pattern
-- established here.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- EXTENSIONS
-- -----------------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- UTILITY: updated_at trigger function (reused by every table)
-- -----------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- TABLE: organizations
-- -----------------------------------------------------------------------------
create table organizations (
  id                uuid primary key default uuid_generate_v4(),
  name              text not null,
  slug              text not null unique,
  industry          text,                          -- drives default enabled_modules
  country           text not null default 'KE',
  enabled_modules   jsonb not null default '["crm","dashboard"]'::jsonb,
  settings          jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

create index idx_organizations_slug on organizations (slug) where deleted_at is null;

create trigger trg_organizations_updated_at
  before update on organizations
  for each row execute function set_updated_at();

-- -----------------------------------------------------------------------------
-- TABLE: users (public profile — extends auth.users, never duplicates auth data)
-- -----------------------------------------------------------------------------
create table users (
  id            uuid primary key references auth.users (id) on delete cascade,
  full_name     text,
  avatar_url    text,
  phone         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger trg_users_updated_at
  before update on users
  for each row execute function set_updated_at();

-- Auto-create a public.users row whenever a new auth.users row is created
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.users (id, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'avatar_url'
  );
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- -----------------------------------------------------------------------------
-- TABLE: organization_members (the core multi-tenant join table)
-- -----------------------------------------------------------------------------
create type org_role as enum ('owner', 'admin', 'manager', 'accountant',
                               'sales_rep', 'hr_manager', 'inventory_staff',
                               'support_agent', 'read_only', 'custom');

create table organization_members (
  id                uuid primary key default uuid_generate_v4(),
  organization_id   uuid not null references organizations (id) on delete cascade,
  user_id           uuid not null references users (id) on delete cascade,
  role              org_role not null default 'read_only',
  status            text not null default 'active' check (status in ('active', 'suspended')),
  invited_by        uuid references users (id),
  joined_at         timestamptz not null default now(),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (organization_id, user_id)
);

create index idx_org_members_org on organization_members (organization_id);
create index idx_org_members_user on organization_members (user_id);

create trigger trg_org_members_updated_at
  before update on organization_members
  for each row execute function set_updated_at();

-- -----------------------------------------------------------------------------
-- SECURITY DEFINER HELPER: avoids RLS recursion on organization_members
-- Every tenant-scoped RLS policy uses this function rather than querying
-- organization_members directly inside its own policy.
-- -----------------------------------------------------------------------------
create or replace function user_org_ids()
returns setof uuid
language sql
security definer
stable
set search_path = public
as $$
  select organization_id
  from organization_members
  where user_id = auth.uid()
    and status = 'active';
$$;

create or replace function user_role_in_org(p_org_id uuid)
returns org_role
language sql
security definer
stable
set search_path = public
as $$
  select role
  from organization_members
  where user_id = auth.uid()
    and organization_id = p_org_id
    and status = 'active';
$$;

-- -----------------------------------------------------------------------------
-- TABLE: teams (sub-groups within an organization — optional, e.g. "Nairobi Branch")
-- -----------------------------------------------------------------------------
create table teams (
  id                uuid primary key default uuid_generate_v4(),
  organization_id   uuid not null references organizations (id) on delete cascade,
  name              text not null,
  description       text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index idx_teams_org on teams (organization_id);

create trigger trg_teams_updated_at
  before update on teams
  for each row execute function set_updated_at();

create table team_members (
  team_id     uuid not null references teams (id) on delete cascade,
  user_id     uuid not null references users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (team_id, user_id)
);

-- -----------------------------------------------------------------------------
-- TABLE: role_permissions (granular, per-organization, per-module RBAC)
-- Enables custom roles per blueprint Section 6, not just hardcoded checks.
-- -----------------------------------------------------------------------------
create table role_permissions (
  id                uuid primary key default uuid_generate_v4(),
  organization_id   uuid not null references organizations (id) on delete cascade,
  role              org_role not null,
  module            text not null,                 -- e.g. 'crm', 'inventory', 'payroll'
  can_view          boolean not null default false,
  can_create        boolean not null default false,
  can_edit          boolean not null default false,
  can_delete        boolean not null default false,
  can_export        boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (organization_id, role, module)
);

create index idx_role_permissions_org on role_permissions (organization_id);

create trigger trg_role_permissions_updated_at
  before update on role_permissions
  for each row execute function set_updated_at();

-- -----------------------------------------------------------------------------
-- TABLE: invitations
-- -----------------------------------------------------------------------------
create table invitations (
  id                uuid primary key default uuid_generate_v4(),
  organization_id   uuid not null references organizations (id) on delete cascade,
  email             text not null,
  role              org_role not null default 'read_only',
  token             text not null unique default encode(gen_random_bytes(32), 'hex'),
  invited_by        uuid not null references users (id),
  status            text not null default 'pending' check (status in ('pending', 'accepted', 'expired', 'revoked')),
  expires_at        timestamptz not null default (now() + interval '7 days'),
  created_at        timestamptz not null default now()
);

create index idx_invitations_org on invitations (organization_id);
create index idx_invitations_token on invitations (token);
create index idx_invitations_email on invitations (email);

-- -----------------------------------------------------------------------------
-- TABLE: subscriptions (billing tier — payment integration arrives later)
-- -----------------------------------------------------------------------------
create type subscription_plan as enum ('free', 'starter', 'professional', 'business', 'enterprise');

create table subscriptions (
  id                  uuid primary key default uuid_generate_v4(),
  organization_id     uuid not null unique references organizations (id) on delete cascade,
  plan                subscription_plan not null default 'free',
  status              text not null default 'active' check (status in ('active', 'past_due', 'canceled', 'trialing')),
  current_period_end  timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create trigger trg_subscriptions_updated_at
  before update on subscriptions
  for each row execute function set_updated_at();

-- -----------------------------------------------------------------------------
-- TABLE: notifications (in-app; email/SMS/WhatsApp delivery channels arrive Phase 5)
-- -----------------------------------------------------------------------------
create table notifications (
  id                uuid primary key default uuid_generate_v4(),
  organization_id   uuid not null references organizations (id) on delete cascade,
  user_id           uuid not null references users (id) on delete cascade,
  type              text not null,
  title             text not null,
  body              text,
  read_at           timestamptz,
  created_at        timestamptz not null default now()
);

create index idx_notifications_user on notifications (user_id, read_at);
create index idx_notifications_org on notifications (organization_id);

-- -----------------------------------------------------------------------------
-- TABLE: audit_logs (immutable — insert-only, never updated or deleted by app)
-- -----------------------------------------------------------------------------
create table audit_logs (
  id                uuid primary key default uuid_generate_v4(),
  organization_id   uuid references organizations (id) on delete cascade,
  user_id           uuid references users (id),
  action            text not null,                 -- e.g. 'insert', 'update', 'delete'
  entity_type       text not null,                 -- e.g. 'organization', 'organization_members'
  entity_id         uuid,
  old_data          jsonb,
  new_data          jsonb,
  ip_address        text,
  created_at        timestamptz not null default now()
);

create index idx_audit_logs_org on audit_logs (organization_id, created_at desc);

-- Generic audit trigger function — attached selectively to sensitive tables
create or replace function log_audit_event()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_org_id uuid;
begin
  v_org_id := coalesce(
    (case when TG_OP = 'DELETE' then old.organization_id else new.organization_id end),
    null
  );

  insert into audit_logs (organization_id, user_id, action, entity_type, entity_id, old_data, new_data)
  values (
    v_org_id,
    auth.uid(),
    lower(TG_OP),
    TG_TABLE_NAME,
    case when TG_OP = 'DELETE' then old.id else new.id end,
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('UPDATE','INSERT') then to_jsonb(new) else null end
  );

  return coalesce(new, old);
end;
$$;

create trigger trg_audit_organizations
  after insert or update or delete on organizations
  for each row execute function log_audit_event();

create trigger trg_audit_organization_members
  after insert or update or delete on organization_members
  for each row execute function log_audit_event();

create trigger trg_audit_role_permissions
  after insert or update or delete on role_permissions
  for each row execute function log_audit_event();

-- =============================================================================
-- ROW LEVEL SECURITY
-- Default posture: enable RLS on every tenant-owned table; a table with RLS
-- enabled and no policy is fully locked. No table ships without both.
-- =============================================================================

alter table organizations         enable row level security;
alter table users                 enable row level security;
alter table organization_members  enable row level security;
alter table teams                 enable row level security;
alter table team_members          enable row level security;
alter table role_permissions      enable row level security;
alter table invitations           enable row level security;
alter table subscriptions         enable row level security;
alter table notifications         enable row level security;
alter table audit_logs            enable row level security;

-- ---- organizations ----------------------------------------------------------
create policy "members can view their organizations"
  on organizations for select
  using (id in (select user_org_ids()));

create policy "owners and admins can update their organization"
  on organizations for update
  using (id in (select user_org_ids()) and user_role_in_org(id) in ('owner', 'admin'));

create policy "authenticated users can create an organization"
  on organizations for insert
  with check (auth.uid() is not null);

-- ---- users --------------------------------------------------------------
create policy "users can view their own profile"
  on users for select
  using (id = auth.uid());

create policy "org members can view co-members' profiles"
  on users for select
  using (id in (
    select om.user_id from organization_members om
    where om.organization_id in (select user_org_ids())
  ));

create policy "users can update their own profile"
  on users for update
  using (id = auth.uid());

-- ---- organization_members ------------------------------------------------
create policy "members can view fellow members of their orgs"
  on organization_members for select
  using (organization_id in (select user_org_ids()));

create policy "owners and admins can add members"
  on organization_members for insert
  with check (user_role_in_org(organization_id) in ('owner', 'admin'));

-- NOTE: There is deliberately no "first owner" bootstrap clause here.
-- An authenticated user has no organization_members row yet when their
-- organization is created, so any client-side INSERT policy attempting
-- to detect "this org has zero members" would have to query
-- organization_members itself — which is RLS-filtered to rows the
-- current user can already see, i.e. none. That makes any such check
-- vacuously true for every outsider, not just genuine first owners
-- (this exact bug shipped in an earlier draft of this migration and was
-- caught in review before deployment). Instead, organization creation
-- and first-owner membership are both created transactionally by the
-- create-organization Edge Function, which uses the service-role client
-- (bypasses RLS by design) and enforces its own auth.uid() check as the
-- authorization boundary for that specific trusted path. See
-- supabase/functions/create-organization and API_Specification.md.

create policy "owners and admins can update member roles"
  on organization_members for update
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) in ('owner', 'admin'));

create policy "owners and admins can remove members"
  on organization_members for delete
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) in ('owner', 'admin'));

-- ---- teams / team_members -------------------------------------------------
create policy "members can view teams in their org"
  on teams for select
  using (organization_id in (select user_org_ids()));

create policy "managers and above can manage teams"
  on teams for all
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) in ('owner', 'admin', 'manager'));

create policy "members can view team membership in their org"
  on team_members for select
  using (team_id in (select id from teams where organization_id in (select user_org_ids())));

-- ---- role_permissions ------------------------------------------------------
create policy "members can view their org's role permissions"
  on role_permissions for select
  using (organization_id in (select user_org_ids()));

create policy "owners and admins can manage role permissions"
  on role_permissions for insert
  with check (user_role_in_org(organization_id) in ('owner', 'admin'));

create policy "owners and admins can update role permissions"
  on role_permissions for update
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) in ('owner', 'admin'));

create policy "owners and admins can delete role permissions"
  on role_permissions for delete
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) in ('owner', 'admin'));

-- ---- invitations ------------------------------------------------------------
create policy "owners and admins can view invitations for their org"
  on invitations for select
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) in ('owner', 'admin'));

create policy "owners and admins can create invitations"
  on invitations for insert
  with check (user_role_in_org(organization_id) in ('owner', 'admin'));

create policy "owners and admins can revoke invitations"
  on invitations for update
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) in ('owner', 'admin'));

-- Note: invite acceptance by token (unauthenticated or newly authenticated
-- users looking up a specific token) is handled via a SECURITY DEFINER
-- Postgres function, not a broad SELECT policy — the token itself is the
-- authorization, and it must not be guessable via a table scan.

-- ---- subscriptions ------------------------------------------------------
create policy "members can view their org's subscription"
  on subscriptions for select
  using (organization_id in (select user_org_ids()));

create policy "owners can update their org's subscription"
  on subscriptions for update
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) = 'owner');

-- ---- notifications ------------------------------------------------------
create policy "users can view their own notifications"
  on notifications for select
  using (user_id = auth.uid());

create policy "users can mark their own notifications read"
  on notifications for update
  using (user_id = auth.uid());

-- ---- audit_logs -----------------------------------------------------------
create policy "owners and admins can view their org's audit log"
  on audit_logs for select
  using (organization_id in (select user_org_ids())
         and user_role_in_org(organization_id) in ('owner', 'admin'));

-- No insert/update/delete policies on audit_logs for regular roles —
-- writes happen exclusively via the SECURITY DEFINER trigger function,
-- which bypasses RLS. This makes the audit trail tamper-resistant by
-- ordinary application or user access.

-- =============================================================================
-- SEED: default role_permissions template applied to every new organization
-- (invoked by the organization-creation server action, not a raw insert here)
-- =============================================================================
-- Example shape for reference — actual seeding happens in application code
-- at org-creation time, looping module list × role list:
--
-- insert into role_permissions (organization_id, role, module, can_view, can_create, can_edit, can_delete, can_export)
-- values ('<new_org_id>', 'owner', 'crm', true, true, true, true, true), ...
-- =============================================================================
