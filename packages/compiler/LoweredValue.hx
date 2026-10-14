package;

#if (macro || reflaxe_runtime)

/**
    Whether a lowered Kotlin expression carries a nullable target type.
    Written by the same line that renders `.` / `?.` / `!!.`, so the
    coerce layer reads one authoritative fact instead of re-inferring
    from text.
**/
enum Presence {
    /** Renders to a non-null target expression. */
    Present;
    /** Renders to a nullable target expression (null may flow at runtime). */
    MaybeAbsent;
    /** Renders to an explicit null literal. */
    NullLiteral;
    /** Lowering cannot produce a value here (unreachable code). */
    Unreachable;
}

/**
    A lowered value: the rendered target text plus the facts every consumer
    needs to place it correctly (storage shape, nullability, error domain,
    unit, origin). See arch-review-claude.md §3.2 for the full design.
**/
typedef Lowered = {
    var text:String;
    var storage:Null<String>;
    var presence:Presence;
    var errorDomain:Null<String>;
    var unit:Null<String>;
    var origin:Null<String>;
    @:optional var pos:Null<haxe.macro.Expr.Position>;
}
#end

