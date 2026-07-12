-- =============================================================================
-- Migration: Organization creation function
-- Adds create_organization_with_owner(), the single source of truth for
-- the "new org + first owner + free subscription + default role
-- permissions" transaction described in API_Specification.md.
--
-- Implemented as a Postgres function rather than multiple sequential
-- Edge Function REST calls specifically for atomicity: a single function
-- call is one transaction — if slug generation, the owner-membership
-- insert, or permission seeding fails, nothing partial is left behind.
-- SECURITY DEFINER + an explicit auth.uid() check is the authorization
-- boundary for this specific trusted path, matching the pattern already
-- used by user_org_ids()/user_role_in_org() (see the original migration's
-- header comments and RLS_Policy_Reference.md's Security Fix Log).
-- =============================================================================

create or replace function slugify(p_input text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(lower(trim(p_input)), '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function create_organization_with_owner(
  p_name text,
  p_industry text default null,
  p_country text default 'KE'
)
returns table (organization_id uuid, slug text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_base_slug text;
  v_candidate_slug text;
  v_suffix int := 0;
  v_org_id uuid;
  v_default_modules jsonb;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED: must be authenticated to create an organization';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'VALIDATION_ERROR: organization name is required';
  end if;

  -- Slug uniqueness: try the base slug, then base-2, base-3, ... until free.
  -- Done inside this SECURITY DEFINER function (not the client/RLS-scoped
  -- connection) so the uniqueness check sees ALL organizations, not just
  -- ones the calling user can already view.
  v_base_slug := slugify(p_name);
  if v_base_slug = '' then
    v_base_slug := 'organization';
  end if;
  v_candidate_slug := v_base_slug;

  while exists (select 1 from organizations where slug = v_candidate_slug) loop
    v_suffix := v_suffix + 1;
    v_candidate_slug := v_base_slug || '-' || v_suffix;
  end loop;

  -- Industry-based default module set — mirrors the mapping described in
  -- Phase1_Architecture.md Section 7 ("Module activation"). Kept minimal
  -- and explicit rather than a large lookup table, since only Phase 1
  -- modules exist to activate right now.
  v_default_modules := case p_industry
    when 'retail' then '["dashboard","crm","team"]'::jsonb
    else '["dashboard","crm","team"]'::jsonb
  end;

  insert into organizations (name, slug, industry, country, enabled_modules)
  values (trim(p_name), v_candidate_slug, p_industry, coalesce(p_country, 'KE'), v_default_modules)
  returning id into v_org_id;

  insert into organization_members (organization_id, user_id, role, status)
  values (v_org_id, v_user_id, 'owner', 'active');

  insert into subscriptions (organization_id, plan, status)
  values (v_org_id, 'free', 'active');

  -- Seed default role_permissions per Permission_Matrix.md — the
  -- authoritative baseline every organization starts from and can
  -- customize afterward (role_permissions is per-organization, not
  -- global; see Database_ERD.md's "Reading Notes").
  insert into role_permissions (organization_id, role, module, can_view, can_create, can_edit, can_delete, can_export)
  values
    (v_org_id, 'owner', 'organization', true, true, true, true, true),
    (v_org_id, 'owner', 'team', true, true, true, true, true),
    (v_org_id, 'owner', 'roles', true, true, true, true, true),
    (v_org_id, 'owner', 'billing', true, true, true, true, true),
    (v_org_id, 'owner', 'notifications', true, false, true, false, false),

    (v_org_id, 'admin', 'organization', true, false, true, false, false),
    (v_org_id, 'admin', 'team', true, true, true, true, true),
    (v_org_id, 'admin', 'roles', true, true, true, true, true),
    (v_org_id, 'admin', 'billing', true, false, false, false, false),
    (v_org_id, 'admin', 'notifications', true, false, true, false, false),

    (v_org_id, 'manager', 'organization', true, false, false, false, false),
    (v_org_id, 'manager', 'team', true, false, false, false, false),
    (v_org_id, 'manager', 'notifications', true, false, true, false, false),

    (v_org_id, 'accountant', 'organization', true, false, false, false, false),
    (v_org_id, 'accountant', 'billing', true, false, false, false, false),
    (v_org_id, 'accountant', 'notifications', true, false, true, false, false),

    (v_org_id, 'sales_rep', 'organization', true, false, false, false, false),
    (v_org_id, 'sales_rep', 'notifications', true, false, true, false, false),

    (v_org_id, 'hr_manager', 'organization', true, false, false, false, false),
    (v_org_id, 'hr_manager', 'team', true, false, false, false, false),
    (v_org_id, 'hr_manager', 'notifications', true, false, true, false, false),

    (v_org_id, 'inventory_staff', 'organization', true, false, false, false, false),
    (v_org_id, 'inventory_staff', 'notifications', true, false, true, false, false),

    (v_org_id, 'support_agent', 'organization', true, false, false, false, false),
    (v_org_id, 'support_agent', 'notifications', true, false, true, false, false),

    (v_org_id, 'read_only', 'organization', true, false, false, false, false),
    (v_org_id, 'read_only', 'team', true, false, false, false, false),
    (v_org_id, 'read_only', 'notifications', true, false, true, false, false);

  return query select v_org_id, v_candidate_slug;
end;
$$;

-- Callable directly by any authenticated user via RPC — the function's
-- own auth.uid() check IS the authorization boundary (per its header
-- comment), so no additional grant restriction is needed beyond the
-- standard "authenticated" execute grant.
grant execute on function create_organization_with_owner(text, text, text) to authenticated;
