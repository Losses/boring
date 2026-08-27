#!/usr/bin/env bun
/**
 * English documentation style self-check for boring docs.
 *
 * Scans English text files (README, AGENT.md, docs) for vocabulary and
 * rhetorical patterns that the repository style rules ban: metaphor verbs
 * used as technical terms, internet jargon, coined compression words,
 * contrast constructions, and decorative adjectives.
 *
 * Usage:
 *     bun tools/doc-style/check.ts            # scan README.md, AGENT.md, docs/
 *     bun tools/doc-style/check.ts FILE ...   # scan specific files or dirs
 *
 * Exit status: 0 when no hits remain, 1 when hits remain after the allowlist.
 * Each hit is a candidate for manual judgment, not an automatic violation.
 */

import { resolve } from "node:path";
import { Glob } from "bun";

export type WordTag = "metaphor" | "jargon" | "putdown" | "coinage" | "adjective";
export type PatternTag = "contrast" | "em-dash" | "ai-filler";
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

type WithRegex = { readonly regex: RegExp };

type CompiledTerm = BannedTerm & WithRegex;

const REPO_ROOT = resolve(import.meta.dir, "..", "..");

// Metaphor verbs, internet jargon, coined compression words, and decorative
// adjectives named in style corrections. In writing, replace each with a
// plain verb or noun; swapping one metaphor for a near-synonym metaphor is
// not a fix. Single words match with word boundaries and common inflections;
// multi-word entries match as phrases.
const BANNED_TERMS: ReadonlyArray<BannedTerm> = [
  // gate and doorway metaphors
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
  // stuffing and cramming
  { match: "shoehorn", tag: "metaphor" },
  { match: "cram", tag: "metaphor" },
  { match: "stuff", tag: "metaphor" },
  { match: "tuck", tag: "metaphor" },
  { match: "cobble", tag: "metaphor" },
  { match: "duct-tape", tag: "metaphor" },
  { match: "band-aid", tag: "metaphor" },
  // eating
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
  { match: "engine-level", tag: "coinage" },
  { match: "frame-level", tag: "coinage" },
  { match: "byte-level", tag: "coinage" },
  { match: "block-level", tag: "coinage" },
  { match: "glyph-level", tag: "coinage" },
  { match: "field-level", tag: "coinage" },
  { match: "document-level", tag: "coinage" },
  { match: "browser-level", tag: "coinage" },
  { match: "site-level", tag: "coinage" },
  { match: "session-level", tag: "coinage" },
  { match: "process-level", tag: "coinage" },
  { match: "content-level", tag: "coinage" },
  { match: "symbol-level", tag: "coinage" },
  { match: "element-level", tag: "coinage" },
  { match: "paragraph-level", tag: "coinage" },
  { match: "substring-level", tag: "coinage" },
  { match: "character-level", tag: "coinage" },
  { match: "node-level", tag: "coinage" },
  { match: "page-level", tag: "coinage" },
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
// em-dashes, AI filler transitions.
const PATTERNS: ReadonlyArray<StylePattern> = [
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

async function scanMarkdownDir(cwd: string): Promise<string[]> {
  const entries: string[] = [];
  try {
    for await (const entry of new Glob("**/*.md").scan({ cwd, absolute: true })) {
      entries.push(entry);
    }
  } catch {
    console.error(`skip ${cwd}: directory not readable`);
  }
  return entries;
}

async function readTargets(args: ReadonlyArray<string>): Promise<ReadonlyArray<TargetFile>> {
  const targets: string[] = [];
  if (args.length > 0) {
    for (const arg of args) {
      const path = resolve(arg);
      const stat = await Bun.file(path).stat();
      if (stat.isDirectory()) {
        targets.push(...(await scanMarkdownDir(path)));
      } else {
        targets.push(path);
      }
    }
  } else {
    targets.push(resolve(REPO_ROOT, "README.md"));
    targets.push(resolve(REPO_ROOT, "AGENT.md"));
    targets.push(...(await scanMarkdownDir(resolve(REPO_ROOT, "docs"))));
  }
  targets.sort();
  const readable: TargetFile[] = [];
  for (const path of targets) {
    const file = Bun.file(path);
    if (!(await file.exists())) {
      console.error(`skip ${path}: file not found`);
      continue;
    }
    readable.push({ path, text: await file.text() });
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
    for (const hit of scanText(target.text, shownPath(target.path))) {
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
