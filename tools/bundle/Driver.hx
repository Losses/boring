import haxe.Json;
import js.Syntax;

/**
    The bundle driver of feature spec 59.

    One project file (`boring.json`) names the bundles; one recipe per
    target (the table below) holds what the defines cannot derive;
    this entry point runs the fixed action set over them:

        bun out/bundle/driver.js gen <id>...
        bun out/bundle/driver.js test <id>...
        bun out/bundle/driver.js pack <id>...
        bun out/bundle/driver.js compare
        bun out/bundle/driver.js verify [--with-pack]

    Every generated tree lands under `<outRoot>/<id>/gen` and
    `<outRoot>/<id>/gen-tests`, derived from the project file and never
    named by it; the results file of a bundle is
    `<resultsDir>/<id>.jsonl`. The generation defines derive from the
    target, the precision, and the id; the pack defines derive from the
    bundle's `package`. A project file that carries an unknown field,
    misses a required one, or repeats a bundle id stops the run with
    the field named.

    The recipe table (spec 59):

    | Target | Build | Run | Pack spawns |
    | --- | --- | --- | --- |
    | haxe | `haxe` over the reference entry | `bun` on the emitted js | nothing |
    | ts | none; `bun` transpiles | `bun test <gen-tests>` | `tsc` |
    | kotlin | `kotlinc`: library jar from `<gen>`, then a tests jar against it | `java -cp <both jars> TestMainKt` | `kotlinc` |
    | rust | `cargo test` in the crate root | `cargo test` | nothing |
    | swift | `swiftc`: library, then the test executable against it | the executable | nothing |
    | dart | none | `dart <gen-tests>/main.dart` | nothing |

    The rust build step runs the compile half of `cargo test`
    (`cargo test --no-run`) and the run step runs the whole command, so
    one `cargo test` executes per test action. The swift recipe reads
    the library module name from the `swift-test-import` define of the
    bundle's effective arguments, compiles the library with
    `-emit-module` so the test executable's `import` resolves, and
    compiles every test source (the backend's entry is TestMain.swift).
    swiftc has no package graph, so a tree that imports a SwiftPM-only
    module (SystemPackage backs the std.Fs host edge) takes that module
    from `BORING_SWIFT_SYSTEM_PACKAGE`, a directory holding the built
    swiftmodule and its shared library; the run stops with the variable
    named when the tree needs it and the variable is unset. The pack
    step resolves the host compiler through `BORING_PACKAGE_TSC` /
    `BORING_PACKAGE_KOTLINC` or from `PATH`.

    `compare` delegates to the consistency manager of spec 19: the
    driver compiles `tools/test-consistency/manager.hxml` from the
    checkout this driver was compiled in and runs it with the project's
    results directory, every bundle id, and the project's baseline.
**/
class Driver {
    static final TOP_LEVEL_FIELDS:Array<String> = ["outRoot", "resultsDir", "baseline", "sourceRoots", "rootsFile", "haxeArgs", "bundles"];
    static final BUNDLE_FIELDS:Array<String> = ["id", "target", "precision", "haxeArgs", "rootsFile", "build", "run", "package"];
    static final STEP_FIELDS:Array<String> = ["args", "env"];
    static final PACKAGE_FIELDS:Array<String> = ["name", "version"];
    static final TARGETS:Array<String> = ["haxe", "ts", "kotlin", "rust", "swift", "dart"];

    // ------------------------------------------------------------------
    // Node bindings
    // ------------------------------------------------------------------

    static function exists(path:String):Bool {
        return Syntax.code("require('fs').existsSync({0})", path);
    }

    static function readText(path:String):String {
        return Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
    }

    static function makeDirs(path:String):Void {
        Syntax.code("require('fs').mkdirSync({0}, {recursive: true})", path);
    }

    static function deleteFile(path:String):Void {
        Syntax.code("require('fs').rmSync({0}, {force: true})", path);
    }

    static function joinPath(a:String, b:String):String {
        return Syntax.code("require('path').join({0}, {1})", a, b);
    }

    static function resolveAgainst(base:String, rel:String):String {
        return Syntax.code("require('path').resolve({0}, {1})", base, rel);
    }

