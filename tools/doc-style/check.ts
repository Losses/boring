#!/usr/bin/env bun
/**
 * English wording self-check for boring documents and source comments.
 *
 * Scans Markdown and comments in supported source files for vocabulary and
 * rhetorical patterns that the repository style rules ban: metaphor verbs,
 * internet jargon, coined compression words, contrast constructions, and
 * decorative adjectives.
 *
 * Usage:
 *     bun tools/doc-style/check.ts            # scan documents and comments
 *     bun tools/doc-style/check.ts FILE ...   # scan specific files or dirs
 *
 * Exit status: 0 when no hits remain, 1 when hits remain after the allowlist.
 * Each hit is a candidate that requires manual judgment and may be accepted.
 */

import { extname, relative, resolve } from "node:path";
import { Glob } from "bun";

export type WordTag = "metaphor" | "jargon" | "putdown" | "coinage" | "adjective";
export type PatternTag = "contrast" | "em-dash" | "ai-filler" | "coinage";
export type StyleTag = WordTag | PatternTag;

export type BannedTerm = {
  readonly match: string;
  readonly tag: WordTag;
};

export type StylePattern = {
  readonly regex: RegExp;
  readonly tag: PatternTag;
};

export type StyleHit = {
  readonly file: string;
  readonly line: number;
  readonly tag: StyleTag;
  readonly token: string;
  readonly text: string;
};

export type TargetFile = {
  readonly path: string;
  readonly text: string;
};

type CommentSyntax = {
  readonly block: boolean;
  readonly hash: boolean;
  readonly line: boolean;
  readonly nestedBlock: boolean;
  readonly nixMultiline: boolean;
  readonly rawRust: boolean;
  readonly rawSwift: boolean;
  readonly template: boolean;
  readonly triple: boolean;
};

type WithRegex = { readonly regex: RegExp };

type CompiledTerm = BannedTerm & WithRegex;

const REPO_ROOT = resolve(import.meta.dir, "..", "..");

const MARKDOWN_EXTENSION = ".md";
const SOURCE_EXTENSIONS: ReadonlySet<string> = new Set([
  ".dart",
  ".hxml",
  ".hx",
  ".kt",
  ".nix",
  ".rs",
  ".sh",
  ".swift",
  ".toml",
  ".ts",
]);
const TARGET_GLOB = "**/*.{dart,hxml,hx,kt,md,nix,rs,sh,swift,toml,ts}";
const EXCLUDED_PARTS: ReadonlySet<string> = new Set([
  ".git",
  "gen",
  "gen-tests",
  "node_modules",
  "out",
  "target",
]);

function commentSyntax(extension: string): CommentSyntax | undefined {
  if ([".hx", ".ts", ".rs", ".kt", ".swift", ".dart"].includes(extension)) {
    return {
      block: true,
      hash: false,
      line: true,
      nestedBlock: extension !== ".ts",
      nixMultiline: false,
      rawRust: extension === ".rs",
      rawSwift: extension === ".swift",
      template: extension === ".ts",
      triple: [".kt", ".swift", ".dart"].includes(extension),
    };
  }
  if (extension === ".nix") {
    return {
      block: true,
      hash: true,
      line: false,
      nestedBlock: true,
      nixMultiline: true,
      rawRust: false,
      rawSwift: false,
      template: false,
      triple: true,
    };
  }
  if ([".hxml", ".sh", ".toml"].includes(extension)) {
    return {
      block: false,
      hash: true,
      line: false,
      nestedBlock: false,
      nixMultiline: false,
      rawRust: false,
      rawSwift: false,
      template: false,
      triple: false,
    };
  }
  return undefined;
}

