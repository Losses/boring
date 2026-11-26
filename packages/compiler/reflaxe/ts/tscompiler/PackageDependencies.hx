package tscompiler;

/**
    Modules another bundle provides as a package: the dependant skips
    writing them and imports them by package specifier. The driver writes
    <module> TAB <package name> for every module the declared
    bundle dependsOn tree provides.
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

    /** The package specifier for a provided module, or null when local. **/
    public static function specifier(module:String):Null<String> {
        final packageName = packageOf(module);
        if (packageName == null) return null;
        return packageName + "/" + module.split(".").join("/");
    }
}
