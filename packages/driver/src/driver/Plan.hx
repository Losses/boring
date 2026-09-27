package driver;


/** Computes generation arguments and action participants from validated data. */
class Plan {
    public static function sortedUnique(values:Array<String>):Array<String> {
        final sorted:Array<String> = [];
        for (value in values) {
            var duplicate = false;
            for (prior in sorted) if (prior == value) duplicate = true;
            if (!duplicate) sorted.push(value);
        }
        var index = 1;
        while (index < sorted.length) {
            final value = sorted[index];
            var slot = index;
            while (slot > 0 && sorted[slot - 1] > value) {
                sorted[slot] = sorted[slot - 1];
                slot--;
            }
            sorted[slot] = value;
            index++;
        }
        return sorted;
    }

    static function moduleName(value:String):Bool {
        if (value == "") return false;
        for (index in 0...value.length) {
            final code = value.charCodeAt(index);
            final letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 95;
            final digit = code >= 48 && code <= 57;
            if (!letter && (!digit || index == 0)) return false;
        }
        return true;
    }

    /** Maps one direct directory listing to module roots in stable order. */
    public static function discoverTypes(pack:String, suffix:String, entries:Array<String>):Array<String> {
        final types:Array<String> = [];
        for (entry in entries) {
            if (entry.length <= 3 || entry.substr(entry.length - 3) != ".hx") continue;
            final module = entry.substr(0, entry.length - 3);
            if (!moduleName(module) || module.length < suffix.length
                || module.substr(module.length - suffix.length) != suffix) continue;
            types.push(pack + "." + module);
        }
        return sortedUnique(types);
    }

    public static function sourceSet(project:Project, name:String):Null<SourceSet> {
        for (set in project.sourceSets) if (set.name == name) return set;
        return null;
    }

    public static function sourceArgs(set:SourceSet, discovered:Array<String>):Array<String> {
        final args:Array<String> = [];
        for (pack in set.packages) {
            args.push("--macro");
            args.push("haxe.macro.Compiler.include('" + pack + "', false, null, null, true)");
        }
        for (typePath in sortedUnique(set.types.concat(discovered))) args.push(typePath);
        return args;
    }

    public static function rootsContents(set:SourceSet, discovered:Array<String>):String {
        final args = sourceArgs(set, discovered);
        var contents = "";
        var index = 0;
        while (index < args.length) {
            if (args[index] == "--macro") {
                contents += "--macro " + args[index + 1] + "\n";
                index += 2;
            } else {
                contents += args[index] + "\n";
                index++;
            }
        }
        return contents;
    }

    static function addStep(steps:Array<ExecutionStep>, name:String, command:String, args:Array<String>, cwd:String, env:Array<EnvVar>):Void {
        final step:ExecutionStep = {name: name, command: command, args: args.copy(), cwd: cwd, env: env.copy()};
        steps.push(step);
    }

    public static function testSteps(project:Project, bundle:Bundle, generatedDir:String, genTests:String, build:String,
        results:String, genFiles:Array<String>, testFiles:Array<String>, haxeMain:String,
        swiftModule:Null<String>, systemPackage:Null<String>, host:String, existingLibraryPath:String):Array<ExecutionStep> {
        if (!bundle.hasTests) throw new DriverException(InvalidConfig('bundle "${bundle.id}": this target configuration has test=false and cannot run the test action'));
        final steps:Array<ExecutionStep> = [];
        final runEnv = bundle.run.env.copy();
        final resultVariable:EnvVar = {key: "BORING_TEST_RESULTS", value: results};
        runEnv.push(resultVariable);
        if (bundle.target == "ts") {
            addStep(steps, "run", "bun", ["test", genTests].concat(bundle.run.args), project.root, runEnv);
        } else if (bundle.target == "dart") {
            addStep(steps, "run", "dart", [genTests + "/main.dart"].concat(bundle.run.args), project.root, runEnv);
        } else if (bundle.target == "haxe") {
            final args = ["-cp", genTests];
            for (root in project.sourceRoots) {
                args.push("-cp");
                args.push(root);
            }
            final buildArgs = args.concat(bundle.build.args).concat(["-main", haxeMain, "-js", generatedDir + "/test-main.js"]);
            addStep(steps, "build", "haxe", buildArgs, project.root, bundle.build.env);
            addStep(steps, "run", "bun", [generatedDir + "/test-main.js"].concat(bundle.run.args), project.root, runEnv);
        } else if (bundle.target == "kotlin") {
            if (genFiles.length == 0) throw new DriverException(InvalidConfig('bundle "${bundle.id}": no .kt sources under $generatedDir; run gen first'));
            if (testFiles.length == 0) throw new DriverException(InvalidConfig('bundle "${bundle.id}": no .kt sources under $genTests; run gen first'));
            final libraryJar = build + "/library.jar";
            final testsJar = build + "/tests.jar";
            addStep(steps, "build library jar", "kotlinc", genFiles.concat(bundle.build.args).concat(["-include-runtime", "-d", libraryJar]), project.root, bundle.build.env);
            addStep(steps, "build tests jar", "kotlinc", ["-cp", libraryJar].concat(testFiles).concat(bundle.build.args).concat(["-d", testsJar]), project.root, bundle.build.env);
            addStep(steps, "run", "java", ["-cp", libraryJar + ":" + testsJar].concat(bundle.run.args).concat(["TestMainKt"]), project.root, runEnv);
        } else if (bundle.target == "rust") {
            addStep(steps, "build", "cargo", ["test", "--no-run"].concat(bundle.build.args), generatedDir, bundle.build.env);
            addStep(steps, "run", "cargo", ["test"].concat(bundle.run.args), generatedDir, runEnv);
        } else if (bundle.target == "swift") {
            if (swiftModule == null) throw new DriverException(InvalidConfig('bundle "${bundle.id}": missing swift-test-import'));
            final module = swiftModule + "";
            if (genFiles.length == 0) throw new DriverException(InvalidConfig('bundle "${bundle.id}": no .swift sources under $generatedDir; run gen first'));
            if (testFiles.length == 0) throw new DriverException(InvalidConfig('bundle "${bundle.id}": no .swift sources under $genTests; run gen first'));
            final packagePath = systemPackage == null ? "" : systemPackage + "";
            final importArgs = systemPackage == null ? [] : ["-I", packagePath];
            final linkArgs = systemPackage == null ? [] : ["-L", packagePath, "-lSystemPackage"];
            addStep(steps, "build library", "swiftc", ["-emit-library", "-emit-module"].concat(importArgs).concat(genFiles)
                .concat(bundle.build.args).concat(["-module-name", module, "-o", build + "/" + swiftLibraryName(module, host)]), project.root, bundle.build.env);
            addStep(steps, "build test executable", "swiftc", importArgs.concat(testFiles).concat(bundle.build.args)
                .concat(["-I", build, "-L", build, "-l" + module]).concat(linkArgs).concat(["-o", build + "/test-runner"]), project.root, bundle.build.env);
            final runPaths = systemPackage == null ? build : build + ":" + packagePath;
            final libraryVariable:EnvVar = {key: swiftLibraryPathVariable(host), value: existingLibraryPath == "" ? runPaths : runPaths + ":" + existingLibraryPath};
            runEnv.push(libraryVariable);
            addStep(steps, "run", build + "/test-runner", bundle.run.args, project.root, runEnv);
        } else {
            throw new DriverException(InvalidConfig('bundle "${bundle.id}": target "${bundle.target}" has no recipe'));
        }
        return steps;
    }

