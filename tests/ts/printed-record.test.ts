import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

interface MemberTree {
  file: string;
  signature: string;
  fields: string[];
}

interface TargetConfig {
  compilerClass: string;
  define: string;
  file: string;
  id: string;
  shadow: string;
  signature: string;
  testDefine?: string;
}

const memberTrees: MemberTree[] = [
  {
    file: "reference/ts/gen/boring/PrintedRecord.ts",
    signature: "public toString(): string",
    fields: ["this.count", "this.ratio", "this.inner"],
  },
  {
    file: "reference/swift/gen/boring/PrintedRecord.swift",
    signature: "func toString() -> String",
    fields: ["self.count", "self.ratio", "self.inner"],
  },
  {
    file: "reference/swift-f32/gen/boring/PrintedRecord.swift",
    signature: "func toString() -> String",
    fields: ["self.count", "self.ratio", "self.inner"],
  },
  {
    file: "reference/dart/gen/lib/boring/printed_record.dart",
    signature: "String toString()",
    fields: ["this.count", "this.ratio", "this.inner"],
  },
  {
    file: "reference/rust-gen/src/boring/printed_record.rs",
    signature: "pub fn to_string(&self) -> String",
    fields: ["self.count", "self.ratio", "self.inner"],
  },
  {
    file: "reference/rust-f32-gen/src/boring/printed_record.rs",
    signature: "pub fn to_string(&self) -> String",
    fields: ["self.count", "self.ratio", "self.inner"],
  },
];

const mutationTargets: TargetConfig[] = [
  {
    compilerClass: "tscompiler.Compiler.use()",
    define: "ts-output",
    file: "boring/PrintedRecord.ts",
    id: "ts",
    shadow: "packages/compiler/reflaxe/ts/std-shadow",
    signature: "public toString(): string",
  },
  {
    compilerClass: "swiftcompiler.Compiler.use()",
    define: "swift-output",
    file: "boring/PrintedRecord.swift",
    id: "swift",
    shadow: "packages/compiler/reflaxe/swift/std-shadow",
    signature: "func toString() -> String",
  },
  {
    compilerClass: "dartcompiler.Compiler.use()",
    define: "dart-output",
    file: "lib/boring/printed_record.dart",
    id: "dart",
    shadow: "packages/compiler/reflaxe/dart/std-shadow",
    signature: "String toString()",
    testDefine: "dart-test-output",
  },
  {
    compilerClass: "rustcompiler.Compiler.use()",
    define: "rust-output",
    file: "boring/printed_record.rs",
    id: "rust",
    shadow: "packages/compiler/reflaxe/rust/std-shadow",
    signature: "pub fn to_string(&self) -> String",
  },
];

