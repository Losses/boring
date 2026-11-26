#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
    Package shell configuration shared by every reflaxe target (feature
    spec 24). One compilation emits one source tree per target; this
    module decides whether the tree also carries the ecosystem's package
    manifest and which identity the manifest states. Every field comes
    from a compile-time define: the generator owns what the compilation
    derives (entry paths, the dependency entries the driver declares for
    the bundle, the dialect floor); the consumer's build owns the rest.

    - `package-shell=emit` (or the absent define): write the manifest.
    - `package-shell=none`: source only; the consumer maintains its own
      manifest.
    - `package-name`: the manifest name, default `generated`.
    - `package-artifact-stem`: the artifact file name stem, default the
      manifest name. Registry layouts that keep one package per manifest
      name set this to distinguish precision variants without minting
      new package names.
    - `package-version`: the manifest version, default `0.1.0`.
    - `package-license`: optional; the license field appears only under
      this define.
**/
typedef PackageDependency = {
    name:String,
    version:String,
    path:String,
    group:String,
    swiftUrl:String,
    swiftPath:String
}

class PackageShell {
    /**
        The dependency entries the driver declares for this bundle:
        `-D package-dependency-<id>=<registry name>@<version>`. Sorted by
        name so identical compilations emit identical manifests.
    **/
    public static function dependencyMode():String {
        final value = Context.definedValue("package-dependency-mode");
        return value == null || value == "" ? "registry" : value;
    }

    public static function dependencySpec(dependency:PackageDependency):String {
        return switch (dependencyMode()) {
            case "workspace": "workspace:*";
            case "path": "file:" + dependency.path;
            case _: dependency.version;
        }
    }

    public static function dependencies():Array<PackageDependency> {
        final defines = Context.getDefines();
        final out:Array<PackageDependency> = [];
        for (key in defines.keys()) {
            if (!StringTools.startsWith(key, "package-dependency-")) continue;
            if (key == "package-dependency-mode"
                || StringTools.startsWith(key, "package-dependency-dir-")
                || StringTools.startsWith(key, "package-dependency-path-")
                || StringTools.startsWith(key, "package-dependency-group-")
                || StringTools.startsWith(key, "package-dependency-swift-url-")
                || StringTools.startsWith(key, "package-dependency-swift-path-")) continue;
            final id = key.substr("package-dependency-".length);
            final value = defines.get(key);
            if (value == null) continue;
            final at = value.lastIndexOf("@");
            if (at <= 0 || at == value.length - 1) continue;
            out.push({
                name: value.substring(0, at),
                version: value.substr(at + 1),
                path: defineOr("package-dependency-path-" + id, ""),
                group: defineOr("package-dependency-group-" + id, ""),
                swiftUrl: defineOr("package-dependency-swift-url-" + id, ""),
                swiftPath: defineOr("package-dependency-swift-path-" + id, "")
            });
        }
        out.sort(function(a, b) return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0));
        return out;
    }

    static function defineOr(key:String, fallback:String):String {
        final value = Context.definedValue(key);
        return value == null ? fallback : value;
    }

    /** True when the compilation emits a package manifest. Errors on any value outside emit/none. */
    public static function enabled():Bool {
        SharedModuleTrace.record("PackageShell");
        final value = Context.definedValue("package-shell");
        if (value == null || value == "emit") {
            return true;
        }
        if (value == "none") {
            return false;
        }
        Context.error("package-shell accepts emit or none", Context.currentPos());
        return true;
    }

    /**
        The manifest package name; `generated` when the define is absent.
        The default stays neutral: the compiler assumes no repository or
        package identity of the sources it compiles.
    **/
    public static function name():String {
        SharedModuleTrace.record("PackageShell");
        final value = Context.definedValue("package-name");
        return value == null ? "generated" : value;
    }

    /**
        The install-artifact file name stem (the `.crate`, `.tgz`, and
        `.zip` base before `-<version>`), the manifest name when the
        define is absent. The manifest identity stays `name()`; this
        only names the artifact file a registry distributes.
    **/
    public static function artifactStem():String {
        SharedModuleTrace.record("PackageShell");
        final value = Context.definedValue("package-artifact-stem");
        return value == null ? name() : value;
    }

    /** The manifest version; `0.1.0` when the define is absent. */
    public static function version():String {
        SharedModuleTrace.record("PackageShell");
        final value = Context.definedValue("package-version");
        return value == null ? "0.1.0" : value;
    }

    /** The license line value, or null to omit the field. */
    public static function license():Null<String> {
        SharedModuleTrace.record("PackageShell");
        return Context.definedValue("package-license");
    }

    /**
        The `[[test]]` integration tests and their paths, or null.
        Rust only: the one manifest field that carries repository geometry,
        so it exists solely through this define. Several tests ride in one
        define separated by ";" (`name1:path1;name2:path2`), because Haxe
        dedupes repeated -D keys, so a second -D package-test would
        silently replace the first. (TraitIdentityAdapter)
    **/
    public static function rustTests():Array<{name:String, path:String}> {
        SharedModuleTrace.record("PackageShell");
        final value = Context.definedValue("package-test");
        if (value == null) {
            return [];
        }
        final tests:Array<{name:String, path:String}> = [];
        for (entry in value.split(";")) {
            final separator = entry.indexOf(":");
            if (separator <= 0 || separator + 1 >= entry.length) {
                Context.error("package-test accepts name:path entries separated by ;", Context.currentPos());
                continue;
            }
            tests.push({name: entry.substring(0, separator), path: entry.substring(separator + 1)});
        }
        return tests;
    }
}
#end
