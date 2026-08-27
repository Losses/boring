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
    expect(content).toContain("SortedMapByKey.builder<ClusterTag, number>(compareClusterTag)");
    expect(content).toContain("SortedSetByKey.builder<ClusterTag>(compareClusterTag)");
  });

  test("Int key builder call site has no comparator injection", () => {
    const codePointNamesPath = path.join(genDir, "boring/CodePointNames.ts");
    expect(fs.existsSync(codePointNamesPath)).toBe(true);
    const content = fs.readFileSync(codePointNamesPath, "utf8");
    expect(content).toContain("SortedMap.builder<string>()");
    expect(content).not.toContain("compare");
  });
});
