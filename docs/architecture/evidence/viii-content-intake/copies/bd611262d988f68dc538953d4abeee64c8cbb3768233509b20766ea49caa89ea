import haxe.Json;
import js.Syntax;

typedef TestRecord = {
    id:String,
    ?name:String,
    verdict:String,
    ?message:String
};

class Main {
    static function exists(path:String):Bool {
        return Syntax.code("require('fs').existsSync({0})", path);
    }

    static function readFile(path:String):String {
        return Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
    }

    static function print(s:String):Void {
        Syntax.code("process.stdout.write({0} + '\\n')", s);
    }

    static function printErr(s:String):Void {
        Syntax.code("process.stderr.write({0})", s);
    }

    static function exit(code:Int):Void {
        Syntax.code("process.exit({0})", code);
    }

    static function getArgs():Array<String> {
        final raw:Array<String> = Syntax.code("process.argv.slice(2)");
        return raw;
    }

    static function getEnv(key:String):Null<String> {
        return Syntax.code("process.env[{0}] || null", key);
    }

    /**
        The mechanism-coverage declaration of the project the results
        directory belongs to, or null when no project up the chain
        declares one. The nearest ancestor holding
        tools/test-consistency/mechanism-coverage.json names the
        project, and the file found is the file the check reads. A
        consumer project's results directory sits outside every boring
        checkout, so the walk finds nothing and the check is skipped
        (feature spec 59); boring's own results directory resolves
        inside the repository, so the gate keeps running there.
    **/
    static function findMechanismCoverage(resultsDir:String):Null<String> {
        // Resolve to an absolute path so the walk starts at the results
        // directory itself whatever the invocation named.
        var dir:String = Syntax.code("require('path').resolve({0})", resultsDir);
        final marker = "tools/test-consistency/mechanism-coverage.json";
        while (true) {
            final candidate:String = Syntax.code("require('path').join({0}, {1})", dir, marker);
            if (exists(candidate)) {
                return candidate;
            }
            final parent:String = Syntax.code("require('path').dirname({0})", dir);
            if (parent == dir) {
                break;
            }
            dir = parent;
        }
        return null;
    }

