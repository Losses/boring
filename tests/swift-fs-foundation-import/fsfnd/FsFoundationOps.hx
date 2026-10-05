package fsfnd;

import std.Fs;

/**
 * Minimal std.Fs consumer for the Foundation-import regression
 * (docs/specs/stdlib/17-platform-modules.md). A fallible read and a
 * rename force the host-edge failure classifier (boringFsError) and the
 * rename helper into the generated file, which is where the failure
 * classifier's NSError / NSPOSIXErrorDomain references land. The
 * FoundationEssentials module the pinned Swift 6.2.4 toolchain ships
 * does not export either symbol, so the generated file must also import
 * Foundation.
 */
class FsFoundationOps {
    /** A missing path must surface as std.FsError.notFound, not a compile error. */
    public static function readText(path:String):String {
        return Fs.readText(path);
    }

    /** Rename lowers to boringFsRename, which constructs NSError(domain: NSPOSIXErrorDomain, ...). */
    public static function rename(from:String, to:String):Void {
        Fs.rename(from, to);
    }
}
