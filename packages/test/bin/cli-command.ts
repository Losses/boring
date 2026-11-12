// CLI command executor for the driver probes.
//
// Boundary (packages/test/README.md): bin/ drives one test run; this module
// only spawns a program and returns/raises its observable outcome. It decides
// no verdict; the callers assert on the returned output.
export type CommandResult = { code: number; output: string };

export function command(program: string, args: string[], env: NodeJS.ProcessEnv = process.env, cwd: string = process.cwd()): CommandResult {
  const result = Bun.spawnSync([program, ...args], {
    cwd,
    env,
    stdout: "pipe",
    stderr: "pipe",
  });
  const output = result.stdout.toString() + result.stderr.toString();
  if (result.exitCode !== 0) {
    throw new Error(`${program} ${args.join(" ")} failed (${result.exitCode}):
${output}`);
  }
  return { code: result.exitCode, output };
}
