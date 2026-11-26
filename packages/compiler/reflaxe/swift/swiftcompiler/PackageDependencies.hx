package swiftcompiler;

/**
    Modules another bundle provides as a Swift module. The dependant skips
    writing them and imports the dependency's module; SwiftPM converts
    hyphens in a target name to underscores in the module name.
**/
class PackageDependencies {
    static var entries:Array<{module:String, moduleName:String}> = null;

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
            final moduleName = StringTools.replace(trimmed.substr(tab + 1), "-", "_");
            entries.push({module: trimmed.substr(0, tab), moduleName: moduleName});
        }
    }

    public static function provides(module:String):Bool {
        load();
        for (entry in entries) if (entry.module == module) return true;
        return false;
    }

    /** The distinct dependency module names, sorted for deterministic output. */
    public static function modules():Array<String> {
        load();
        final names = [];
        for (entry in entries) if (names.indexOf(entry.moduleName) < 0) names.push(entry.moduleName);
        names.sort(Reflect.compare);
        return names;
    }
}
