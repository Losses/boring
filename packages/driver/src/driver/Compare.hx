package driver;

import driver.Comparison.ExtraEntry;
import registry.Json;
import registry.Json.JsonValue;
import registry.JsonException;
import std.Console;
import std.Path;
import std.Process;
#if (ts_output || kotlin_output || rust_output || swift_output || dart_output)
import std.Fs;
#else
import js.Syntax;
#end

class Compare {
    static function exists(path:String):Bool {
        #if (ts_output || kotlin_output || rust_output || swift_output || dart_output)
        return Fs.exists(path);
        #else
        return Syntax.code("require('fs').existsSync({0})", path);
        #end
    }

    static function readFile(path:String):String {
        #if (ts_output || kotlin_output || rust_output || swift_output || dart_output)
        return Fs.readText(path);
        #else
        return Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
        #end
    }

    static function outputLine(s:String):Void {
        Console.log(s);
    }

    static function printErr(s:String):Void {
        Console.error(StringTools.endsWith(s, "\n") ? s.substr(0, s.length - 1) : s);
    }

    static function exit(code:Int):Void {
        Process.exit(code);
    }

    /**
        The mechanism-coverage declaration of the project the results
        directory belongs to, or an empty string when no project up the chain
        declares one. The nearest ancestor holding
        packages/test/assertions/consistency/mechanism-coverage.json names the
        project, and the file found is the file the check reads. A
        consumer project's results directory sits outside every boring
        checkout, so the walk finds nothing and the check is skipped
        (feature spec 59); boring's own results directory resolves
        inside the repository, so the gate keeps running there.
    **/
    static function findMechanismCoverage(resultsDir:String, projectFile:String):String {
        // Resolve to an absolute path so the walk starts at the results
        // directory itself whatever the invocation named.
        var dir = Path.normalize(Path.join(Process.cwd(), resultsDir));
        // A project's mechanism declaration belongs to that project. Stop at
        // the nearest boring.json; do not inherit a marker from an enclosing
        // checkout. A consumer project created inside a boring worktree must
        // skip the repository's coverage gate exactly like one created
        // outside it.
        final projectRoot = projectFile == "" ? "" : Path.normalize(Path.dirname(projectFile));
        final marker = "packages/test/assertions/consistency/mechanism-coverage.json";
        while (true) {
            final candidate = Path.join(dir, marker);
            if (exists(candidate)) {
                return candidate;
            }
            if (projectRoot != "" && dir == projectRoot) {
                break;
            }
            final parent = Path.dirname(dir);
            if (parent == dir) {
                break;
            }
            dir = parent;
        }
        return "";
    }

    static function containsName(names:Array<String>, wanted:String):Bool {
        for (name in names) if (name == wanted) return true;
        return false;
    }

    /**
        The bundle project file of the project the results directory belongs
        to, or an empty string when no ancestor holds `boring.json`. The
        nearest ancestor holding it names the project: its bundles carry the
        `rootsFile` entries whose `@only-in` markers declare target-only
        modules.
    **/
    static function findProjectFile(resultsDir:String):String {
        var dir = Path.normalize(Path.join(Process.cwd(), resultsDir));
        final marker = "boring.json";
        while (true) {
            final candidate = Path.join(dir, marker);
            if (exists(candidate)) {
                return candidate;
            }
            final parent = Path.dirname(dir);
            if (parent == dir) {
                break;
            }
            dir = parent;
        }
        return "";
    }

    static function readText(path:String):String {
        return readFile(path);
    }

