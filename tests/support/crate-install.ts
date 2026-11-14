/**
 * Cargo install check for the crate artifacts of feature spec 25.
 *
 * The cargo registry client unpacks a downloaded .crate and requires every
 * member to sit under <name>-<version>/, the directory it derives from the
 * index entry. A member outside that directory stops the install with
 * "invalid tarball downloaded, contains a file at ... which isn't under ...".
 * This module serves one crate from a local sparse registry and runs
 * "cargo add" plus "cargo build" in a consumer package, so the check reports
 * what a consumer sees.
 *
 * The registry name of a crate is its file name without the extension
 * (<name>-<version>.crate), the name the generated index uses.
 *
 * Run it over crate files or directories:
 *     bun tests/support/crate-install.ts <path>...
 */

import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export type CrateIdentity = {
  readonly name: string;
  readonly version: string;
};

export type CrateInstallReport = {
  readonly crate: string;
  readonly name: string;
  readonly version: string;
};

type CommandResult = {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
};

const CRATE_FILE = /^(.+)-(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?)\.crate$/;

/** The name and version a crate file name states. */
export function crateIdentity(cratePath: string): CrateIdentity {
  const fileName = path.basename(cratePath);
  const match = CRATE_FILE.exec(fileName);
  const name = match === null ? undefined : match[1];
  const version = match === null ? undefined : match[2];
  if (name === undefined || version === undefined) {
    throw new Error("crate file name is not <name>-<version>.crate: " + fileName);
  }
  return { name, version };
}

/** The sparse index file of one crate name (cargo's prefix tiers). */
export function sparseIndexPath(name: string): string {
  if (name.length === 1) return "1/" + name;
  if (name.length === 2) return "2/" + name;
  if (name.length === 3) return "3/" + name.slice(0, 1) + "/" + name;
  return name.slice(0, 2) + "/" + name.slice(2, 4) + "/" + name;
}

async function run(command: string[], cwd: string, env: Record<string, string>): Promise<CommandResult> {
  const proc = Bun.spawn(command, {
    cwd,
    env: { ...process.env, ...env },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [exitCode, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  return { exitCode, stdout, stderr };
}

/** Every regular file under one directory, as absolute paths. */
export function filesUnder(root: string): string[] {
  const found: string[] = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) {
      found.push(...filesUnder(full));
    } else {
      found.push(full);
    }
  }
  return found;
}

/**
 * Serves one crate from a local sparse registry, then installs it into a
 * consumer package with the cargo CLI. Throws with the tool output when
 * either command fails, so a failure names the member or the manifest cargo
 * rejected.
 */
export async function installCrate(cratePath: string): Promise<CrateInstallReport> {
  const identity = crateIdentity(cratePath);
  const crateBytes = fs.readFileSync(cratePath);
  const checksum = createHash("sha256").update(crateBytes).digest("hex");
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "boring-crate-install-"));
  const indexFile = sparseIndexPath(identity.name);
  const crateFile = identity.name + "-" + identity.version + ".crate";
  const indexEntry = JSON.stringify({
    name: identity.name,
    vers: identity.version,
    deps: [],
    cksum: checksum,
    features: {},
    yanked: false,
    v: 2,
  }) + "\n";
  let server: ReturnType<typeof Bun.serve> | null = null;
  try {
    server = Bun.serve({
      hostname: "127.0.0.1",
      port: 0,
      fetch(request) {
        const url = new URL(request.url);
        const port = server === null ? 0 : server.port;
        if (url.pathname === "/index/config.json") {
          return new Response(JSON.stringify({ dl: "http://127.0.0.1:" + port + "/dl/{crate}-{version}.crate" }) + "\n");
        }
        if (url.pathname === "/index/" + indexFile) {
          return new Response(indexEntry);
        }
        if (url.pathname === "/dl/" + crateFile) {
          return new Response(crateBytes);
        }
        return new Response("not found\n", { status: 404 });
      },
    });
    const consumer = path.join(root, "consumer");
    fs.mkdirSync(path.join(consumer, "src"), { recursive: true });
    fs.mkdirSync(path.join(consumer, ".cargo"), { recursive: true });
    fs.writeFileSync(path.join(consumer, "Cargo.toml"), [
      "[package]",
      'name = "consumer"',
      'version = "0.1.0"',
      'edition = "2021"',
      "",
      "[dependencies]",
      "",
      // The consumer is its own workspace root: the check must not join the
      // workspace of a directory the temporary tree happens to sit under.
      "[workspace]",
      "",
    ].join("\n"));
    fs.writeFileSync(path.join(consumer, "src", "main.rs"), "fn main() {}\n");
    fs.writeFileSync(path.join(consumer, ".cargo", "config.toml"), [
      "[registries.local]",
      'index = "sparse+http://127.0.0.1:' + server.port + '/index/"',
      "",
    ].join("\n"));
    const env = {
      // An isolated cargo home keeps the check off the host's cache.
      CARGO_HOME: path.join(root, "cargo-home"),
      CARGO_TERM_COLOR: "never",
      CARGO_NET_RETRY: "0",
    };
    const spec = identity.name + "@" + identity.version;
    const add = await run(["cargo", "add", "--registry", "local", spec], consumer, env);
    if (add.exitCode !== 0) {
      throw new Error("cargo add " + spec + " failed with exit code " + add.exitCode + ":\n" + add.stdout + add.stderr);
    }
    const build = await run(["cargo", "build", "--message-format=short"], consumer, env);
    if (build.exitCode !== 0) {
      throw new Error("cargo build of " + spec + " failed with exit code " + build.exitCode + ":\n" + build.stdout + build.stderr);
    }
    const consumerBinary = path.join(consumer, "target", "debug", "consumer");
    if (!fs.existsSync(consumerBinary)) {
      throw new Error("cargo build of " + spec + " left no consumer binary at " + consumerBinary);
    }
    return { crate: cratePath, name: identity.name, version: identity.version };
  } finally {
    if (server !== null) {
      server.stop(true);
    }
    fs.rmSync(root, { recursive: true, force: true });
  }
}

if (import.meta.main) {
  const targets = process.argv.slice(2);
  if (targets.length === 0) {
    console.error("usage: bun tests/support/crate-install.ts <crate file or directory>...");
    process.exit(2);
  }
  const crates: string[] = [];
  for (const target of targets) {
    if (fs.statSync(target).isDirectory()) {
      crates.push(...filesUnder(target).filter(file => file.endsWith(".crate")));
    } else {
      crates.push(target);
    }
  }
  if (crates.length === 0) {
    console.error("crate-install: no .crate file under: " + targets.join(" "));
    process.exit(2);
  }
  let failed = 0;
  for (const crate of crates) {
    try {
      const report = await installCrate(crate);
      console.log("ok " + report.crate + " (" + report.name + " " + report.version + ")");
    } catch (error) {
      failed++;
      console.error("FAIL " + crate + ": " + (error instanceof Error ? error.message : String(error)));
    }
  }
  console.log(crates.length - failed + "/" + crates.length + " crates installed");
  process.exit(failed === 0 ? 0 : 1);
}