// Metaphor verbs, internet jargon, coined compression words, and decorative
// adjectives named in style corrections. In writing, replace each with a
// plain verb or noun; swapping one metaphor for a near-synonym metaphor is
// not a fix. Single words match with word boundaries and common inflections;
// multi-word entries match as phrases.
const BANNED_TERMS: ReadonlyArray<BannedTerm> = [
  // real-world words stretched into project vocabulary
  { match: "corpus", tag: "coinage" },
  { match: "corpora", tag: "coinage" },
  { match: "surface", tag: "coinage" },
  { match: "battery", tag: "coinage" },
  { match: "mutation probe", tag: "coinage" },
  { match: "prose style", tag: "coinage" },
  // access-control metaphors
  { match: "gatekeep", tag: "metaphor" },
  { match: "gatekeeper", tag: "metaphor" },
  { match: "doorway", tag: "metaphor" },
  // bookkeeping and finance metaphors
  { match: "close the loop", tag: "metaphor" },
  { match: "closing the loop", tag: "metaphor" },
  { match: "pay off", tag: "metaphor" },
  { match: "pays off", tag: "metaphor" },
  { match: "paid off", tag: "metaphor" },
  { match: "pay down", tag: "metaphor" },
  // pinning, locking, and baking
  { match: "nail down", tag: "metaphor" },
  { match: "nailed down", tag: "metaphor" },
  { match: "pin down", tag: "metaphor" },
  { match: "pinned down", tag: "metaphor" },
  { match: "lock in", tag: "metaphor" },
  { match: "locked in", tag: "metaphor" },
  { match: "lock down", tag: "metaphor" },
  { match: "bake in", tag: "metaphor" },
  { match: "baked in", tag: "metaphor" },
  { match: "baking in", tag: "metaphor" },
  { match: "hard-wire", tag: "metaphor" },
  { match: "hardwired", tag: "metaphor" },
  { match: "hard-coded", tag: "metaphor" },
  // forced-containment metaphors
  { match: "shoehorn", tag: "metaphor" },
  { match: "cram", tag: "metaphor" },
  { match: "lane", tag: "metaphor" },
  { match: "prose", tag: "metaphor" },
  { match: "stuff", tag: "metaphor" },
  { match: "tuck", tag: "metaphor" },
  { match: "cobble", tag: "metaphor" },
  { match: "duct-tape", tag: "metaphor" },
  { match: "band-aid", tag: "metaphor" },
  // consumption metaphors
  { match: "eat", tag: "metaphor" },
  { match: "devour", tag: "metaphor" },
  { match: "swallow", tag: "metaphor" },
  // motion, body, and landmark metaphors
  { match: "land", tag: "metaphor" },
  { match: "slim down", tag: "metaphor" },
  { match: "amputate", tag: "metaphor" },
  { match: "halve", tag: "metaphor" },
  { match: "cut in half", tag: "metaphor" },
  { match: "crush", tag: "metaphor" },
  { match: "drown", tag: "metaphor" },
  { match: "bleed", tag: "metaphor" },
  { match: "collapse", tag: "metaphor" },
  { match: "freeze", tag: "metaphor" },
  { match: "unfreeze", tag: "metaphor" },
  { match: "outpost", tag: "metaphor" },
  { match: "north star", tag: "metaphor" },
  { match: "crown jewel", tag: "metaphor" },
  { match: "silver bullet", tag: "metaphor" },
  { match: "holy grail", tag: "metaphor" },
  { match: "secret sauce", tag: "metaphor" },
  { match: "moonshot", tag: "metaphor" },
  // internet jargon and business speak
  { match: "synergy", tag: "jargon" },
  { match: "synergize", tag: "jargon" },
  { match: "leverage", tag: "jargon" },
  { match: "leveraged", tag: "jargon" },
  { match: "leveraging", tag: "jargon" },
  { match: "empower", tag: "jargon" },
  { match: "empowering", tag: "jargon" },
  { match: "streamline", tag: "jargon" },
  { match: "streamlined", tag: "jargon" },
  { match: "unlock", tag: "jargon" },
  { match: "unlocking", tag: "jargon" },
  { match: "align on", tag: "jargon" },
  { match: "circle back", tag: "jargon" },
  { match: "double down", tag: "jargon" },
  { match: "boil the ocean", tag: "jargon" },
  { match: "move the needle", tag: "jargon" },
  { match: "low-hanging", tag: "jargon" },
  { match: "low hanging", tag: "jargon" },
  { match: "quick win", tag: "jargon" },
  { match: "no-brainer", tag: "jargon" },
  { match: "game-changer", tag: "jargon" },
  { match: "game changer", tag: "jargon" },
  { match: "supercharge", tag: "jargon" },
  { match: "turbocharge", tag: "jargon" },
  { match: "deep dive", tag: "jargon" },
  { match: "drill down", tag: "jargon" },
  { match: "peel back", tag: "jargon" },
  { match: "flesh out", tag: "jargon" },
  { match: "fleshed out", tag: "jargon" },
  { match: "beef up", tag: "jargon" },
  { match: "beefed up", tag: "jargon" },
  { match: "level up", tag: "jargon" },
  { match: "operationalize", tag: "jargon" },
  { match: "holistic", tag: "jargon" },
  // coined compression words: judge each line by context
  { match: "zero-drift", tag: "coinage" },
  { match: "zero-diff", tag: "coinage" },
  { match: "zero-change", tag: "coinage" },
  { match: "zero-regression", tag: "coinage" },
  { match: "zero-violation", tag: "coinage" },
  { match: "cold build", tag: "coinage" },
  { match: "hot build", tag: "coinage" },
  { match: "read side", tag: "coinage" },
  { match: "write side", tag: "coinage" },
  { match: "source of truth", tag: "coinage" },
  // putdowns that add no information
  { match: "simply", tag: "putdown" },
  { match: "merely", tag: "putdown" },
  { match: "just", tag: "putdown" },
  { match: "trivial", tag: "putdown" },
  { match: "trivially", tag: "putdown" },
  { match: "obviously", tag: "putdown" },
  { match: "clearly", tag: "putdown" },
  { match: "nothing more than", tag: "putdown" },
  { match: "nothing but", tag: "putdown" },
  // decorative adjectives and vague quantifiers: judge each line by context
  { match: "huge", tag: "adjective" },
  { match: "massive", tag: "adjective" },
  { match: "enormous", tag: "adjective" },
  { match: "giant", tag: "adjective" },
  { match: "vast", tag: "adjective" },
  { match: "elegant", tag: "adjective" },
  { match: "elegantly", tag: "adjective" },
  { match: "beautiful", tag: "adjective" },
  { match: "beautifully", tag: "adjective" },
  { match: "powerful", tag: "adjective" },
  { match: "robust", tag: "adjective" },
  { match: "seamless", tag: "adjective" },
  { match: "seamlessly", tag: "adjective" },
  { match: "effortless", tag: "adjective" },
  { match: "blazing", tag: "adjective" },
  { match: "lightning", tag: "adjective" },
  { match: "drastic", tag: "adjective" },
  { match: "drastically", tag: "adjective" },
  { match: "dramatic", tag: "adjective" },
  { match: "dramatically", tag: "adjective" },
  { match: "significantly", tag: "adjective" },
  { match: "probably", tag: "adjective" },
  { match: "truly", tag: "adjective" },
  { match: "really", tag: "adjective" },
  { match: "genuinely", tag: "adjective" },
  { match: "world-class", tag: "adjective" },
  { match: "best-in-class", tag: "adjective" },
  { match: "best of breed", tag: "adjective" },
  { match: "state-of-the-art", tag: "adjective" },
  { match: "cutting edge", tag: "adjective" },
  { match: "bleeding edge", tag: "adjective" },
];

