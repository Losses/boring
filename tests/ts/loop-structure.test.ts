import { describe, expect, test } from "bun:test";

/**
 * Structure guard for docs/specs/features/09-iterators.md, binding the four
 * codec source trees. Behavior tests cannot see the shape of the code; this
 * scan is what generated output will be held to, so the hand-written trees
 * pass it first:
 *
 *   1. No callback-driven iteration call site exists in any tree.
 *   2. No function expression, arrow function, or lambda appears inside a
 *      `for` or `while` body (matched per language through its lambda token).
 *   3. Every `for (` head under the TypeScript trees binds an index counter:
 *      the head contains no ` of ` and no ` in `, and its condition section
 *      carries no property access, so the bound evaluates per iteration as a
 *      local. The init section may declare the hoisted bound next to the
 *      counter (`let i = 0, count = xs.length`), which reads the property
 *      once; that is the hoist, not a per-iteration read.
 */

interface SourceTree {
  readonly label: string;
  readonly directory: string;
  readonly pattern: string;
  /** Tokens whose presence inside a loop body marks a closure. */
  readonly lambdaTokens: readonly string[];
  /** True to run the ts-specific for-head checks on this tree. */
  readonly checkForHeads: boolean;
}

const SOURCE_TREES: readonly SourceTree[] = [
  {
    label: "ts/src",
    directory: import.meta.dir + "/../../ts/src",
    pattern: "**/*.ts",
    lambdaTokens: ["=>"],
    checkForHeads: true,
  },
  {
    label: "ts/gen",
    directory: import.meta.dir + "/../../ts/gen",
    pattern: "**/*.ts",
    lambdaTokens: ["=>"],
    checkForHeads: true,
  },
  {
    label: "haxe/src",
    directory: import.meta.dir + "/../../haxe/src",
    pattern: "**/*.hx",
    lambdaTokens: ["->", "function"],
    checkForHeads: false,
  },
  {
    label: "rust/src",
    directory: import.meta.dir + "/../../rust/src",
    pattern: "**/*.rs",
    lambdaTokens: ["|"],
    checkForHeads: false,
  },
  {
    label: "rust-gen/src",
    directory: import.meta.dir + "/../../rust-gen/src",
    pattern: "**/*.rs",
    lambdaTokens: ["|"],
    checkForHeads: false,
  },
  {
    label: "kotlin/src",
    directory: import.meta.dir + "/../../kotlin/src",
    pattern: "**/*.kt",
    lambdaTokens: ["->", "{ it"],
    checkForHeads: false,
  },
];

const BANNED_CALL_SITES: readonly string[] = [
  ".map(",
  ".filter(",
  ".reduce(",
  ".forEach(",
  ".flatMap(",
  ".some(",
  ".every(",
  ".fold(",
  ".sortedBy(",
];

/** Matches `||` but not a lone Rust closure pipe. */
function containsClosurePipe(body: string): boolean {
  for (let i = 0; i < body.length; i += 1) {
    if (body[i] !== "|") {
      continue;
    }
    const before = body[i - 1];
    const after = body[i + 1];
    if (before !== "|" && after !== "|") {
      return true;
    }
  }
  return false;
}

function bodyHasLambda(tree: SourceTree, body: string): boolean {
  if (tree.label === "rust/src") {
    return containsClosurePipe(body);
  }
  for (const token of tree.lambdaTokens) {
    if (body.includes(token)) {
      return true;
    }
  }
  return false;
}

interface LoopHit {
  readonly kind: "call-site" | "loop-lambda" | "for-head";
  readonly file: string;
  readonly line: number;
  readonly detail: string;
}

function lineOfOffset(text: string, offset: number): number {
  let line = 1;
  for (let i = 0; i < offset; i += 1) {
    if (text[i] === "\n") {
      line += 1;
    }
  }
  return line;
}

/**
 * Blanks line and block comments with spaces, keeping newlines, so the word
 * `for` inside a doc comment never reads as a loop head. Offsets and line
 * numbers are preserved.
 */
function stripComments(text: string): string {
  const chars: string[] = text.split("");
  let mode: "none" | "line" | "block" = "none";
  let i = 0;
  while (i < text.length) {
    const two = text.slice(i, i + 2);
    if (mode === "none") {
      if (two === "//" || two === "/*") {
        mode = two === "//" ? "line" : "block";
        chars[i] = " ";
        chars[i + 1] = " ";
        i += 2;
        continue;
      }
      i += 1;
      continue;
    }
    if (mode === "line") {
      if (text[i] === "\n") {
        mode = "none";
      } else {
        chars[i] = " ";
      }
      i += 1;
      continue;
    }
    if (two === "*/") {
      chars[i] = " ";
      chars[i + 1] = " ";
      mode = "none";
      i += 2;
      continue;
    }
    if (text[i] !== "\n") {
      chars[i] = " ";
    }
    i += 1;
  }
  return chars.join("");
}

