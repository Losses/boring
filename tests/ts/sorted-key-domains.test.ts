import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("sorted key domains generated tree", () => {
  const genDir = path.resolve(__dirname, "../../reference/ts/gen");

  test("TS generated tree exports comparison function for structure keys", () => {
    const clusterTagsPath = path.join(genDir, "boring/ClusterTags.ts");
    expect(fs.existsSync(clusterTagsPath)).toBe(true);
    const content = fs.readFileSync(clusterTagsPath, "utf8");
    expect(content).toContain("export function compareClusterTag(");
    expect(content).toContain("export function compareSubTag(");
  });

  test("Structure key builder call site injects the comparator reference", () => {
    const clusterTagsPath = path.join(genDir, "boring/ClusterTags.ts");
    const content = fs.readFileSync(clusterTagsPath, "utf8");
    expect(content).toContain("SortedTable.mapBuilder<ClusterTag, number>(compareClusterTag)");
    expect(content).toContain("SortedTable.setBuilder<ClusterTag>(compareClusterTag)");
  });

  test("Int key builder call site binds the resident comparator", () => {
    const codePointNamesPath = path.join(genDir, "boring/CodePointNames.ts");
    expect(fs.existsSync(codePointNamesPath)).toBe(true);
    const content = fs.readFileSync(codePointNamesPath, "utf8");
    expect(content).toContain("SortedTable.mapBuilder<number, string>(SortedTable.compareInts)");
    expect(content).not.toContain("function compare");
  });

  test("String key builder call site binds the resident comparator", () => {
    const scriptNamesPath = path.join(genDir, "boring/ScriptNames.ts");
    expect(fs.existsSync(scriptNamesPath)).toBe(true);
    const content = fs.readFileSync(scriptNamesPath, "utf8");
    expect(content).toContain("SortedTable.mapBuilder<string, number>(SortedTable.compareStrings)");
  });

  test("Rust generated tree widens an int capacity bound without an error enum", () => {
    const clusterTagsPath = path.resolve(__dirname, "../../reference/rust-gen/src/boring/cluster_tags.rs");
    expect(fs.existsSync(clusterTagsPath)).toBe(true);
    const content = fs.readFileSync(clusterTagsPath, "utf8");
    expect(content).toContain("let capacity = usize::try_from(u32::from_ne_bytes((set.size()).to_ne_bytes())).unwrap_or(0);");
    expect(content).toContain("let mut scores = Vec::with_capacity(capacity);");
  });
});
