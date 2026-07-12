/**
 * Shared Tailwind preset — the executable form of design_system.md.
 * Every app extends this preset rather than redefining tokens, so a color
 * or spacing change happens in exactly one place.
 */

/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: "#3730A3",
          hover: "#312E81",
          dark: "#818CF8",
          "dark-hover": "#6366F1",
        },
        accent: {
          DEFAULT: "#059669",
          strong: "#047857", // WCAG AA text-safe variant (5.48:1) — use for small text/labels
          dark: "#34D399",
        },
        warning: {
          DEFAULT: "#D97706",
          strong: "#B45309", // WCAG AA text-safe variant (5.02:1) — use for small text/labels
          dark: "#FBBF24",
        },
        danger: {
          DEFAULT: "#DC2626",
          dark: "#F87171",
        },
        surface: {
          DEFAULT: "#FFFFFF",
          dark: "#111827",
        },
        background: {
          DEFAULT: "#FAFAFA",
          dark: "#0B0F19",
        },
        border: {
          DEFAULT: "#E5E7EB",
          dark: "#1F2937",
        },
        ink: {
          primary: "#111827",
          "primary-dark": "#F9FAFB",
          secondary: "#6B7280",
          "secondary-dark": "#9CA3AF",
        },
      },
      fontFamily: {
        sans: ["var(--font-inter)", "ui-sans-serif", "system-ui", "sans-serif"],
      },
      borderRadius: {
        DEFAULT: "8px",
      },
      spacing: {
        18: "4.5rem",
      },
      transitionDuration: {
        DEFAULT: "180ms",
      },
    },
  },
  plugins: [],
};
