import type { BoringRule } from "../rule-types.ts";

type NoVisitor = Record<string, never>;

// Directive shapes covered: whole-file, line, and next-line disable
// comments; enable comments; inline rule overrides. A rule name in an
// inline override may carry a plugin prefix ("boring/rule").
const DIRECTIVE_PATTERN =
  /^\s*eslint-(disable|enable)\b|^\s*eslint\s+[a-z0-9-]+(?:\/[a-z0-9-]+)*\s*:/;

/**
 * Bans every form of inline ESLint directive: disable comments, enable
 * comments, and inline rule overrides. The typing rules of this repository
 * admit no per-file exceptions, so silencing them in place is always wrong;
 * fix the code, or change the rule in eslint.config.ts for every file at
 * once. Runs together with linterOptions.noInlineConfig, which keeps the
 * directives inert; this rule turns their presence into an error.
 */
export const noEslintDisable: BoringRule<NoVisitor, "eslintDisable"> = {
  meta: {
    type: "problem",
    docs: {
      description:
        "Bans eslint-disable comments and inline rule overrides; the typing rules admit no exceptions.",
    },
    schema: [],
    messages: {
      eslintDisable:
        "Inline ESLint directives are banned. Fix the code, or change the rule in eslint.config.ts for every file at once.",
    },
  },
  create(context) {
    for (const comment of context.sourceCode.getAllComments()) {
      if (DIRECTIVE_PATTERN.test(comment.value)) {
        context.report({ node: comment, messageId: "eslintDisable" });
      }
    }
    return {};
  },
};
