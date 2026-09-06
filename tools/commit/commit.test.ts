import { describe, expect, test } from "bun:test";
import { usageText, validateCommitMessage } from "./message.ts";

function rules(message: string): ReadonlyArray<string> {
  return validateCommitMessage(message).map((issue) => issue.rule);
}

describe("validateCommitMessage", () => {
  test("accepts a bare type with description", () => {
    expect(validateCommitMessage("docs: add language specification index")).toEqual([]);
  });

  test("accepts a scoped type", () => {
    expect(validateCommitMessage("feat(codec): add big-endian f64 writer")).toEqual([]);
  });

  test("accepts a breaking-change marker", () => {
    expect(validateCommitMessage("refactor(ts)!: return reader errors as values")).toEqual([]);
  });

  test("accepts a body and footers", () => {
    const message = [
      "fix(haxe): reject truncated record input",
      "",
      "The reader now reports an unexpected end of input when a record",
      "stops inside its bounds block.",
      "",
      "Closes #12",
    ].join("\n");
    expect(validateCommitMessage(message)).toEqual([]);
  });

  test("rejects an unknown type", () => {
    expect(rules("feature: add writer")).toEqual(["type"]);
  });

  test("rejects a malformed header", () => {
    expect(rules("feat(codec) add writer")[0]).toBe("header-shape");
  });

  test("rejects a missing space after the colon", () => {
    expect(rules("feat:add writer")[0]).toBe("header-shape");
  });

  test("rejects a trailing period", () => {
    expect(rules("feat: add writer.")).toEqual(["description-period"]);
  });

  test("rejects an over-long description", () => {
    const long = "a".repeat(73);
    expect(rules(`feat: ${long}`)).toEqual(["header-length"]);
  });

  test("rejects co-authored-by trailers in every casing", () => {
    const base = "feat: add writer";
    expect(rules(`${base}\n\nCo-Authored-By: someone`)).toContain("coauthor-ban");
    expect(rules(`${base}\n\nco-authored-by: someone`)).toContain("coauthor-ban");
    expect(rules(`${base}\n\n  CO-AUTHORED-BY : someone`)).toContain("coauthor-ban");
    expect(rules(`${base}\n\nCo-Author: someone`)).toContain("coauthor-ban");
    expect(rules(`${base}\n\nCoAuth: someone`)).toContain("coauthor-ban");
    expect(rules(`${base}\n\ncoauthor: someone`)).toContain("coauthor-ban");
    expect(rules(`feat: add writer (co-author: someone)`)).toContain("coauthor-ban");
  });

  test("rejects style violations in the header title", () => {
    expect(rules("feat(codec): robust f64 writer")).toContain("style-adjective");
    expect(rules("feat: unlock cache performance")).toContain("style-jargon");
    expect(rules("fix(ts): shoehorn error type")).toContain("style-metaphor");
  });

  test("rejects style violations in the commit body", () => {
    const message = [
      "feat(codec): add writer",
      "",
      "This is not a reader but a writer.",
    ].join("\n");
    expect(rules(message)).toContain("style-contrast");

    const messageFiller = [
      "feat(codec): add writer",
      "",
      "In other words, the record stays 44 bytes.",
    ].join("\n");
    expect(rules(messageFiller)).toContain("style-ai-filler");

    const messageDash = [
      "feat(codec): add writer",
      "",
      "The codec—when verified—passes tests.",
    ].join("\n");
    expect(rules(messageDash)).toContain("style-em-dash");
  });

  test("rejects a malformed footer line", () => {
    expect(rules("feat: add writer\n\nCloses#12 wrong")).toContain("footer-shape");
  });

  test("rejects over-long body lines", () => {
    const body = "b".repeat(101);
    expect(rules(`feat: add writer\n\n${body}`)).toContain("line-length");
  });

  test("usage text states the standard and the coauthor ban", () => {
    expect(usageText()).toContain("Conventional Commits v1.0.0");
    expect(usageText()).toContain("Co-Authored-By trailers are banned");
  });
});