    static function print(s:String):Void {
        Syntax.code("process.stdout.write({0} + '\\n')", s);
    }

    static function printErr(s:String):Void {
        Syntax.code("process.stderr.write({0} + '\\n')", s);
    }

    static function exit(code:Int):Void {
        Syntax.code("process.exit({0})", code);
    }

    static function fail(message:String):Void {
        printErr("Error: " + message);
        exit(1);
    }

    /** The regular files under one directory, relative to it, sorted. */
    static function walkFiles(dir:String, suffix:String):Array<String> {
        final out:Array<String> = [];
        walkFilesInner(dir, "", suffix, out);
        out.sort(Reflect.compare);
        return out;
    }

    static function walkFilesInner(dir:String, prefix:String, suffix:String, out:Array<String>):Void {
        final listDir = prefix.length == 0 ? dir : joinPath(dir, prefix);
        if (!exists(listDir)) {
            return;
        }
        final entries:Array<String> = Syntax.code("require('fs').readdirSync({0})", listDir);
        for (entry in entries) {
            final full = prefix.length == 0 ? entry : prefix + "/" + entry;
            final absolute = joinPath(dir, full);
            final isDir:Bool = Syntax.code("require('fs').statSync({0}).isDirectory()", absolute);
            if (isDir) {
                walkFilesInner(dir, full, suffix, out);
            } else if (StringTools.endsWith(full, suffix)) {
                out.push(full);
            }
        }
    }

    /**
        One command through the host shell API. Output is captured and
        returned with the exit code; the caller decides what to show.
    **/
    static function runCommand(cmd:String, args:Array<String>, cwd:String, envExtra:Dynamic):{code:Int, output:String} {
        final env:Dynamic = Syntax.code("({...process.env})");
        if (envExtra != null) {
            for (field in Reflect.fields(envExtra)) {
                Reflect.setField(env, field, Reflect.field(envExtra, field));
            }
        }
        final proc:Dynamic = Syntax.code(
            "require('child_process').spawnSync({0}, {1}, {cwd: {2}, env: {3}, encoding: 'utf8', maxBuffer: 1024 * 1024 * 64})",
            cmd, args, cwd, env);
        if (proc.error != null) {
            return {code: -1, output: Std.string(proc.error)};
        }
        final code = proc.status == null ? -1 : (proc.status:Int);
        final output = (proc.stdout == null ? "" : proc.stdout) + (proc.stderr == null ? "" : proc.stderr);
        return {code: code, output: output};
    }

    // ------------------------------------------------------------------
    // The project file
    // ------------------------------------------------------------------

    static function isString(value:Dynamic):Bool {
        return Std.isOfType(value, String);
    }

    static function isStringArray(value:Dynamic):Bool {
        if (!Std.isOfType(value, Array)) {
            return false;
        }
        final array:Array<Dynamic> = value;
        for (entry in array) {
            if (!isString(entry)) {
                return false;
            }
        }
        return true;
    }

    static function isObject(value:Dynamic):Bool {
        return Reflect.isObject(value) && !isString(value) && !Std.isOfType(value, Array);
    }

    /**
        Strips `//` line comments so the project file can carry a note.
        The scanner tracks double-quoted strings, so a `//` inside a
        string value survives.
    **/
    static function stripComments(text:String):String {
        final buf = new StringBuf();
        var inString = false;
        var i = 0;
        while (i < text.length) {
            final c = text.charAt(i);
            if (inString) {
                buf.add(c);
                if (c == "\\") {
                    if (i + 1 < text.length) {
                        buf.add(text.charAt(i + 1));
                        i += 2;
                        continue;
                    }
                } else if (c == '"') {
                    inString = false;
                }
                i++;
                continue;
            }
            if (c == '"') {
                inString = true;
                buf.add(c);
                i++;
                continue;
            }
            if (c == "/" && i + 1 < text.length && text.charAt(i + 1) == "/") {
                while (i < text.length && text.charAt(i) != "\n") {
                    i++;
                }
                continue;
            }
            buf.add(c);
            i++;
        }
        return buf.toString();
    }

