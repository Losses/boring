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
    /** Multiple cases declare `final row` - needs block scoping. */
    public static function toneRow(kind:ToneKind, n:Int):Int {
        return switch (kind) {
            case Yinping: 0;
            case Yangping:
                final row = n * 2;
                row;
            case Shang:
                final row = n * 3;
                row;
            case Qu:
                final row = n * 4;
                row;
            case Neutral: 0;
            case Ru:
                final row = n * 5;
                row;
        };
    }

    /** Cases declare `final inkTop` and `final inkBottom`. */
    public static function toneInk(kind:ToneKind, inkTop:Float, inkBottom:Float):Float {
        return switch (kind) {
            case Yinping: 0.0;
            case Yangping:
                final top = inkTop;
                final bottom = inkBottom;
                top + bottom;
            case Shang:
                final top = inkTop * 2.0;
                final bottom = inkBottom * 2.0;
                top + bottom;
            case Qu:
                final top = inkTop * 3.0;
                final bottom = inkBottom * 3.0;
                top + bottom;
            case Neutral: 0.0;
            case Ru:
                final top = inkTop * 4.0;
                final bottom = inkBottom * 4.0;
                top + bottom;
        };
    }

    /** Mixed: some cases declare, some don't. */
    public static function mixed(kind:ToneKind, n:Int):Int {
        return switch (kind) {
            case Yinping: 1;
            case Yangping: 2;
            case Shang:
                final tmp = n + 10;
                tmp;
            case Qu:
                final tmp = n + 20;
                tmp;
            case Neutral: 3;
            case Ru:
                final tmp = n + 30;
                tmp;
        };
    }
}
