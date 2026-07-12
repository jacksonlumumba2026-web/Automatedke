# Automated KE 2.0

Business automation platform for Kenyan and African SMEs. See `/docs` for the full product blueprint and engineering reference documents.

## Prerequisites
- Node.js ≥ 20.11
- pnpm ≥ 9
- [Supabase CLI](https://supabase.com/docs/guides/cli) (`brew install supabase/tap/supabase` or equivalent)
- Docker (required by the Supabase CLI for local development)

## Getting Started

```bash
pnpm install
cp .env.example apps/web/.env.local   # fill in local Supabase values below
supabase start                        # spins up local Postgres, Auth, Studio
supabase db reset                     # applies all migrations in supabase/migrations
pnpm db:types                         # generates packages/types/database.types.ts
pnpm dev                              # starts apps/web at localhost:3000
```

`supabase start` prints local API URL and anon key — put these in `apps/web/.env.local` as `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY`.

## Monorepo Layout

```
apps/web         Next.js application
packages/config   Shared ESLint, TypeScript, and Tailwind configuration
packages/types    Generated Supabase types (do not hand-edit)
supabase/         Migrations and local Supabase config
docs/             Blueprint and engineering reference documents
```

## Common Commands

| Command | Purpose |
|---|---|
| `pnpm dev` | Run the web app locally |
| `pnpm lint` | Lint all packages |
| `pnpm typecheck` | Typecheck all packages |
| `pnpm test` | Run all tests |
| `pnpm db:types` | Regenerate types from the local Supabase schema |
| `pnpm db:migrate:local` | Reset local DB and reapply all migrations |

## Before Committing

`husky` + `lint-staged` run automatically on commit (lint + format on staged files). CI additionally runs the full lint/typecheck/test suite and a migration-diff check on every pull request — see `.github/workflows/ci.yml` and `Deployment_Architecture.md`.

## Engineering Reference

All architecture, schema, security, and standards documents referenced throughout this codebase live in `/docs` and are the source of truth for any implementation decision not obvious from the code itself.
