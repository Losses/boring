import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Entry-point contract of the runtime package
 * (docs/plans/2026-08-28-runtime-unification.md).
 *
 * The general entry must stay loadable in a browser: no `node:` import
 * specifier and no test helper in it. The test entry owns the
 * file-system writer. Generated business code must reference only the
 * general entry.
 */
describe("runtime entry points", () => {
  const genDir = path.resolve(__dirname, "../../reference/ts/gen");
  const generalEntry = path.join(genDir, "runtime.ts");
  const testEntry = path.join(genDir, "runtime/test.ts");
  const genTestsDir = path.resolve(__dirname, "../../reference/ts/gen-tests");

  test("general entry exists and contains no node: import specifier", () => {
    expect(fs.existsSync(generalEntry)).toBe(true);
    const content = fs.readFileSync(generalEntry, "utf8");
    expect(content.includes("node:")).toBe(false);
  });

  test("general entry contains no Test class; test entry owns it", () => {
    const general = fs.readFileSync(generalEntry, "utf8");
    expect(general.includes("class Test")).toBe(false);
    expect(general.includes("test-results")).toBe(false);

    expect(fs.existsSync(testEntry)).toBe(true);
    const testEntryContent = fs.readFileSync(testEntry, "utf8");
    expect(testEntryContent.includes("class Test")).toBe(true);
    expect(testEntryContent.includes("node:fs")).toBe(true);
  });

  test("generated business code imports only the general entry", () => {
    const failures: string[] = [];
    const visit = (dir: string) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          visit(full);
        } else if (entry.name.endsWith(".ts")) {
          const content = fs.readFileSync(full, "utf8");
          if (content.includes('"@boring/runtime/test"')) {
            failures.push(path.relative(genDir, full));
          }
        }
      }
    };
    visit(genDir);
    expect(failures).toEqual([]);
  });

  test("generated test code never imports the general entry for Test", () => {
    const failures: string[] = [];
    for (const entry of fs.readdirSync(genTestsDir, { withFileTypes: true })) {
      if (!entry.name.endsWith(".ts")) continue;
      const full = path.join(genTestsDir, entry.name);
      const content = fs.readFileSync(full, "utf8");
      const generalImport = content.match(/import \{[^}]*\} from "@boring\/runtime";/);
      if (generalImport && generalImport[0].includes("Test")) {
        failures.push(entry.name);
      }
    }
    expect(failures).toEqual([]);
  });
});
