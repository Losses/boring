import { describe, expect, test } from "bun:test";
import { SwitchOps } from "../../reference/ts/gen/boring/SwitchOps";

describe("variant switch lowering", () => {
  test("supports statement and initializer positions", () => {
    expect(SwitchOps.assign({ kind: "Empty" })).toBe("empty");
    expect(SwitchOps.assign({ kind: "Text", value: "y" })).toBe("text:y");
    expect(SwitchOps.statement({ kind: "Empty" })).toBe("empty");
    expect(SwitchOps.statement({ kind: "Number", value: 3 })).toBe("number:3");
    expect(SwitchOps.initializer({ kind: "Text", value: "x" })).toBe("text:x");
  });

  test("supports default arms", () => {
    expect(SwitchOps.defaulted({ kind: "Empty" })).toBe("empty");
    expect(SwitchOps.defaulted({ kind: "Other" })).toBe("fallback");
  });
});
