/**
 * Shared ESLint preset — consumed by every app/package in the monorepo.
 * jsx-a11y is enabled at "error" (not "warn") deliberately: accessibility
 * violations are treated as build-breaking, not advisory, per the
 * Development Principles and Coding Standards documents.
 */
module.exports = {
  root: true,
  extends: [
    "next/core-web-vitals",
    "plugin:@typescript-eslint/recommended",
    "plugin:jsx-a11y/recommended",
    "prettier",
  ],
  plugins: ["@typescript-eslint", "jsx-a11y", "import"],
  parserOptions: {
    ecmaVersion: "latest",
    sourceType: "module",
  },
  rules: {
    // --- Type safety ---
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": [
      "error",
      { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
    ],
    "@typescript-eslint/no-floating-promises": "error",
    "@typescript-eslint/consistent-type-imports": "error",

    // --- Accessibility (error, not warn — see file header) ---
    "jsx-a11y/anchor-is-valid": "error",
    "jsx-a11y/no-autofocus": "warn",
    "jsx-a11y/label-has-associated-control": "error",
    "jsx-a11y/click-events-have-key-events": "error",
    "jsx-a11y/no-static-element-interactions": "error",

    // --- Security-relevant ---
    "no-restricted-imports": [
      "error",
      {
        paths: [
          {
            name: "@/lib/supabase/admin",
            message:
              "The Supabase admin (service-role) client must never be imported outside server-only contexts. If this is a genuine server-only file, add an eslint-disable comment explaining why.",
          },
        ],
      },
    ],

    // --- Consistency ---
    "import/order": [
      "warn",
      {
        groups: ["builtin", "external", "internal", "parent", "sibling", "index"],
        "newlines-between": "always",
        alphabetize: { order: "asc", caseInsensitive: true },
      },
    ],
  },
  overrides: [
    {
      files: ["**/*.test.ts", "**/*.test.tsx"],
      rules: {
        "@typescript-eslint/no-explicit-any": "off",
      },
    },
  ],
};
