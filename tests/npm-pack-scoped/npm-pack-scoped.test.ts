import { expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * The scoped npm package name of one bundle (feature spec 59): the driver
 * passes the bundle's own ecosystem name to the TypeScript compiler, whose
 * package.json states the scoped name. The shared name stays the unscoped
 * form the other ecosystems accept, so this bundle publishes
 * @tiqian/protocol to npm while a cargo, pub or Maven target of the same
 * package keeps its own coordinate.
 */
const root = path.resolve(import.meta.dir, "../..");
const project = path.join(import.meta.dir, "boring.json");
const out = path.join(import.meta.dir, "out");
const tsc = process.env.BORING_PACKAGE_TSC ?? path.join(root, "node_modules/typescript/bin/tsc");

function run(command: string[], cwd: string, env: Record<string, string> = {}) {
  return Bun.spawnSync(command, { cwd, env: { ...process.env, ...env }, stdout: "pipe", stderr: "pipe" });
}

test("the npm bundle publishes the scoped ecosystem name", async () => {
  const driver = path.join(root, "out/driver/driver.js");
  expect(fs.existsSync(driver), "build the driver first: haxe packages/driver/driver.hxml").toBe(true);

  const pack = run(["bun", driver, "pack", "npm", "--project", project], root, { BORING_PACKAGE_TSC: tsc });
  const output = pack.stdout.toString() + pack.stderr.toString();
  fs.mkdirSync(out, { recursive: true });
  await Bun.write(path.join(out, "pack.log"), output);
  expect(pack.exitCode, "pack: " + output).toBe(0);

  const manifest = JSON.parse(fs.readFileSync(path.join(out, "npm", "gen", "package.json"), "utf8"));
  expect(manifest.name).toBe("@tiqian/protocol");

  const archive = path.join(out, "npm", "@tiqian-protocol-0.1.0.tgz");
  expect(fs.existsSync(archive), "archive: " + archive).toBe(true);
  const member = Bun.spawnSync(["tar", "-xzOf", archive, "package/package.json"]);
  expect(member.exitCode, member.stderr.toString()).toBe(0);
  expect(JSON.parse(member.stdout.toString()).name).toBe("@tiqian/protocol");
}, 300_000);
