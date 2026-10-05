package fsprobe;

import std.Console;
import std.Fs;
import std.FsError;
import std.FsException;

/**
 * Observation fixture for the canonical std.Fs host-failure model
 * (docs/specs/stdlib/17-platform-modules.md "Failure behavior"). It
 * asserts nothing: it runs one host operation per normalized kind against
 * paths the native harness prepares, and prints one deterministic line per
 * observation. The kind is read off the FsError variant, never out of the
 * message, and a missing path, a directory used as a file, a file used as a
 * directory, and a permission-denied directory all reach the same
 * `catch (error:std.FsException)` shape.
 */
class FsFailureProbe {
    public static function rootPath():String {
        return "out/fs-failure-model";
    }

    public static function missingPath():String {
        return rootPath() + "/definitely-missing.txt";
    }

    static function say(label:String, text:String):Void {
        Console.log(label + "|" + text);
    }

    static function line(operation:String, path:String, kind:String, nativeDetail:String):String {
        return "caught|std.FsException|" + operation + "|" + path + "|" + kind + "|" + nativeDetail;
    }

    /** One caught failure as identity|operation|path|kind|nativeDetail, the kind read off the variant. */
    static function report(label:String, error:FsException):Void {
        switch (error.error) {
            case NotFound(operation, path, nativeDetail):
                say(label, line(operation, path, "NotFound", nativeDetail));
            case PermissionDenied(operation, path, nativeDetail):
                say(label, line(operation, path, "PermissionDenied", nativeDetail));
            case NotDirectory(operation, path, nativeDetail):
                say(label, line(operation, path, "NotDirectory", nativeDetail));
            case IsDirectory(operation, path, nativeDetail):
                say(label, line(operation, path, "IsDirectory", nativeDetail));
            case AlreadyExists(operation, path, nativeDetail):
                say(label, line(operation, path, "AlreadyExists", nativeDetail));
            case InvalidInput(operation, path, nativeDetail):
                say(label, line(operation, path, "InvalidInput", nativeDetail));
            case Unavailable(operation, path):
                say(label, line(operation, path, "Unavailable", ""));
            case Other(operation, path, nativeDetail):
                say(label, line(operation, path, "Other", nativeDetail));
        }
    }

    /** Every host failure observed through the canonical catch shape. */
    public static function observe():Void {
        say("m0", "probe-start");
        final missing = missingPath();
        final readDirPath = rootPath() + "/read-dir";
        final permDirPath = rootPath() + "/perm-dir";
        final regularFile = rootPath() + "/regular-file";

        // isDirectory stays total: a missing path is a returned false, not a failure.
        say("m1", "isDirectory-missing|" + Std.string(Fs.isDirectory(missing)));

        try {
            final text = Fs.readText(missing);
            say("m2", "readText-returned|" + text);
        } catch (error:FsException) {
            report("m2", error);
        }

        try {
            final text = Fs.readText(readDirPath);
            say("m3", "readText-returned|" + text);
        } catch (error:FsException) {
            report("m3", error);
        }

        try {
            Fs.writeText(regularFile + "/child", "x");
            say("m4", "writeText-returned");
        } catch (error:FsException) {
            report("m4", error);
        }

        try {
            final names = Fs.readDir(permDirPath);
            say("m5", "readDir-returned|" + Std.string(names.length));
        } catch (error:FsException) {
            report("m5", error);
        }
    }

    /**
     * The uncaught path: no catch names std.FsException, so the failure
     * leaves this function as its Result error instead of a panic.
     */
    public static function escaped():String {
        return Fs.readText(missingPath());
    }
}
