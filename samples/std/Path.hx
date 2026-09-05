package std;

/**
 * Path joining and splitting as pure string logic
 * (docs/specs/stdlib/17-platform-modules.md). This is a compiled std
 * module, outside the platform-module class: every target shares one
 * implementation, because path operations are string logic with no host
 * capability behind them. Every function accepts both "/" and "\" as
 * separators on input and returns "/"-separated text except on the
 * Windows path kinds where translation would change or corrupt the path;
 * the "Windows path kinds" section of the spec rules the per-kind
 * behavior. `expandHome` is the one place this module depends on another
 * std module: it reads the home directory through std.Env.
 */
class Path {
    /** Device paths: "\\?\" and ".\" prefixes; every function returns the input unchanged. */
    static inline final DEVICE_A = "\\\\?\\";
    static inline final DEVICE_B = "\\\\.\\";

    /** UNC paths: a leading "\\" that is not a device prefix. */
    static inline final UNC_LEAD = "\\\\";

    /**
     * The kind of a path, per the spec's classification table. The
     * numeric codes keep the switch below dense: 0 device, 1 unc, 2
     * drive absolute, 3 drive relative, 4 root relative, 5 POSIX
     * absolute, 6 POSIX double slash, 7 relative.
     */
    static function kind(p:String):Int {
        if (StringTools.startsWith(p, DEVICE_A) || StringTools.startsWith(p, DEVICE_B))
            return 0;
        if (StringTools.startsWith(p, UNC_LEAD))
            return 1;
        if (p.length >= 2 && p.charAt(1) == ":") {
            final c = p.charAt(0).toLowerCase();
            final letter = c >= "a" && c <= "z";
            if (letter) {
                final sep = p.length >= 3 ? p.charAt(2) : "";
                if (sep == "/" || sep == "\\")
                    return 2;
                return 3;
            }
        }
        if (p.length >= 1 && p.charAt(0) == "\\")
            return 4;
        if (p.length >= 1 && p.charAt(0) == "/") {
            if (p.length >= 2 && p.charAt(1) == "/") {
                // A forward UNC (//server/share/...) keeps the server and
                // share as its root; a lone POSIX double slash (//a)
                // stays kind 6 (the spec's dirname example fixes the
                // two-segment form as UNC).
                return hasUncShape(p) ? 1 : 6;
            }
            return 5;
        }
        return 7;
    }

    /** True when a "//..." path carries a second segment (the UNC shape). */
    static function hasUncShape(p:String):Bool {
        final n = p.length;
        var i = 2;
        var segments = 0;
        while (i < n) {
            if (isSep(p, i)) {
                i++;
                continue;
            }
            segments++;
            while (i < n && !isSep(p, i))
                i++;
            if (segments >= 2)
                return true;
        }
        return false;
    }

    /** True when the path uses a "/" or "\" separator at `index`. */
    static function isSep(p:String, index:Int):Bool {
        if (index < 0 || index >= p.length)
            return false;
        final c = p.charAt(index);
        return c == "/" || c == "\\";
    }

    /** The input with every "\" mapped to "/". */
    static function translated(p:String):String {
        return p.split("\\").join("/");
    }

    /** The last separator at or after `from`, or -1. */
    static function lastSep(p:String, from:Int):Int {
        var last = -1;
        var i = from;
        while (i < p.length) {
            if (isSep(p, i))
                last = i;
            i++;
        }
        return last;
    }

    /**
     * The index one past the protected root of a "/"-translated path:
     * 3 for "C:/", 1 for "/", 2 for "//", the whole text for a device
     * path, and 0 for a relative path. UNC carries its own scan.
     */
    static function rootEnd(t:String, k:Int):Int {
        if (k == 0)
            return t.length;
        if (k == 1)
            return uncRootEnd(t);
        if (k == 2)
            return 3;
        if (k == 3)
            return 2;
        if (k == 4 || k == 5)
            return 1;
        if (k == 6)
            return 2;
        return 0;
    }

    /**
     * The index one past the "//server/share" root of a translated UNC
     * path: the leading "//" plus the two segments that follow.
     */
    static function uncRootEnd(t:String):Int {
        final n = t.length;
        var i = 2;
        var segment = 0;
        while (i < n) {
            if (isSep(t, i)) {
                i++;
                continue;
            }
            segment++;
            while (i < n && !isSep(t, i))
                i++;
            if (segment >= 2)
                return i;
        }
        return n;
    }

    /** Join two path segments with the platform-agnostic separator. */
    public static function join(a:String, b:String):String {
        final kb = kind(b);
        if (kb == 0 || kb == 1 || kb == 2 || kb == 5 || kb == 6)
            return b;
        if (a == "")
            return normalize(b);
        if (kind(a) == 0)
            return b;
        if (isSep(a, a.length - 1))
            return normalize(a + b);
        return normalize(a + "/" + b);
    }

