package tests;

import driver.Config;
import driver.Plan;
import driver.DriverException;
import driver.Diagnostic;
import driver.DriverFault;
import driver.CompareCore;
import driver.ResultInput;

class DriverPlanTests {
    @:test("driver host identifies the same operating system")
    public static function hostPlatform():Void {
        #if js
        final expected:String = js.Syntax.code("process.env.BORING_EXPECT_PLATFORM || ''");
        final actual:String = js.Syntax.code("process.platform");
        #else
        final configured = std.Env.get("BORING_EXPECT_PLATFORM");
        final expected:String = configured == null ? "" : configured;
        final actual = std.Process.platform();
        #end
        if (expected == "") return;
        if (actual != expected) {
            throw new DriverException(InvalidConfig("driver host platform differs"));
        }
    }

    @:test("driver parses target configurations consistently")
    public static function parse():Void {
        final project = Config.parse('{"outRoot":"out","baseline":"baseline","sourceRoots":["src"],"haxeArgs":["-D","shared=1"],"bundles":[{"id":"baseline","target":"ts","precision":"f32","haxeArgs":["-D","local=2"]},{"id":"header","target":"ts","test":false},{"id":"alternate","target":"ts","compare":false}]}', "boring.json", "/project");
        if (project.bundles.length != 3 || project.bundles[0].id != "baseline" || !project.bundles[0].hasTests || project.bundles[1].hasTests || !project.bundles[2].hasTests || project.bundles[2].hasComparison) {
            throw new DriverException(InvalidConfig("driver configuration differs"));
        }
        if (Plan.testable(project.bundles).length != 2 || Plan.comparable(project.bundles).length != 1 || Plan.packable(project.bundles).length != 0) {
            throw new DriverException(InvalidConfig("driver action participants differ"));
        }
    }

    @:test("driver plans generation arguments consistently")
    public static function generation():Void {
        final project = Config.parse('{"outRoot":"out","baseline":"baseline","sourceRoots":["src"],"haxeArgs":["-D","shared=1"],"bundles":[{"id":"baseline","target":"ts","precision":"f32","haxeArgs":["-D","local=2"]},{"id":"header","target":"ts","test":false}]}', "boring.json", "/project");
        final args = Plan.genArgs(project, project.bundles[0], false, "/project/out/baseline/gen", "/project/out/baseline/gen-tests", null, null);
        final expected = ["-cp", "src", "-D", "ts-test-runner=bun", "-D", "shared=1", "-D", "local=2", "-D", "ts-output=/project/out/baseline/gen", "-D", "ts-test-output=/project/out/baseline/gen-tests", "-D", "float-precision=f32"];
        if (args.copy().join("\n") != expected.join("\n")) {
            throw new DriverException(InvalidConfig("driver generation arguments differ: " + args.copy().join(" ")));
        }
    }

    @:test("driver chooses the Swift library name for each host")
    public static function swiftLibrary():Void {
        if (Plan.swiftLibraryName("Codec", "linux") != "libCodec.so"
            || Plan.swiftLibraryName("Codec", "darwin") != "libCodec.dylib"
            || Plan.swiftLibraryPathVariable("linux") != "LD_LIBRARY_PATH"
            || Plan.swiftLibraryPathVariable("darwin") != "DYLD_LIBRARY_PATH") {
            throw new DriverException(InvalidConfig("driver Swift library plan differs"));
        }
    }

    @:test("driver gives the same invalid configuration message")
    public static function invalidConfig():Void {
        var message = "";
        try {
            Config.parse('{"outRoot":"out","baseline":"bad","sourceRoots":[],"bundles":[{"id":"bad","target":"ts","test":false}]}',
                "boring.json", "/project");
        } catch (error:DriverException) {
            message = Diagnostic.describe(error.fault);
        }
        if (message != 'boring.json: baseline "bad" must have tests') {
            throw new DriverException(InvalidConfig("driver diagnostic differs: " + message));
        }
        message = "";
        try {
            Config.parse('{"outRoot":"out","baseline":"bad","sourceRoots":[],"bundles":[{"id":"bad","target":"ts","compare":false}]}',
                "boring.json", "/project");
        } catch (error:DriverException) {
            message = Diagnostic.describe(error.fault);
        }
        if (message != 'boring.json: baseline "bad" must participate in compare') {
            throw new DriverException(InvalidConfig("driver comparison diagnostic differs: " + message));
        }
        message = "";
        try {
            Config.parse('{"outRoot":"out","baseline":"good","sourceRoots":[],"bundles":[{"id":"good","target":"ts"},{"id":"bad","target":"ts","test":false,"compare":true}]}',
                "boring.json", "/project");
        } catch (error:DriverException) {
            message = Diagnostic.describe(error.fault);
        }
        if (message != 'boring.json: bundle "bad": compare=true requires test=true') {
            throw new DriverException(InvalidConfig("driver compare/test diagnostic differs: " + message));
        }
    }

    @:test("driver compares results and reports the same divergence")
    public static function comparison():Void {
        final baseline:ResultInput = {id: "baseline", text: '{"id":"same","name":"same","verdict":"pass"}\n'};
        final other:ResultInput = {id: "other", text: '{"id":"same","name":"same","verdict":"fail"}\n'};
        final result = CompareCore.run([baseline, other], "baseline");
        if (result.errors.length != 1 || result.errors[0] != "[other] Verdict mismatch on same: baseline=pass, actual=fail"
            || result.allIds.join(",") != "same") {
            throw new DriverException(InvalidConfig("driver comparison differs"));
        }
    }

