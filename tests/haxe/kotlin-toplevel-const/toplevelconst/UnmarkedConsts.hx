package toplevelconst;

/**
    The unmarked control: the same declarations without `@:topLevel` keep
    the holder object and their `const val` members, so the default shape
    stays observable beside the extracted one.
**/
class UnmarkedConsts {
    public static final PLATFORM_MULTI_FACE_STRING_DRAW_ISSUE:String = "PlatformMultiFaceStringDraw";

    public static final COVERAGE_ISSUE:String = "UnverifiedDisplaySubstitutionCoverage";

    public static final FLOAT_CONST:Float = 16;

    static final PRIVATE_CONST:Int = 7;
}