    static function checkMechanismCoverage(allIds:Array<String>, path:String):Bool {
        if (!exists(path)) {
            printErr('Error: Missing mechanism coverage file: $path\\n');
            return false;
        }
        final data:Dynamic = Json.parse(readFile(path));
        final covered:Array<Dynamic> = data.covered;
        final allowlisted:Array<Dynamic> = data.uncoveredAllowlist;
        final allowlist = new Map<String, Bool>();
        for (entry in allowlisted) {
            if (entry.mechanism == null || entry.reason == null || StringTools.trim(entry.reason) == "") {
                printErr("Error: Every uncovered mechanism requires a reason.\\n");
                return false;
            }
            allowlist.set(entry.mechanism, true);
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
        final coveredByName = new Map<String, Bool>();
        for (entry in covered)
            coveredByName.set(entry.mechanism, true);
        final errors:Array<String> = [];
        for (mechanism in mechanisms) {
            if (!coveredByName.exists(mechanism) && !allowlist.exists(mechanism))
                errors.push('$mechanism is missing from coverage data');
        }
        for (entry in allowlisted) {
            if (coveredByName.exists(entry.mechanism))
                errors.push('${entry.mechanism} is both covered and allowlisted');
        }
        var coveredCount = 0;
        for (entry in covered) {
            final mechanism:String = entry.mechanism;
            if (allowlist.exists(mechanism)) {
                errors.push('$mechanism is both covered and allowlisted');
                continue;
            }
            final probes:Array<Dynamic> = entry.probes;
            if (probes == null || probes.length == 0) {
                errors.push('$mechanism has no probes');
                continue;
            }
            coveredCount++;
            for (probe in probes) {
                final name:String = probe;
                var found = false;
                for (id in allIds) {
                    if (id.indexOf(name) >= 0) {
                        found = true;
                        break;
                    }
                }
                if (!found)
                    errors.push('$mechanism names nonexistent probe $name');
            }
        }
        print('Mechanism coverage: covered $coveredCount / allowlisted ${allowlisted.length}');
        if (errors.length > 0) {
            printErr('Mechanism coverage check failed for: ${errors.join(", ")}\\n');
            return false;
        }
        return true;
    }

    public static function main() {
        var resultsDir = "out/test-results";
        var targets = ["kotlin", "haxe", "ts", "rust", "swift", "dart"];
        var baselineTarget = "kotlin";

        final args = getArgs();
        var i = 0;
        while (i < args.length) {
            final arg = args[i];
            if (StringTools.startsWith(arg, "--dir=")) {
                resultsDir = arg.substr(6);
            } else if (arg == "--dir" && i + 1 < args.length) {
                resultsDir = args[i + 1];
                i++;
            } else if (StringTools.startsWith(arg, "--targets=")) {
                targets = arg.substr(10).split(",");
            } else if (StringTools.startsWith(arg, "--baseline=")) {
                baselineTarget = arg.substr(11);
            } else if (arg == "--baseline" && i + 1 < args.length) {
                baselineTarget = args[i + 1];
                i++;
            }
            i++;
        }

        final envDir = getEnv("BORING_TEST_RESULTS_DIR");
        if (envDir != null && envDir != "") {
            resultsDir = envDir;
        }

        // 1. Verify existence of results file for every target
        var hasMissingFiles = false;
        final targetFiles = new Map<String, String>();
        for (target in targets) {
            final filePath = resultsDir + "/" + target + ".jsonl";
            targetFiles.set(target, filePath);
            if (!exists(filePath)) {
                printErr('Error: Missing test results file for target \'$target\': $filePath\n');
                hasMissingFiles = true;
            }
        }

        if (hasMissingFiles) {
            exit(1);
            return;
        }

        // 2. Parse JSONL files
        final targetRecords = new Map<String, Map<String, TestRecord>>();
        final notApplicableIds = new Map<String, Map<String, Bool>>();
        final verdictIds = new Map<String, Map<String, Bool>>();
        final allIdsMap = new Map<String, Bool>();

        for (target in targets) {
            final filePath = targetFiles.get(target);
            final records = new Map<String, TestRecord>();
            final notApplicable = new Map<String, Bool>();
            final verdict = new Map<String, Bool>();
            final content = readFile(filePath);
            final lines = content.split("\n");
            for (line in lines) {
                final trimmed = StringTools.trim(line);
                if (trimmed.length == 0)
                    continue;
                try {
                    final parsed:TestRecord = Json.parse(trimmed);
                    if (parsed.id != null && parsed.verdict != null) {
                        records.set(parsed.id, parsed);
                        if (parsed.verdict == "not_applicable") {
                            notApplicable.set(parsed.id, true);
                        } else {
                            verdict.set(parsed.id, true);
                        }
                        allIdsMap.set(parsed.id, true);
                    }
                } catch (e:Dynamic) {
                    printErr('Error: Failed to parse JSONL line in $filePath: $trimmed\n');
                    exit(1);
                    return;
                }
            }
            targetRecords.set(target, records);
            notApplicableIds.set(target, notApplicable);
            verdictIds.set(target, verdict);
        }

        // A target must not both run a test and declare it not applicable:
        // the not-applicable record exists in place of a verdict, so a
        // target that writes both masks a real run behind the declaration
        // (feature spec 19).
        final bothDivergences:Array<String> = [];
        for (target in targets) {
            final notApplicable = notApplicableIds.get(target);
            final verdict = verdictIds.get(target);
            for (id in notApplicable.keys()) {
                if (verdict.exists(id)) {
                    bothDivergences.push('[$target] Test $id has both a not_applicable record and a verdict; a declared exclusion must not run the test');
                }
            }
        }

        final allIds = [for (id in allIdsMap.keys()) id];
        allIds.sort(Reflect.compare);

        final baselineRecords = targetRecords.get(baselineTarget);
        if (baselineRecords == null || allIds.length == 0) {
            printErr('Error: Baseline target \'$baselineTarget\' produced no test records.\n');
            exit(1);
            return;
        }

        // 3. Matrix header and comparison
        final colWidths = new Map<String, Int>();
        var maxIdLen = "TEST ID".length;
        for (id in allIds) {
            if (id.length > maxIdLen)
                maxIdLen = id.length;
        }
        colWidths.set("id", maxIdLen);

        for (target in targets) {
            final header = target == baselineTarget ? target + " (baseline)" : target;
            var maxLen = header.length;
            for (id in allIds) {
                final rec = targetRecords.get(target).get(id);
                final statusStr = rec != null ? rec.verdict : "MISSING";
                if (statusStr.length > maxLen)
                    maxLen = statusStr.length;
            }
            colWidths.set(target, maxLen);
        }

        // Build Matrix Header
        final headerParts = [StringTools.rpad("TEST ID", " ", colWidths.get("id"))];
        for (target in targets) {
            final header = target == baselineTarget ? target + " (baseline)" : target;
            headerParts.push(StringTools.rpad(header, " ", colWidths.get(target)));
        }
        final separatorParts = [
            for (target in ["id"].concat(targets))
                StringTools.rpad("", "-", colWidths.get(target))
        ];

        print(headerParts.join(" | "));
        print(separatorParts.join("-+-"));

        final divergences:Array<String> = [];

        for (id in allIds) {
            final baseRec = baselineRecords.get(id);
            final rowParts = [StringTools.rpad(id, " ", colWidths.get("id"))];

            for (target in targets) {
                final rec = targetRecords.get(target).get(id);
                final cellStr = rec != null ? rec.verdict : "MISSING";
                rowParts.push(StringTools.rpad(cellStr, " ", colWidths.get(target)));

                if (target != baselineTarget) {
                    if (baseRec == null && rec != null) {
                        divergences.push('[$target] Extra test ID not in baseline: $id');
                    } else if (baseRec != null && rec == null) {
                        divergences.push('[$target] Missing test ID present in baseline: $id');
                    } else if (baseRec != null && rec != null) {
                        if (rec.verdict == "not_applicable") {
                            // The target declares the test not applicable and
                            // the baseline carries the id: a declared
                            // exclusion, counted in the matrix and not a
                            // divergence (feature spec 19).
                        } else if (baseRec.verdict == "not_applicable") {
                            // The baseline declares the test not applicable;
                            // a target that runs it keeps its own verdict.
                            // The runner name must still match.
                            final baseName = baseRec.name != null ? baseRec.name : "";
                            final recName = rec.name != null ? rec.name : "";
                            if (baseName != recName) {
                                divergences.push('[$target] Runner name mismatch on $id:\n  baseline: $baseName\n  actual:   $recName');
                            }
                        } else {
                            if (baseRec.verdict != rec.verdict) {
                                divergences.push('[$target] Verdict mismatch on $id: baseline=${baseRec.verdict}, actual=${rec.verdict}');
                            } else {
                                final baseName = baseRec.name != null ? baseRec.name : "";
                                final recName = rec.name != null ? rec.name : "";
                                if (baseName != recName) {
                                    divergences.push('[$target] Runner name mismatch on $id:\n  baseline: $baseName\n  actual:   $recName');
                                }
                            }
                            if (baseRec.verdict == rec.verdict && baseRec.verdict == "fail") {
                                final baseMsg = baseRec.message != null ? baseRec.message : "";
                                final recMsg = rec.message != null ? rec.message : "";
                                if (baseMsg != recMsg) {
                                    divergences.push('[$target] Failure message mismatch on $id:\n  baseline: $baseMsg\n  actual:   $recMsg');
                                }
                            }
                        }
                    }
                }
            }

            print(rowParts.join(" | "));
        }

        print("");
        // The mechanism-coverage gate belongs to the project that owns
        // the results directory: it runs only when that project declares
        // its mechanisms through the coverage file, so a consumer's
        // comparison is judged by the divergence list alone while
        // boring's own runs keep the gate (feature spec 59).
        final coveragePath = findMechanismCoverage(resultsDir);
        var coverageOk = true;
        if (coveragePath != null) {
            coverageOk = checkMechanismCoverage(allIds, coveragePath);
        } else {
            print("Mechanism coverage: skipped; the results directory declares no mechanisms.");
        }
        final allDivergences = divergences.concat(bothDivergences);
        if (allDivergences.length == 0 && coverageOk) {
            print('All ${targets.length} targets (${targets.join(", ")}) are 100% consistent across ${allIds.length} tests.');
            exit(0);
        } else {
            printErr('Cross-target consistency check failed with ${allDivergences.length} divergence(s):\n');
            for (d in allDivergences) {
                printErr('  * $d\n');
            }
            exit(1);
        }
    }
}
