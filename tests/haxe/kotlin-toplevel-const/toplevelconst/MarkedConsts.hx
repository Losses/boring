package toplevelconst;

/**
    The marked holder of the Kotlin field form (features/10): every
    `static final` here carries `@:topLevel`, so the Kotlin declaration
    leaves the class namespace and emits at file top level as `const val`.
    A Kotlin consumer then imports the constant name itself, which is the
    shape the handwritten engine publishes
    (`org.tiqian.shaping.PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE`).

    `FLOAT_CONST` is written as an Int literal on purpose: a `const val`
    initializer must be a compile-time constant, so the literal has to
    render as a Float literal.
**/
class MarkedConsts {
    @:topLevel
    public static final PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE:String = "PlatformMultiFaceStringDraw";

    @:topLevel
    public static final COVERAGE_ISSUE:String = "UnverifiedDisplaySubstitutionCoverage";

    @:topLevel
    public static final FLOAT_CONST:Float = 16;

    @:topLevel
    static final PRIVATE_CONST:Int = 7;
}
