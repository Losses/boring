import haxe.Json;
import sys.FileSystem;
import sys.io.File;

class SemanticPassRegistry {
    static final consumers:Array<{module:String, targets:Array<String>}> = [
        {module: "DataTableHelper", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "DefaultArgExpander", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "EnumCycleDetector", targets: ["rust", "swift"]},
        {module: "EnumQueryExpander", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "ExpressionPredicates", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "FloatPrecision", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "FusionPlan", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "Intercept", targets: ["swift"]},
        {module: "NameConversion", targets: ["dart", "swift"]},
        {module: "PackageArtifacts", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "PackageShell", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "PipelineExpander", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "PolicyQueries", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "RuntimeConfig", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "RuntimeResidents", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "SealedVariantHelper", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "StaticFieldHelper", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "StaticFunctionMarkers", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "StaticReferenceScan", targets: ["dart", "rust"]},
        {module: "StructuralKeyValidator", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "TerminationAnalysis", targets: ["dart", "rust"]},
        {module: "TypeCheckHelper", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "ValueTypeSupport", targets: ["dart", "kotlin", "rust", "swift", "ts"]}
    ];

    /** Whether `target` is expected to consume `module` directly. */
    public static function expected(module:String, target:String):Bool {
        for (entry in consumers) {
            if (entry.module == module) {
                return entry.targets.indexOf(target) >= 0;
            }
        }
        return false;
    }

    /**
        Write the consumer table for the trace runner. The table stays the
        single source of truth: the runner reads this artifact instead of
        restating the expectations in TypeScript.
    **/
    public static function emitArtifact():Void {
        final root = SemanticExceptionLedger.repoRoot();
        final rows = [for (entry in consumers) {module: entry.module, targets: entry.targets}];
        FileSystem.createDirectory(root + "/out");
        File.saveContent(root + "/out/shared-module-consumers.json", Json.stringify({modules: rows}, null, "  ") + "\n");
    }
}