    /**
        The target-only declarations of the project, derived from the
        `# @only-in: <scope> <module>` markers in the roots files of every
        bundle in `boring.json`. A marker names a dimension and a side --
        `precision:binary64`, `precision:f32`, `target:<target>` -- and the
        entry it produces lists every bundle whose target/precision is on
        that side, so a test id may be a declared extra for exactly those
        bundles. The roots guard verifies the same markers against the tree
        (the module is rooted on the declared side and nowhere else), so a
        marker is never a per-id allowlist: ids follow their module.
        A project without boring.json, or with a bundle whose roots file is
        missing, contributes no declarations; the ids then fail as extras
        exactly as they did before.
    **/
    static function loadOnlyInDeclarations(projectPath:String):Array<ExtraEntry> {
        final entries:Array<ExtraEntry> = [];
        if (projectPath == "" || !exists(projectPath)) {
            return entries;
        }
        final projectDir = Path.dirname(projectPath);
        // boring.json may carry // comment lines (JSONC); drop them before
        // parsing, exactly as the roots guard does.
        final kept:Array<String> = [];
        for (line in readText(projectPath).split("\n")) {
            final text = StringTools.trim(line);
            final comment = text.length > 1 && StringTools.startsWith(text, "//");
            if (!comment) {
                kept.push(line);
            }
        }
        var data:JsonValue;
        try {
            data = Json.read(kept.join("\n"));
        } catch (error:JsonException) {
            return entries;
        }
        final bundles = Json.arrayValues(Json.getField(data, "bundles"));
        if (bundles == null) {
            return entries;
        }
        final ids:Array<String> = [];
        final targets:Array<String> = [];
        final precisions:Array<String> = [];
        final rootsFiles:Array<String> = [];
        for (bundle in bundles) {
            final id = Json.stringValue(Json.getField(bundle, "id"));
            final roots = Json.stringValue(Json.getField(bundle, "rootsFile"));
            if (id == null || roots == null) {
                continue;
            }
            final idText:String = id == null ? "" : id;
            final rootsText:String = roots == null ? "" : roots;
            if (idText == "" || rootsText == "") {
                continue;
            }
            final targetValue = Json.stringValue(Json.getField(bundle, "target"));
            final precisionValue = Json.stringValue(Json.getField(bundle, "precision"));
            ids.push(idText);
            targets.push(targetValue == null ? "" : targetValue);
            precisions.push(precisionValue == null ? "binary64" : precisionValue);
            rootsFiles.push(rootsText);
        }
        for (index in 0...rootsFiles.length) {
            final declaredIn = rootsFiles[index];
            final rootsPath = StringTools.startsWith(declaredIn, "/")
                ? declaredIn
                : Path.join(projectDir, declaredIn);
            if (!exists(rootsPath)) {
                continue;
            }
            var rootsText:String = "";
            try {
                rootsText = readText(rootsPath);
            } catch (error:std.FsException) {
                continue;
            }
            for (line in rootsText.split("\n")) {
                final text = StringTools.trim(line);
                if (!StringTools.startsWith(text, "# @only-in:")) {
                    continue;
                }
                final rest = StringTools.trim(text.substr("# @only-in:".length));
                final space = rest.indexOf(" ");
                if (space < 1) {
                    continue;
                }
                final scope = rest.substr(0, space);
                final moduleName = StringTools.trim(rest.substr(space + 1));
                if (moduleName == "") {
                    continue;
                }
                final colon = scope.indexOf(":");
                if (colon < 1) {
                    continue;
                }
                final dimension = scope.substr(0, colon);
                final side = scope.substr(colon + 1);
                final matching:Array<String> = [];
                for (bundleIndex in 0...ids.length) {
                    final onSide = dimension == "target"
                        ? targets[bundleIndex] == side
                        : dimension == "precision" && precisions[bundleIndex] == side;
                    if (onSide) {
                        matching.push(ids[bundleIndex]);
                    }
                }
                if (matching.length == 0) {
                    continue;
                }
                entries.push({
                    module: moduleName,
                    reason: '@only-in: $scope declared in $declaredIn',
                    bundles: matching
                });
            }
        }
        return entries;
    }

