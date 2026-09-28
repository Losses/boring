package driver;

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
        tools/test-consistency/mechanism-coverage.json names the
        project, and the file found is the file the check reads. A
        consumer project's results directory sits outside every boring
        checkout, so the walk finds nothing and the check is skipped
        (feature spec 59); boring's own results directory resolves
        inside the repository, so the gate keeps running there.
    **/
    static function findMechanismCoverage(resultsDir:String):String {
        // Resolve to an absolute path so the walk starts at the results
        // directory itself whatever the invocation named.
        var dir = Path.normalize(Path.join(Process.cwd(), resultsDir));
        final marker = "tools/test-consistency/mechanism-coverage.json";
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

    static function containsName(names:Array<String>, wanted:String):Bool {
        for (name in names) if (name == wanted) return true;
        return false;
    }

    static function checkMechanismCoverage(allIds:Array<String>, path:String):Bool {
        if (!exists(path)) {
            printErr('Error: Missing mechanism coverage file: $path');
            return false;
        }
        var data:JsonValue = Json.read("{}");
        try {
            data = Json.read(readFile(path));
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
            final reasonText:String = cast(reason, String);
            if (StringTools.trim(reasonText) == "") {
                printErr("Error: Every uncovered mechanism requires a reason.");
                return false;
            }
            final mechanismName:String = cast(name, String);
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
                final probeName:String = cast(name, String);
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
        final comparison = CompareCore.run(inputs, baselineTarget);
        for (line in comparison.lines) outputLine(line);
        final coveragePath = findMechanismCoverage(resultsDir);
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
