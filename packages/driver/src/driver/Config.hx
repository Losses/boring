package driver;

import registry.Json;
import registry.Json.JsonField;
import registry.Json.JsonValue;
import registry.JsonException;

/** Parses the project file without host I/O or reflection. */
class Config {
    static final PROJECT_FIELDS = ["outRoot", "resultsDir", "baseline", "sourceRoots", "sourceSets", "rootsFile", "haxeArgs", "bundles"];
    static final BUNDLE_FIELDS = ["id", "target", "precision", "haxeArgs", "rootsFile", "sourceSet", "build", "run", "package", "test", "compare", "afterGen", "mavenPublication", "kmpPublication", "dependsOn", "dependencyMode", "dependencyPaths"];
    static final SOURCE_SET_FIELDS = ["packages", "types", "discover"];
    static final DISCOVER_FIELDS = ["root", "packages", "suffix"];
    static final STEP_FIELDS = ["args", "env", "cargoArgs"];
    static final COMMAND_FIELDS = ["command", "args", "env"];
    static final PACKAGE_FIELDS = ["name", "version", "license", "npmName", "cargoName", "pubName", "mavenName", "swiftUrl", "swiftPath", "mavenGroup"];
    static final TARGETS = ["haxe", "ts", "kotlin", "rust", "swift", "dart"];

    static function fail(message:String):Void {
        throw new DriverException(InvalidConfig(message));
    }

    static function invalidObject(where:String):Array<JsonField> {
        fail('$where must be one JSON object');
        return [];
    }

    static function invalidArray(where:String):Array<JsonValue> {
        fail('$where must be an array');
        return [];
    }

    static function invalidString(where:String, name:String, required:Bool):String {
        if (required) fail('$where: missing required field "$name" (a string)');
        else fail('$where: field "$name" must be a string');
        return "";
    }

    static function requiredValue(value:JsonValue, message:String):String {
        final text = Json.stringValue(value);
        if (text == null) {
            fail(message);
            return "";
        }
        return text;
    }

    static function requiredBool(value:JsonValue, message:String):Bool {
        final result = Json.boolValue(value);
        if (result == null) {
            fail(message);
            return false;
        }
        return result;
    }

    static function stripComments(text:String):String {
        var result = "";
        var inString = false;
        var index = 0;
        while (index < text.length) {
            final code = text.charCodeAt(index);
            if (inString && code == 92 && index + 1 < text.length) {
                result += String.fromCharCode(code) + String.fromCharCode(text.charCodeAt(index + 1));
                index += 2;
                continue;
            }
            if (code == 34) inString = !inString;
            if (!inString && code == 47 && index + 1 < text.length && text.charCodeAt(index + 1) == 47) {
                while (index < text.length && text.charCodeAt(index) != 10) index++;
                continue;
            }
            result += String.fromCharCode(code);
            index++;
        }
        return result;
    }

    static function fieldsOf(value:JsonValue, where:String):Array<JsonField> {
        final fields = Json.objectFields(value);
        return fields == null ? invalidObject(where) : fields;
    }

    static function array(value:JsonValue, where:String):Array<JsonValue> {
        final values = Json.arrayValues(value);
        return values == null ? invalidArray(where) : values;
    }

    static function field(fields:Array<JsonField>, name:String):JsonValue {
        for (item in fields) if (item.name == name) return item.value;
        return JNull;
    }

    static function has(fields:Array<JsonField>, name:String):Bool {
        for (item in fields) if (item.name == name) return true;
        return false;
    }

    static function checkFields(fields:Array<JsonField>, allowed:Array<String>, where:String):Void {
        for (item in fields) if (allowed.indexOf(item.name) < 0) {
            fail('$where: unknown field "${item.name}"; the accepted fields are ${allowed.join(", ")}');
        }
    }

    static function requiredString(fields:Array<JsonField>, name:String, where:String):String {
        final value = field(fields, name);
        final text = Json.stringValue(value);
        if (text == null) return invalidString(where, name, true);
        return text + "";
    }

