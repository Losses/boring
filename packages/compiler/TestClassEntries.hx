#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import reflaxe.data.ClassFuncData;

/**
    The conventional class test entry (feature spec 19). A class that holds
    ordinary static test functions and carries no `@:test` marker declares
    one public static function named `runTestEntries` that takes no
    arguments and returns Void. The body calls the entry points of that
    class, so a runner reaches entries the `@:test` collection never sees
    while the target names no consumer package and no consumer class.

    The entry registers no test id. The cross-target test id set therefore
    stays unchanged, which is the reason the entry exists: a class the
    `@:test` collection leaves out still runs on a target whose runner is
    generated from that collection, and the work it performs (a trace write,
    a table build) reaches the run.

    Only the Kotlin runner calls the entry. A consumer tree that drives its
    own list (the Haxe reference runner of a translation project) calls the
    entry points itself, and the TS, Rust, Swift, and Dart runners call one
    entry per `@:test` function and hold no class-scoped entry.

    The entry belongs to a class with no `@:test` function. A class that
    carries `@:test` functions already holds a class instance in the Kotlin
    runner and uses the per-class flush entry of feature spec 27 for the
    work that follows its tests.
**/
class TestClassEntries {
    /** The agreed name of the entry; a class declares it verbatim. */
    public static inline var ENTRY_NAME = "runTestEntries";

    /**
        Whether `f` is the class test entry of its class. A function that
        carries `@:test` stays an ordinary test even when it shares the
        name: the class then reaches the runner through the `@:test`
        collection and keeps its test id.
    **/
    public static function isEntry(f:ClassFuncData):Bool {
        return f.field.name == ENTRY_NAME && !f.field.meta.has(":test");
    }

    /**
        Validates the shape the Kotlin runner relies on: a public static
        function taking no arguments and returning Void. A malformed entry
        stops the compilation on every target, because every target types
        the declaration.
    **/
    public static function validate(f:ClassFuncData, className:String):Void {
        final id = "class test entry " + className + "." + ENTRY_NAME;
        if (!f.field.isPublic) {
            Context.error(id + " must be public", f.field.pos);
        }
        if (!f.isStatic) {
            Context.error(id + " must be static", f.field.pos);
        }
        if (f.args.length != 0) {
            Context.error(id + " must take no arguments and return Void", f.field.pos);
        }
        final isVoid = switch (Context.follow(f.ret)) {
            case TAbstract(a, _): a.get().name == "Void";
            case _: false;
        };
        if (!isVoid) {
            Context.error(id + " must take no arguments and return Void", f.field.pos);
        }
    }
}
#end
