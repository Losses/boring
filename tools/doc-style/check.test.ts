import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  extractComments,
  matchedTerms,
  readTargets,
  scanText,
} from "./check.ts";

const temporaryPaths: string[] = [];

afterEach(() => {
  for (const path of temporaryPaths.splice(0)) rmSync(path, { force: true, recursive: true });
});

describe("matchedTerms", () => {
  test("detects metaphor verbs with word boundaries and inflections", () => {
    const hits = matchedTerms("The codec shoehorns the header into the record.");
    expect(hits.map((hit) => hit.match)).toEqual(["shoehorn"]);
  });

  test("reports the narrowest term when two entries match one word", () => {
    const hits = matchedTerms("The cache sits before decoding, unlocking the fast path.");
    expect(hits.map((hit) => hit.match)).toEqual(["unlocking"]);
  });

  test("keeps plain engineering vocabulary out of the hits", () => {
    const hits = matchedTerms("The decoder reads the record and returns six fields.");
    expect(hits).toEqual([]);
  });

  test("flags putdown wording", () => {
    const hits = matchedTerms("You just need to call decode before reading.");
    expect(hits.map((hit) => hit.match)).toEqual(["just"]);
  });

  test("flags prose style as coined wording", () => {
    const hits = matchedTerms("The prose style checker reads this sentence.");
    expect(hits.map((hit) => hit.match)).toEqual(["prose style"]);
  });
});

describe("scanText", () => {
  test("reports file, line number, tag, and trimmed text", () => {
    const hits = scanText(
      "The first line holds no violation.\nThe codec crams the fields into the tail.\n",
      "fixture.md",
    );
    expect(hits.length).toBe(1);
    const hit = hits[0];
    if (hit === undefined) throw new Error("expected one hit");
    expect(hit.file).toBe("fixture.md");
    expect(hit.line).toBe(2);
    expect(hit.tag).toBe("metaphor");
    expect(hit.token).toBe("cram");
    expect(hit.text).toBe("The codec crams the fields into the tail.");
  });

  test("detects negate-first contrast constructions", () => {
    const hits = scanText("This is not a cache but a queue.\n", "fixture.md");
    expect(hits.map((hit) => hit.tag)).toEqual(["contrast"]);
  });

  test("detects em-dashes", () => {
    const hits = scanText("The codec—despite the name—is small.\n", "fixture.md");
    expect(hits.map((hit) => hit.tag)).toEqual(["em-dash"]);
  });

  test("detects filler transitions", () => {
    const hits = scanText("In other words, the record is 44 bytes.\n", "fixture.md");
    expect(hits.map((hit) => hit.tag)).toEqual(["ai-filler"]);
  });

  test("flags every X-level coinage through the suffix pattern", () => {
    const hits = scanText("The decoder keeps frame-level state in a table.\n", "fixture.md");
    expect(hits.map((hit) => hit.tag)).toEqual(["coinage"]);
  });

  test("keeps the platform term top-level out of the hits", () => {
    const hits = scanText(
      "Dart emits the function as a top-level declaration, so top-level calls stay direct.\n",
      "fixture.md",
    );
    expect(hits).toEqual([]);
  });

  test("returns no hits for compliant text", () => {
    const hits = scanText(
      "The record is 44 bytes and holds one code point with five measured values.\n",
      "fixture.md",
    );
    expect(hits).toEqual([]);
  });
});

describe("extractComments", () => {
  test("keeps C-style comments and their original line numbers", () => {
    const source = [
      'const message = "The codec crams fields.";',
      "// The decoder reads fields.",
      "/* The codec crams",
      " * fields into the tail. */",
    ].join("\n");
    const hits = scanText(extractComments(source, ".ts"), "fixture.ts");
    expect(hits.map((hit) => [hit.line, hit.token])).toEqual([[3, "cram"]]);
  });

  test("keeps nested block comments", () => {
    const source = "/* Outer text. /* The codec crams fields. */ End. */";
    const hits = scanText(extractComments(source, ".rs"), "fixture.rs");
    expect(hits.map((hit) => hit.token)).toEqual(["cram"]);
  });

  test("does not nest TypeScript block comments", () => {
    const source = "/* Marker text: /*. */\n// The codec crams fields.";
    const hits = scanText(extractComments(source, ".ts"), "fixture.ts");
    expect(hits.map((hit) => [hit.line, hit.token])).toEqual([[2, "cram"]]);
  });

  test("keeps comments after Rust lifetimes", () => {
    const source = "fn read<'a>(value: &'a str) {}\n// The codec crams fields.";
    const hits = scanText(extractComments(source, ".rs"), "fixture.rs");
    expect(hits.map((hit) => [hit.line, hit.token])).toEqual([[2, "cram"]]);
  });

  test("skips TypeScript templates and escaped strings", () => {
    const source = [
      "const template = `// The codec crams fields.`;",
      'const quoted = "/* The codec crams fields. */";',
      "// The decoder returns fields.",
    ].join("\n");
    expect(scanText(extractComments(source, ".ts"), "fixture.ts")).toEqual([]);
  });

  test("skips Rust raw strings", () => {
    const source = [
      'let text = r#"// The codec crams fields."#;',
      'let bytes = br##"/* The codec crams fields. */"##;',
      "//! The decoder returns fields.",
    ].join("\n");
    expect(scanText(extractComments(source, ".rs"), "fixture.rs")).toEqual([]);
  });

  test("skips Kotlin, Swift, and Dart multiline strings", () => {
    const source = '"""\n// The codec crams fields.\n"""\n// The decoder returns fields.';
    for (const extension of [".kt", ".swift", ".dart"]) {
      expect(scanText(extractComments(source, extension), `fixture${extension}`)).toEqual([]);
    }
  });

  test("skips Swift extended strings", () => {
    const source = '#"// The codec crams fields."#\n// The decoder returns fields.';
    expect(scanText(extractComments(source, ".swift"), "fixture.swift")).toEqual([]);
  });

  test("handles Nix strings and hash comments", () => {
    const source = [
      'value = "# The codec crams fields.";',
      "other = ''# The codec crams fields.'';",
      "# The codec crams fields.",
    ].join("\n");
    const hits = scanText(extractComments(source, ".nix"), "fixture.nix");
    expect(hits.map((hit) => [hit.line, hit.token])).toEqual([[3, "cram"]]);
  });

  test("does not treat a shell parameter operator as a comment", () => {
    const source = 'value=${name#prefix}\n# The codec crams fields.';
    const hits = scanText(extractComments(source, ".sh"), "fixture.sh");
    expect(hits.map((hit) => [hit.line, hit.token])).toEqual([[2, "cram"]]);
  });
});

describe("readTargets", () => {
  test("finds documents and source files while excluding generated trees", async () => {
    const root = mkdtempSync(resolve(import.meta.dir, ".check-fixture-"));
    temporaryPaths.push(root);
    mkdirSync(resolve(root, "src"));
    mkdirSync(resolve(root, "gen"));
    writeFileSync(resolve(root, "guide.md"), "Plain text.\n");
    writeFileSync(resolve(root, "src", "main.hx"), "// Plain comment.\n");
    writeFileSync(resolve(root, "src", "data.json"), "{}\n");
    writeFileSync(resolve(root, "gen", "output.ts"), "// Generated.\n");

    const targets = await readTargets([root]);
    expect(targets.map((target) => target.path.slice(root.length + 1))).toEqual([
      "guide.md",
      "src/main.hx",
    ]);
  });
});
