#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;

/** Shared structural dispatch for assignment targets. Renderers retain target-specific syntax and policy. */
enum AssignTargetFieldKind {
    Instance(owner:Ref<ClassType>, field:Ref<ClassField>);
    Anonymous(field:Ref<ClassField>);
}

class AssignTargetPlan {
    /**
        Owned-conversion suffixes a rendered target must never carry. Each
        one marks the text as a fresh value produced by a conversion the
        emitter decided at the wrong granularity: the assignment would land
        in that fresh value and be dropped while the product still compiles
        and value tests stay green (the silent lost-write class).
        (DegradedLvalueGuard)
    **/
    public static final lvalueConversionSuffixes:Array<String> = [
        ".clone()", ".to_string()", ".to_vec()", ".to_owned()", ".toOwned()",
        ".unwrap()", ".unwrap_or_default()", ".slice()", ".copy()",
        ".toList()", ".toMutableList()", ".toUString()"
    ];

    /**
        Wrapper calls that convert the whole referent into a fresh value:
        writing through the wrapped text writes into the temporary.
        (DegradedLvalueGuard)
    **/
    public static final lvalueConversionWrappers:Array<String> = [
        "Array.from(", "toMutableList(", "toList(", "List.from("
    ];

    public static function assignTarget(e:TypedExpr,
            renderArray:(TypedExpr, TypedExpr)->String,
            renderStatic:(TypedExpr)->String,
            renderInstance:(TypedExpr, AssignTargetFieldKind, TypedExpr)->String,
            renderLocal:TVar->String,
            fail:(TypedExpr, String)->String):String {
        final text = switch (e.expr) {
            case TArray(arr, idx): renderArray(arr, idx);
            case TField(_, FStatic(_, _)): renderStatic(e);
            case TField(subj, FInstance(owner, _, field)):
                renderInstance(subj, Instance(owner, field), e);
            case TField(subj, FAnon(field)):
                renderInstance(subj, Anonymous(field), e);
            case TLocal(v): renderLocal(v);
            case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner):
                assignTarget(inner, renderArray, renderStatic, renderInstance, renderLocal, fail);
            case _: fail(e, "assignment target has no lowering");
        };
        return assertLvalueSite(e, text);
    }

    /**
        The assignment-target boundary is an lvalue site. A degradation
        decision made on the rendered shape only loses the write silently
        when the conversion is the place-path's value-producing step: the
        write would land in the fresh value instead of the original slot.
        A conversion that only feeds a place path is legitimate: Rust's
        interior mutability reads *`x.lock().unwrap()` and *`c.borrow_mut()` write
        through, so the guard masks those readers and only refuses a
        place-terminal or mid-path conversion that no top-level deref
        rescues, with the site position. (DegradedLvalueGuard)
    **/

    /**
        Interior-mutability and lock readers produce a place (a guard
        that deref-coerces), so they never make the target a fresh value
        and are masked before the conversion check.
    **/
    public static final placePathReaders:Array<String> = [
        "lock().unwrap()", "try_lock().unwrap()",
        "borrow().unwrap()", "borrow_mut().unwrap()",
        "borrow()", "borrow_mut()"
    ];

    /**
        Returns the conversion suffix found at a place-path terminal or
        mid-path position (a lost-write shape), or null when the target
        is a plain place. Pure text predicate so it is probeable without
        a TypedExpr. (DegradedLvalueGuard)
    **/
    public static function lvalueConversionHit(text:String):Null<String> {
        var masked = text;
        for (reader in placePathReaders)
            masked = StringTools.replace(masked, reader, "\x01");
        final derefed = StringTools.startsWith(masked, "*");
        for (suffix in lvalueConversionSuffixes) {
            var at = masked.indexOf(suffix);
            while (at >= 0) {
                if (at + suffix.length == masked.length) {
                    if (!derefed)
                        return suffix;
                } else {
                    final next = masked.charCodeAt(at + suffix.length);
                    if (next == ".".code || next == "[".code)
                        return suffix;
                }
                final next2 = masked.indexOf(suffix, at + 1);
                if (next2 <= at) break;
                at = next2;
            }
        }
        for (wrapper in lvalueConversionWrappers) {
            if (topLevelWrapped(masked, wrapper) && !derefed)
                return wrapper;
        }
        return null;
    }

    /** Reports a degraded lvalue at generation time. (DegradedLvalueGuard) */
    public static function assertLvalueSite(e:TypedExpr, text:String):String {
        final hit = lvalueConversionHit(text);
        if (hit != null)
            Context.error("assignment target carries a place-terminal conversion ("
                + hit + "); the write would land on the converted temporary and be silently dropped", e.pos);
        return text;
    }

    /** True when text opens with prefix and its matching close is the last character. */
    static function topLevelWrapped(text:String, prefix:String):Bool {
        if (!StringTools.startsWith(text, prefix) || text.length <= prefix.length)
            return false;
        if (text.charCodeAt(text.length - 1) != ")".code)
            return false;
        var depth = 0;
        for (i in (prefix.length - 1)...text.length) {
            final c = text.charCodeAt(i);
            if (c == "(".code) depth++;
            else if (c == ")".code) {
                depth--;
                if (depth == 0)
                    return i == text.length - 1;
            }
        }
        return false;
    }
}
#end