    static function checkUnknownFields(object:Dynamic, allowed:Array<String>, where:String):Void {
        for (field in Reflect.fields(object)) {
            if (allowed.indexOf(field) < 0) {
                fail('$where: unknown field "$field"; the accepted fields are ${allowed.join(", ")}');
            }
        }
    }

    static function requireString(object:Dynamic, field:String, where:String):String {
        if (!Reflect.fields(object).contains(field) || !isString(Reflect.field(object, field))) {
            fail('$where: missing required field "$field" (a string)');
        }
        return Reflect.field(object, field);
    }

    static function optionalString(object:Dynamic, field:String, where:String):Null<String> {
        if (!Reflect.fields(object).contains(field)) {
            return null;
        }
        final value = Reflect.field(object, field);
        if (!isString(value)) {
            fail('$where: field "$field" must be a string');
        }
        return value;
    }

    static function stringArrayField(object:Dynamic, field:String, where:String):Array<String> {
        if (!Reflect.fields(object).contains(field)) {
            return [];
        }
        final value = Reflect.field(object, field);
        if (!isStringArray(value)) {
            fail('$where: field "$field" must be an array of strings');
        }
        final array:Array<String> = value;
        return array;
    }

    /** The `{ "args": [...], "env": {...} }` override of one recipe step. */
    static function stepOverride(object:Dynamic, field:String, where:String):{args:Array<String>, env:Dynamic} {
        if (!Reflect.fields(object).contains(field)) {
            return {args: [], env: null};
        }
        final value = Reflect.field(object, field);
        if (!isObject(value)) {
            fail('$where: field "$field" must be an object');
        }
        checkUnknownFields(value, STEP_FIELDS, '$where: $field');
        final args = stringArrayField(value, "args", '$where: $field');
        var env:Dynamic = null;
        if (Reflect.fields(value).contains("env")) {
            final envValue = Reflect.field(value, "env");
            if (!isObject(envValue)) {
                fail('$where: $field: field "env" must be an object of strings');
            }
            for (key in Reflect.fields(envValue)) {
                if (!isString(Reflect.field(envValue, key))) {
                    fail('$where: $field: env "$key" must be a string');
                }
            }
            env = envValue;
        }
        return {args: args, env: env};
    }

