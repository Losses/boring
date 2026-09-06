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

  test("supports switches inside conditional arms", () => {
    expect(SwitchOps.conditional({ kind: "Empty" }, true)).toBe("fallback");
    expect(SwitchOps.conditional({ kind: "Empty" }, false)).toBe("empty");
    expect(SwitchOps.conditional({ kind: "Number", value: 3 }, false)).toBe("number:3");
    expect(SwitchOps.conditional({ kind: "Text", value: "x" }, false)).toBe("text:x");
  });
});