// Rhetorical sentence patterns: negate-first contrast, intensifiers,
// em-dashes and AI filler transitions. The first entry bans the complete
// hyphenated scope suffix class with one pattern; listing every compound is
// unnecessary. "top-level" is platform vocabulary and stays the single exemption.
const PATTERNS: ReadonlyArray<StylePattern> = [
  { regex: /\b(?!top-levels?\b)[a-z]+-levels?\b/i, tag: "coinage" },
  { regex: /\bnot [^.]{0,60} but\b/i, tag: "contrast" },
  { regex: /,\s+not\s/i, tag: "contrast" },
  { regex: /,\s+but rather\b/i, tag: "contrast" },
  { regex: /,\s+and not\b/i, tag: "contrast" },
  { regex: /\brather than\b/i, tag: "contrast" },
  { regex: /\binstead of\b/i, tag: "contrast" },
  { regex: /\bisn't? [^.]{0,60},?\s*(?:it's|it is)\b/i, tag: "contrast" },
  { regex: /\bis not [^.]{0,60},?\s*(?:it is)\b/i, tag: "contrast" },
  { regex: /—/, tag: "em-dash" },
  { regex: /\bin other words\b/i, tag: "ai-filler" },
  { regex: /\bthat is to say\b/i, tag: "ai-filler" },
  { regex: /\bthis means\b/i, tag: "ai-filler" },
  { regex: /\bwhich means\b/i, tag: "ai-filler" },
  { regex: /\bessentially\b/i, tag: "ai-filler" },
  { regex: /\bbasically\b/i, tag: "ai-filler" },
  { regex: /\bit(?:'s| is) worth (?:noting|mentioning)\b/i, tag: "ai-filler" },
  { regex: /\bput differently\b/i, tag: "ai-filler" },
  { regex: /\bto put it (?:another way|simply)\b/i, tag: "ai-filler" },
  { regex: /\bat the end of the day\b/i, tag: "ai-filler" },
  { regex: /\bin reality\b/i, tag: "ai-filler" },
  { regex: /\bthe reality is\b/i, tag: "ai-filler" },
  { regex: /\bin practice\b/i, tag: "ai-filler" },
  { regex: /\bneedless to say\b/i, tag: "ai-filler" },
  { regex: /\bactually[,:]/i, tag: "ai-filler" },
  { regex: /\bbut actually\b/i, tag: "ai-filler" },
];

// Known accepted uses. A line matching one of these regexes is skipped
// entirely, so keep entries narrow: a line holding both an accepted use and
// a real violation would be missed, and the skip is per line, not per match.
// YOU ARE NOT ALLOWED TO EXPAND THIS LIST WITHOUT CLEAR PERMISSION.
// Object.freeze( is the platform API name quoted in code snippets; the call
// form with the open parenthesis cannot appear in prose metaphor use.
const ALLOW: ReadonlyArray<RegExp> = [/Object\.freeze\(/];

function escapeRegex(term: string): string {
  return term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function compileTerm(term: BannedTerm): RegExp {
  if (term.match.includes(" ")) {
    return new RegExp(escapeRegex(term.match), "i");
  }
  return new RegExp(`\\b${escapeRegex(term.match)}(?:s|es|ed|ing)?\\b`, "i");
}

const COMPILED_TERMS: ReadonlyArray<CompiledTerm> = BANNED_TERMS.map((term) => ({
  ...term,
  regex: compileTerm(term),
}));

export function matchedTerms(line: string): ReadonlyArray<BannedTerm> {
  const matched = COMPILED_TERMS.filter((term) => term.regex.test(line));
  // Drop terms fully contained in a longer matched term on the same line so
  // each line reports the narrowest cause once.
  return matched.filter(
    (term) =>
      !matched.some(
        (other) => other.match !== term.match && other.match.includes(term.match),
      ),
  );
}

function blankText(text: string): string[] {
  return Array.from(text, (character) => (character === "\n" ? "\n" : " "));
}

function rawRustEnd(text: string, index: number): string | undefined {
  const match = /^(?:br|r)(#+)?"/.exec(text.slice(index));
  if (match === null) return undefined;
  return `"${match[1] ?? ""}`;
}

function rawSwiftEnd(text: string, index: number): string | undefined {
  const match = /^(#+)("{1,3})/.exec(text.slice(index));
  if (match === null) return undefined;
  const hashes = match[1];
  const quotes = match[2];
  if (hashes === undefined || quotes === undefined) return undefined;
  return `${quotes}${hashes}`;
}

/**
 * Returns only source comments while preserving every character position and
 * newline. This is a lexer rather than a parser: it recognizes the literal
 * forms that can contain comment markers in the repository's source languages.
 */
export function extractComments(text: string, extension: string): string {
  const syntax = commentSyntax(extension);
  if (syntax === undefined) return blankText(text).join("");

  const output = blankText(text);
  let blockDepth = 0;
  let index = 0;
  let stringEnd: string | undefined;
  let escaped = false;

  while (index < text.length) {
    if (blockDepth > 0) {
      if (syntax.nestedBlock && text.startsWith("/*", index)) {
        output[index] = "/";
        output[index + 1] = "*";
        blockDepth += 1;
        index += 2;
        continue;
      }
      if (text.startsWith("*/", index)) {
        output[index] = "*";
        output[index + 1] = "/";
        blockDepth -= 1;
        index += 2;
        continue;
      }
      output[index] = text[index] ?? " ";
      index += 1;
      continue;
    }

    if (stringEnd !== undefined) {
      if (!escaped && text.startsWith(stringEnd, index)) {
        index += stringEnd.length;
        stringEnd = undefined;
        continue;
      }
      const character = text[index];
      if (stringEnd.length === 1 && character === "\\" && !escaped) {
        escaped = true;
      } else {
        escaped = false;
      }
      index += 1;
      continue;
    }

    if (syntax.line && text.startsWith("//", index)) {
      const end = text.indexOf("\n", index);
      const limit = end < 0 ? text.length : end;
      for (let commentIndex = index; commentIndex < limit; commentIndex += 1) {
        output[commentIndex] = text[commentIndex] ?? " ";
      }
      index = limit;
      continue;
    }
    if (syntax.block && text.startsWith("/*", index)) {
      output[index] = "/";
      output[index + 1] = "*";
      blockDepth = 1;
      index += 2;
      continue;
    }
    if (syntax.hash && text[index] === "#") {
      const previous = index === 0 ? "\n" : text[index - 1];
      const shellComment = extension !== ".sh" || previous === "\n" || /\s/.test(previous ?? "");
      if (!shellComment) {
        index += 1;
        continue;
      }
      const end = text.indexOf("\n", index);
      const limit = end < 0 ? text.length : end;
      for (let commentIndex = index; commentIndex < limit; commentIndex += 1) {
        output[commentIndex] = text[commentIndex] ?? " ";
      }
      index = limit;
      continue;
    }

    const rustEnd = syntax.rawRust ? rawRustEnd(text, index) : undefined;
    if (rustEnd !== undefined) {
      stringEnd = rustEnd;
      index += text[index] === "b" ? rustEnd.length + 2 : rustEnd.length + 1;
      continue;
    }
    const swiftEnd = syntax.rawSwift ? rawSwiftEnd(text, index) : undefined;
    if (swiftEnd !== undefined) {
      stringEnd = swiftEnd;
      index += swiftEnd.length;
      continue;
    }
    if (syntax.nixMultiline && text.startsWith("''", index)) {
      stringEnd = "''";
      index += 2;
      continue;
    }
    if (syntax.triple && (text.startsWith("\"\"\"", index) || text.startsWith("'''", index))) {
      stringEnd = text.slice(index, index + 3);
      index += 3;
      continue;
    }
    const character = text[index];
    const rustLifetime = extension === ".rs"
      && character === "'"
      && /^[A-Za-z_][A-Za-z0-9_]*/.test(text.slice(index + 1));
    if ((character === "\"" || character === "'") && !rustLifetime) {
      stringEnd = character;
      escaped = false;
      index += 1;
      continue;
    }
    if (syntax.template && character === "`") {
      stringEnd = "`";
      escaped = false;
      index += 1;
      continue;
    }
    index += 1;
  }

  return output.join("");
}

export function scanText(text: string, file: string): ReadonlyArray<StyleHit> {
  const hits: StyleHit[] = [];
  const lines = text.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line === undefined) continue;
    if (ALLOW.some((regex) => regex.test(line))) continue;
    const number = index + 1;
    for (const term of matchedTerms(line)) {
      hits.push({
        file,
        line: number,
        tag: term.tag,
        token: term.match,
        text: line.trim(),
      });
    }
    for (const pattern of PATTERNS) {
      if (pattern.regex.test(line)) {
        hits.push({
          file,
          line: number,
          tag: pattern.tag,
          token: pattern.regex.source,
          text: line.trim(),
        });
      }
    }
  }
  return hits;
}

function excludedTarget(path: string): boolean {
  const parts = relative(REPO_ROOT, path).split(/[\\/]/);
  if (parts.some((part) => EXCLUDED_PARTS.has(part))) return true;
  if (parts[0] === "tools" && parts[1] === "unicode-data") return true;
  return parts.some((part) => part.endsWith("-gen"));
}

async function scanTargetDir(cwd: string): Promise<string[]> {
  const entries: string[] = [];
  try {
    for await (const entry of new Glob(TARGET_GLOB).scan({ cwd, absolute: true })) {
      if (!excludedTarget(entry)) entries.push(entry);
    }
  } catch {
    console.error(`skip ${cwd}: directory not readable`);
  }
  return entries;
}

export async function readTargets(args: ReadonlyArray<string>): Promise<ReadonlyArray<TargetFile>> {
  const targets: string[] = [];
  if (args.length > 0) {
    for (const arg of args) {
      const path = resolve(arg);
      const file = Bun.file(path);
      try {
        const stat = await file.stat();
        if (stat.isDirectory()) {
          targets.push(...(await scanTargetDir(path)));
        } else {
          targets.push(path);
        }
      } catch {
        console.error(`skip ${path}: file not found`);
      }
    }
  } else {
    targets.push(...(await scanTargetDir(REPO_ROOT)));
  }
  const readable: TargetFile[] = [];
  for (const path of [...new Set(targets)].sort()) {
    const extension = extname(path);
    if (extension !== MARKDOWN_EXTENSION && !SOURCE_EXTENSIONS.has(extension)) continue;
    readable.push({ path, text: await Bun.file(path).text() });
  }
  return readable;
}

function shownPath(path: string): string {
  const relative = path.startsWith(REPO_ROOT);
  return relative ? path.slice(REPO_ROOT.length + 1) : path;
}

export async function main(args: ReadonlyArray<string>): Promise<number> {
  const hits: StyleHit[] = [];
  for (const target of await readTargets(args)) {
    const extension = extname(target.path);
    const text = extension === MARKDOWN_EXTENSION
      ? target.text
      : extractComments(target.text, extension);
    for (const hit of scanText(text, shownPath(target.path))) {
      hits.push(hit);
    }
  }
  for (const hit of hits) {
    console.log(`${hit.file}:${hit.line}: [${hit.tag}] ${hit.token}: ${hit.text}`);
  }
  console.log();
  console.log(`hits: ${hits.length}.`);
  console.log(
    "This tool is an automated checklist; the word list and sentence patterns are incomplete and grow with each correction.",
  );
  console.log(
    "Each hit is a candidate for manual judgment; rewrite the ones that violate the rules.",
  );
  console.log("Automated checking does not replace reading the final text.");
  return hits.length > 0 ? 1 : 0;
}

if (import.meta.main) {
  process.exit(await main(process.argv.slice(2)));
}
