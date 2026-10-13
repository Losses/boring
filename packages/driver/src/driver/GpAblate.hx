package driver;

import driver.Host.HostResult;

/** GP-ABLATE: two-arm compile-time ablation probe (WBS 0.3).

    Arm A (normal) runs \`haxe <fixture> && <compile>\` and must succeed
    (rc=0). Arm B (ablated) runs the same with \`-D <target>_coerce_ablate=<Role>\`
    added and must fail (rc!=0). The two rc values must differ, and when
    --expect names a fragment the ablated arm's output must contain it. **/
class GpAblate {
    static var project:Project;

    public static function run(p:Project, args:Array<String>):Int {
        project = p;
        var fixture:String = null;
        var define:String = null;
        var compile:String = "";
        var expect:String = "";

        var i = 0;
        while (i < args.length) {
            final a = args[i];
            if (StringTools.startsWith(a, "--define=")) { define = a.substr("--define=".length); i++; }
            else if (a == "--define") { if (i + 1 >= args.length) fail("--define needs a value"); define = args[i + 1]; i += 2; }
            else if (StringTools.startsWith(a, "--compile=")) { compile = a.substr("--compile=".length); i++; }
            else if (a == "--compile") { if (i + 1 >= args.length) fail("--compile needs a value"); compile = args[i + 1]; i += 2; }
            else if (StringTools.startsWith(a, "--expect=")) { expect = a.substr("--expect=".length); i++; }
            else if (a == "--expect") { if (i + 1 >= args.length) fail("--expect needs a value"); expect = args[i + 1]; i += 2; }
            else { if (fixture != null) fail("too many positional args; gp-ablate takes <fixture.hxml> [--define <switch>] [--compile <shell>] [--expect <fragment>]"); fixture = a; i++; }
        }

        if (fixture == null) fail("gp-ablate needs a fixture hxml path");
        if (define == null) fail("gp-ablate needs --define <target>_coerce_ablate=<Role>");

        final fixtureAbs = Host.resolve(project.root, fixture);
        if (!Host.exists(fixtureAbs)) fail("fixture not found: " + fixtureAbs);

        final armA = buildArm(fixture, null, compile);
        final armB = buildArm(fixture, define, compile);

        Host.outputLine("GP-ABLATE  fixture=" + fixture + "  define=" + define);
        Host.outputLine("           compile=[" + compile + "]");
        Host.outputLine("  arm A (normal):  " + armA);
        Host.outputLine("  arm B (ablated): " + armB);

        final ra = runShell(armA);
        final rb = runShell(armB);

        final fragmentOk = expect == "" || rb.output.indexOf(expect) >= 0;
        final pass = ra.code == 0 && rb.code != 0 && fragmentOk;

        writeStatus(fixture, define, armA, armB, ra, rb, expect, pass);

        Host.outputLine("  arm A rc=" + Std.string(ra.code) + "  arm B rc=" + Std.string(rb.code));
        if (pass) {
            Host.outputLine("GP-ABLATE: pass (rc differ; ablated arm fails"
                + (expect != "" ? " with expected fragment" : "") + ")");
        } else {
            Host.outputLine("GP-ABLATE: fail");
            if (ra.code != 0) Host.outputLine("  arm A unexpectedly failed rc=" + Std.string(ra.code));
            if (rb.code == 0) Host.outputLine("  arm B unexpectedly succeeded (rc=0)");
            if (rb.code != 0 && expect != "" && !fragmentOk) {
                Host.outputLine("  ablated output missing expected fragment: \"" + expect + "\"");
            }
        }
        return pass ? 0 : 1;
    }

    static function fail(message:String):Void {
        Host.outputLine("gp-ablate: " + message);
        Host.exit(1);
    }

    static function buildArm(fixture:String, define:String, compile:String):String {
        final hx = define == null
            ? "haxe \"" + fixture + "\""
            : "haxe \"" + fixture + "\" -D " + define;
        if (compile == "") return hx;
        return hx + " && " + compile;
    }

    static function runShell(command:String):HostResult {
        return Host.run("bash", ["-c", command], project.root, []);
    }

    static function writeStatus(fixture:String, define:String, armA:String, armB:String,
            ra:HostResult, rb:HostResult, expect:String, pass:Bool):Void {
        final cacheRoot = Host.resolve(project.root, "out/.gp-cache");
        Host.makeDirs(cacheRoot);
        final statusPath = Host.join(cacheRoot, "ablate-status.tsv");
        var buf = new StringBuf();
        buf.add("stage\tstatus\ttarget\texit\tdetail\n");
        buf.add("gp-ablate:normal\t" + (ra.code == 0 ? "ok" : "fail") + "\t" + fixture + "\t" + Std.string(ra.code) + "\tdefine=(none)\n");
        buf.add("gp-ablate:ablated\t" + (rb.code != 0 ? "ok" : "fail") + "\t" + fixture + "\t" + Std.string(rb.code) + "\tdefine=" + define + "\n");
        Host.writeText(statusPath, buf.toString());

        final summaryPath = Host.join(cacheRoot, "ablate-summary.txt");
        var sum = new StringBuf();
        sum.add("GP-ABLATE  fixture=" + fixture + "  define=" + define + "\n");
        sum.add("expect=[" + expect + "]\n");
        sum.add("verdict=" + (pass ? "PASS" : "FAIL") + "\n\n");
        sum.add("--- arm A (normal) rc=" + Std.string(ra.code) + " ---\n" + ra.output + "\n");
        sum.add("--- arm B (ablated) rc=" + Std.string(rb.code) + " ---\n" + rb.output + "\n");
        Host.writeText(summaryPath, sum.toString());
    }
}