    static function optionalString(fields:Array<JsonField>, name:String, where:String):Null<String> {
        if (!has(fields, name)) return null;
        final value = field(fields, name);
        final text = Json.stringValue(value);
        if (text == null) {
            invalidString(where, name, false);
            return null;
        }
        return text;
    }

    /**
        One optional ecosystem package-name override. An absent field reads
        as the empty string, which selects the shared `name`; a present
        field must name the package of that ecosystem.
    **/
    static function packageOverride(fields:Array<JsonField>, name:String, where:String):String {
        final value = optionalString(fields, name, where);
        if (value == null) return "";
        if (value == "") fail('$where: field "$name" must not be empty');
        return value;
    }

    /**
        The package name one bundle's target publishes under. The shared
        `name` is the default every ecosystem accepts; a target whose
        ecosystem accepts a name the shared field cannot carry states it in
        its own field. npm accepts an `@scope/name`, cargo rejects `@` and
        upper-case letters, pub accepts only lower-case letters, digits and
        underscores, and a Maven coordinate holds neither `@` nor `/`. Each
        target reads the field of its own ecosystem; the others stay inert,
        so one package block serves every target of a package.
    **/
    public static function ecosystemName(target:String, name:String, npmName:String, cargoName:String,
            pubName:String, mavenName:String):String {
        if (target == "ts" && npmName != "") return npmName;
        if (target == "rust" && cargoName != "") return cargoName;
        if (target == "dart" && pubName != "") return pubName;
        if (target == "kotlin" && mavenName != "") return mavenName;
        return name;
    }

    static function strings(fields:Array<JsonField>, name:String, where:String):Array<String> {
        if (!has(fields, name)) return [];
        final values = array(field(fields, name), '$where: field "$name"');
        final result:Array<String> = [];
        for (value in values) {
            final text = requiredValue(value, '$where: field "$name" must be an array of strings');
            result.push(text);
        }
        return result;
    }

    static function validModulePath(path:String):Bool {
        if (path == "") return false;
        var segmentStart = true;
        for (index in 0...path.length) {
            final code = path.charCodeAt(index);
            if (code == 46) {
                if (segmentStart) return false;
                segmentStart = true;
                continue;
            }
            final letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95;
            final digit = code >= 48 && code <= 57;
            if (!letter && (!digit || segmentStart)) return false;
            segmentStart = false;
        }
        return !segmentStart;
    }

    static function sourcePaths(fields:Array<JsonField>, key:String, name:String):Array<String> {
        final paths = strings(fields, key, 'boring.json: source set "$name"');
        final seen:Array<String> = [];
        for (path in paths) {
            if (!validModulePath(path)) fail('boring.json: source set "$name": $key entry "$path" must be a nonempty dotted Haxe path');
            if (seen.indexOf(path + "") >= 0) fail('boring.json: source set "$name": duplicate $key entry "$path"');
            seen.push(path);
        }
        return paths;
    }

    static function validRelativeRoot(root:String):Bool {
        if (root == "" || root.charAt(0) == "/") return false;
        for (part in root.split("/")) {
            if (part == "" || part == "." || part == "..") return false;
            for (index in 0...part.length) {
                final code = part.charCodeAt(index);
                final letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
                final digit = code >= 48 && code <= 57;
                if (!letter && !digit && code != 95 && code != 45 && code != 46) return false;
            }
        }
        return true;
    }