    public static function swiftLibraryName(module:String, host:String):String {
        return "lib" + module + (host == "darwin" ? ".dylib" : ".so");
    }

    public static function swiftLibraryPathVariable(host:String):String {
        return host == "darwin" ? "DYLD_LIBRARY_PATH" : "LD_LIBRARY_PATH";
    }

    /**
        The runtime defines the driver holds at their documented
        defaults, before the project's arguments so `haxeArgs` overrides
        them. The test-runner define follows the recipe's run command;
        `runtime-import` and `runtime-emit` have no default (the
        consumer's identity is not derivable) and arrive through the
        roots file or `haxeArgs`.
    **/
    public static function targetDefaultDefines(target:String):Array<String> {
        if (target == "ts") return ["ts-test-runner=bun"];
        if (target == "dart") return ["dart-test-runner=native"];
        if (target == "swift") return ["swift-test-runner=native"];
        return [];
    }

    /**
        The haxe arguments of one generation. Order: the classpaths, the
        target defaults, the roots file, the project's arguments, the
        bundle's arguments, then the derived defines; haxe keeps the
        last value of a repeated define, so the derived output
        directories win over anything the roots file states, and the
        roots file wins over the driver's defaults.
    **/
    public static function genArgs(project:Project, bundle:Bundle, pack:Bool, genDir:String, genTestsDir:String, packageTsc:Null<String>, packageKotlinc:Null<String>, discoveredTypes:Array<String>):Array<String> {
        final args:Array<String> = [];
        for (root in project.sourceRoots) {
            args.push("-cp");
            args.push(root);
        }
        for (define in targetDefaultDefines(bundle.target)) {
            args.push("-D");
            args.push(define);
        }
        final rootsFile = bundle.rootsFile != "" ? bundle.rootsFile : project.rootsFile;
        if (rootsFile != "") {
            args.push(rootsFile);
        }
        for (arg in project.haxeArgs) {
            args.push(arg);
        }
        for (arg in bundle.haxeArgs) {
            args.push(arg);
        }
        final selected = sourceSet(project, bundle.sourceSet);
        if (selected != null) {
            for (arg in sourceArgs(selected, discoveredTypes)) args.push(arg);
        }
        if (bundle.target != "haxe") {
            args.push("-D");
            args.push(bundle.target + "-output=" + genDir);
            args.push("-D");
            args.push(bundle.target + "-test-output=" + genTestsDir);
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
            if (bundle.packageLicense != "") {
                args.push("-D");
                args.push("package-license=" + bundle.packageLicense);
            }
            args.push("-D");
            args.push("package-shell=emit");
            args.push("-D");
            args.push("package-artifacts=emit");
            if (bundle.target == "ts") {
                args.push("-D");
                args.push("package-tsc=" + packageTsc);
            } else if (bundle.target == "kotlin") {
                args.push("-D");
                args.push("package-kotlinc=" + packageKotlinc);
            }
        }
        return args;
    }

    public static function testable(bundles:Array<Bundle>):Array<Bundle> {
        return [for (bundle in bundles) if (bundle.hasTests) bundle];
    }

    public static function comparable(bundles:Array<Bundle>):Array<Bundle> {
        return [for (bundle in bundles) if (bundle.hasComparison) bundle];
    }

    public static function packable(bundles:Array<Bundle>):Array<Bundle> {
        return [for (bundle in bundles) if (bundle.packageName != "") bundle];
    }
}
