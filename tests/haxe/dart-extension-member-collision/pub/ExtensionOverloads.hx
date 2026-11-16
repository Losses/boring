package pub;

import pub.CollisionMode;

/**
	Two marked extension functions over the same receiver with one rendered
	member name. A Dart extension cannot overload a member, so the first
	declaration keeps the extension spelling and the later one stays in its
	declaring class; its call sites use the class-qualified static form.
**/
@:mainOnly
class ExtensionOverloads {
    @:extension
    public static function mark(mode:CollisionMode):String
        return switch (mode) {
            case CollisionMode.Hot: "hot";
            case CollisionMode.Cold: "cold";
        };
}

@:mainOnly
class ExtensionOverloadsExtra {
    @:extension
    public static function mark(mode:CollisionMode, suffix:String):String
        return switch (mode) {
            case CollisionMode.Hot: "hot" + suffix;
            case CollisionMode.Cold: "cold" + suffix;
        };
}