    /** The directory part of a path. */
    public static function dirname(p:String):String {
        if (p == "")
            return ".";
        final k = kind(p);
        if (k == 0)
            return p;
        final t = translated(p);
        final root = rootEnd(t, k);
        if (k == 1) {
            // UNC: never strip the root; at the root, return the root.
            final end = uncRootEnd(t);
            if (t.length == end)
                return t;
            final dir = cutDirname(t, end);
            return dir == "" ? t.substring(0, end) : dir;
        }
        if (k == 3) {
            // Drive-relative: with no separator after the drive there is
            // no directory component.
            if (lastSep(t, 2) < 0)
                return ".";
        }
        if (k == 4 && t.length == 1)
            return "/";
        if (k == 5 && t.length == 1)
            return "/";
        if (k == 6 && t.length == 2)
            return t;
        final dir = cutDirname(t, root);
        if (k == 2) {
            if (dir == "")
                return t.substring(0, 3);
            return dir;
        }
        if (k == 4 || k == 5) {
            if (dir == "")
                return "/";
            return dir;
        }
        if (k == 6) {
            if (dir == "")
                return "//";
            return dir;
        }
        return dir == "" ? "." : dir;
    }

    /** The text before the last separator at or after `root`. */
    static function cutDirname(t:String, root:Int):String {
        var end = t.length;
        // A root form keeps its trailing separator; a plain trailing
        // separator is not part of the last segment.
        while (end > root && isSep(t, end - 1))
            end--;
        if (end <= root)
            return "";
        final last = lastSep(t, root);
        if (last < root)
            return "";
        if (last == 0)
            return "/";
        return t.substring(0, last);
    }

    /** Resolve `.` and `..` segments; map `\` to `/` first. */
    public static function normalize(p:String):String {
        final k = kind(p);
        if (k == 0)
            return p;
        final t = translated(p);
        if (k == 3)
            return t;
        final root = rootEnd(t, k);
        if (k == 1 && t.length == root)
            return t;
        final prefix = t.substring(0, root);
        final tail = t.substring(root);
        if (k == 2 || k == 4 || k == 5 || k == 6) {
            if (tail == "")
                return prefix;
        }
        final kept:Array<String> = [];
        var depth = 0;
        final segments = tail.split("/");
        var i = 0;
        while (i < segments.length) {
            final segment = segments[i];
            if (segment == "" || segment == ".")
                i++;
            else if (segment == "..") {
                // A ".." pops the last ordinary segment. When the kept
                // top is itself a leading ".." (a relative path that has
                // already climbed above the cwd), the new ".." appends:
                // POSIX "a/../../b" is "../b" and "../../b" stays
                // "../../b". A rooted path never keeps "..": the dot
                // resolves against the root and is dropped there.
                if (depth > 0 && kept[depth - 1] == "..") {
                    depth = stackPush(kept, depth, segment);
                } else if (depth > 0) {
                    depth--;
                } else if (k == 7) {
                    depth = stackPush(kept, depth, segment);
                }
                i++;
            } else {
                depth = stackPush(kept, depth, segment);
                i++;
            }
        }
        if (k == 1 && depth == 0)
            return prefix;
        final bodyParts:Array<String> = [];
        var j = 0;
        while (j < depth) {
            bodyParts.push(kept[j]);
            j++;
        }
        final body = bodyParts.join("/");
        if (body == "")
            return prefix == "" ? "." : prefix;
        if (k == 1)
            return prefix + "/" + body;
        return prefix + body;
    }

    /**
     * Append a segment to the stack array. A pop only lowers `depth`,
     * leaving the popped entry in place, so an append first overwrites a
     * freed slot when one exists and grows the array only when the stack
     * is at its length. The array writes therefore always stay inside the
     * bounds every target's list enforces.
     */
    static function stackPush(kept:Array<String>, depth:Int, segment:String):Int {
        if (depth < kept.length)
            kept[depth] = segment;
        else
            kept.push(segment);
        return depth + 1;
    }

    /** Expand a leading `~` to the home directory via `std.Env`. */
    public static function expandHome(p:String):String {
        if (p == "~" || StringTools.startsWith(p, "~/") || StringTools.startsWith(p, "~\\")) {
            final home = homeDir();
            if (home == null)
                return p;
            if (home == "")
                return p;
            if (p.length == 1)
                return home;
            final rest = p.substring(2);
            // A trailing separator after the tilde carries no segment;
            // the expanded home stands alone.
            if (rest == "")
                return home;
            return home + "/" + normalize(rest);
        }
        return p;
    }

    /** HOME on POSIX hosts, USERPROFILE on Windows hosts, via std.Env. */
    static function homeDir():Null<String> {
        final home = Env.get("HOME");
        if (home == null)
            return Env.get("USERPROFILE");
        if (home == "")
            return Env.get("USERPROFILE");
        return home;
    }
}
