import driver.Compare;
import js.Syntax;

/** Compatibility entry for the comparison command provided by driver. */
class Main {
    public static function main():Void {
        var resultsDir = "out/test-results";
        var targets = ["kotlin", "haxe", "ts", "rust", "swift", "dart"];
        var baseline = "kotlin";
        final args:Array<String> = Syntax.code("process.argv.slice(2)");
        var i = 0;
        while (i < args.length) {
            final arg = args[i];
            if (StringTools.startsWith(arg, "--dir=")) {
                resultsDir = arg.substr(6);
            } else if (arg == "--dir" && i + 1 < args.length) {
                resultsDir = args[++i];
            } else if (StringTools.startsWith(arg, "--targets=")) {
                targets = arg.substr(10).split(",");
            } else if (StringTools.startsWith(arg, "--baseline=")) {
                baseline = arg.substr(11);
            } else if (arg == "--baseline" && i + 1 < args.length) {
                baseline = args[++i];
            }
            i++;
        }
        final fromEnv:Null<String> = Syntax.code("process.env.BORING_TEST_RESULTS_DIR || null");
        if (fromEnv != null && fromEnv != "") {
            resultsDir = fromEnv;
        }
        Compare.run(resultsDir, targets, baseline);
    }
}
