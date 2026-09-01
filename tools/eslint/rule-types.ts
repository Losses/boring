import type { RuleDefinition, RuleDefinitionTypeOptions, TextSourceCode } from "@eslint/core";

/** Half-open byte range of a node or token. */
export type ByteRange = [number, number];

/**
 * A collected comment as eslint hands it to rules: kind, text, and byte
 * range. Location data is present at runtime and used by report.
 */
export type CommentToken = {
  readonly type: string;
  readonly value: string;
  readonly range: ByteRange;
};

/** Reader for the comment augmentation below. */
export type CommentReader = () => ReadonlyArray<CommentToken>;

declare module "@eslint/core" {
  interface TextSourceCode {
    // eslint's runtime text source code exposes collected comments through
    // getAllComments(); @eslint/core 1.2.1 omits this member.
    getAllComments: CommentReader;
  }
}

/**
 * A visitor callback for one syntax kind. Declared once so every rule names
 * its visitor entries with the named function type.
 */
export type VisitNode<Node> = (node: Node) => void;

/**
 * The fields each rule customizes on top of RuleDefinitionTypeOptions.
 * Kept as a named type so the RuleDefinition instantiation below passes only
 * named references as type arguments. Code narrows to TextSourceCode: every
 * file this plugin lints is text.
 */
export type RuleOverrides<Visitor, MessageIds extends string> = {
  Code: TextSourceCode;
  Visitor: Visitor;
  MessageIds: MessageIds;
};

/**
 * Rule shape typed against @eslint/core. ESLint 10 types plugin rules with
 * RuleDefinition, whose context is leaner than the typescript-eslint rule
 * module context, so rules written against the core shape assign into the
 * plugin record without a boundary cast.
 */
export type BoringRule<Visitor, MessageIds extends string> = RuleDefinition<
  RuleDefinitionTypeOptions & RuleOverrides<Visitor, MessageIds>
>;