    static function loadProject(projectPath:String):Project {
        if (!exists(projectPath)) {
            fail('project file not found: $projectPath (pass --project <file>)');
        }
        final where = "boring.json";
        var raw:Dynamic;
        try {
            raw = Json.parse(stripComments(readText(projectPath)));
        } catch (error:Dynamic) {
            fail('$where is not valid JSON: $error');
            return null;
        }
        if (!isObject(raw)) {
            fail('$where must be one JSON object');
        }
        checkUnknownFields(raw, TOP_LEVEL_FIELDS, where);
        final outRoot = requireString(raw, "outRoot", where);
        final baseline = requireString(raw, "baseline", where);
        final resultsDir = optionalString(raw, "resultsDir", where);
        final rootsFile = optionalString(raw, "rootsFile", where);
        final haxeArgs = stringArrayField(raw, "haxeArgs", where);
        if (!Reflect.fields(raw).contains("sourceRoots") || !isStringArray(Reflect.field(raw, "sourceRoots"))) {
            fail('$where: missing required field "sourceRoots" (an array of classpaths)');
        }
        final sourceRoots:Array<String> = Reflect.field(raw, "sourceRoots");
        if (!Reflect.fields(raw).contains("bundles") || !Std.isOfType(Reflect.field(raw, "bundles"), Array)) {
            fail('$where: missing required field "bundles" (a non-empty array)');
        }
        final rawBundles:Array<Dynamic> = Reflect.field(raw, "bundles");
        if (rawBundles.length == 0) {
            fail('$where: field "bundles" must hold at least one bundle');
        }

        final bundles:Array<Bundle> = [];
        final seen = new Map<String, Bool>();
        for (entry in rawBundles) {
            if (!isObject(entry)) {
                fail('$where: every bundle must be a JSON object');
            }
            final bundleWhere = '$where: bundle';
            checkUnknownFields(entry, BUNDLE_FIELDS, bundleWhere);
            final id = requireString(entry, "id", bundleWhere);
            final target = requireString(entry, "target", bundleWhere);
            if (seen.exists(id)) {
                fail('$where: duplicate bundle id "$id"; the id is the results stem and the output directory name, so it must be unique');
            }
            seen.set(id, true);
            if (TARGETS.indexOf(target) < 0) {
                fail('$bundleWhere "$id": field "target" must be one of ${TARGETS.join(", ")}');
            }
            final precision = optionalString(entry, "precision", bundleWhere);
            if (precision != null && precision != "f32") {
                fail('$bundleWhere "$id": field "precision" accepts f32 or absence (binary64)');
            }
            final bundle:Bundle = {
                id: id,
                target: target,
                precision: precision,
                haxeArgs: stringArrayField(entry, "haxeArgs", '$bundleWhere "$id"'),
                rootsFile: optionalString(entry, "rootsFile", '$bundleWhere "$id"'),
                build: stepOverride(entry, "build", '$bundleWhere "$id"'),
                run: stepOverride(entry, "run", '$bundleWhere "$id"'),
                packageName: null,
                packageVersion: null,
            };
            if (Reflect.fields(entry).contains("package")) {
                final packageValue = Reflect.field(entry, "package");
                if (!isObject(packageValue)) {
                    fail('$bundleWhere "$id": field "package" must be an object');
                }
                checkUnknownFields(packageValue, PACKAGE_FIELDS, '$bundleWhere "$id": package');
                bundle.packageName = requireString(packageValue, "name", '$bundleWhere "$id": package');
                bundle.packageVersion = requireString(packageValue, "version", '$bundleWhere "$id": package');
            }
            bundles.push(bundle);
        }
        if (!seen.exists(baseline)) {
            fail('$where: field "baseline" names "$baseline", which is not a bundle id in this file');
        }
        final project:Project = {
            path: projectPath,
            root: Syntax.code("require('path').dirname(require('path').resolve({0}))", projectPath),
            outRoot: outRoot,
            resultsDir: resultsDir == null ? "out/test-results" : resultsDir,
            baseline: baseline,
            sourceRoots: sourceRoots,
            rootsFile: rootsFile,
            haxeArgs: haxeArgs,
            bundles: bundles,
        };
        return project;
    }

    // ------------------------------------------------------------------
    // Derivation
    // ------------------------------------------------------------------

    static function genDir(project:Project, bundle:Bundle):String {
        return joinPath(joinPath(project.outRoot, bundle.id), "gen");
    }

    static function genTestsDir(project:Project, bundle:Bundle):String {
        return joinPath(joinPath(project.outRoot, bundle.id), "gen-tests");
    }

    static function buildDir(project:Project, bundle:Bundle):String {
        return joinPath(joinPath(project.outRoot, bundle.id), "build");
    }

    static function resultsPath(project:Project, bundle:Bundle):String {
        return joinPath(project.resultsDir, bundle.id + ".jsonl");
    }

    /**
        The runtime defines the driver holds at their documented
        defaults, before the project's arguments so `haxeArgs` overrides
        them. The test-runner define follows the recipe's run command;
        `runtime-import` and `runtime-emit` have no default (the
        consumer's identity is not derivable) and arrive through the
        roots file or `haxeArgs`.
    **/
    static function targetDefaultDefines(target:String):Array<String> {
        return switch (target) {
            case "ts": ["ts-test-runner=bun"];
            case "dart": ["dart-test-runner=native"];
            case "swift": ["swift-test-runner=native"];
            default: [];
        };
    }

