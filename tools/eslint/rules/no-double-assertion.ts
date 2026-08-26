import type { TSESTree } from "@typescript-eslint/utils";
import type { BoringRule, VisitNode } from "../rule-types.ts";

type DoubleAssertionVisitor = {
  TSAsExpression: VisitNode<TSESTree.TSAsExpression>;
  TSTypeAssertion: VisitNode<TSESTree.TSTypeAssertion>;
};

/**
 * Bans chained type assertions: `value as unknown as T`, `value as A as B`,
 * and the angle-bracket form. A double assertion silences the type system
 * instead of convincing it, so the fix belongs in the declarations.
 */
export const noDoubleAssertion: BoringRule<DoubleAssertionVisitor, "doubleAssertion"> = {
  meta: {
    type: "problem",
    docs: {
      description: "Bans chained type assertions such as `as unknown as T`.",
    },
    schema: [],
    messages: {
      doubleAssertion:
        "Chained type assertions (`as X as Y`, including `as unknown as T`) are banned. Fix the declaration or the types instead.",
    },
  },
  create(context) {
    function checkAssertion(
      node: TSESTree.TSAsExpression | TSESTree.TSTypeAssertion,
    ): void {
      const inner = node.expression;
      if (inner.type === "TSAsExpression" || inner.type === "TSTypeAssertion") {
        context.report({ node, messageId: "doubleAssertion" });
      }
    }

    return {
      TSAsExpression: checkAssertion,
      TSTypeAssertion: checkAssertion,
    };
  },
};
