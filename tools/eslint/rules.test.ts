import { describe, expect, test } from "bun:test";
import tsParser from "@typescript-eslint/parser";
import { Linter } from "eslint";
import { boringPlugin } from "./plugin.ts";

interface LintHit {
  messageId: string | undefined;
  line: number;
  column: number;
}

const RULE_SET: Record<string, "error"> = {
  "boring/no-double-assertion": "error",
  "boring/no-eslint-disable": "error",
  "boring/no-functional-iteration": "error",
  "boring/no-inline-types": "error",
  "boring/no-interface-methods": "error",
};

function lintTypescript(code: string): LintHit[] {
  const linter = new Linter();
  const messages = linter.verify(code, [
    {
      plugins: { boring: boringPlugin },
      // Directives stay inert (as in the repository config) so a directive
      // cannot silence the rule that flags it, and bookkeeping messages
      // from the linter itself stay out of the assertions.
      linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: "off" },
      languageOptions: {
        parser: tsParser,
        ecmaVersion: "latest",
        sourceType: "module",
      },
      rules: RULE_SET,
    },
  ]);
  return messages
    .filter((message) => message.ruleId !== null)
    .map((message) => ({
      messageId: message.messageId,
      line: message.line,
      column: message.column,
    }));
}

describe("boring/no-double-assertion", () => {
  test("flags `as unknown as` chains", () => {
    expect(lintTypescript("const x = y as unknown as Foo;")).toEqual([
      { messageId: "doubleAssertion", line: 1, column: 11 },
    ]);
  });

  test("flags angle-bracket chains", () => {
    expect(lintTypescript("const x = <Foo>(<unknown>y);")).toEqual([
      { messageId: "doubleAssertion", line: 1, column: 11 },
    ]);
  });

  test("allows a single assertion", () => {
    expect(lintTypescript("const x = y as Foo;")).toEqual([]);
  });
});

describe("boring/no-inline-types", () => {
  test("flags inline object types in interfaces", () => {
    expect(lintTypescript("interface A { p: { x: number } }")).toEqual([
      { messageId: "inlineType", line: 1, column: 18 },
    ]);
  });

  test("flags inline object types in parameters", () => {
    expect(lintTypescript("function f(o: { a: number }) {}")).toEqual([
      { messageId: "inlineType", line: 1, column: 15 },
    ]);
  });

  test("flags inline types inside generic arguments", () => {
    expect(lintTypescript("const m = new Map<string, { v: number }>();")).toEqual([
      { messageId: "inlineType", line: 1, column: 27 },
    ]);
  });

  test("flags inline tuple types", () => {
    expect(lintTypescript("function t(): [number, number] { return [1, 2]; }")).toEqual([
      { messageId: "inlineType", line: 1, column: 15 },
    ]);
  });

  test("flags inline function types", () => {
    expect(lintTypescript("const cb: (e: number) => void = (e) => {};")).toEqual([
      { messageId: "inlineType", line: 1, column: 11 },
    ]);
  });

  test("allows the direct right-hand side of a type alias", () => {
    expect(lintTypescript("type Point = { x: number };\ninterface B { p: Point }")).toEqual([]);
  });

  test("allows unions of named references", () => {
    expect(lintTypescript("type N = number | string;")).toEqual([]);
  });
});

describe("boring/no-interface-methods", () => {
  test("flags method signatures in interfaces", () => {
    expect(lintTypescript("interface C { run(): void }")).toEqual([
      { messageId: "interfaceMethod", line: 1, column: 15 },
    ]);
  });

  test("allows a property with a named function type", () => {
    expect(
      lintTypescript("type RunFn = (e: number) => void;\ninterface D { run: RunFn }"),
    ).toEqual([]);
  });
});

describe("boring/no-eslint-disable", () => {
  test("flags eslint-disable-next-line comments", () => {
    expect(
      lintTypescript("// eslint-disable-next-line boring/no-inline-types\nconst a = 1;\n"),
    ).toEqual([{ messageId: "eslintDisable", line: 1, column: 1 }]);
  });

  test("flags eslint-disable-line comments", () => {
    expect(lintTypescript("const a = 1; // eslint-disable-line\n")).toEqual([
      { messageId: "eslintDisable", line: 1, column: 14 },
    ]);
  });

  test("flags block disable and enable pairs", () => {
    expect(
      lintTypescript("/* eslint-disable */\nconst a = 1;\n/* eslint-enable */\n"),
    ).toEqual([
      { messageId: "eslintDisable", line: 1, column: 1 },
      { messageId: "eslintDisable", line: 3, column: 1 },
    ]);
  });

  test("flags inline rule overrides", () => {
    expect(
      lintTypescript('/* eslint boring/no-inline-types: "off" */\nconst a = 1;\n'),
    ).toEqual([{ messageId: "eslintDisable", line: 1, column: 1 }]);
  });

  test("leaves ordinary comments alone", () => {
    expect(lintTypescript("// reads the vector file\nconst a = 1;\n")).toEqual([]);
  });
});

describe("boring/no-functional-iteration", () => {
  test("flags callback iteration methods", () => {
    expect(lintTypescript("const d = records.map(toRecord);")).toEqual([
      { messageId: "functionalIteration", line: 1, column: 11 },
    ]);
    expect(lintTypescript("const f = xs.filter(ok);")).toEqual([
      { messageId: "functionalIteration", line: 1, column: 11 },
    ]);
  });

  test("flags comparator sort and leaves the bare call alone", () => {
    expect(lintTypescript("xs.sort(byKey);")).toEqual([
      { messageId: "functionalIteration", line: 1, column: 1 },
    ]);
    expect(lintTypescript("xs.sort();")).toEqual([]);
  });

  test("leaves plain calls and property reads alone", () => {
    expect(lintTypescript("const n = xs.length;")).toEqual([]);
    expect(lintTypescript("const m = xs.map;")).toEqual([]);
    expect(lintTypescript("run(records);")).toEqual([]);
  });
});