    /**
        The haxe arguments of one generation. Order: the classpaths, the
        target defaults, the roots file, the project's arguments, the
        bundle's arguments, then the derived defines — haxe keeps the
        last value of a repeated define, so the derived output
        directories win over anything the roots file states, and the
        roots file wins over the driver's defaults.
    **/
    static function genArgs(project:Project, bundle:Bundle, pack:Bool):Array<String> {
        final args:Array<String> = [];
        for (root in project.sourceRoots) {
            args.push("-cp");
            args.push(root);
        }
        for (define in targetDefaultDefines(bundle.target)) {
            args.push("-D");
            args.push(define);
        }
        final rootsFile = bundle.rootsFile != null ? bundle.rootsFile : project.rootsFile;
        if (rootsFile != null) {
            args.push(rootsFile);
        }
        for (arg in project.haxeArgs) {
            args.push(arg);
        }
        for (arg in bundle.haxeArgs) {
            args.push(arg);
        }
        if (bundle.target != "haxe") {
            args.push("-D");
            args.push(bundle.target + "-output=" + genDir(project, bundle));
            args.push("-D");
            args.push(bundle.target + "-test-output=" + genTestsDir(project, bundle));
        }
        if (bundle.precision == "f32") {
            args.push("-D");
            args.push("float-precision=f32");
        }
        if (pack) {
            args.push("-D");
            args.push("package-name=" + bundle.packageName);
            args.push("-D");
            args.push("package-version=" + bundle.packageVersion);
            args.push("-D");
            args.push("package-shell=emit");
            args.push("-D");
            args.push("package-artifacts=emit");
            switch (bundle.target) {
                case "ts":
                    args.push("-D");
                    args.push("package-tsc=" + resolvePackTool("BORING_PACKAGE_TSC", "tsc", bundle));
                case "kotlin":
                    args.push("-D");
                    args.push("package-kotlinc=" + resolvePackTool("BORING_PACKAGE_KOTLINC", "kotlinc", bundle));
                default:
            }
        }
        return args;
    }

    /**
        The host compiler one compiled target packs through, from the
        environment or from `PATH` (spec 59).
    **/
    static function resolvePackTool(envVar:String, name:String, bundle:Bundle):String {
        final fromEnv:String = Syntax.code("process.env[{0}] || null", envVar);
        if (fromEnv != null && fromEnv.length > 0) {
            return fromEnv;
        }
        final pathValue:String = Syntax.code("process.env.PATH || ''");
        for (dir in pathValue.split(":")) {
            if (dir.length == 0) {
                continue;
            }
            final candidate = joinPath(dir, name);
            if (exists(candidate)) {
                return candidate;
            }
        }
        fail('bundle "${bundle.id}": pack on the ${bundle.target} target needs $name; set $envVar or put $name on PATH');
        return "";
    }

    // ------------------------------------------------------------------
    // Actions
    // ------------------------------------------------------------------

    static function step(project:Project, bundle:Bundle, action:String, stepName:String, cmd:String, args:Array<String>, env:Dynamic, cwd:Null<String>):Void {
        final workDir = cwd == null ? project.root : cwd;
        print('  $ ' + cmd + " " + args.join(" "));
        final result = runCommand(cmd, args, workDir, env);
        if (result.code != 0) {
            printErr('Error: bundle "${bundle.id}", action "$action", step "$stepName" failed with exit code ${result.code}.');
            printErr('  command: $cmd ${args.join(" ")}');
            printErr("  --- output (tail) ---");
            final lines = result.output.split("\n");
            final tail = lines.length > 40 ? lines.slice(lines.length - 40) : lines;
            for (line in tail) {
                printErr("  " + line);
            }
            exit(1);
        }
    }

    static function selectBundles(project:Project, ids:Array<String>):Array<Bundle> {
        final out:Array<Bundle> = [];
        for (id in ids) {
            var found = false;
            for (bundle in project.bundles) {
                if (bundle.id == id) {
                    out.push(bundle);
                    found = true;
                    break;
                }
            }
            if (!found) {
                final known = [for (bundle in project.bundles) bundle.id];
                fail('unknown bundle id "$id"; this project declares ${known.join(", ")}');
            }
        }
        return out;
    }

    static function actionGen(project:Project, bundles:Array<Bundle>, pack:Bool):Void {
        for (bundle in bundles) {
            if (pack && bundle.packageName == null) {
                fail('bundle "${bundle.id}": the pack action requires a package (name and version) on every named bundle');
            }
        }
        for (bundle in bundles) {
            final gen = genDir(project, bundle);
            final genTests = genTestsDir(project, bundle);
            makeDirs(gen);
            makeDirs(genTests);
            print('[${pack ? "pack" : "gen"}] ${bundle.id} -> $gen, $genTests');
            step(project, bundle, pack ? "pack" : "gen", "generate", "haxe", genArgs(project, bundle, pack), null, null);
        }
    }

