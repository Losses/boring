#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
    Package shell configuration shared by every reflaxe target (feature
    spec 24). One compilation emits one source tree per target; this
    module decides whether the tree also carries the ecosystem's package
    manifest and which identity the manifest states. Every field comes
    from a compile-time define: the generator owns what the compilation
    derives (entry paths, the empty dependency set, the dialect floor),
    and the consumer's build owns everything else.

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
class PackageShell {
    /** True when the compilation emits a package manifest. Errors on any value outside emit/none. */
    public static function enabled():Bool {
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
        final value = Context.definedValue("package-artifact-stem");
        return value == null ? name() : value;
    }

    /** The manifest version; `0.1.0` when the define is absent. */
    public static function version():String {
        final value = Context.definedValue("package-version");
        return value == null ? "0.1.0" : value;
    }

    /** The license line value, or null to omit the field. */
    public static function license():Null<String> {
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
