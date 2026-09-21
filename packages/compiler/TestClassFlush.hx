#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import reflaxe.data.ClassFuncData;

/**
    The conventional per-class flush entry of a test class (feature spec
    27). A test class may carry one function named `flushTestTrace` that
    carries no `@:test` marker; the Kotlin runner calls it on the class
    instance once the class's @:test functions returned, so the class
    writes the trace it recorded without the runner naming any consumer
    package or class. The entry registers no test, so the cross-target
    test id set stays unchanged.

    Every test-emitting target accepts the entry. Kotlin renders it
    beside the test functions and calls it; TS, Rust, Swift, and Dart
    drop it, because their runners call one top-level function per
    `@:test` function and hold no class instance to flush.
**/
class TestClassFlush {
    /** The agreed name of the entry; a test class declares it verbatim. */
    public static inline var ENTRY_NAME = "flushTestTrace";

    /**
        Whether `f` is the flush entry of its class. A function carrying
        `@:test` stays an ordinary test even when it shares the name: the
        four shipping consumers that wrote a `@:test flushTestTrace`
        fallback keep their test id, and the runner adds no second call.
    **/
    public static function isEntry(f:ClassFuncData):Bool {
        return f.field.name == ENTRY_NAME && !f.field.meta.has(":test");
    }

    /**
        Validates the shape every target relies on: a public static
        function taking no arguments and returning Void. Each target
        calls this before accepting the entry, so a malformed entry fails
        the compilation on every target, Kotlin included.
    **/
    public static function validate(f:ClassFuncData, className:String):Void {
        final id = "flush entry " + className + "." + ENTRY_NAME;
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
