import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

describe("capture switch generated trees", () => {
  const read = (target: string) => {
    const extension = target === "ts" ? "ts" : target === "kotlin" ? "kt" : target === "swift" ? "swift" : "dart";
    const file = target === "dart"
      ? "reference/dart/gen/lib/boring/capture_switch_ops.dart"
      : `reference/${target}/gen/boring/CaptureSwitchOps.${extension}`;
    return fs.readFileSync(path.resolve(__dirname, `../../${file}`), "utf8");
  };

  test("pins captured switch lowering in generated targets", () => {
    for (const target of ["ts", "kotlin", "swift", "dart"] as const) {
      withTargetTree(target, "capture-switch-ops: pins captured switch lowering in generated targets", () => {
        expect(read(target)).toContain("describe");
        expect(read(target)).toContain("messageLength");
      });
    }
  });
});
