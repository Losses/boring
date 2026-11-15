import { describe, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

/**
 * Import-form guard for the reflaxe TypeScript target
 * (packages/compiler/reflaxe/ts/tscompiler/TsImports.hx, importedNames).
 *
 * A generated module imports exactly the names its body reads. A name read
 * at runtime must stay a plain binding; a name read only in a type position
 * must bind with the inline `type` modifier. An interface or typedef lowers
 * to `export interface`, which has no runtime binding, so a plain value
 * import of it throws "does not provide an export named" under Node ESM
 * before any code runs.
 *
 * The check classifies every declaration of the target module by face: a
 * class has a value face and a type face, an interface or type alias has a
 * type face only, a function or const has a value face only. Then
 *
 *   - a plain specifier requires a value face on the target declaration;
 *   - a `type` specifier requires a type face on the target declaration.
 *
 * The pre-fix shape `import { EnvVar } from "./EnvVar.ts"` (EnvVar is an
 * interface) fails the first rule. A value wrongly marked `type` fails the
 * second. `bun run typecheck` is the independent reverse check: tsc rejects
 * a type-only binding that the body reads as a value.
 */

const GEN = resolve(import.meta.dir, "../../reference/ts/gen");

interface Faces {
  value: boolean;
  type: boolean;
}

interface Specifier {
  name: string;
  typeOnly: boolean;
}

interface ImportStatement {
  specifiers: Specifier[];
  module: string;
}

/** Every generated TypeScript file under the tree, sorted for stable output. */
function generatedFiles(dir: string): string[] {
  const out: string[] = [];
  for(const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if(entry.isDirectory()) out.push(...generatedFiles(path));
    else if(entry.name.endsWith(".ts")) out.push(path);
  }
  out.sort();
  return out;
}

/** Declaration names of one module, keyed by the faces the declaration has. */
function facesOf(source: string): Map<string, Faces> {
  const faces = new Map<string, Faces>();
  const add = (name: string, kind: "value" | "type"): void => {
    const current = faces.get(name) ?? { value: false, type: false };
    current[kind] = true;
    faces.set(name, current);
  };
  // A class or enum is a value and carries an instance type; an interface or
  // type alias is a type only; a function, const or namespace is a value only.
  for(const match of source.matchAll(/^export (?:abstract )?(?:class|enum) ([A-Za-z0-9_$]+)/gm)) {
    add(match[1]!, "value");
    add(match[1]!, "type");
  }
  for(const match of source.matchAll(/^export (?:function|const|let|var|namespace) ([A-Za-z0-9_$]+)/gm)) {
    add(match[1]!, "value");
  }
  for(const match of source.matchAll(/^export (?:interface|type) ([A-Za-z0-9_$]+)/gm)) {
    add(match[1]!, "type");
  }
  return faces;
}

/** Named import bindings of one module, with the inline type marker split out. */
function importStatements(source: string): ImportStatement[] {
  const out: ImportStatement[] = [];
  for(const match of source.matchAll(/^import \{([^}]*)\} from "([^"]+)";$/gm)) {
    const specifiers: Specifier[] = [];
    for(const raw of match[1]!.split(",")) {
      const trimmed = raw.trim();
      if(trimmed === "") continue;
      const typeOnly = trimmed.startsWith("type ");
      const binding = typeOnly ? trimmed.slice("type ".length).trim() : trimmed;
      const name = binding.split(/\s+as\s+/)[0]!.trim();
      specifiers.push({ name, typeOnly });
    }
    out.push({ specifiers, module: match[2]! });
  }
  return out;
}

/** Resolves a generated relative specifier to its emitted sibling file. */
function targetFile(importing: string, module: string): string | null {
  if(!module.startsWith("./") && !module.startsWith("../")) return null;
  const base = resolve(dirname(importing), module);
  if(base.endsWith(".ts") && existsSync(base)) return base;
  if(existsSync(base + ".ts")) return base + ".ts";
  return null;
}

describe("type-only import forms in the generated tree", () => {
  test("an interface target binds with the inline type modifier", () => {
    const source = readFileSync(join(GEN, "driver/CommandStep.ts"), "utf8");
    expect(source).toContain('import { type EnvVar } from "./EnvVar.ts";');
  });

  test("a name read at runtime keeps the plain binding beside a type binding", () => {
    const source = readFileSync(join(GEN, "registry/Main.ts"), "utf8");
    expect(source).toContain('import { Core, type InputRecord } from "./Core.ts";');
  });

  test("each specifier face matches the target declaration face", () => {
    let plainChecked = 0;
    let typeChecked = 0;
    for(const file of generatedFiles(GEN)) {
      const source = readFileSync(file, "utf8");
      for(const statement of importStatements(source)) {
        const target = targetFile(file, statement.module);
        if(target === null) continue;
        const faces = facesOf(readFileSync(target, "utf8"));
        for(const specifier of statement.specifiers) {
          const declared = faces.get(specifier.name);
          const where = file + " -> " + statement.module + " (" + specifier.name + ")";
          if(specifier.typeOnly) {
            expect(existsSync(target), where).toBe(true);
            expect(declared !== undefined && declared.type, "type specifier needs a type face: " + where).toBe(true);
            typeChecked += 1;
          } else {
            expect(declared !== undefined && declared.value, "plain specifier needs a value face: " + where).toBe(true);
            plainChecked += 1;
          }
        }
      }
    }
    expect(typeChecked, "no type-marked specifier observed; the guard would be vacuous").toBeGreaterThan(0);
    expect(plainChecked, "too few plain specifiers; the guard would be weak").toBeGreaterThan(20);
  });
});