function read(relative: string): string {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

function memberBody(content: string, signature: string): string {
  const start = content.indexOf(signature);
  expect(start).toBeGreaterThanOrEqual(0);
  const end = content.indexOf("\n  }", start) >= 0
    ? content.indexOf("\n  }", start)
    : content.indexOf("\n    }", start);
  expect(end).toBeGreaterThan(start);
  return content.slice(start, end);
}

function outerClass(content: string): string {
  const boundaries = [
    content.indexOf("export class PrintedInner"),
    content.indexOf("final class PrintedInner"),
    content.indexOf("pub struct PrintedInner"),
  ].filter((position) => position >= 0);
  expect(boundaries.length).toBeGreaterThan(0);
  return content.slice(0, Math.min(...boundaries));
}

function sourceVariant(kind: "removed-marker" | "explicit-member"): string {
  const source = read("samples/boring/PrintedRecord.hx");
  if(kind === "removed-marker") {
    const variant = source.replace("@:dataClass\nclass PrintedRecord", "class PrintedRecord");
    expect(variant).not.toContain("@:dataClass\nclass PrintedRecord");
    return variant;
  }
  const variant = source.replace(
    "\n}\n\n@:dataClass\nclass PrintedInner",
    '\n\n\tpublic function toString():String {\n\t\treturn "explicit";\n\t}\n}\n\n@:dataClass\nclass PrintedInner',
  );
  expect(variant).toContain('return "explicit";');
  return variant;
}

async function generateMutation(
  rootDir: string,
  variant: "removed-marker" | "explicit-member",
  target: TargetConfig,
): Promise<string> {
  const sourceRoot = path.join(rootDir, variant, "samples");
  const sourceFile = path.join(sourceRoot, "boring/PrintedRecord.hx");
  const output = path.join(rootDir, variant, target.id);
  const hxml = path.join(rootDir, `${variant}-${target.id}.hxml`);
  fs.mkdirSync(path.dirname(sourceFile), { recursive: true });
  fs.writeFileSync(sourceFile, sourceVariant(variant));
  fs.writeFileSync(hxml, [
    "-lib reflaxe",
    "-lib boring",
    `-cp ${path.join(root, target.shadow)}`,
    `-cp ${path.join(root, target.shadow.replace("/std-shadow", ""))}`,
    `-cp ${path.join(root, "samples")}`,
    `-cp ${sourceRoot}`,
    `--macro Intercept.run(["${sourceRoot}"])`,
    "--macro haxe.macro.Compiler.addGlobalMetadata('boring', '@:build(std.RecordMember.build())')",
    `--macro ${target.compilerClass}`,
    `-D ${target.define}=${output}`,
    ...(target.testDefine == null ? [] : [`-D ${target.testDefine}=${path.join(rootDir, variant, `${target.id}-tests`)}`]),
    "boring.PrintedRecord",
    "",
  ].join("\n"));

  const proc = Bun.spawn(["haxe", hxml], {
    cwd: root,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [exitCode, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  expect({ exitCode, stdout, stderr }).toEqual({ exitCode: 0, stdout: "", stderr: "" });
  return read(path.relative(root, path.join(output, target.file)));
}

describe("record printed-member generated trees", () => {
  test("four non-native targets synthesize the constructor-ordered member", () => {
    for(const tree of memberTrees) {
      const content = read(tree.file);
      const body = memberBody(content, tree.signature);
      let previous = -1;
      for(const field of tree.fields) {
        const position = body.indexOf(field);
        expect(position).toBeGreaterThan(previous);
        previous = position;
      }
      expect(body).toContain(tree.fields[2] + (tree.file.includes("rust") ? ").clone().to_string()" : ".toString()"));
    }
  });

  test("Kotlin keeps native data-class printing and renders explicit text", () => {
    for(const file of [
      "reference/kotlin/gen/boring/PrintedRecord.kt",
      "reference/kotlin-f32/gen/boring/PrintedRecord.kt",
    ]) {
      const content = read(file);
      const start = content.indexOf("data class PrintedRecord");
      const end = content.indexOf("data class PrintedInner");
      expect(start).toBeGreaterThanOrEqual(0);
      expect(end).toBeGreaterThan(start);
      expect(content.slice(start, end)).not.toContain("toString");
    }

    for(const file of [
      "reference/kotlin/gen/boring/PrintedCustom.kt",
      "reference/kotlin-f32/gen/boring/PrintedCustom.kt",
    ]) {
      expect(read(file)).toContain("override fun toString(): String");
    }
  });

  test("marker and explicit-member mutations affect the four emitted members", async () => {
    const mutationRoot = fs.mkdtempSync(path.join(root, ".printed-record-mutation-"));
    try {
      for(const target of mutationTargets) {
        const removed = await generateMutation(mutationRoot, "removed-marker", target);
        expect(outerClass(removed)).not.toContain(target.signature);

        const explicit = await generateMutation(mutationRoot, "explicit-member", target);
        const explicitOuter = outerClass(explicit);
        expect(explicitOuter).toContain(target.signature);
        const firstMember = explicitOuter.indexOf(target.signature);
        expect(firstMember).toBeGreaterThanOrEqual(0);
        expect(explicitOuter.indexOf(target.signature, firstMember + target.signature.length)).toBe(-1);
        expect(explicitOuter).toContain("explicit");
      }
    } finally {
      fs.rmSync(mutationRoot, { recursive: true, force: true });
    }
  }, 120_000);
});
