import haxe.Json;
import js.Syntax;

typedef TestRecord = {
	id: String,
	?name: String,
	verdict: String,
	?message: String
};

class Main {
	static function exists(path: String): Bool {
		return Syntax.code("require('fs').existsSync({0})", path);
	}

	static function readFile(path: String): String {
		return Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
	}

	static function print(s: String): Void {
		Syntax.code("process.stdout.write({0} + '\\n')", s);
	}

	static function printErr(s: String): Void {
		Syntax.code("process.stderr.write({0})", s);
	}

	static function exit(code: Int): Void {
		Syntax.code("process.exit({0})", code);
	}

	static function getArgs(): Array<String> {
		final raw: Array<String> = Syntax.code("process.argv.slice(2)");
		return raw;
	}

	static function getEnv(key: String): Null<String> {
		return Syntax.code("process.env[{0}] || null", key);
	}

	public static function main() {
		var resultsDir = "out/test-results";
		var targets = ["kotlin", "haxe", "ts", "rust"];
		final baselineTarget = "kotlin";

		final args = getArgs();
		var i = 0;
		while(i < args.length) {
			final arg = args[i];
			if(StringTools.startsWith(arg, "--dir=")) {
				resultsDir = arg.substr(6);
			} else if(arg == "--dir" && i + 1 < args.length) {
				resultsDir = args[i + 1];
				i++;
			} else if(StringTools.startsWith(arg, "--targets=")) {
				targets = arg.substr(10).split(",");
			}
			i++;
		}

		final envDir = getEnv("BORING_TEST_RESULTS_DIR");
		if(envDir != null && envDir != "") {
			resultsDir = envDir;
		}

		// 1. Verify existence of results file for every target
		var hasMissingFiles = false;
		final targetFiles = new Map<String, String>();
		for(target in targets) {
			final filePath = resultsDir + "/" + target + ".jsonl";
			targetFiles.set(target, filePath);
			if(!exists(filePath)) {
				printErr('Error: Missing test results file for target \'$target\': $filePath\n');
				hasMissingFiles = true;
			}
		}

		if(hasMissingFiles) {
			exit(1);
			return;
		}

		// 2. Parse JSONL files
		final targetRecords = new Map<String, Map<String, TestRecord>>();
		final allIdsMap = new Map<String, Bool>();

		for(target in targets) {
			final filePath = targetFiles.get(target);
			final records = new Map<String, TestRecord>();
			final content = readFile(filePath);
			final lines = content.split("\n");
			for(line in lines) {
				final trimmed = StringTools.trim(line);
				if(trimmed.length == 0) continue;
				try {
					final parsed: TestRecord = Json.parse(trimmed);
					if(parsed.id != null && parsed.verdict != null) {
						records.set(parsed.id, parsed);
						allIdsMap.set(parsed.id, true);
					}
				} catch(e: Dynamic) {
					printErr('Error: Failed to parse JSONL line in $filePath: $trimmed\n');
					exit(1);
					return;
				}
			}
			targetRecords.set(target, records);
		}

		final allIds = [for(id in allIdsMap.keys()) id];
		allIds.sort(Reflect.compare);

		final baselineRecords = targetRecords.get(baselineTarget);
		if(baselineRecords == null || allIds.length == 0) {
			printErr('Error: Baseline target \'$baselineTarget\' produced no test records.\n');
			exit(1);
			return;
		}

		// 3. Matrix header and comparison
		final colWidths = new Map<String, Int>();
		var maxIdLen = "TEST ID".length;
		for(id in allIds) {
			if(id.length > maxIdLen) maxIdLen = id.length;
		}
		colWidths.set("id", maxIdLen);

		for(target in targets) {
			final header = target == baselineTarget ? target + " (baseline)" : target;
			var maxLen = header.length;
			for(id in allIds) {
				final rec = targetRecords.get(target).get(id);
				final statusStr = rec != null ? rec.verdict : "MISSING";
				if(statusStr.length > maxLen) maxLen = statusStr.length;
			}
			colWidths.set(target, maxLen);
		}

		// Build Matrix Header
		final headerParts = [StringTools.rpad("TEST ID", " ", colWidths.get("id"))];
		for(target in targets) {
			final header = target == baselineTarget ? target + " (baseline)" : target;
			headerParts.push(StringTools.rpad(header, " ", colWidths.get(target)));
		}
		final separatorParts = [for(target in ["id"].concat(targets)) StringTools.rpad("", "-", colWidths.get(target))];

		print(headerParts.join(" | "));
		print(separatorParts.join("-+-"));

		final divergences: Array<String> = [];

		for(id in allIds) {
			final baseRec = baselineRecords.get(id);
			final rowParts = [StringTools.rpad(id, " ", colWidths.get("id"))];

			for(target in targets) {
				final rec = targetRecords.get(target).get(id);
				final cellStr = rec != null ? rec.verdict : "MISSING";
				rowParts.push(StringTools.rpad(cellStr, " ", colWidths.get(target)));

				if(target != baselineTarget) {
					if(baseRec == null && rec != null) {
						divergences.push('[$target] Extra test ID not in baseline: $id');
					} else if(baseRec != null && rec == null) {
						divergences.push('[$target] Missing test ID present in baseline: $id');
					} else if(baseRec != null && rec != null) {
						if(baseRec.verdict != rec.verdict) {
							divergences.push('[$target] Verdict mismatch on $id: baseline=${baseRec.verdict}, actual=${rec.verdict}');
						} else {
							final baseName = baseRec.name != null ? baseRec.name : "";
							final recName = rec.name != null ? rec.name : "";
							if(baseName != recName) {
								divergences.push('[$target] Runner name mismatch on $id:\n  baseline: $baseName\n  actual:   $recName');
							}
						}
						if(baseRec.verdict == rec.verdict && baseRec.verdict == "fail") {
							final baseMsg = baseRec.message != null ? baseRec.message : "";
							final recMsg = rec.message != null ? rec.message : "";
							if(baseMsg != recMsg) {
								divergences.push('[$target] Failure message mismatch on $id:\n  baseline: $baseMsg\n  actual:   $recMsg');
							}
						}
					}
				}
			}

			print(rowParts.join(" | "));
		}

		print("");
		if(divergences.length == 0) {
			print('All ${targets.length} targets (${targets.join(", ")}) are 100% consistent across ${allIds.length} tests.');
			exit(0);
		} else {
			printErr('Cross-target consistency check failed with ${divergences.length} divergence(s):\n');
			for(d in divergences) {
				printErr('  * $d\n');
			}
			exit(1);
		}
	}
}