/** A loop body together with the offset of its opening brace. */
interface LoopBody {
  readonly body: string;
  readonly offset: number;
}

/**
 * Extracts every `for`/`while` body: finds the head keyword, skips to the
 * head's opening brace, and brace-matches to its close. Rust `for` heads
 * carry no parentheses; the others do.
 */
function loopBodies(text: string): LoopBody[] {
  const bodies: LoopBody[] = [];
  const headPattern = /\b(?:for|while)\b/g;
  let match: RegExpExecArray | null;
  while ((match = headPattern.exec(text)) !== null) {
    const start = match.index;
    const brace = text.indexOf("{", start);
    if (brace === -1) {
      continue;
    }
    // The brace belongs to this head only if no statement separator or `;`
    // intervenes; otherwise the head is malformed for this scanner and the
    // body check skips it (the language's own compiler still rejects it).
    const headSlice = text.slice(start, brace);
    if (headSlice.includes(";") && !headSlice.includes("(")) {
      continue;
    }
    let depth = 0;
    let end = -1;
    for (let i = brace; i < text.length; i += 1) {
      const ch = text[i];
      if (ch === "{") {
        depth += 1;
      } else if (ch === "}") {
        depth -= 1;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }
    if (end === -1) {
      continue;
    }
    bodies.push({ body: text.slice(brace + 1, end), offset: brace });
    headPattern.lastIndex = end;
  }
  return bodies;
}

/**
 * Returns the condition (middle) section of a classic `for` head. The init
 * section may declare a hoisted bound, so property reads there are legal;
 * the condition is what evaluates every iteration.
 */
function conditionSection(head: string): string {
  const sections = head.split(";");
  return sections.length === 3 ? sections[1]! : head;
}

/** Returns the text between the parentheses of a `for (` head. */
function forHeadText(text: string, headStart: number): string | undefined {
  const open = text.indexOf("(", headStart);
  if (open === -1) {
    return undefined;
  }
  let depth = 0;
  for (let i = open; i < text.length; i += 1) {
    const ch = text[i]!;
    if (ch === "(") {
      depth += 1;
    } else if (ch === ")") {
      depth -= 1;
      if (depth === 0) {
        return text.slice(open + 1, i);
      }
    }
  }
  return undefined;
}

async function scanTree(tree: SourceTree): Promise<LoopHit[]> {
  const hits: LoopHit[] = [];
  const paths: string[] = [];
  for await (const entry of new Bun.Glob(tree.pattern).scan({ cwd: tree.directory })) {
    paths.push(`${tree.directory}/${entry}`);
  }
  for (const path of paths) {
    const text = stripComments(await Bun.file(path).text());
    for (const site of BANNED_CALL_SITES) {
      if (text.includes(site)) {
        hits.push({ kind: "call-site", file: path, line: 0, detail: site });
      }
    }
    for (const loop of loopBodies(text)) {
      if (bodyHasLambda(tree, loop.body)) {
        hits.push({
          kind: "loop-lambda",
          file: path,
          line: lineOfOffset(text, loop.offset),
          detail: "closure inside a loop body",
        });
      }
    }
    if (tree.checkForHeads) {
      const headPattern = /\bfor\s*\(/g;
      let match: RegExpExecArray | null;
      while ((match = headPattern.exec(text)) !== null) {
        const head = forHeadText(text, match.index);
        if (head === undefined) {
          continue;
        }
        const line = lineOfOffset(text, match.index);
        if (head.includes(" of ") || head.includes(" in ")) {
          hits.push({
            kind: "for-head",
            file: path,
            line,
            detail: `head iterates instead of indexing: for (${head.trim()})`,
          });
        } else if (conditionSection(head).includes(".")) {
          hits.push({
            kind: "for-head",
            file: path,
            line,
            detail: `condition reads a property; hoist the bound: for (${head.trim()})`,
          });
        }
      }
    }
  }
  return hits;
}

describe("loop structure", () => {
  for (const tree of SOURCE_TREES) {
    test(`${tree.label} carries no functional iteration, loop closures, or unhoisted bounds`, async () => {
      const hits = await scanTree(tree);
      expect(hits).toEqual([]);
    });
  }
});
