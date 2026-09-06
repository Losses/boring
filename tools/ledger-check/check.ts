import { existsSync, readdirSync, readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";

const root = process.cwd();
const ledgerPath = join(root, "packages/compiler/semantic-exceptions.json");
const records = JSON.parse(readFileSync(ledgerPath, "utf8"));
const fail = (message: string): never => { throw new Error(`semantic exception ledger: ${message}`); };
if (!Array.isArray(records)) fail("top-level value is not an array");
const ids = new Set<string>();
const pairs = new Set<string>();
for (const record of records) {
  const id = typeof record?.id === "string" ? record.id : "<missing-id>";
  for (const key of ["id", "mechanism", "target", "shape", "reason", "ruling", "fixture"]) {
    if (typeof record?.[key] !== "string" || record[key].length === 0) fail(`${id}: missing or empty ${key}`);
  }
  if (ids.has(id)) fail(`${id}: duplicate id`);
  ids.add(id);
  const pair = `${record.mechanism}\0${record.target}`;
  if (pairs.has(pair)) fail(`${id}: duplicate mechanism-target pair`);
  pairs.add(pair);
  if (record.fixture !== "none" && !existsSync(join(root, record.fixture))) fail(`${id}: fixture path does not exist`);
}
const sorted = [...records].sort((a, b) => a.id.localeCompare(b.id));
mkdirSync(join(root, "out"), { recursive: true });
writeFileSync(join(root, "out/semantic-pass-exceptions.json"), JSON.stringify({ exceptionCount: sorted.length, records: sorted }, null, 2) + "\n");