    @:test("driver plans every target test command consistently")
    public static function testCommands():Void {
        final config = '{"outRoot":"out","baseline":"ts","sourceRoots":["src"],"bundles":['
            + '{"id":"haxe","target":"haxe"},{"id":"ts","target":"ts"},'
            + '{"id":"kotlin","target":"kotlin"},{"id":"rust","target":"rust"},'
            + '{"id":"swift","target":"swift"},{"id":"dart","target":"dart"}]}';
        final project = Config.parse(config, "boring.json", "/project");
        final expected = [
            "haxe:build|haxe|-cp,/project/gen-tests,-cp,src,-main,TestMain,-js,/project/gen/test-main.js|/project|"
                + ";run|bun|/project/gen/test-main.js|/project|BORING_TEST_RESULTS=/project/results/haxe.jsonl",
            "ts:run|bun|test,/project/gen-tests|/project|BORING_TEST_RESULTS=/project/results/ts.jsonl",
            "kotlin:build library jar|kotlinc|library.kt,-include-runtime,-d,/project/build/library.jar|/project|"
                + ";build tests jar|kotlinc|-cp,/project/build/library.jar,test.kt,-d,/project/build/tests.jar|/project|"
                + ";run|java|-cp,/project/build/library.jar:/project/build/tests.jar,TestMainKt|/project|BORING_TEST_RESULTS=/project/results/kotlin.jsonl",
            "rust:build|cargo|test,--no-run|/project/gen|"
                + ";run|cargo|test|/project/gen|BORING_TEST_RESULTS=/project/results/rust.jsonl",
            "swift:build library|swiftc|-emit-library,-emit-module,library.kt,-module-name,Codec,-o,/project/build/libCodec.dylib|/project|"
                + ";build test executable|swiftc|test.kt,-I,/project/build,-L,/project/build,-lCodec,-o,/project/build/test-runner|/project|"
                + ";run|/project/build/test-runner||/project|BORING_TEST_RESULTS=/project/results/swift.jsonl,DYLD_LIBRARY_PATH=/project/build",
            "dart:run|dart|/project/gen-tests/main.dart|/project|BORING_TEST_RESULTS=/project/results/dart.jsonl"
        ];
        final actual:Array<String> = [];
        for (bundle in project.bundles) {
            final steps = Plan.testSteps(project, bundle, "/project/gen", "/project/gen-tests", "/project/build",
                "/project/results/" + bundle.id + ".jsonl", ["library.kt"], ["test.kt"], "TestMain",
                "Codec", null, "darwin", "");
            final signatures:Array<String> = [];
            for (step in steps) {
                final environment:Array<String> = [];
                for (item in step.env) environment.push(item.key + "=" + item.value);
                signatures.push(step.name + "|" + step.command + "|" + step.args.join(",") + "|" + step.cwd
                    + "|" + environment.join(","));
            }
            actual.push(bundle.id + ":" + signatures.join(";"));
        }
        if (actual.copy().join(";") != expected.join(";")) {
            throw new DriverException(InvalidConfig("driver target command plan differs: " + actual.copy().join(";")));
        }
    }

    @:test("driver plans package flags and rejects reserved results overrides")
    public static function packAndEnvironment():Void {
        final config = '{"outRoot":"out","baseline":"ts","sourceRoots":[],"bundles":['
            + '{"id":"ts","target":"ts","package":{"name":"demo","version":"1.0.0","license":"MPL-2.0"}}]}';
        final project = Config.parse(config, "boring.json", "/project");
        final args = Plan.genArgs(project, project.bundles[0], true, "/project/gen", "/project/gen-tests", "/usr/bin/tsc", null);
        if (args.indexOf("package-name=demo") < 0 || args.indexOf("package-version=1.0.0") < 0
            || args.indexOf("package-license=MPL-2.0") < 0
            || args.indexOf("package-artifacts=emit") < 0 || args.indexOf("package-tsc=/usr/bin/tsc") < 0) {
            throw new DriverException(InvalidConfig("driver package plan differs"));
        }
        final noLicense = Config.parse('{"outRoot":"out","baseline":"ts","sourceRoots":[],"bundles":['
            + '{"id":"ts","target":"ts","package":{"name":"demo","version":"1.0.0"}}]}',
            "boring.json", "/project");
        final argsWithoutLicense = Plan.genArgs(noLicense, noLicense.bundles[0], true, "/project/gen", "/project/gen-tests", "/usr/bin/tsc", null);
        for (arg in argsWithoutLicense) {
            if (arg.indexOf("package-license=") == 0) throw new DriverException(InvalidConfig("driver inferred a package license"));
        }
        var message = "";
        try {
            Config.parse('{"outRoot":"out","baseline":"ts","sourceRoots":[],"bundles":['
                + '{"id":"ts","target":"ts","run":{"env":{"BORING_TEST_RESULTS":"wrong.jsonl"}}}]}',
                "boring.json", "/project");
        } catch (error:DriverException) {
            message = Diagnostic.describe(error.fault);
        }
        if (message != 'boring.json: bundle "ts": run.env may not set BORING_TEST_RESULTS; the driver derives the results path') {
            throw new DriverException(InvalidConfig("driver reserved environment diagnostic differs"));
        }
        message = "";
        try {
            Config.parse('{"outRoot":"out","baseline":"ts","sourceRoots":[],"bundles":['
                + '{"id":"ts","target":"ts","package":{"name":"demo","version":"1.0.0","license":""}}]}',
                "boring.json", "/project");
        } catch (error:DriverException) {
            message = Diagnostic.describe(error.fault);
        }
        if (message != 'boring.json: bundle "ts": package license must not be empty') {
            throw new DriverException(InvalidConfig("driver package license diagnostic differs"));
        }
    }
}
