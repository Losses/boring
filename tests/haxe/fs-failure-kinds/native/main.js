// TypeScript native harness for the fs-failure-kinds fixture. The runner
// copies this file into the generated tree root and runs it with bun.
import { FsFailOracle } from "./fsfail/FsFailOracle.js";
import * as fs from "node:fs";

const dir = "out/fs-failure-kinds";
fs.mkdirSync(dir, { recursive: true });
const missing = dir + "/absent.txt";
const file = dir + "/plain.txt";
const denied = dir + "/denied.txt";
fs.writeFileSync(file, "content");
fs.writeFileSync(denied, "secret");

console.log("missing-read=" + FsFailOracle.readIdentity(missing));
console.log("not-a-directory-read=" + FsFailOracle.readIdentity(file + "/child"));
console.log("write-over-directory=" + FsFailOracle.writeIdentity(dir));
console.log("predicates-missing=" + FsFailOracle.predicatePair(missing));
console.log("manual-catch=" + FsFailOracle.manualCatchIdentity());
fs.chmodSync(denied, 0o000);
console.log("denied-read=" + FsFailOracle.readIdentity(denied));
fs.chmodSync(denied, 0o644);
