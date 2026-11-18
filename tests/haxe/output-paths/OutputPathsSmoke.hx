import swiftcompiler.OutputPaths;

/**
    Regression for the windows CI job's output-tree relativization (task
    t-mwlffeyx-sqcu). That job passes the two tree defines as absolute
    Windows paths (backslash separators, drive prefix); splitting on "/"
    alone made the test tree resolve to ../D:\..., and the output manager
    created a directory named D: under the generated tree.
**/
class OutputPathsSmoke {
    static function main():Void {
        // The POSIX define form the linux and macos jobs pass.
        expect("/w/reference/swift/gen", "/w/reference/swift/gen-tests", "../gen-tests", "posix");
        // The Windows define form: backslashes plus a drive prefix.
        expect("D:\\w\\reference\\swift\\gen", "D:\\w\\reference\\swift\\gen-tests", "../gen-tests", "windows");
        // The drive component never reaches the result, in either case.
        expect("d:\\w\\reference\\swift\\gen", "D:/w/reference/swift/gen-tests", "../gen-tests", "drive case");
        // A test module adds one more segment under the test tree.
        expect("D:\\a\\b\\reference\\swift\\gen", "D:\\a\\b\\reference\\swift\\gen-tests\\tests", "../gen-tests/tests", "test module");
        // Mixed separators name the same tree too.
        expect("D:\\w\\gen", "D:/w/gen-tests", "../gen-tests", "mixed separators");
        // Shapes the emitter also asks for.
        expect("/w/gen", "/w/gen", "", "same directory");
        expect("/w/gen/sub", "/w/gen", "..", "parent");
        expect("reference/swift/gen", "reference/swift/gen-tests", "../gen-tests", "root relative");
        // Two different drives have no relative path. Fail here: writing a
        // "C:" component into the output tree corrupts it.
        var rejected = false;
        try {
            OutputPaths.relativeFromTo("D:\\w\\gen", "C:\\w\\gen-tests");
        } catch (problem:Dynamic) {
            rejected = true;
        }
        if (!rejected) {
            throw "different drives: expected a rejection, got a relative path";
        }
        Sys.println("output-paths-ok");
    }

    static function expect(from:String, to:String, want:String, label:String):Void {
        final got = OutputPaths.relativeFromTo(from, to);
        if (got != want) {
            throw label + ': expected "' + want + '", got "' + got + '" (from ' + from + ', to ' + to + ")";
        }
    }
}
