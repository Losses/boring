import std.Fs;

/**
 * The minimal `package-shell=emit` observation input of the Swift
 * target: one std.Fs.appendText call, the single host edge whose Swift
 * lowering imports SystemPackage into the generated *source* file
 * (docs/specs/stdlib/17-platform-modules.md, build-chain migration rule
 * 3). The generated Package.swift stays dependency-free, so this input
 * pins the whole split at once: the source file carries `import
 * SystemPackage`, the manifest declares nothing.
 */
class Main {
    /** Append one line through the filesystem host edge. */
    public static function appendLine(path:String, line:String):Void {
        Fs.appendText(path, line);
    }

    static function main():Void {
        appendLine("observed-append.txt", "line\n");
    }
}
