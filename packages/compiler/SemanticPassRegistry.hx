import haxe.macro.Context;
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

    public static function validate():Void {
        var cache = new Map<String, String>();
        for (entry in consumers)
            for (target in entry.targets) {
                final dir = SemanticExceptionLedger.repoRoot() + "/packages/compiler/reflaxe/" + target;
                for (file in files(dir))
                    cache.set(file, File.getContent(file));
                var count = 0;
                for (content in cache)
                    if (consumes(content, entry.module))
                        count++;
                if (count == 0)
                    Context.error("target " + target + " does not consume registered shared mechanism " + entry.module, Context.currentPos());
                cache = new Map<String, String>();
            }
    }

    /**
        A target consumes a mechanism when code outside comments and string
        literals references the module. The detector blanks comments and
        string contents first, so a name that survives only inside them is
        not a consumer. The import check requires the exact module name
        followed by a separator, so a longer name with the same prefix is
        not a consumer either.
    **/
    static function consumes(content:String, module:String):Bool {
        final code = stripLiterals(stripComments(content));
        if (code.indexOf(module + ".") >= 0)
            return true;
        var at = code.indexOf("import ");
        while (at >= 0) {
            final name = at + "import ".length;
            if (code.substr(name, module.length) == module) {
                final after = code.charAt(name + module.length);
                if (after == ";" || after == "." || after == " ")
                    return true;
            }
            at = code.indexOf("import ", at + 1);
        }
        return false;
    }

    /** Replace every character inside a string literal with a space. **/
    static function stripLiterals(source:String):String {
        final result = new StringBuf();
        var i = 0;
        while (i < source.length) {
            final c = source.charAt(i);
            if (c == "\"" || c == "'") {
                final quote = c;
                result.add(c);
                i++;
                while (i < source.length && source.charAt(i) != quote) {
                    if (source.charAt(i) == "\\" && i + 1 < source.length) {
                        result.add(" ");
                        i += 2;
                    } else {
                        result.add(" ");
                        i++;
                    }
                }
                if (i < source.length) {
                    result.add(source.charAt(i));
                    i++;
                }
                continue;
            }
            result.add(c);
            i++;
        }
        return result.toString();
    }

    static function stripComments(source:String):String {
        final result = new StringBuf();
        var i = 0;
        while (i < source.length) {
            final c = source.charAt(i);
            final next = i + 1 < source.length ? source.charAt(i + 1) : "";
            if (c == "/" && next == "/") {
                while (i < source.length && source.charAt(i) != "\n")
                    i++;
                if (i < source.length)
                    i++;
                continue;
            }
            if (c == "/" && next == "*") {
                i += 2;
                while (i + 1 < source.length && !(source.charAt(i) == "*" && source.charAt(i + 1) == "/"))
                    i++;
                i += 2;
                result.add(" ");
                continue;
            }
            if (c == "\"" || c == "'") {
                final quote = c;
                result.add(c);
                i++;
                while (i < source.length && source.charAt(i) != quote) {
                    if (source.charAt(i) == "\\") {
                        result.add(source.charAt(i));
                        i++;
                    }
                    if (i < source.length) {
                        result.add(source.charAt(i));
                        i++;
                    }
                }
                if (i < source.length) {
                    result.add(source.charAt(i));
                    i++;
                }
                continue;
            }
            result.add(c);
            i++;
        }
        return result.toString();
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
