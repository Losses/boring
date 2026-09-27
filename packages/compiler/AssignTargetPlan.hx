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
        The assignment-target boundary is an lvalue site. A target whose
        rendered text still carries an owned-conversion suffix or a
        whole-value wrapper is a degradation decision made on the rendered
        shape instead of the site; the write would land on a temporary and
        be silently dropped. The site does not degrade silently: refuse the
        generation here with the site position. (DegradedLvalueGuard)
    **/
    public static function assertLvalueSite(e:TypedExpr, text:String):String {
        for (suffix in lvalueConversionSuffixes) {
            if (StringTools.endsWith(text, suffix))
                Context.error("assignment target renders with an owned conversion suffix ("
                    + suffix + "); the write would land on a temporary and be silently dropped", e.pos);
        }
        for (wrapper in lvalueConversionWrappers) {
            if (topLevelWrapped(text, wrapper))
                Context.error("assignment target is wrapped by a fresh-value conversion ("
                    + wrapper + " ...); the write would land on the temporary and be silently dropped", e.pos);
        }
        return text;
    }

    /** True when text opens with prefix and its matching close is the last character. */
    static function topLevelWrapped(text:String, prefix:String):Bool {
        if (!StringTools.startsWith(text, prefix) || text.length <= prefix.length)
            return false;
        if (text.charCodeAt(text.length - 1) != ")".code)
            return false;
        var depth = 0;
        final open = prefix.charCodeAt(prefix.length - 1);
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
