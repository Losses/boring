package boring;

/**
 * Switch case block scoping: multiple arms declare the same local name.
 * TypeScript shares scope across switch cases, so each arm that declares
 * locals must be wrapped in a block to avoid redeclaration errors.
 */
enum ToneKind {
    Yinping;
    Yangping;
    Shang;
    Qu;
    Neutral;
    Ru;
}

class SwitchCaseScopeOps {
    /** Multiple cases declare `const row` - needs block scoping. */
    public static function toneRow(kind:ToneKind, n:Int):Int {
        return switch (kind) {
            case Yinping: 0;
            case Yangping:
                const row = n * 2;
                row;
            case Shang:
                const row = n * 3;
                row;
            case Qu:
                const row = n * 4;
                row;
            case Neutral: 0;
            case Ru:
                const row = n * 5;
                row;
        };
    }

    /** Cases declare `const inkTop` and `const inkBottom`. */
    public static function toneInk(kind:ToneKind, inkTop:Float, inkBottom:Float):Float {
        return switch (kind) {
            case Yinping: 0.0;
            case Yangping:
                const top = inkTop;
                const bottom = inkBottom;
                top + bottom;
            case Shang:
                const top = inkTop * 2.0;
                const bottom = inkBottom * 2.0;
                top + bottom;
            case Qu:
                const top = inkTop * 3.0;
                const bottom = inkBottom * 3.0;
                top + bottom;
            case Neutral: 0.0;
            case Ru:
                const top = inkTop * 4.0;
                const bottom = inkBottom * 4.0;
                top + bottom;
        };
    }

    /** Mixed: some cases declare, some don't. */
    public static function mixed(kind:ToneKind, n:Int):Int {
        return switch (kind) {
            case Yinping: 1;
            case Yangping: 2;
            case Shang:
                const tmp = n + 10;
                tmp;
            case Qu:
                const tmp = n + 20;
                tmp;
            case Neutral: 3;
            case Ru:
                const tmp = n + 30;
                tmp;
        };
    }
}
