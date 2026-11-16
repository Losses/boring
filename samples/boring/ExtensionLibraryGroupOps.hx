package boring;

#if dart_output
/**
    Two extension-holder classes in one module over the same receiver. A Dart
    library holds one extension declaration per receiver, so the emitter must
    group the marked functions of both classes into that declaration. Grouping
    per class declared the extension name twice and `dart analyze` rejected
    the library with duplicate_definition.
**/
enum ExtensionGroupMode {
    Cold;
    Hot;
}

@:mainOnly
class ExtensionGroupHolders {
    @:extension
    public static function groupSuffix(mode:ExtensionGroupMode, suffix:String):String
        return switch (mode) {
            case ExtensionGroupMode.Hot: "hot" + suffix;
            case ExtensionGroupMode.Cold: "cold" + suffix;
        };
}

@:mainOnly
class ExtensionGroupHoldersExtra {
    @:extension
    public static function groupPrefix(mode:ExtensionGroupMode, prefix:String):String
        return prefix + switch (mode) {
            case ExtensionGroupMode.Hot: "hot";
            case ExtensionGroupMode.Cold: "cold";
        };
}

class ExtensionLibraryGroupOps {
    public static function describe(mode:ExtensionGroupMode):String
        return ExtensionGroupHoldersExtra.groupPrefix(mode, "p:") + "/" + ExtensionGroupHolders.groupSuffix(mode, "!");
}
#else
class ExtensionLibraryGroupOps {}
#end
