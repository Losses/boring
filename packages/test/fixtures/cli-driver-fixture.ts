// CLI driver probe fixtures — deterministic environment, no execution logic.
//
// Boundary (packages/test/README.md): fixtures/ provides the fixture project
// and the stub toolchain (fake haxe/tsc/bun/postgen shims) for the CLI
// cross-target probe. It runs nothing; the orchestration lives in
// tests/driver/cli-cross-target.ts and the executor in packages/test/bin/cli-command.ts.
import { chmodSync, cpSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

export type CliFixture = {
  fixture: string;
  project: string;
  verifyRoot: string;
  toolbin: string;
  afterGenLog: string;
  fakeToolsEnv: NodeJS.ProcessEnv;
};

const here = resolve(import.meta.dir);
const repoRoot = resolve(here, "..", "..", "..");

export function createCliFixture(): CliFixture {
  const fixture = mkdtempSync(join(tmpdir(), "boring-driver-cli-"));
  cpSync(join(repoRoot, "tests/driver/fixtures/compare"), fixture, { recursive: true });
  const project = join(fixture, "boring.json");
  const verifyRoot = join(fixture, "verify");
  const toolbin = join(fixture, "toolbin");
  const afterGenLog = join(fixture, "after-gen.log");
  mkdirSync(verifyRoot);
  mkdirSync(toolbin);
  mkdirSync(join(verifyRoot, "src", "demo"), { recursive: true });
  writeFileSync(join(verifyRoot, "src", "demo", "ZTest.hx"), "package demo; class ZTest {}\n");
  writeFileSync(join(verifyRoot, "src", "demo", "ATest.hx"), "package demo; class ATest {}\n");
  writeFileSync(join(verifyRoot, "src", "demo", "Helper.hx"), "package demo; class Helper {}\n");
  writeFileSync(join(verifyRoot, "boring.json"), JSON.stringify({
    outRoot: "out", resultsDir: "results", baseline: "only", sourceRoots: ["src"],
    sourceSets: { core: { types: ["demo.Helper"], discover: [{ root: "src", packages: ["demo"], suffix: "Test" }] } },
    bundles: [{ id: "only", target: "ts", sourceSet: "core", package: { name: "demo", version: "1.0.0" },
      afterGen: { command: "postgen" } }],
  }));
  for (const name of ["haxe", "tsc"]) {
    const path = join(toolbin, name);
    writeFileSync(path, "#!/usr/bin/env sh\nexit 0\n");
    chmodSync(path, 0o755);
  }
  const bunStub = join(toolbin, "bun");
  writeFileSync(bunStub, '#!/usr/bin/env sh\nif [ "$1" = test ]; then printf \'{"id":"smoke","name":"smoke","verdict":"pass"}\\n\' > "$BORING_TEST_RESULTS"; fi\n');
  chmodSync(bunStub, 0o755);
  const postgen = join(toolbin, "postgen");
  writeFileSync(postgen, '#!/usr/bin/env sh\nprintf \'ran\\n\' >> "$BORING_AFTER_GEN_LOG"\n');
  chmodSync(postgen, 0o755);
  const fakeToolsEnv: NodeJS.ProcessEnv = { ...process.env, PATH: `${toolbin}:${process.env.PATH ?? ""}`, BORING_AFTER_GEN_LOG: afterGenLog };
  return { fixture, project, verifyRoot, toolbin, afterGenLog, fakeToolsEnv };
}
