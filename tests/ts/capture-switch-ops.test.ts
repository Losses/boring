import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("capture switch generated trees", () => {
  const read = (target: string) => {
    const extension = target === "ts" ? "ts" : target === "kotlin" ? "kt" : target === "swift" ? "swift" : "dart";
    return fs.readFileSync(path.resolve(__dirname, `../../reference/${target}/gen/boring/CaptureSwitchOps.${extension}`), "utf8");
  };

  test("pins captured switch lowering in generated targets", () => {
    for (const target of ["ts", "kotlin", "swift", "dart"]) {
      expect(read(target)).toContain("describe");
      expect(read(target)).toContain("messageLength");
    }
  });
});
