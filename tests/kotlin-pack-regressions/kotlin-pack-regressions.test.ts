import { expect, test } from "bun:test";

/**
 * Regression for the Kotlin pack path over a bundle source set.
 *
 * test:stage1:kotlin compiles the reference tree, which is not the source set
 * a consumer's bundle declares. tiqian's engine-haxe targets compile through
 * boring pack, and three emitter regressions only reached kotlinc there: a
 * binary32 sumOfFloat selector that lost its Double widening, a
 * null-initialized local read inside a nested generated run block that lost
 * its extraction, and a has/get ternary passed to a defaulted parameter that
 * lost its elvis. This project declares its own bundle and runs the driver's
 * pack action, so the same path is covered here.
 */
const root = import.meta.dir + "/../..";
const project = import.meta.dir + "/boring.json";
const out = import.meta.dir + "/out";

function run(command: string[], cwd: string) {
  return Bun.spawnSync(command, { cwd, stdout: "pipe", stderr: "pipe" });
}

function diagnostics(result: ReturnType<typeof run>): string {
  return result.stdout.toString() + result.stderr.toString();
}

test("the pack path compiles the three emitter shapes for both precisions", async () => {
  const driver = run(["haxe", "packages/driver/driver.hxml"], root);
  expect(driver.exitCode, "driver build: " + diagnostics(driver)).toBe(0);

  const pack = run(
    ["bun", "out/driver/driver.js", "pack", "kotlin-f32", "kotlin-f64", "--project", project],
    root,
  );
  const output = diagnostics(pack);
  await Bun.write(out + "/pack.log", output);
  expect(output.split("\n").filter((line) => line.includes(": error:"))).toEqual([]);
  expect(pack.exitCode, "pack: " + output).toBe(0);

  for (const bundle of ["kotlin-f32", "kotlin-f64"]) {
    const jar = out + "/" + bundle + "/maven/kotlin-pack-regressions/kotlin-pack-regressions-" + bundle.slice(-3)
      + "/0.1.0/kotlin-pack-regressions-" + bundle.slice(-3) + "-0.1.0.jar";
    expect(await Bun.file(jar).exists(), bundle + " jar: " + jar).toBe(true);
  }

  const f32 = await Bun.file(out + "/kotlin-f32/gen/kotlinpack/SumFixture.kt").text();
  expect(f32, "binary32 selector widens to Double inside sumOf").toContain(
    "values.sumOf { value -> (value).toDouble() }.toFloat()",
  );

  const f64 = await Bun.file(out + "/kotlin-f64/gen/kotlinpack/SumFixture.kt").text();
  expect(f64, "binary64 selector keeps its Double rendering").toContain(
    "values.sumOf { value -> value }",
  );

  const capture = await Bun.file(out + "/kotlin-f32/gen/kotlinpack/CaptureFixture.kt").text();
  expect(capture, "the nested run block read keeps its extraction").toContain(
    "e > terminalBest!!.end",
  );
  expect(capture, "the function-level read needs no extraction").toContain(
    "else terminalBest.end",
  );

  const nullableF32 = await Bun.file(out + "/kotlin-f32/gen/kotlinpack/NullableArgFixture.kt").text();
  expect(nullableF32, "the binary32 ternary argument keeps its elvis").toContain("?: 0.0f");

  const nullableF64 = await Bun.file(out + "/kotlin-f64/gen/kotlinpack/NullableArgFixture.kt").text();
  expect(nullableF64, "the binary64 ternary argument keeps its elvis").toContain("?: 0.0");
}, 300_000);
