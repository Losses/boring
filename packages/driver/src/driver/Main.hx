package driver;

import driver.Host.HostResult;

/** Host entry for the driver package. Configuration and command arguments are
    computed by Config and Plan; this class executes target toolchains. */
class Main {
    // ------------------------------------------------------------------
    // Host operations
    // ------------------------------------------------------------------

    static function exists(path:String):Bool {
        return Host.exists(path);
    }

    static function readText(path:String):String {
        return Host.readText(path);
    }

    static function makeDirs(path:String):Void {
        Host.makeDirs(path);
    }

    static function deleteFile(path:String):Void {
        Host.deleteFile(path);
    }

    static function joinPath(a:String, b:String):String {
        return Host.join(a, b);
    }

    static function resolveAgainst(base:String, rel:String):String {
        return Host.resolve(base, rel);
    }

    static function print(s:String):Void {
        Host.outputLine(s);
    }

    static function printErr(s:String):Void {
        Host.printError(s);
    }

    static function exit(code:Int):Void {
        Host.exit(code);
    }

    static function fail(message:String):Void {
        printErr("Error: " + message);
        exit(1);
    }

    /** The regular files under one directory, relative to it, sorted. */
    static function walkFiles(dir:String, suffix:String):Array<String> {
        final out:Array<String> = [];
        walkFilesInner(dir, "", suffix, out);
        var i = 1;
        while (i < out.length) {
            final value = out[i];
            var j = i;
            while (j > 0 && out[j - 1] > value) {
                out[j] = out[j - 1];
                j--;
            }
            out[j] = value;
            i++;
        }
        return out;
    }

