/**
 * Commit message validation per Conventional Commits v1.0.0.
 * https://www.conventionalcommits.org/en/v1.0.0/
 *
 * The rules below are the repository contract enforced by
 * `tools/commit/commit.ts` and by the commit-msg git hook. Every violation
 * reports the rule name and the offending line so the caller can fix the
 * message without reading the standard.
 */

export type CommitIssue = {
  readonly line: number;
  readonly rule: string;
  readonly problem: string;
};

const ALLOWED_TYPES: ReadonlyArray<string> = [
  "build",
  "chore",
  "ci",
  "docs",
  "feat",
  "fix",
  "perf",
  "refactor",
  "revert",
  "style",
  "test",
];

const HEADER_MAX_LENGTH = 72;
const BODY_MAX_LENGTH = 100;

// <type>[optional scope][!]: <description>
const HEADER_PATTERN = /^([a-z][a-z0-9-]*)(?:\(([a-z0-9][a-z0-9-]*)\))?(!)?: (.+)$/;
// A footer token line: "Token: value" or "Token #value".
const FOOTER_PATTERN = /^([A-Za-z][A-Za-z0-9-]*)(: | #)(.+)$/;
// A line that starts like a trailer but may be malformed.
const TRAILER_LIKE_PATTERN = /^[A-Za-z][A-Za-z0-9-]*[:#]/;
// Co-author trailers are banned in every casing and spacing variant.
const COAUTHOR_PATTERN = /^\s*co-authored-by\s*:/i;

type Paragraph = {
  readonly lines: string[];
  readonly startLine: number;
};

function splitParagraphs(lines: ReadonlyArray<string>): ReadonlyArray<Paragraph> {
  const paragraphs: Paragraph[] = [];
  let current: string[] = [];
  let startLine = 1;
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line === undefined) continue;
    if (line === "") {
      if (current.length > 0) {
        paragraphs.push({ lines: current, startLine });
        current = [];
      }
      continue;
    }
    if (current.length === 0) startLine = index + 1;
    current.push(line);
  }
  if (current.length > 0) {
    paragraphs.push({ lines: current, startLine });
  }
  return paragraphs;
}

export function usageText(): string {
  return [
    "Conventional Commits v1.0.0 format:",
    "",
    "  <type>(<scope>)!: <description>",
    "  <blank line>",
    "  <optional body>",
    "  <blank line>",
    "  <optional footers>",
    "",
    "Rules enforced by this repository:",
    `- type is one of: ${ALLOWED_TYPES.join(" ")}`,
  "- scope is optional: lowercase letters, digits, and hyphens",
  "- ! is optional and marks a breaking change",
  `- description: 1 to ${HEADER_MAX_LENGTH} characters, no trailing period`,
  `- body and footer lines stay within ${BODY_MAX_LENGTH} characters`,
  '- footers look like "Closes #123" or "BREAKING CHANGE: explanation"',
  "- Co-Authored-By trailers are banned in every form",
    "",
    "Correct examples:",
    "",
    "  feat(codec): add big-endian f64 writer",
    "  fix(haxe): reject truncated record input",
    "  docs: add language specification index",
    "  refactor(ts)!: return reader errors as values",
  ].join("\n");
}

export function validateCommitMessage(message: string): ReadonlyArray<CommitIssue> {
  const issues: CommitIssue[] = [];
  const normalized = message.replace(/\n+$/, "");
  const lines = normalized.split("\n");
  const header = lines[0] ?? "";

  const match = HEADER_PATTERN.exec(header);
  if (match === null) {
    issues.push({
      line: 1,
      rule: "header-shape",
      problem:
        "the header must look like <type>(<scope>)!: <description> with a colon and one space before the description",
    });
  } else {
    const type = match[1] ?? "";
    const description = match[4] ?? "";
    if (!ALLOWED_TYPES.includes(type)) {
      issues.push({
        line: 1,
        rule: "type",
        problem: `unknown type "${type}"; allowed types: ${ALLOWED_TYPES.join(" ")}`,
      });
    }
    if (description.length > HEADER_MAX_LENGTH) {
      issues.push({
        line: 1,
        rule: "header-length",
        problem: `description has ${description.length} characters; the limit is ${HEADER_MAX_LENGTH}`,
      });
    }
    if (description.endsWith(".")) {
      issues.push({
        line: 1,
        rule: "description-period",
        problem: "the description ends with a period; drop it",
      });
    }
  }

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (line === undefined) continue;
    const number = index + 1;
    if (COAUTHOR_PATTERN.test(line)) {
      issues.push({
        line: number,
        rule: "coauthor-ban",
        problem: "Co-Authored-By trailers are banned in this repository; remove the trailer",
      });
    }
    if (line.length > BODY_MAX_LENGTH) {
      issues.push({
        line: number,
        rule: "line-length",
        problem: `line has ${line.length} characters; the limit is ${BODY_MAX_LENGTH}`,
      });
    }
  }

  // Footers come after the body, so only the final paragraph carries
  // trailers. Lines in it that start like a trailer must match the footer
  // shape; continuation lines start with a space.
  const paragraphs = splitParagraphs(lines);
  const lastParagraph = paragraphs[paragraphs.length - 1];
  if (lastParagraph !== undefined && paragraphs.length > 1) {
    for (let offset = 0; offset < lastParagraph.lines.length; offset += 1) {
      const line = lastParagraph.lines[offset];
      if (line === undefined) continue;
      if (line.startsWith(" ")) continue;
      if (TRAILER_LIKE_PATTERN.test(line) && FOOTER_PATTERN.exec(line) === null) {
        issues.push({
          line: lastParagraph.startLine + offset,
          rule: "footer-shape",
          problem:
            'footer lines look like "Token: value" or "Token #value"; continuation lines start with a space',
        });
      }
    }
  }

  return issues;
}
