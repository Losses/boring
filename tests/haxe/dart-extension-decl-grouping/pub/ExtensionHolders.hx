package pub;

/**
	Two extension-holder classes in one module over the same receiver.

	Every marked extension function of a library shares one extension
	declaration (features/10), and Dart rejects a second extension of the
	same name inside one library, so the Dart emitter must group these
	functions across both classes into one `HolderModeExtension`. Grouping
	per class declared that name twice and failed `dart analyze` with
	duplicate_definition.
**/
@:mainOnly
class ExtensionHolders {
    @:extension
    public static function modeSuffix(mode:HolderMode, suffix:String):String
        return switch (mode) {
            case HolderMode.Hot: "hot" + suffix;
            case HolderMode.Cold: "cold" + suffix;
        };
}

@:mainOnly
class ExtensionHoldersExtra {
    @:extension
    public static function modePrefix(mode:HolderMode, prefix:String):String
        return prefix + switch (mode) {
            case HolderMode.Hot: "hot";
            case HolderMode.Cold: "cold";
        };
}
