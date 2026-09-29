import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const targets = ["dart", "kotlin", "rust", "swift", "ts"];
// This backstop mirrors the SemanticPassRegistry consumers table. The
// ComparatorPlan row is removed: the four target consumers migrated to
// SourceComparisonAnalysis plans and Swift mentions the module only in a
// comment (registry comment control:
// tests/haxe/semantic-registry-comment-control/run.sh). The
// EnumCycleDetector row lists the real consumers rust and swift; dart,
// kotlin and ts reach the detector through PolicyQueries.
const modules = ["DataTableHelper", "DefaultArgExpander", "EnumCycleDetector", "EnumQueryExpander", "ExpressionPredicates", "FloatPrecision", "FusionPlan", "Intercept", "NameConversion", "PackageArtifacts", "PackageShell", "PipelineExpander", "PolicyQueries", "RuntimeConfig", "RuntimeResidents", "SealedVariantHelper", "StaticFieldHelper", "StaticFunctionMarkers", "StaticReferenceScan", "StructuralKeyValidator", "TerminationAnalysis", "TypeCheckHelper", "ValueTypeSupport"];
const consumers: Record<string, string[]> = {
  DataTableHelper: targets, DefaultArgExpander: targets, EnumCycleDetector: ["rust", "swift"], EnumQueryExpander: targets, ExpressionPredicates: targets, FloatPrecision: targets, FusionPlan: targets, Intercept: ["swift"], NameConversion: ["dart", "swift"], PackageArtifacts: targets, PackageShell: targets, PipelineExpander: targets, PolicyQueries: targets, RuntimeConfig: targets, RuntimeResidents: targets, SealedVariantHelper: targets, StaticFieldHelper: targets, StaticFunctionMarkers: targets, StaticReferenceScan: ["dart", "rust"], StructuralKeyValidator: targets, TerminationAnalysis: ["dart", "rust"], TypeCheckHelper: targets, ValueTypeSupport: targets
};
function files(dir: string): string[] { return !existsSync(dir) ? [] : readdirSync(dir, { withFileTypes: true }).flatMap(entry => entry.isDirectory() ? files(join(dir, entry.name)) : entry.name.endsWith(".hx") ? [join(dir, entry.name)] : []); }
for (const module of modules) {
  for (const target of consumers[module]!) {
    const content = files(join(root, "packages/compiler/reflaxe", target)).map(file => readFileSync(file, "utf8")).join("\n");
    if (content.indexOf(module) < 0) throw new Error(`target ${target} does not consume registered shared mechanism ${module}`);
    if (new RegExp(`^\\s*(?:enum|class|typedef|abstract)\\s+${module}\\b`, "m").test(content)) throw new Error(`target ${target} redefines registered shared mechanism ${module}`);
  }
}