    static function discoverRules(fields:Array<JsonField>, name:String):Array<Discovery> {
        final rules:Array<Discovery> = [];
        if (!has(fields, "discover")) return rules;
        final values = array(field(fields, "discover"), 'boring.json: source set "$name": field "discover"');
        for (entry in values) {
            final where = 'boring.json: source set "$name": discover';
            final ruleFields = fieldsOf(entry, where);
            checkFields(ruleFields, DISCOVER_FIELDS, where);
            final root = requiredString(ruleFields, "root", where);
            if (!validRelativeRoot(root)) fail('$where: root "$root" must be a nonempty project-relative directory');
            if (!has(ruleFields, "packages")) fail('$where: field "packages" must name at least one package');
            final packages = sourcePaths(ruleFields, "packages", name);
            if (packages.length == 0) fail('$where: field "packages" must name at least one package');
            final suffix = requiredString(ruleFields, "suffix", where);
            if (!validModulePath(suffix) || suffix.indexOf(".") >= 0) {
                fail('$where: suffix "$suffix" must be a nonempty Haxe identifier');
            }
            for (prior in rules) {
                if (prior.root == root && prior.suffix == suffix) {
                    for (pack in packages) if (prior.packages.indexOf(pack + "") >= 0) {
                        fail('$where: duplicate package "$pack" for root "$root" and suffix "$suffix"');
                    }
                }
            }
            rules.push({root: root, packages: packages, suffix: suffix});
        }
        return rules;
    }

    static function parseSourceSets(fields:Array<JsonField>):Array<SourceSet> {
        final sets:Array<SourceSet> = [];
        if (!has(fields, "sourceSets")) return sets;
        final entries = fieldsOf(field(fields, "sourceSets"), 'boring.json: field "sourceSets"');
        for (entry in entries) {
            final name = entry.name;
            if (name == "") fail('boring.json: source set name must not be empty');
            for (set in sets) if (set.name == name) fail('boring.json: duplicate source set "$name"');
            final values = fieldsOf(entry.value, 'boring.json: source set "$name"');
            checkFields(values, SOURCE_SET_FIELDS, 'boring.json: source set "$name"');
            final packages = sourcePaths(values, "packages", name);
            final types = sourcePaths(values, "types", name);
            final discover = discoverRules(values, name);
            if (packages.length == 0 && types.length == 0 && discover.length == 0) fail('boring.json: source set "$name" needs at least one package, type, or discover rule');
            sets.push({name: name, packages: packages, types: types, discover: discover});
        }
        return sets;
    }

    static function env(fields:Array<JsonField>, where:String):Array<EnvVar> {
        if (!has(fields, "env")) return [];
        final values = fieldsOf(field(fields, "env"), '$where: field "env"');
        final result:Array<EnvVar> = [];
        for (item in values) {
            final value = requiredValue(item.value, '$where: env "${item.name}" must be a string');
            final variable:EnvVar = {key: item.name, value: value};
            result.push(variable);
        }
        return result;
    }

    static function step(fields:Array<JsonField>, name:String, where:String):StepOverride {
        if (!has(fields, name)) {
            final empty:StepOverride = {args: [], env: [], cargoArgs: null};
            return empty;
        }
        final values = fieldsOf(field(fields, name), '$where: field "$name"');
        checkFields(values, STEP_FIELDS, '$where: $name');
        // cargoArgs carries options for cargo (for example --features f32)
        // that must come before the test-harness -- separator; the rust
        // plan inserts them there and every other target ignores them.
        final cargoArgs:Null<Array<String>> = has(values, "cargoArgs") ? strings(values, "cargoArgs", '$where: $name') : null;
        final stepValue:StepOverride = {args: strings(values, "args", '$where: $name'), env: env(values, '$where: $name'), cargoArgs: cargoArgs};
        return stepValue;
    }

    static function command(fields:Array<JsonField>, name:String, where:String):Null<CommandStep> {
        if (!has(fields, name)) return null;
        final values = fieldsOf(field(fields, name), '$where: field "$name"');
        checkFields(values, COMMAND_FIELDS, '$where: $name');
        final command = requiredString(values, "command", '$where: $name');
        if (command == "") fail('$where: $name command must not be empty');
        final result:CommandStep = {command: command, args: strings(values, "args", '$where: $name'), env: env(values, '$where: $name')};
        return result;
    }

    static function emptyJson():JsonValue {
        return JObject([]);
    }

