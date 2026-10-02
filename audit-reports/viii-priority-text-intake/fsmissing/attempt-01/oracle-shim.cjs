// Platform-module shim of the Haxe oracle.
//
// On the Haxe target `std.Fs` and `std.Env` are JS platform modules: the
// compiled body reads `globalThis.std.Fs` with no null guard, and the
// in-source test runner installs that object before the compiled body runs
// (packages/compiler/TestCollector.hx, the `fsOracle`/`envOracle` records).
// This file installs the same records with the same bodies, so the oracle
// observes the same host edge the in-source test entry observes.
//
// The bodies are copied from packages/compiler/TestCollector.hx:
//   readText:    try { nodeFs.readFileSync(p, "utf8") } catch (e) { throw new haxe.Exception(p + ": " + Std.string(e)) }
//   isDirectory: try { nodeFs.statSync(p).isDirectory() } catch (e) { return false }
//
// They are JS, not Haxe: the oracle class itself calls the production
// `std.Fs` face, and this file only supplies the host object underneath it.
const nodeFs = require("node:fs");

function haxeException(message) {
    const error = new Error(message);
    error.name = "haxe.Exception";
    return error;
}

globalThis.std = globalThis.std || {};
globalThis.std.Fs = {
    exists: (p) => nodeFs.existsSync(p),
    readText: (p) => {
        try { return nodeFs.readFileSync(p, "utf8"); }
        catch (e) { throw haxeException(p + ": " + String(e)); }
    },
    writeText: (p, d) => {
        try { nodeFs.writeFileSync(p, d, "utf8"); }
        catch (e) { throw haxeException(p + ": " + String(e)); }
    },
    appendText: (p, d) => {
        try { nodeFs.appendFileSync(p, d, "utf8"); }
        catch (e) { throw haxeException(p + ": " + String(e)); }
    },
    makeDirs: (p) => {
        try { nodeFs.mkdirSync(p, { recursive: true }); }
        catch (e) { throw haxeException(p + ": " + String(e)); }
    },
    readDir: (p) => {
        try { return nodeFs.readdirSync(p); }
        catch (e) { throw haxeException(p + ": " + String(e)); }
    },
    isDirectory: (p) => {
        try { return nodeFs.statSync(p).isDirectory(); }
        catch (e) { return false; }
    },
};
globalThis.std.Env = {
    get: (k) => (process.env[k] === undefined ? null : String(process.env[k])),
    set: (k, v) => { process.env[k] = v; },
    remove: (k) => { delete process.env[k]; },
};

require(process.argv[2]);
