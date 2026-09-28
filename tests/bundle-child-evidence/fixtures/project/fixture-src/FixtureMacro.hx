package;

#if macro
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;

/**
 * A compile time macro of the fixture project. Its one call prints to the
 * compiler's standard output, so a successful generation writes a marker on
 * standard output while the deprecated member warning goes to standard
 * error. Both streams are the evidence a successful step must retain.
 *
 * Three optional defines give the focused suite its external filesystem
 * conditions. They are fixture inputs only; the production module reads
 * none of them.
 *
 * - `-D fixture-count=<file>` appends one line, which proves a captured step
 *   executed its command exactly once.
 * - `-D fixture-evidence=<parent>` makes the current run's stream path a
 *   directory before the driver writes it, which forces a capture write
 *   failure after a child that exited zero.
**/
class FixtureMacro {
    public static function note():Void {
        Sys.println("stdout marker from the fixture generation step");
        countStep(Context.definedValue("fixture-count"));
        blockStream(Context.definedValue("fixture-evidence"));
    }

    static function countStep(target:Null<String>):Void {
        if (target == null) {
            return;
        }
        final out = File.append(target);
        out.writeString("ran\n");
        out.close();
    }

    /** Turns this run's standard output path into a directory. */
    static function blockStream(parent:Null<String>):Void {
        if (parent == null) {
            return;
        }
        for (entry in FileSystem.readDirectory(parent)) {
            if (entry.indexOf("run-") != 0) {
                continue;
            }
            final childDirectory = parent + "/" + entry + "/0001";
            if (FileSystem.exists(childDirectory)) {
                FileSystem.createDirectory(childDirectory + "/stdout.bin");
                return;
            }
        }
    }
}
#end