    static function readJson(text:String):JsonValue {
        var parsed:JsonValue = emptyJson();
        try {
            parsed = Json.read(stripComments(text));
        } catch (error:JsonException) {
            throw new DriverException(InvalidConfig('boring.json is not valid JSON: ${error.message}'));
        }
        return parsed;
    }

    public static function parse(text:String, projectPath:String, root:String):Project {
        final raw = readJson(text);
        final fields = fieldsOf(raw, "boring.json");
        checkFields(fields, PROJECT_FIELDS, "boring.json");
        final outRoot = requiredString(fields, "outRoot", "boring.json");
        final baseline = requiredString(fields, "baseline", "boring.json");
        final resultsDir = optionalString(fields, "resultsDir", "boring.json");
        final rootsFileValue = optionalString(fields, "rootsFile", "boring.json");
        final rootsFile = rootsFileValue == null ? "" : rootsFileValue + "";
        if (!has(fields, "sourceRoots")) fail('boring.json: missing required field "sourceRoots" (an array of classpaths)');
        final sourceRoots = strings(fields, "sourceRoots", "boring.json");
        final sourceSets = parseSourceSets(fields);
        if (!has(fields, "bundles")) fail('boring.json: missing required field "bundles" (a non-empty array)');
        final entries = array(field(fields, "bundles"), 'boring.json: field "bundles"');
        if (entries.length == 0) fail('boring.json: field "bundles" must hold at least one bundle');
        final bundles:Array<BundleSpec> = [];
        final seen:Array<String> = [];
        for (entry in entries) {
            final values = fieldsOf(entry, "boring.json: bundle");
            checkFields(values, BUNDLE_FIELDS, "boring.json: bundle");
            final id = requiredString(values, "id", "boring.json: bundle");
            final target = requiredString(values, "target", "boring.json: bundle");
            if (seen.indexOf(id) >= 0) fail('boring.json: duplicate bundle id "$id"');
            seen.push(id);
            if (TARGETS.indexOf(target) < 0) fail('boring.json: bundle "$id": field "target" must be one of ${TARGETS.join(", ")}');
            final precision = optionalString(values, "precision", 'boring.json: bundle "$id"');
            if (precision != null) {
                if (precision + "" != "f32") fail('boring.json: bundle "$id": field "precision" accepts f32 or absence (binary64)');
            }
            var hasTests = true;
            if (has(values, "test")) {
                hasTests = requiredBool(field(values, "test"), 'boring.json: bundle "$id": field "test" must be a boolean');
            }
            var hasComparison = hasTests;
            if (has(values, "compare")) {
                hasComparison = requiredBool(field(values, "compare"), 'boring.json: bundle "$id": field "compare" must be a boolean');
                if (hasComparison && !hasTests) fail('boring.json: bundle "$id": compare=true requires test=true');
            }
            var kmpPublication = false;
            if (has(values, "kmpPublication")) {
                kmpPublication = requiredBool(field(values, "kmpPublication"), 'boring.json: bundle "$id": field "kmpPublication" must be a boolean');
            }
            if (has(values, "kmpPublication") && target != "kotlin") {
                fail('boring.json: bundle "$id": field "kmpPublication" is only valid on the kotlin target');
            }
            if (kmpPublication && has(values, "mavenPublication")) {
                fail('boring.json: bundle "$id": kmpPublication and mavenPublication are mutually exclusive');
            }
            var packageName = "";
            var packageVersion = "";
            var packageLicense = "";
            var packageNpmName = "";
            var packageCargoName = "";
            var packagePubName = "";
            var packageMavenName = "";
            var packageSwiftUrl = "";
            var packageSwiftPath = "";
            var packageMavenGroup = "";
            if (has(values, "package")) {
                final packageFields = fieldsOf(field(values, "package"), 'boring.json: bundle "$id": package');
                final packageWhere = 'boring.json: bundle "$id": package';
                checkFields(packageFields, PACKAGE_FIELDS, packageWhere);
                final baseName = requiredString(packageFields, "name", packageWhere);
                packageVersion = requiredString(packageFields, "version", packageWhere);
                if (has(packageFields, "license")) {
                    packageLicense = requiredString(packageFields, "license", packageWhere);
                    if (packageLicense == "") fail('boring.json: bundle "$id": package license must not be empty');
                }
                packageNpmName = packageOverride(packageFields, "npmName", packageWhere);
                packageCargoName = packageOverride(packageFields, "cargoName", packageWhere);
                packagePubName = packageOverride(packageFields, "pubName", packageWhere);
                packageMavenName = packageOverride(packageFields, "mavenName", packageWhere);
                packageSwiftUrl = packageOverride(packageFields, "swiftUrl", packageWhere);
                packageSwiftPath = packageOverride(packageFields, "swiftPath", packageWhere);
                packageMavenGroup = packageOverride(packageFields, "mavenGroup", packageWhere);
                packageName = ecosystemName(target, baseName, packageNpmName, packageCargoName, packagePubName,
                    packageMavenName);
                if (packageName == "" || packageVersion == "") {
                    fail('boring.json: bundle "$id": package name and version must not be empty');
                }
            }
            final dependsOn = parseDependsOn(values, id);
            final dependencyMode = parseDependencyMode(values, id);
            final dependencyPaths:Array<{id:String, path:String}> = [];
            if (has(values, "dependencyPaths")) {
                final pathsWhere = 'boring.json: bundle "$id": dependencyPaths';
                for (entry in fieldsOf(field(values, "dependencyPaths"), pathsWhere)) {
                    dependencyPaths.push({id: entry.name, path: requiredValue(entry.value, pathsWhere + ': "' + entry.name + '" must be a string')});
                }
                for (dep in dependsOn) {
                    var found = false;
                    for (entry in dependencyPaths) if (entry.id == dep) found = true;
                    if (!found) {
                        fail('boring.json: bundle "$id": dependencyPaths has no entry for dependsOn "' + dep + '"');
                    }
                }
            } else if (dependencyMode == "path") {
                fail('boring.json: bundle "$id": dependencyMode path needs dependencyPaths');
            }
            final runOverride = step(values, "run", 'boring.json: bundle "$id"');
            for (variable in runOverride.env) {
                if (variable.key == "BORING_TEST_RESULTS") {
                    fail('boring.json: bundle "$id": run.env may not set BORING_TEST_RESULTS; the driver derives the results path');
                }
            }
            final bundleRootsValue = optionalString(values, "rootsFile", 'boring.json: bundle "$id"');
            final bundleRoots = bundleRootsValue == null ? "" : bundleRootsValue + "";
            final sourceSetValue = optionalString(values, "sourceSet", 'boring.json: bundle "$id"');
            final sourceSet = sourceSetValue == null ? "" : sourceSetValue + "";
            if (has(values, "sourceSet")) {
                if (sourceSet == "") fail('boring.json: bundle "$id": sourceSet must not be empty');
                var foundSet = false;
                for (set in sourceSets) if (set.name == sourceSet) foundSet = true;
                if (!foundSet) fail('boring.json: bundle "$id": unknown source set "$sourceSet"');
            }
            if (has(values, "mavenPublication") && target != "kotlin") {
                fail('boring.json: bundle "$id": field "mavenPublication" is only valid on the kotlin target');
            }
            final bundle:BundleSpec = {
                id: id, target: target, precision: precision == null ? "" : precision + "", hasTests: hasTests,
                hasComparison: hasComparison,
                haxeArgs: strings(values, "haxeArgs", 'boring.json: bundle "$id"'),
                rootsFile: bundleRoots,
                sourceSet: sourceSet,
                build: step(values, "build", 'boring.json: bundle "$id"'),
                run: runOverride,
                afterGen: command(values, "afterGen", 'boring.json: bundle "$id"'),
                mavenPublication: command(values, "mavenPublication", 'boring.json: bundle "$id"'),
                kmpPublication: kmpPublication,
                packageName: packageName, packageVersion: packageVersion, packageLicense: packageLicense,
                packageNpmName: packageNpmName, packageCargoName: packageCargoName, packagePubName: packagePubName,
                packageMavenName: packageMavenName, packageSwiftUrl: packageSwiftUrl, packageSwiftPath: packageSwiftPath,
                packageMavenGroup: packageMavenGroup, dependencyMode: dependencyMode, dependencyPaths: dependencyPaths,
                dependsOn: dependsOn
            };
            bundles.push(bundle);
        }
        validateDependsOn(bundles);
        if (seen.indexOf(baseline) < 0) fail('boring.json: field "baseline" names "$baseline", which is not a bundle id in this file');
        for (bundle in bundles) if (bundle.id == baseline && !bundle.hasTests) fail('boring.json: baseline "$baseline" must have tests');
        for (bundle in bundles) if (bundle.id == baseline && !bundle.hasComparison) fail('boring.json: baseline "$baseline" must participate in compare');
        final project:Project = new Project(projectPath, root, outRoot,
            resultsDir == null ? "out/test-results" : resultsDir, baseline, sourceRoots, sourceSets,
            rootsFile, strings(fields, "haxeArgs", "boring.json"), bundles);
        return project;
    }

