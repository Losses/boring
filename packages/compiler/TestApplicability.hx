#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

/**
    The target-applicability declaration of a `@:test` function (feature
    spec 19). A test may name the targets it does not apply to through
    the `except` named argument of its `@:test` metadata:

        @:test("description", except = ["swift"])

    The excluded target does not run the test body; it writes a
    `not_applicable` record to its results file instead, so the id stays
    in the cross-target set and the consistency manager counts it as a
    declared exclusion, never a divergence. A test with no `except`
    argument applies to every target.

    The declaration is structural metadata (`MetaAccess.extract`), never
    a name convention. The valid target names are the six results-file
    targets: haxe, ts, kotlin, swift, dart, rust.
**/
class TestApplicability {
    /** The valid target names a test may name in its `except` argument. */
    public static final TARGETS:Array<String> = ["haxe", "ts", "kotlin", "swift", "dart", "rust"];

    /**
        The target names a test excludes, in declaration order, or an
        empty array when the test declares no `except` argument.
    **/
    public static function exceptTargets(field:ClassField):Array<String> {
        final result:Array<String> = [];
        for (entry in field.meta.extract(":test")) {
            if (entry.params == null) {
                continue;
            }
            for (param in entry.params) {
                switch (param.expr) {
                    case EBinop(OpAssign, left, right):
                        switch (left.expr) {
                            case EConst(CIdent(name)):
                                if (name == "except") {
                                    for (item in stringItems(right)) {
                                        result.push(item);
                                    }
                                }
                            case _:
                        }
                    case _:
                }
            }
        }
        return result;
    }

    /** Whether the named target is excluded for this test. */
    public static function isExcluded(field:ClassField, target:String):Bool {
        return exceptTargets(field).indexOf(target) >= 0;
    }

    /**
        Validates the `except` argument of a `@:test` function: every
        name must be a valid target, and no name may repeat. A violation
        stops the compilation at the test's position.
    **/
    public static function validate(field:ClassField):Void {
        final seen = new Map<String, Bool>();
        for (entry in field.meta.extract(":test")) {
            if (entry.params == null) {
                continue;
            }
            for (param in entry.params) {
                switch (param.expr) {
                    case EBinop(OpAssign, left, right):
                        switch (left.expr) {
                            case EConst(CIdent(name)):
                                if (name == "except") {
                                    for (item in stringItems(right)) {
                                        if (TARGETS.indexOf(item) < 0) {
                                            Context.error('Test function ' + field.name + ' names unknown target "' + item
                                                + '" in its except argument; valid targets are ' + TARGETS.join(", "), field.pos);
                                        }
                                        if (seen.exists(item)) {
                                            Context.error('Test function ' + field.name + ' names target "' + item
                                                + '" more than once in its except argument', field.pos);
                                        }
                                        seen.set(item, true);
                                    }
                                }
                            case _:
                        }
                    case _:
                }
            }
        }
    }

    /**
        The string items of an array literal, in order. A non-array or a
        non-string item is a declaration error.
    **/
    static function stringItems(e:Expr):Array<String> {
        final result:Array<String> = [];
        switch (e.expr) {
            case EArrayDecl(items):
                for (item in items) {
                    switch (item.expr) {
                        case EConst(CString(s, _)):
                            result.push(s);
                        case _:
                            Context.error("the except argument of @:test must list string target names", item.pos);
                    }
                }
            case _:
                Context.error("the except argument of @:test must be an array of string target names", e.pos);
        }
        return result;
    }
}
#end
