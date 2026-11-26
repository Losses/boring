package rustcompiler;

/**
    Modules another bundle provides as a crate. The dependant skips writing
    them and imports them through the dependency's crate path; the driver
    writes <module> TAB <package name> for each declared dependsOn tree.
**/
class PackageDependencies {
    static var entries:Array<{module:String, crateName:String}> = null;

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
            final crateName = StringTools.replace(trimmed.substr(tab + 1), "-", "_");
            entries.push({module: trimmed.substr(0, tab), crateName: crateName});
        }
    }

    public static function crateOf(module:String):Null<String> {
        load();
        for (entry in entries) if (entry.module == module) return entry.crateName;
        return null;
    }
}