    static function walkFilesInner(dir:String, prefix:String, suffix:String, out:Array<String>):Void {
        final listDir = prefix.length == 0 ? dir : joinPath(dir, prefix);
        if (!exists(listDir)) {
            return;
        }
        final entries = Host.readDir(listDir);
        for (entry in entries) {
            final full = prefix.length == 0 ? entry : prefix + "/" + entry;
            final absolute = joinPath(dir, full);
            final isDir = Host.isDirectory(absolute);
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
    static function runCommand(cmd:String, args:Array<String>, cwd:String, envExtra:Array<EnvVar>):HostResult {
        return Host.run(cmd, args, cwd, envExtra);
    }

    // ------------------------------------------------------------------
    // The project file
    // ------------------------------------------------------------------

    static function loadProject(projectPath:String):Project {
        if (!exists(projectPath)) {
            fail('project file not found: $projectPath (pass --project <file>)');
        }
        final root = Host.dirname(Host.resolve(Host.cwd(), projectPath));
        var parsed:Null<Project> = null;
        try {
            parsed = Config.parse(readText(projectPath), projectPath, root);
        } catch (error:DriverException) {
            fail(Diagnostic.describe(error.fault));
        }
        if (parsed == null) throw new DriverException(InvalidConfig('project file could not be read: $projectPath'));
        return parsed;
    }

    // ------------------------------------------------------------------
    // Derivation
    // ------------------------------------------------------------------

    /**
        The derived paths resolve against the project root (the
        driver's working directory is unused): a driver compiled in one checkout
        runs a project file that names another (the generation step
        already runs there, through the step command's working
        directory), so every consumer of these paths agrees on where
        the trees live.
    **/
    static function genDir(project:Project, bundle:Bundle):String {
        return resolveAgainst(project.root, joinPath(joinPath(project.outRoot, bundle.id), "gen"));
    }

    static function genTestsDir(project:Project, bundle:Bundle):String {
        return resolveAgainst(project.root, joinPath(joinPath(project.outRoot, bundle.id), "gen-tests"));
    }

    static function buildDir(project:Project, bundle:Bundle):String {
        return resolveAgainst(project.root, joinPath(joinPath(project.outRoot, bundle.id), "build"));
    }

    static function resultsPath(project:Project, bundle:Bundle):String {
        return resolveAgainst(project.root, joinPath(project.resultsDir, bundle.id + ".jsonl"));
    }

    static function genArgs(project:Project, bundle:Bundle, pack:Bool):Array<String> {
        final packageTsc = pack && bundle.target == "ts" ? resolvePackTool("BORING_PACKAGE_TSC", "tsc", bundle) : null;
        final packageKotlinc = pack && bundle.target == "kotlin" ? resolvePackTool("BORING_PACKAGE_KOTLINC", "kotlinc", bundle) : null;
        return Plan.genArgs(project, bundle, pack, genDir(project, bundle), genTestsDir(project, bundle), packageTsc, packageKotlinc,
            discoverSourceTypes(project, bundle.sourceSet));
    }

    static function discoverSourceTypes(project:Project, setName:String):Array<String> {
        final selected = Plan.sourceSet(project, setName);
        if (selected == null) return [];
        final found:Array<String> = [];
        for (rule in selected.discover) {
            for (pack in rule.packages) {
                final directory = resolveAgainst(project.root, joinPath(rule.root, pack.split(".").join("/")));
                if (!exists(directory) || !Host.isDirectory(directory)) {
                    fail('source set "$setName": discover directory does not exist: $directory');
                    return [];
                }
                final entries:Array<String> = [];
                for (entry in Host.readDir(directory)) {
                    if (!Host.isDirectory(joinPath(directory, entry))) entries.push(entry);
                }
                final matches = Plan.discoverTypes(pack, rule.suffix, entries);
                if (matches.length == 0) {
                    fail('source set "$setName": no modules ending in "${rule.suffix}" under $directory');
                    return [];
                }
                for (typePath in matches) found.push(typePath);
            }
        }
        return Plan.sortedUnique(found);
    }

    static function actionRoots(project:Project, setName:String, outputPath:String):Void {
        final selected = Plan.sourceSet(project, setName);
        if (selected == null) {
            fail('unknown source set "$setName"');
            return;
        }
        final output = resolveAgainst(project.root, outputPath);
        makeDirs(Host.dirname(output));
        final contents = Plan.rootsContents(selected, discoverSourceTypes(project, setName));
        var suffix = 0;
        var temporary = output + ".tmp-" + suffix;
        while (exists(temporary)) {
            suffix++;
            temporary = output + ".tmp-" + suffix;
        }
        Host.writeText(temporary, contents);
        Host.rename(temporary, output);
        print('[roots] $setName -> $output');
    }

    /**
        The host compiler one compiled target packs through, from the
        environment or from `PATH` (spec 59).
    **/
    static function resolvePackTool(envVar:String, name:String, bundle:Bundle):String {
        final configured = Host.env(envVar);
        final fromEnv:String = configured == null ? "" : configured;
        if (fromEnv.length > 0) {
            return fromEnv;
        }
        final pathValue = Host.env("PATH");
        for (dir in (pathValue == null ? "" : pathValue).split(":")) {
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

    static function step(project:Project, bundle:Bundle, action:String, stepName:String, cmd:String, args:Array<String>, env:Array<EnvVar>, cwd:Null<String>):Void {
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
                final known:Array<String> = [];
                for (bundle in project.bundles) known.push(bundle.id);
                fail('unknown bundle id "$id"; this project declares ${known.join(", ")}');
            }
        }
        return out;
    }

    static function actionGen(project:Project, bundles:Array<Bundle>, pack:Bool):Void {
        for (bundle in bundles) {
            if (pack && bundle.packageName == "") {
                fail('bundle "${bundle.id}": the pack action requires a package (name and version) on every named bundle');
            }
        }
        for (bundle in bundles) {
            final generated = genDir(project, bundle);
            final genTests = genTestsDir(project, bundle);
            makeDirs(generated);
            makeDirs(genTests);
            print('[${pack ? "pack" : "gen"}] ${bundle.id} -> $generated, $genTests');
            step(project, bundle, pack ? "pack" : "gen", "generate", "haxe", genArgs(project, bundle, pack), [], null);
            final afterGen = bundle.afterGen;
            if (afterGen != null) {
                step(project, bundle, pack ? "pack" : "gen", "afterGen", afterGen.command,
                    afterGen.args, afterGen.env, null);
            }
        }
    }

    static function actionTest(project:Project, bundles:Array<Bundle>):Void {
        makeDirs(resolveAgainst(project.root, project.resultsDir));
        for (bundle in bundles) {
            if (!bundle.hasTests) {
                fail('bundle "${bundle.id}": this target configuration has test=false and cannot run the test action');
            }
            print('[test] ${bundle.id}');
            final generated = genDir(project, bundle);
            final genTests = genTestsDir(project, bundle);
            final build = buildDir(project, bundle);
            final results = resultsPath(project, bundle);
            deleteFile(results);
            makeDirs(build);
            final suffix = bundle.target == "kotlin" ? ".kt" : ".swift";
            final genFiles:Array<String> = [];
            final testFiles:Array<String> = [];
            if (bundle.target == "kotlin" || bundle.target == "swift") {
                for (file in walkFiles(generated, suffix)) genFiles.push(joinPath(generated, file));
                for (file in walkFiles(genTests, suffix)) testFiles.push(joinPath(genTests, file));
            }
            final swiftModule = bundle.target == "swift" ? swiftTestImport(project, bundle) : null;
            final systemPackage = bundle.target == "swift" ? swiftSystemPackageDir(bundle, genFiles, testFiles) : null;
            final host = Host.platform();
            final variable = Plan.swiftLibraryPathVariable(host);
            final previousPath = Host.env(variable);
            final existingPath = previousPath == null ? "" : previousPath;
            try {
                final steps = Plan.testSteps(project, bundle, generated, genTests, build, results,
                    genFiles, testFiles, haxeTestMain(project, bundle), swiftModule, systemPackage, host, existingPath);
                for (planned in steps) {
                    step(project, bundle, "test", planned.name, planned.command, planned.args, planned.env, planned.cwd);
                }
            } catch (error:DriverException) {
                fail(Diagnostic.describe(error.fault));
            }
        }
    }

    /**
        The directory holding a prebuilt SystemPackage swiftmodule, when
        the bundle's generated tree imports it. swiftc carries no package
        graph: the SwiftPM-only module a std.Fs host edge imports is not
        derivable from the compilation, so the environment names a built
        module directory (BORING_SWIFT_SYSTEM_PACKAGE). Without it the
        run stops with the variable named and without a bare compiler
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
        final configured = Host.env("BORING_SWIFT_SYSTEM_PACKAGE");
        final fromEnv:String = configured == null ? "" : configured;
        if (fromEnv.length == 0) {
            fail('bundle "${bundle.id}": the generated tree imports SystemPackage, which the swift toolchain does not ship; build the module (e.g. from the apple/swift-system sources pinned by Package.resolved) and point BORING_SWIFT_SYSTEM_PACKAGE at the directory holding SystemPackage.swiftmodule and its shared library');
        }
        if (!exists(joinPath(fromEnv, "SystemPackage.swiftmodule"))) {
            fail('bundle "${bundle.id}": BORING_SWIFT_SYSTEM_PACKAGE names $fromEnv, which holds no SystemPackage.swiftmodule');
        }
        return fromEnv;
    }

    /**
        The value of one `-D <name>=<value>` pair of an argument list,
        when the list carries it.
    **/
    static function defineValue(args:Array<String>, name:String):Null<String> {
        var i = 0;
        while (i + 1 < args.length) {
            if (args[i] == "-D" && StringTools.startsWith(args[i + 1], name + "=")) {
                return args[i + 1].substr(name.length + 1);
            }
            i++;
        }
        return null;
    }

    /**
        The value of one `-D <name>=<value>` pair on the bundle's
        roots file include chain, when the chain carries it. The roots
        file is what the generation command feeds haxe, so a define it
        pulls in is as effective as one in `haxeArgs`; a project whose
        target entries already state `swift-test-import` needs no
        copy in the project file. Include lines resolve against the
        project root, where the generation command runs, with the
        including file's own directory as fallback; a later define
        wins, matching haxe's own last-value rule.
    **/
    static function rootsFileDefine(project:Project, bundle:Bundle, name:String):Null<String> {
        final rootsFile = bundle.rootsFile != "" ? bundle.rootsFile : project.rootsFile;
        if (rootsFile == "") {
            return null;
        }
        return hxmlDefineValue(resolveAgainst(project.root, rootsFile), name, [], project.root);
    }

    static function hxmlDefineValue(path:String, name:String, seen:Array<String>, base:String):Null<String> {
        if (seen.indexOf(path) >= 0 || !exists(path)) {
            return null;
        }
        seen.push(path);
        var found:Null<String> = null;
        for (rawLine in readText(path).split("\n")) {
            final line = hxmlStripComment(rawLine);
            final tokens = splitWhitespace(line);
            if (tokens.length == 0) {
                continue;
            }
            if (tokens[0] == "-D" || tokens[0] == "--define") {
                // One hxml line carries the pair haxe sees: -D plus one
                // name=value token; the JSON haxeArgs form splits them.
                if (StringTools.startsWith(tokens[1], name + "=")) {
                    found = tokens[1].substr(name.length + 1);
                } else if (tokens[1] == name && tokens.length >= 3) {
                    found = tokens.slice(2).join(" ");
                }
                continue;
            }
            if (tokens.length == 1 && !StringTools.startsWith(tokens[0], "-")) {
                // haxe resolves an include against its working
                // directory, which is the project root here; the
                // including file's own directory is the fallback for
                // entries written the other way.
                var included = hxmlDefineValue(resolveAgainst(base, tokens[0]), name, seen, base);
                if (included == null) {
                    included = hxmlDefineValue(resolveAgainst(directoryOf(path), tokens[0]), name, seen, base);
                }
                if (included != null) {
                    found = included + "";
                }
            }
        }
        return found;
    }

    static function hxmlStripComment(line:String):String {
        final cut = line.indexOf("#");
        return StringTools.trim(cut < 0 ? line : line.substr(0, cut));
    }

    static function splitWhitespace(line:String):Array<String> {
        final tokens:Array<String> = [];
        var start = -1;
        var i = 0;
        while (i < line.length) {
            final c = line.charAt(i);
            final space = c == " " || c == "\t" || c == "\r" || c == "\n";
            if (space && start >= 0) {
                tokens.push(line.substr(start, i - start));
                start = -1;
            } else if (!space && start < 0) {
                start = i;
            }
            i++;
        }
        if (start >= 0) tokens.push(line.substr(start));
        return tokens;
    }

    static function directoryOf(path:String):String {
        final cut = path.lastIndexOf("/");
        return cut < 0 ? "." : path.substr(0, cut);
    }

    /**
        The library module name of the swift recipe, read from the
        `swift-test-import` define of the bundle's effective
        arguments, or of the roots file include chain that the same
        command compiles through.
    **/
    static function swiftTestImport(project:Project, bundle:Bundle):String {
        final module = defineValue(genArgs(project, bundle, false), "swift-test-import");
        if (module == null) {
            final fromRoots = rootsFileDefine(project, bundle, "swift-test-import");
            if (fromRoots != null) {
                return fromRoots;
            }
            fail('bundle "${bundle.id}": the swift recipe needs the library module name; put -D swift-test-import=<module> in the bundle haxeArgs, or in the roots file chain that the bundle compiles through');
            return "";
        }
        return module;
    }

    /**
        The main class of the haxe recipe's test build, read from the
        `haxe-test-main` define of the bundle's effective arguments.
        The binary64 reference entry is TestMain; the f32 oracle runner
        (features/44) is generated as TestMainF32 into the bundle's
        derived gen-tests directory, so the f32 bundle states the
        entry.
    **/
    static function haxeTestMain(project:Project, bundle:Bundle):String {
        final main = defineValue(genArgs(project, bundle, false), "haxe-test-main");
        return main == null ? "TestMain" : main;
    }

    static function actionCompare(project:Project):Void {
        final ids:Array<String> = [];
        for (bundle in Plan.comparable(project.bundles)) ids.push(bundle.id);
        print('[compare] baseline ${project.baseline} over ${ids.copy().join(",")}');
        Compare.run(resolveAgainst(project.root, project.resultsDir), ids, project.baseline);
    }

    static function actionVerify(project:Project, withPack:Bool):Void {
        actionGen(project, project.bundles, false);
        actionTest(project, Plan.testable(project.bundles));
        actionCompare(project);
        if (withPack) {
            actionGen(project, Plan.packable(project.bundles), true);
        }
    }

    // ------------------------------------------------------------------
    // Entry
    // ------------------------------------------------------------------

    public static function main():Void {
        final rawArgs = Host.args();
        var projectPath = "boring.json";
        var withPack = false;
        var outputPath = "";
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
            if (arg == "--output") {
                if (i + 1 >= rawArgs.length) fail("--output needs a file path");
                outputPath = rawArgs[i + 1];
                i += 2;
                continue;
            }
            if (StringTools.startsWith(arg, "--output=")) {
                outputPath = arg.substr("--output=".length);
                i++;
                continue;
            }
            rest.push(arg);
            i++;
        }
        if (rest.length == 0) {
            printErr("Usage: boring <gen|test|pack|compare|verify|roots> [<id>...] [--project <file>] [--with-pack] [--output <file>]");
            exit(2);
            return;
        }
        final action:String = rest[0];
        final ids:Array<String> = [];
        var idIndex = 1;
        while (idIndex < rest.length) {
            ids.push(rest[idIndex]);
            idIndex++;
        }
        final project = loadProject(projectPath);
        if (action == "roots") {
            if (ids.length != 1) fail("roots needs exactly one source set name");
            if (outputPath == "") fail("roots needs --output <file>");
            actionRoots(project, ids[0], outputPath);
            print("bundle driver: ok");
            return;
        }
        if (outputPath != "") fail("--output is only accepted by roots");
        final known:Array<String> = [];
        for (bundle in project.bundles) known.push(bundle.id);
        if (action == "gen") {
            if (ids.length == 0) fail('gen names no bundle; this project declares ${known.join(", ")}');
            actionGen(project, selectBundles(project, ids), false);
        } else if (action == "test") {
            if (ids.length == 0) fail('test names no bundle; this project declares ${known.join(", ")}');
            actionTest(project, selectBundles(project, ids));
        } else if (action == "pack") {
            if (ids.length == 0) fail('pack names no bundle; this project declares ${known.join(", ")}');
            actionGen(project, selectBundles(project, ids), true);
        } else if (action == "compare") {
            actionCompare(project);
        } else if (action == "verify") {
            actionVerify(project, withPack);
        } else {
            fail('unknown action "$action"; the actions are gen, test, pack, compare, verify, roots');
        }
        print("bundle driver: ok");
    }
}