    static function actionTest(project:Project, bundles:Array<Bundle>):Void {
        makeDirs(project.resultsDir);
        for (bundle in bundles) {
            print('[test] ${bundle.id}');
            final gen = genDir(project, bundle);
            final genTests = genTestsDir(project, bundle);
            final build = buildDir(project, bundle);
            final results = resultsPath(project, bundle);
            final absoluteResults = resolveAgainst(project.root, results);
            deleteFile(results);
            final runEnv:Dynamic = Syntax.code("({})", 0);
            Reflect.setField(runEnv, "BORING_TEST_RESULTS", absoluteResults);
            if (bundle.run.env != null) {
                for (field in Reflect.fields(bundle.run.env)) {
                    Reflect.setField(runEnv, field, Reflect.field(bundle.run.env, field));
                }
            }
            switch (bundle.target) {
                case "ts":
                    step(project, bundle, "test", "run", "bun", ["test", genTests].concat(bundle.run.args), runEnv, null);
                case "dart":
                    step(project, bundle, "test", "run", "dart", [joinPath(genTests, "main.dart")].concat(bundle.run.args), runEnv, null);
                case "haxe":
                    var buildArgs = ["-cp", genTests];
                    for (root in project.sourceRoots) {
                        buildArgs.push("-cp");
                        buildArgs.push(root);
                    }
                    buildArgs = buildArgs.concat(bundle.build.args);
                    buildArgs = buildArgs.concat(["-main", "TestMain", "-js", joinPath(gen, "test-main.js")]);
                    step(project, bundle, "test", "build", "haxe", buildArgs, bundle.build.env, null);
                    step(project, bundle, "test", "run", "bun", [joinPath(gen, "test-main.js")].concat(bundle.run.args), runEnv, null);
                case "kotlin":
                    makeDirs(build);
                    final libraryJar = joinPath(build, "library.jar");
                    final testsJar = joinPath(build, "tests.jar");
                    final genFiles = [for (file in walkFiles(gen, ".kt")) joinPath(gen, file)];
                    final testFiles = [for (file in walkFiles(genTests, ".kt")) joinPath(genTests, file)];
                    if (genFiles.length == 0) {
                        fail('bundle "${bundle.id}": no .kt sources under $gen; run gen first');
                    }
                    if (testFiles.length == 0) {
                        fail('bundle "${bundle.id}": no .kt sources under $genTests; run gen first');
                    }
                    step(project, bundle, "test", "build library jar", "kotlinc",
                        genFiles.concat(bundle.build.args).concat(["-include-runtime", "-d", libraryJar]), bundle.build.env, null);
                    step(project, bundle, "test", "build tests jar", "kotlinc",
                        ["-cp", libraryJar].concat(testFiles).concat(bundle.build.args).concat(["-d", testsJar]), bundle.build.env, null);
                    step(project, bundle, "test", "run", "java",
                        ["-cp", libraryJar + ":" + testsJar].concat(bundle.run.args).concat(["TestMainKt"]), runEnv, null);
                case "rust":
                    step(project, bundle, "test", "build", "cargo", ["test", "--no-run"].concat(bundle.build.args), bundle.build.env, gen);
                    step(project, bundle, "test", "run", "cargo", ["test"].concat(bundle.run.args), runEnv, gen);
                case "swift":
                    final module = swiftTestImport(project, bundle);
                    makeDirs(build);
                    final genFiles = [for (file in walkFiles(gen, ".swift")) joinPath(gen, file)];
                    final testFiles = [for (file in walkFiles(genTests, ".swift")) joinPath(genTests, file)];
                    if (genFiles.length == 0) {
                        fail('bundle "${bundle.id}": no .swift sources under $gen; run gen first');
                    }
                    if (testFiles.length == 0) {
                        fail('bundle "${bundle.id}": no .swift sources under $genTests; run gen first');
                    }
                    final systemPackage = swiftSystemPackageDir(bundle, genFiles, testFiles);
                    final importArgs = systemPackage == null ? [] : ["-I", systemPackage];
                    // -emit-module writes <module>.swiftmodule beside the
                    // library, which is what the executable's import reads.
                    step(project, bundle, "test", "build library", "swiftc",
                        ["-emit-library", "-emit-module"].concat(importArgs).concat(genFiles).concat(bundle.build.args)
                            .concat(["-module-name", module, "-o", joinPath(build, "lib" + module + ".so")]),
                        bundle.build.env, null);
                    // The backend names its entry TestMain.swift and the test
                    // classes live beside it; every test source compiles into
                    // the executable, the way the kotlin recipe does.
                    final linkArgs = systemPackage == null ? [] : ["-L", systemPackage, "-lSystemPackage"];
                    step(project, bundle, "test", "build test executable", "swiftc",
                        importArgs.concat(testFiles).concat(bundle.build.args)
                            .concat(["-I", build, "-L", build, "-l" + module]).concat(linkArgs)
                            .concat(["-o", joinPath(build, "test-runner")]),
                        bundle.build.env, null);
                    final runEnvSwift:Dynamic = Syntax.code("({...{0}})", runEnv);
                    final existing = Syntax.code("process.env.LD_LIBRARY_PATH || ''");
                    final runPaths = systemPackage == null ? build : build + ":" + systemPackage;
                    Reflect.setField(runEnvSwift, "LD_LIBRARY_PATH", runPaths + ":" + existing);
                    step(project, bundle, "test", "run", joinPath(build, "test-runner"), bundle.run.args, runEnvSwift, null);
                default:
                    fail('bundle "${bundle.id}": target "${bundle.target}" has no recipe');
            }
        }
    }

