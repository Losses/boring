package pub;

import pub.CollisionMode;

/**
	The same two colliding declarations in the opposite source order: the
	class named Extra declares first, the class named ReversedOverloads
	declares second. The fallback follows the declaration order, so the
	second declaration (the plain name) stays in the class and the first one
	keeps the extension spelling.
**/
@:mainOnly
class ReversedOverloadsExtra {
    @:extension
    public static function mark(mode:CollisionMode, suffix:String):String
        return switch (mode) {
            case CollisionMode.Hot: "hot" + suffix;
            case CollisionMode.Cold: "cold" + suffix;
        };
}

@:mainOnly
class ReversedOverloads {
    @:extension
    public static function mark(mode:CollisionMode):String
        return switch (mode) {
            case CollisionMode.Hot: "hot";
            case CollisionMode.Cold: "cold";
        };
}
