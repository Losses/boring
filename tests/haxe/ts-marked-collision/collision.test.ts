import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * TypeScript spells each Haxe module as one file with one namespace. Two
 * classes in one Haxe module can therefore claim the same marked static name
 * (features/10), which the base compiler emitted twice: tsc answered TS2323
 * "Cannot redeclare exported variable" and TS2393 "Duplicate function
 * implementation". The target keeps the natural name for the module's
 * file-named owner and mangles every other claimant as <Owner>_<name> (P-21);
 * the declaration and every call site resolve through that one function.
 *
 * The shape comes from tiqian's engine: LayoutQueryFns.hx declares the
 * TextRange and Int-pair getBoundingBoxes extensions in one module, and the
 * npm pack stopped at package-tsc on the duplicate before the tarball existed.
 */

const root = path.resolve(import.meta.dir, "../../..");
const hxml = "tests/haxe/ts-marked-collision/gen/ts.hxml";

function generate(tag: string): { out: string; testOut: string } {
  const out = path.join(root, "out", "ts-marked-collision", "gen-" + tag);
  const testOut = path.join(root, "out", "ts-marked-collision", "gen-tests-" + tag);
  const run = Bun.spawnSync(
    ["haxe", hxml, "-D", "ts-output=" + out, "-D", "ts-test-output=" + testOut],
    { cwd: root, stdout: "pipe", stderr: "pipe" },
  );
  expect(run.exitCode, run.stderr.toString() || run.stdout.toString()).toBe(0);
  return { out, testOut };
}

function occurrences(haystack: string, needle: string): number {
  return haystack.split(needle).length - 1;
}

test("two marked statics claiming one name in one module emit distinct names", () => {
  const { out } = generate(randomUUID());

  const boxes = fs.readFileSync(path.join(out, "collisionscope", "Boxes.ts"), "utf8");
  // The natural name stays with the module's file-named owner...
  expect(boxes).toContain("export function span(box: Box, from: number): number");
  expect(boxes).toContain("export function label(value: number): number");
  expect(occurrences(boxes, "export function span(")).toBe(1);
  expect(occurrences(boxes, "export function label(")).toBe(1);
  // ...and the other claimant mangles deterministically.
  expect(boxes).toContain("export function BoxSpanRangeFns_span(box: Box, from: number, to: number): number");
  expect(boxes).toContain("export function BoxSpanRangeFns_label(value: string): number");

  const probe = fs.readFileSync(path.join(out, "collisionscope", "BoxProbe.ts"), "utf8");
  expect(probe).toContain("return span(box, from);");
  expect(probe).toContain("return BoxSpanRangeFns_span(box, from, to);");
  expect(probe).toContain("return label(value);");
  expect(probe).toContain("return BoxSpanRangeFns_label(value);");
}, 180_000);
