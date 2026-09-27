package driver;


/** Computes generation arguments and action participants from validated data. */
class Plan {
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
    public static function genArgs(project:Project, bundle:Bundle, pack:Bool, genDir:String, genTestsDir:String, packageTsc:Null<String>, packageKotlinc:Null<String>):Array<String> {
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
