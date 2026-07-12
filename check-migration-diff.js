#!/usr/bin/env node
/**
 * Fails CI if a migration file that already exists on `main` has been
 * modified. Migrations are append-only (Coding Standards, Section 10;
 * Deployment_Architecture.md, Section 5) — once merged, a migration file
 * is a historical record of what was applied to production and must
 * never change. Fixing a mistake means writing a NEW migration, not
 * editing the old one.
 */
const { execSync } = require("node:child_process");

function sh(cmd) {
  return execSync(cmd, { encoding: "utf-8" }).trim();
}

function main() {
  // On PRs, GITHUB_BASE_REF is the target branch (e.g. "main").
  const baseRef = process.env.GITHUB_BASE_REF ? `origin/${process.env.GITHUB_BASE_REF}` : "origin/main";

  let changedFiles;
  try {
    changedFiles = sh(`git diff --name-only ${baseRef}...HEAD -- supabase/migrations`)
      .split("\n")
      .filter(Boolean);
  } catch {
    console.log("Could not diff against base ref — skipping (likely running on main directly).");
    process.exit(0);
  }

  if (changedFiles.length === 0) {
    console.log("No migration files changed. OK.");
    process.exit(0);
  }

  const violations = [];
  for (const file of changedFiles) {
    let existedBefore;
    try {
      sh(`git cat-file -e ${baseRef}:${file}`);
      existedBefore = true;
    } catch {
      existedBefore = false;
    }
    if (existedBefore) {
      violations.push(file);
    }
  }

  if (violations.length > 0) {
    console.error("\n❌ Migration diff check FAILED.\n");
    console.error("The following migration files already exist on the base branch and were modified:\n");
    violations.forEach((f) => console.error(`  - ${f}`));
    console.error(
      "\nMigrations are append-only. Revert changes to these files and add a NEW migration file instead.\n"
    );
    process.exit(1);
  }

  console.log(`OK — ${changedFiles.length} new migration file(s), no existing migrations modified.`);
  process.exit(0);
}

main();
