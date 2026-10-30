import { describe, expect, test } from "bun:test";
import * as path from "node:path";

const root = path.resolve(import.meta.dir, "../..");

/**
    Runs the plain-Haxe contract for the Target Semantic Policy typed-IR
    vocabulary (tests/haxe/semantic-policy/contract.hxml). It asserts the frozen
    variant sets exist and the policy-entry ids are complete and duplicate-free,
    so docs/specs/target-semantic-policy.md and packages/compiler/SemanticPolicy.hx
    cannot drift.
**/
async function runContract(): Promise<{ code: number; output: string }> {
    const proc = Bun.spawn(["haxe", "tests/haxe/semantic-policy/contract.hxml"], {
        cwd: root,
        stdout: "pipe",
        stderr: "pipe",
    });
    const [code, out, err] = await Promise.all([
        proc.exited,
        new Response(proc.stdout).text(),
        new Response(proc.stderr).text(),
    ]);
    return { code, output: out + err };
}

describe("Target Semantic Policy typed-IR contract", () => {
    test("contract compiles and every frozen variant set is constructible", async () => {
        const result = await runContract();
        expect(result.code).toBe(0);
        expect(result.output).toContain("failures=0");
        expect(result.output).toContain("checks=");
    }, 60_000);
});

