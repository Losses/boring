import { genArgs } from "./project-args";

/**
 * Prints one bundle's generation arguments, one per line, for shell callers
 * that need a direct haxe invocation (tests/haxe/ts-platformops-imports/run.sh).
 *
 * Usage: bun tests/support/print-gen-args.ts <bundle-id> [output] [test-output]
 */
const [id, output, testOutput] = process.argv.slice(2);
if(id === undefined || id === "") {
  console.error("usage: print-gen-args.ts <bundle-id> [output] [test-output]");
  process.exit(2);
}
const options: { output?: string; testOutput?: string } = {};
if(output !== undefined) options.output = output;
if(testOutput !== undefined) options.testOutput = testOutput;
for(const arg of genArgs(id, options)) console.log(arg);
