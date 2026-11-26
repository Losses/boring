package dartcompiler;

/**
    Modules another bundle provides as a Dart package. The dependant skips
    writing them and imports them as package:<pubName>/<library path>.
**/
class PackageDependencies {
    static var entries:Array<{module:String, packageName:String}> = null;

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
            entries.push({module: trimmed.substr(0, tab), packageName: trimmed.substr(tab + 1)});
        }
    }

    public static function packageOf(module:String):Null<String> {
        load();
        for (entry in entries) if (entry.module == module) return entry.packageName;
        return null;
    }
}
