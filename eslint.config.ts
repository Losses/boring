import js from "@eslint/js";
import tseslint from "typescript-eslint";
import { boringPlugin } from "./tools/eslint/plugin.ts";

export default tseslint.config(
  {
    ignores: [
      "node_modules/**",
      "out/**",
      "rust/**",
      "tests/vectors/**",
      "bun.lock",
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.ts"],
    plugins: { boring: boringPlugin },
    // Inline eslint-disable comments and inline rule overrides are banned
    // with no exceptions; every directive reports as an error.
    linterOptions: {
      noInlineConfig: true,
      reportUnusedDisableDirectives: "error",
    },
    languageOptions: {
      parserOptions: {
        sourceType: "module",
        ecmaVersion: "latest",
      },
    },
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unsafe-function-type": "error",
      "@typescript-eslint/no-empty-object-type": "error",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      "boring/no-double-assertion": "error",
      "boring/no-eslint-disable": "error",
      "boring/no-inline-types": "error",
      "boring/no-interface-methods": "error",
    },
  },
  {
    // The callback-iteration ban binds the package source: tests and tools
    // may use any form, ts/src is the shape generated output must match.
    files: ["ts/src/**/*.ts"],
    rules: {
      "boring/no-functional-iteration": "error",
    },
  },
);
