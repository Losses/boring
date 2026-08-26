import type { TSESTree } from "@typescript-eslint/utils";
import type { BoringRule, VisitNode } from "../rule-types.ts";

type InterfaceMethodsVisitor = {
  TSMethodSignature: VisitNode<TSESTree.TSMethodSignature>;
};

type MethodKey = TSESTree.TSMethodSignature["key"];

function keyName(key: MethodKey): string {
  if (key.type === "Identifier") {
    return key.name;
  }
  if (key.type === "Literal") {
    return String(key.value);
  }
  return "(computed)";
}

/**
 * Bans method signatures inside interfaces. An interface declares data shape
 * only; behavior is expressed as a property whose type is a named function
 * type. Combined with the no-inline-types rule this leaves exactly one form:
 * `run: RunFn` where `RunFn` is a named type alias.
 */
export const noInterfaceMethods: BoringRule<InterfaceMethodsVisitor, "interfaceMethod"> = {
  meta: {
    type: "problem",
    docs: {
      description:
        "Bans method signatures in interfaces; use a property with a named function type.",
    },
    schema: [],
    messages: {
      interfaceMethod:
        "Interfaces must not declare methods. Replace `{{name}}(...)` with a property whose type is a named function type.",
    },
  },
  create(context) {
    return {
      TSMethodSignature(node) {
        context.report({
          node,
          messageId: "interfaceMethod",
          data: { name: keyName(node.key) },
        });
      },
    };
  },
};