    /**
        The directory holding a prebuilt SystemPackage swiftmodule, when
        the bundle's generated tree imports it. swiftc carries no package
        graph: the SwiftPM-only module a std.Fs host edge imports is not
        derivable from the compilation, so the environment names a built
        module directory (BORING_SWIFT_SYSTEM_PACKAGE). Without it the
        run stops with the variable named instead of a bare compiler
        error. (SwiftModuleDependencies)
    **/
    static function swiftSystemPackageDir(bundle:Bundle, genFiles:Array<String>, testFiles:Array<String>):Null<String> {
        var imports = false;
        for (file in genFiles.concat(testFiles)) {
            if (readText(file).indexOf("import SystemPackage") >= 0) {
                imports = true;
                break;
            }
        }
        if (!imports) {
            return null;
        }
        final fromEnv:String = Syntax.code("process.env.BORING_SWIFT_SYSTEM_PACKAGE || ''");
        if (fromEnv.length == 0) {
            fail('bundle "${bundle.id}": the generated tree imports SystemPackage, which the swift toolchain does not ship; build the module (e.g. from the apple/swift-system sources pinned by Package.resolved) and point BORING_SWIFT_SYSTEM_PACKAGE at the directory holding SystemPackage.swiftmodule and its shared library');
        }
        if (!exists(joinPath(fromEnv, "SystemPackage.swiftmodule"))) {
            fail('bundle "${bundle.id}": BORING_SWIFT_SYSTEM_PACKAGE names $fromEnv, which holds no SystemPackage.swiftmodule');
        }
        return fromEnv;
    }

    /**
        The library module name of the swift recipe, read from the
        `swift-test-import` define of the bundle's effective arguments.
    **/
    static function swiftTestImport(project:Project, bundle:Bundle):String {
        final args = genArgs(project, bundle, false);
        var i = 0;
        while (i + 1 < args.length) {
            if (args[i] == "-D" && StringTools.startsWith(args[i + 1], "swift-test-import=")) {
                return args[i + 1].substr("swift-test-import=".length);
            }
            i++;
        }
        fail('bundle "${bundle.id}": the swift recipe needs the library module name; pass -D swift-test-import=<module> in the bundle haxeArgs');
        return "";
    }

