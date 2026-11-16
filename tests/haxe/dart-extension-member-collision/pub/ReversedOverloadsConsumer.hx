package pub;

import pub.CollisionMode;
import pub.ReversedOverloads.ReversedOverloadsExtra;

/** Calls both declarations of the reversed-order module. */
class ReversedOverloadsConsumer {
    public static function describe(mode:CollisionMode):String {
        return ReversedOverloadsExtra.mark(mode, "!") + "/" + ReversedOverloads.mark(mode);
    }
}
