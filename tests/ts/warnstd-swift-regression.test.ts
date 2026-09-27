import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * R1 warn-zero regression pins (warnstd seat r2): each test reads the
 * generated Swift tree for one minimal mechanism sample under
 * samples/boring and asserts on the generated text itself. The value
 * array and indexOf assertions were negative-validated by regenerating
 * against pre-fix SwiftExpr emitters (8b267acd~1 and b638bb42~1); the
 * captured pre-fix outputs are recorded in .tq-logs/warnstd/seats/r2.log.
 */

const gen = (name: string): string =>
  fs.readFileSync(path.resolve(import.meta.dir, "../../reference/swift/gen/boring", name), "utf8");

describe("warnstd swift regression samples", () => {
  test("ValueArrayBindingVar: a Bytes binding that lowers to the native [UInt8] value array keeps var", () => {
    const out = gen("BytesValueArrayVar.swift");
    expect(out).toContain("var buf = [UInt8](repeating: 0, count: Int(4))");
    expect(out).not.toContain("let buf");
  });

  test("StringIndexOfDeadClamp: a constant non-negative start drops the dead negative-offset clamp", () => {
    const out = gen("StringIndexOfDeadClamp.swift");
    expect(out).toContain("var i = Int(2)");
    expect(out).not.toContain("if i < 0");
  });

  test("ClassInstanceLocalLet: a never-reassigned class-instance local declares let (behavior pin)", () => {
    const out = gen("ClassInstanceLocalLet.swift");
    expect(out).toContain("let inst = ClassInstanceLocalLet()");
    expect(out).not.toContain("var inst");
  });

  test("UnusedLocalNaming: a local the emitter proves unmentioned renders nothing (behavior pin)", () => {
    const out = gen("UnusedSwiftBinding.swift");
    expect(out).not.toContain("var unused");
    expect(out).not.toContain("let unused");
  });
});
