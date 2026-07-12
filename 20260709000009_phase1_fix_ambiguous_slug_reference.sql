-- =============================================================================
-- Migration: CRITICAL FIX — ambiguous column reference in
-- create_organization_with_owner
--
-- `returns table (organization_id uuid, slug text)` implicitly declares
-- `slug` as a PL/pgSQL variable in scope for the entire function body.
-- The slug-uniqueness loop's `where slug = v_candidate_slug` is
-- genuinely ambiguous between that variable and the organizations.slug
-- column being queried — Postgres correctly refuses to guess, raising
-- "column reference \"slug\" is ambiguous" on every call. This means
-- EVERY organization-creation attempt would have failed in production;
-- every prior test in this project only exercised the AUTH_REQUIRED
-- rejection path (no authenticated session available), never the actual
-- success path, so this was invisible until execution-tested end to end
-- just now with a simulated authenticated user.
--
-- Fix: qualify the column reference explicitly.
-- =============================================================================

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

  v_base_slug := slugify(p_name);
  if v_base_slug = '' then
    v_base_slug := 'organization';
  end if;
  v_candidate_slug := v_base_slug;

  -- FIX: organizations.slug qualified explicitly — was bare `slug`,
  -- ambiguous with this function's own RETURNS TABLE `slug` output.
  while exists (select 1 from organizations where organizations.slug = v_candidate_slug) loop
    v_suffix := v_suffix + 1;
    v_candidate_slug := v_base_slug || '-' || v_suffix;
  end loop;

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

grant execute on function create_organization_with_owner(text, text, text) to authenticated;
revoke execute on function create_organization_with_owner(text, text, text) from public, anon;
