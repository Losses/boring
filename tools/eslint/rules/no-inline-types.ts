import type { TSESTree } from "@typescript-eslint/utils";
import type { BoringRule, VisitNode } from "../rule-types.ts";

type InlineTypeNode =
  | TSESTree.TSTypeLiteral
  | TSESTree.TSFunctionType
  | TSESTree.TSMappedType
  | TSESTree.TSTupleType;

type InlineTypesVisitor = {
  TSMappedType: VisitNode<TSESTree.TSMappedType>;
  TSFunctionType: VisitNode<TSESTree.TSFunctionType>;
  TSTupleType: VisitNode<TSESTree.TSTupleType>;
  TSTypeLiteral: VisitNode<TSESTree.TSTypeLiteral>;
};

const KIND_NAMES: Readonly<Record<string, string>> = {
  TSMappedType: "mapped type",
  TSFunctionType: "function type",
  TSTupleType: "tuple type",
  TSTypeLiteral: "object type",
};

function isDirectAliasRhs(node: InlineTypeNode): boolean {
  // typescript-estree normalizes parenthesized types away, so the alias
  // right-hand side is always the direct parent of the inline type node.
  return node.parent !== undefined && node.parent.type === "TSTypeAliasDeclaration";
}

/**
 * Bans every form of inline type: object types, function types, mapped types,
 * and tuple types are only allowed as the direct right-hand side of a type
 * alias. Everywhere else (property annotations, parameters, return types,
 * generic arguments, assertions, variable annotations) the type must be bound
 * to a name first. Unions and intersections of named references stay allowed.
 */
export const noInlineTypes: BoringRule<InlineTypesVisitor, "inlineType"> = {
  meta: {
    type: "problem",
    docs: {
      description:
        "Bans inline object, function, mapped, and tuple types outside of a named type alias.",
    },
    schema: [],
    messages: {
      inlineType:
        "Inline {{kind}} is banned here. Bind it to a name with `type` or `interface` and reference the name at this position.",
    },
  },
  create(context) {
    function check(node: InlineTypeNode): void {
      if (isDirectAliasRhs(node)) return;
      context.report({
        node,
        messageId: "inlineType",
        data: { kind: KIND_NAMES[node.type] ?? "type" },
      });
    }

    return {
      TSMappedType: check,
      TSFunctionType: check,
      TSTupleType: check,
      TSTypeLiteral: check,
    };
  },
};
