package kotlincompiler;

/**
    Modules another bundle provides as a Kotlin package. The dependant skips
    writing them; Kotlin resolves the declarations from the dependency
    artifact on the compile classpath by package path.
**/
class PackageDependencies {
    static var entries:Array<String> = null;

    public static function load():Void {
        if (entries != null) return;
        entries = [];
        final path = haxe.macro.Context.definedValue("package-dependency-file");
        if (path == null || path == "") return;
        if (!sys.FileSystem.exists(path)) return;
        for (line in sys.io.File.getContent(path).split("\n")) {
            final trimmed = StringTools.trim(line);
            if (trimmed == "") continue;
            final tab = trimmed.indexOf("\t");
            if (tab < 0) continue;
            entries.push(trimmed.substr(0, tab));
        }
    }

    public static function provides(module:String):Bool {
        load();
        return entries.indexOf(module) >= 0;
    }
}