    static function actionCompare(project:Project):Void {
        final repoRoot = repoRoot();
        final ids = [for (bundle in project.bundles) bundle.id].join(",");
        print('[compare] baseline ${project.baseline} over $ids');
        step(project, project.bundles[0], "compare", "manager build", "haxe", ["tools/test-consistency/manager.hxml"], null, repoRoot);
        // The manager's matrix and divergence list are the compare
        // result, so they print on success as well as failure.
        final manager = runCommand("bun",
            [joinPath(repoRoot, "out/test-consistency/manager.js"), "--dir=" + project.resultsDir, "--targets=" + ids, "--baseline=" + project.baseline],
            project.root, null);
        print(manager.output);
        if (manager.code != 0) {
            printErr('Error: action "compare" failed: the consistency manager exited with code ${manager.code}.');
            exit(1);
        }
    }

    /**
        The checkout this driver was compiled in: the manager of spec 19
        ships there, and `compare` compiles and runs it.
    **/
    static function repoRoot():String {
        final scriptPath:String = Syntax.code("process.argv[1] || ''");
        final scriptDir:String = Syntax.code("require('path').dirname({0})", scriptPath);
        return Syntax.code("require('path').resolve({0}, '..', '..')", scriptDir);
    }

    static function actionVerify(project:Project, withPack:Bool):Void {
        actionGen(project, project.bundles, false);
        actionTest(project, project.bundles);
        actionCompare(project);
        if (withPack) {
            actionGen(project, project.bundles, true);
        }
    }

    // ------------------------------------------------------------------
    // Entry
    // ------------------------------------------------------------------

    static function main():Void {
        final rawArgs:Array<String> = Syntax.code("process.argv.slice(2)");
        var projectPath = "boring.json";
        var withPack = false;
        final rest:Array<String> = [];
        var i = 0;
        while (i < rawArgs.length) {
            final arg = rawArgs[i];
            if (arg == "--project") {
                if (i + 1 >= rawArgs.length) {
                    fail("--project needs a file path");
                }
                projectPath = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--project=")) {
                projectPath = arg.substr("--project=".length);
                i++;
                continue;
            }
            if (arg == "--with-pack") {
                withPack = true;
                i++;
                continue;
            }
            rest.push(arg);
            i++;
        }
        if (rest.length == 0) {
            printErr("Usage: bun out/bundle/driver.js <gen|test|pack|compare|verify> [<bundle id>...] [--project <file>] [--with-pack]");
            exit(2);
            return;
        }
        final action = rest.shift();
        final ids = rest;
        final project = loadProject(projectPath);
        switch (action) {
            case "gen":
                if (ids.length == 0) {
                    fail('gen names no bundle; this project declares ${[for (b in project.bundles) b.id].join(", ")}');
                }
                actionGen(project, selectBundles(project, ids), false);
            case "test":
                if (ids.length == 0) {
                    fail('test names no bundle; this project declares ${[for (b in project.bundles) b.id].join(", ")}');
                }
                actionTest(project, selectBundles(project, ids));
            case "pack":
                if (ids.length == 0) {
                    fail('pack names no bundle; this project declares ${[for (b in project.bundles) b.id].join(", ")}');
                }
                actionGen(project, selectBundles(project, ids), true);
            case "compare":
                actionCompare(project);
            case "verify":
                actionVerify(project, withPack);
            case _:
                fail('unknown action "$action"; the actions are gen, test, pack, compare, verify');
        }
        print("bundle driver: ok");
    }
}

typedef StepOverride = {
    args:Array<String>,
    env:Dynamic
};

typedef Bundle = {
    id:String,
    target:String,
    precision:Null<String>,
    haxeArgs:Array<String>,
    rootsFile:Null<String>,
    build:StepOverride,
    run:StepOverride,
    packageName:Null<String>,
    packageVersion:Null<String>
};

typedef Project = {
    path:String,
    root:String,
    outRoot:String,
    resultsDir:String,
    baseline:String,
    sourceRoots:Array<String>,
    rootsFile:Null<String>,
    haxeArgs:Array<String>,
    bundles:Array<Bundle>
};
