import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;

class SemanticPassRegistry {
    static final consumers:Array<{module:String, targets:Array<String>}> = [
        {module: "ComparatorPlan", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "DataTableHelper", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "DefaultArgExpander", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
        {module: "EnumCycleDetector", targets: ["dart", "kotlin", "rust", "swift", "ts"]},
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

    public static function validate():Void {
        var cache = new Map<String, String>();
        for (entry in consumers)
            for (target in entry.targets) {
                final dir = SemanticExceptionLedger.repoRoot() + "/packages/compiler/reflaxe/" + target;
                for (file in files(dir))
                    cache.set(file, File.getContent(file));
                var count = 0;
                for (content in cache)
                    if (content.indexOf(entry.module) >= 0)
                        count++;
                if (count == 0)
                    Context.error("target " + target + " does not consume registered shared mechanism " + entry.module, Context.currentPos());
                cache = new Map<String, String>();
            }
    }

    static function files(dir:String):Array<String> {
        var result:Array<String> = [];
        if (!FileSystem.exists(dir))
            return result;
        for (name in FileSystem.readDirectory(dir)) {
            final path = dir + "/" + name;
            if (FileSystem.isDirectory(path))
                result = result.concat(files(path));
            else if (StringTools.endsWith(name, ".hx"))
                result.push(path);
        }
        return result;
    }
}
