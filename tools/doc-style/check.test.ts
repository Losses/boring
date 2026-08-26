import { describe, expect, test } from "bun:test";
import { matchedTerms, scanText } from "./check.ts";

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

  test("flags coined compression compounds", () => {
    const hits = matchedTerms("The decoder keeps frame-level state in a table.");
    expect(hits.map((hit) => hit.tag)).toEqual(["coinage"]);
  });

  test("flags putdown wording", () => {
    const hits = matchedTerms("You just need to call decode before reading.");
    expect(hits.map((hit) => hit.match)).toEqual(["just"]);
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

  test("returns no hits for compliant text", () => {
    const hits = scanText(
      "The record is 44 bytes and holds one code point with five measured values.\n",
      "fixture.md",
    );
    expect(hits).toEqual([]);
  });
});
