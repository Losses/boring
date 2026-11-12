package boring;

/**
    The variable form of the top-level markers (features/10): a marked
    `static final` leaves its holder's namespace on every target. The static
    function reads the private constant, so every target emits it in use.
**/
class TopLevelConstOps {
    @:topLevel
    public static final PLATFORM_ISSUE:String = "PlatformMultiFaceStringDraw";

    @:topLevel
    static final PRIVATE_LIMIT:Int = 7;

    public static function privateLimitThroughPublic():Int {
        return PRIVATE_LIMIT;
    }
}
