package swiftcompiler;

/**
    Output-tree path arithmetic for the Swift emitter.

    The `swift-output` and `swift-test-output` defines are absolute paths on
    every host. On Windows they carry backslash separators and a drive
    prefix (`D:\a\boring\boring\reference\swift\gen`), while
    the compiler writes through the output manager with `/`-separated,
    output-root relative paths. Relativizing the two defines by splitting on
    `/` alone left one component per side, so the test tree resolved to
    `../D:\a\...\gen-tests` and the output manager created a
    directory named `D:` under the generated tree (measured on the windows
    CI job: Invalid argument(mkdir, .../reference/swift/D:)).
**/
class OutputPaths {
    /**
        The path from one directory to another location. Both arguments are
        absolute or both are output-root relative. Separators are normalized
        and a drive prefix is compared as one component, so a Windows caller
        and a POSIX caller with the same tree layout get the same relative
        path (`../gen-tests`).
    **/
    public static function relativeFromTo(fromDir:String, toPath:String):String {
        final fromParts = components(fromDir);
        final toParts = components(toPath);
        final fromDrive = driveOf(fromParts);
        final toDrive = driveOf(toParts);
        if (fromDrive != null && toDrive != null && !sameComponent(fromDrive, toDrive)) {
            // Two trees on different drives have no relative path. The
            // defines name sibling trees, so a mismatch is a caller error;
            // failing here beats writing a "C:" component into the output
            // tree the way the unnormalized split did.
            throw "swift output trees are on different drives: " + fromDir + " and " + toPath;
        }
        var shared = 0;
        while (shared < fromParts.length && shared < toParts.length && sameComponent(fromParts[shared], toParts[shared])) {
            shared += 1;
        }
        final out:Array<String> = [];
        for (_ in shared...fromParts.length) {
            out.push("..");
        }
        for (i in shared...toParts.length) {
            out.push(toParts[i]);
        }
        return out.join("/");
    }

    /** The non-empty, non-"." components of either separator convention. */
    static function components(path:String):Array<String> {
        final parts = StringTools.replace(path, "\\", "/").split("/");
        final out:Array<String> = [];
        for (part in parts) {
            if (part == "" || part == ".") {
                continue;
            }
            out.push(part);
        }
        return out;
    }

    /** The drive component of a split path ("D:"), or null for a POSIX or relative path. */
    static function driveOf(parts:Array<String>):Null<String> {
        if (parts.length == 0) {
            return null;
        }
        final first = parts[0];
        return first.length == 2 && first.charAt(1) == ":" ? first : null;
    }

    /** Whether two components name the same segment; drive letters compare case-insensitively. */
    static function sameComponent(a:String, b:String):Bool {
        if (a == b) {
            return true;
        }
        return a.length == 2 && b.length == 2 && a.charAt(1) == ":" && b.charAt(1) == ":" && a.toLowerCase() == b.toLowerCase();
    }
}