    static function checkMechanismCoverage(allIds:Array<String>, path:String):Bool {
        if (!exists(path)) {
            printErr('Error: Missing mechanism coverage file: $path');
            return false;
        }
        var text:String = "";
        try {
            text = readFile(path);
        } catch (e:std.FsException) {
            printErr('Error: Cannot read mechanism coverage file: $path');
            return false;
        }
        var data:JsonValue = Json.read("{}");
        try {
            data = Json.read(text);
        } catch (error:JsonException) {
            printErr('Error: Invalid mechanism coverage file: $path');
            return false;
        }
        final covered = Json.arrayValues(Json.getField(data, "covered"));
        final allowlisted = Json.arrayValues(Json.getField(data, "uncoveredAllowlist"));
        if (covered == null || allowlisted == null) {
            printErr('Error: Invalid mechanism coverage file: $path');
            return false;
        }
        final allowlist:Array<String> = [];
        for (entry in allowlisted) {
            final name = Json.stringValue(Json.getField(entry, "mechanism"));
            final reason = Json.stringValue(Json.getField(entry, "reason"));
            if (name == null || reason == null) {
                printErr("Error: Every uncovered mechanism requires a reason.");
                return false;
            }
            final reasonText:String = reason == null ? "" : reason;
            if (StringTools.trim(reasonText) == "") {
                printErr("Error: Every uncovered mechanism requires a reason.");
                return false;
            }
            final mechanismName:String = name == null ? "" : name;
            allowlist.push(mechanismName);
        }
        final mechanisms = [
            "ComparatorPlan",
            "DataTableHelper",
            "DataTables",
            "DefaultArgExpander",
            "EnumCycleDetector",
            "EnumQueryExpander",
            "ExpressionPredicates",
            "FloatPrecision",
            "FusionPlan",
            "Intercept",
            "NameConversion",
            "PackageArtifacts",
            "PackageShell",
            "PipelineExpander",
            "PolicyQueries",
            "RuntimeConfig",
            "RuntimeResidents",
            "SealedVariantHelper",
            "StaticFieldHelper",
            "StaticFunctionMarkers",
            "StaticReferenceScan",
            "StructuralKeyValidator",
            "TerminationAnalysis",
            "TestApplicability",
            "TestCollector",
            "TypeCheckHelper",
            "ValueTypeSupport"
        ];
        final coveredByName:Array<String> = [];
        for (entry in covered) {
            final name = Json.stringValue(Json.getField(entry, "mechanism"));
            if (name != null) {
                final mechanismName:String = name == null ? "" : name;
                coveredByName.push(mechanismName);
            }
        }
        final errors:Array<String> = [];
        for (mechanism in mechanisms) {
            if (!containsName(coveredByName, mechanism) && !containsName(allowlist, mechanism))
                errors.push('$mechanism is missing from coverage data');
        }
        for (name in allowlist) {
            if (containsName(coveredByName, name))
                errors.push('$name is both covered and allowlisted');
        }
        var coveredCount = 0;
        for (entry in covered) {
            final nameValue = Json.stringValue(Json.getField(entry, "mechanism"));
            final mechanism:String = nameValue == null ? "" : nameValue;
            if (containsName(allowlist, mechanism)) {
                errors.push('$mechanism is both covered and allowlisted');
                continue;
            }
            final probes = Json.arrayValues(Json.getField(entry, "probes"));
            if (probes == null || probes.length == 0) {
                errors.push('$mechanism has no probes');
                continue;
            }
            coveredCount++;
            for (probe in probes) {
                final name = Json.stringValue(probe);
                if (name == null) {
                    errors.push('$mechanism has a probe that is not a string');
                    continue;
                }
                final probeName:String = name == null ? "" : name;
                var found = false;
                for (id in allIds) {
                    if (id.indexOf(probeName) >= 0) {
                        found = true;
                        break;
                    }
                }
                if (!found)
                    errors.push('$mechanism names nonexistent probe $name');
            }
        }
        outputLine('Mechanism coverage: covered $coveredCount / allowlisted ${allowlisted.length}');
        if (errors.length > 0) {
            printErr('Mechanism coverage check failed for: ${errors.join(", ")}');
            return false;
        }
        return true;
    }

    public static function run(resultsDir:String, targets:Array<String>, baselineTarget:String):Void {
        final inputs:Array<ResultInput> = [];
        var missing = false;
        for (target in targets) {
            final path = Path.join(resultsDir, target + ".jsonl");
            if (!exists(path)) {
                printErr('Error: Missing test results file for target "$target": $path\n');
                missing = true;
            } else {
                inputs.push({id: target, text: readFile(path)});
            }
        }
        if (missing) {
            exit(1);
            return;
        }
        final projectFile = findProjectFile(resultsDir);
        final extraDeclarations = loadOnlyInDeclarations(projectFile);
        final comparison = CompareCore.run(inputs, baselineTarget, extraDeclarations);
        for (line in comparison.lines) outputLine(line);
        if (comparison.declaredExtras.length > 0) {
            outputLine('Declared extra test ids (not in baseline, target-only modules): ${comparison.declaredExtras.length}');
            for (declared in comparison.declaredExtras) outputLine('  - $declared');
        }
        final coveragePath = findMechanismCoverage(resultsDir, projectFile);
        final coverageOk = coveragePath == "" ? true : checkMechanismCoverage(comparison.allIds, coveragePath);
        if (coveragePath == "") outputLine("Mechanism coverage: skipped; the results directory declares no mechanisms.");
        if (comparison.errors.length == 0 && coverageOk) {
            outputLine('All ${targets.length} targets (${targets.join(", ")}) are 100% consistent across ${comparison.allIds.length} tests.');
        } else {
            printErr('Cross-target consistency check failed with ${comparison.errors.length} divergence(s):\n');
            for (error in comparison.errors) printErr('  * $error\n');
            exit(1);
        }
    }
}
