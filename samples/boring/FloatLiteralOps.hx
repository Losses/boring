package boring;

/**
 * Float-literal edge cases for targets that require an integer part on
 * every numeric literal (Rust). The source uses Haxe's `.NNN` form, which
 * the AST carries verbatim; each target's printer must emit `0.NNN`.
 */
class FloatLiteralOps {
    /** Function-argument position: `.001` arrives as a call argument. */
    public static function argLeadingDot():Float {
        return .001;
    }

    /** Local-initializer position: `-.1` arrives as an initializer. */
    public static function localLeadingDotNeg():Float {
        var f = -.1;
        return f;
    }

    /** Small-magnitude literal in function-argument position. */
    public static function argSmall():Float {
        return .25;
    }

    /** Negative small-magnitude literal in local-initializer position. */
    public static function localSmallNeg():Float {
        var f = -.5;
        return f;
    }
}
