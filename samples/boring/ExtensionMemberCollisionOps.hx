package boring;

#if dart_output
/**
    Two marked extension functions over one receiver that render one member
    name with different arities. A Dart extension cannot overload a member, so
    the first declaration keeps the extension spelling and the later one stays
    in its declaring class, where its call sites use the class-qualified static
    form. The samples declared each extension member name once.
**/
enum ExtensionCollisionMode {
    Cold;
    Hot;
}

@:mainOnly
class ExtensionCollisionFirst {
    @:extension
    public static function collisionMark(mode:ExtensionCollisionMode):String
        return switch (mode) {
            case ExtensionCollisionMode.Hot: "hot";
            case ExtensionCollisionMode.Cold: "cold";
        };
}

@:mainOnly
class ExtensionCollisionSecond {
    @:extension
    public static function collisionMark(mode:ExtensionCollisionMode, suffix:String):String
        return switch (mode) {
            case ExtensionCollisionMode.Hot: "hot" + suffix;
            case ExtensionCollisionMode.Cold: "cold" + suffix;
        };
}

class ExtensionMemberCollisionOps {
    public static function describe(mode:ExtensionCollisionMode):String
        return ExtensionCollisionFirst.collisionMark(mode) + "/" + ExtensionCollisionSecond.collisionMark(mode, "!");
}
#else
class ExtensionMemberCollisionOps {}
#end