    static function parseDependencyMode(values:Array<JsonField>, id:String):String {
        final raw = optionalString(values, "dependencyMode", 'boring.json: bundle "$id"') ?? "registry";
        if (raw == "registry" || raw == "path" || raw == "workspace")
            return raw;
        fail('boring.json: bundle "$id": dependencyMode must be registry, path or workspace');
        return "registry";
    }

    static function parseDependsOn(values:Array<JsonField>, bundleId:String):Array<String> {
        final where = 'boring.json: bundle "${bundleId}"';
        if (!has(values, "dependsOn")) return [];
        final out = strings(values, "dependsOn", where);
        for (bundle in out) {
            if (bundle == "") fail('${where}: dependsOn must not name an empty bundle');
            if (bundle == bundleId) fail('${where}: dependsOn may not name the bundle itself');
            if (out.indexOf(bundle) != out.lastIndexOf(bundle)) fail('${where}: dependsOn lists "${bundle}" twice');
        }
        return out;
    }

    static function bundleById(bundles:Array<BundleSpec>, id:String):Null<BundleSpec> {
        for (bundle in bundles) if (bundle.id == id) return bundle;
        return null;
    }

    static function validateDependsOn(bundles:Array<BundleSpec>):Void {
        for (bundle in bundles) {
            for (dep in bundle.dependsOn) {
                final target = bundleById(bundles, dep);
                if (target == null) fail('boring.json: bundle "${bundle.id}": dependsOn names unknown bundle "${dep}"');
                if (target.target != bundle.target) {
                    fail('boring.json: bundle "${bundle.id}": dependsOn "${dep}" has target "${target.target}", expected "${bundle.target}"');
                }
                if (target.packageName == "") {
                    fail('boring.json: bundle "${bundle.id}": dependsOn "${dep}" declares no package; a dependency must declare package.name so the reference uses its published name');
                }
            }
        }
        final done:Array<String> = [];
        for (bundle in bundles) visitDependency(bundle.id, bundles, done, []);
    }

    static function visitDependency(id:String, bundles:Array<BundleSpec>, done:Array<String>, chain:Array<String>):Void {
        if (done.indexOf(id) >= 0) return;
        if (chain.indexOf(id) >= 0) {
            final at = chain.indexOf(id);
            final cycle = chain.slice(at).concat([id]);
            fail('boring.json: bundle "${id}": dependsOn forms a cycle ${cycle.join(" -> ")}');
        }
        chain.push(id);
        final bundle = bundleById(bundles, id);
        if (bundle != null) for (dep in bundle.dependsOn) visitDependency(dep, bundles, done, chain);
        chain.pop();
        done.push(id);
    }
}
