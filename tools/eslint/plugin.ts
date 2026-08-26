import type { RuleDefinition } from "@eslint/core";
import type { ESLint } from "eslint";
import { noDoubleAssertion } from "./rules/no-double-assertion.ts";
import { noEslintDisable } from "./rules/no-eslint-disable.ts";
import { noInlineTypes } from "./rules/no-inline-types.ts";
import { noInterfaceMethods } from "./rules/no-interface-methods.ts";

export type BoringRuleName =
  | "no-double-assertion"
  | "no-eslint-disable"
  | "no-inline-types"
  | "no-interface-methods";

export type BoringRules = Record<BoringRuleName, RuleDefinition>;

export const boringRules: BoringRules = {
  "no-double-assertion": noDoubleAssertion,
  "no-eslint-disable": noEslintDisable,
  "no-inline-types": noInlineTypes,
  "no-interface-methods": noInterfaceMethods,
};

export const boringPlugin: ESLint.Plugin = {
  meta: { name: "boring", version: "0.1.0" },
  rules: boringRules,
};
