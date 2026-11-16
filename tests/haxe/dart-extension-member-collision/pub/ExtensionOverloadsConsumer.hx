package pub;

import pub.CollisionMode;
import pub.ExtensionOverloads.ExtensionOverloadsExtra;

/** Calls both colliding declarations with their Haxe static spelling. */
class ExtensionOverloadsConsumer {
    public static function describe(mode:CollisionMode):String {
        return ExtensionOverloads.mark(mode) + "/" + ExtensionOverloadsExtra.mark(mode, "!");
    }
}
