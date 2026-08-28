import type { TSESTree } from "@typescript-eslint/utils";
import type { BoringRule, VisitNode } from "../rule-types.ts";

type FunctionalIterationVisitor = {
  CallExpression: VisitNode<TSESTree.CallExpression>;
};

/**
 * Method names whose call form hands a callback to the receiver, per the
 * banned-construct list of docs/specs/features/09-iterators.md. Sorting has
 * its own exit through the sort runtime of features/17.
 */
const BANNED_METHODS: ReadonlyArray<string> = [
  "map",
  "filter",
  "reduce",
  "forEach",
  "flatMap",
  "find",
  "some",
  "every",
  "fold",
  "sortedBy",
];

/**
 * The sort runtime module of docs/specs/features/17-sorting.md. Its decorated
 * fallback holds the one sanctioned comparator closure; everywhere else a
 * comparator `sort` is the banned closure form.
 */
const SORT_RUNTIME_SUFFIX = "reference/ts/src/vector-sort.ts";

/**
 * Bans array iteration methods that dispatch through a callback and comparator
 * `sort`, per docs/specs/features/09-iterators.md. Every such call site
 * rewrites to a plain index loop before reaching generated output. Comparator
 * `sort` inside the sort runtime module is the features/17 exit and stays
 * allowed there.
 */
export const noFunctionalIteration: BoringRule<
  FunctionalIterationVisitor,
  "functionalIteration"
> = {
  meta: {
    type: "problem",
    docs: {
      description:
        "Bans callback-driven array iteration methods and comparator sort; iteration is an index loop.",
    },
    schema: [],
    messages: {
      functionalIteration:
        "`.{{name}}` iterates through a callback; rewrite to an index loop per docs/specs/features/09-iterators.md.",
    },
  },
  create(context) {
    const inSortRuntime = (context.filename ?? "").endsWith(SORT_RUNTIME_SUFFIX);
    const inGenerated = (context.filename ?? "").includes("reference/ts/gen/");
    function check(node: TSESTree.CallExpression): void {
      const callee = node.callee;
      if (callee.type !== "MemberExpression") {
        return;
      }
      const property = callee.property;
      if (property.type !== "Identifier") {
        return;
      }
      const name = property.name;
      // A comparator argument is the closure form; the bare `sort()` call
      // delegates to the platform default and stays outside this rule.
      // Generated tree is sanctioned for sortedBy per features/17 rule 6.
      const comparatorSort = name === "sort" && node.arguments.length > 0;
      if (comparatorSort && (inSortRuntime || inGenerated)) {
        return;
      }
      if (comparatorSort || BANNED_METHODS.includes(name)) {
        context.report({
          node,
          messageId: "functionalIteration",
          data: { name },
        });
      }
    }

    return {
      CallExpression: check,
    };
  },
};
