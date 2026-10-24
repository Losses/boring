#if (macro || reflaxe_runtime)

import haxe.macro.Type;

/**
    Asset-module registry (Emit-Assets): modules whose data content is emitted
    as a data file instead of target-language string literals.

    Marking priority: an explicit @:asset metadata on a class wins over the
    v1 name registry, which lists the macro-generated golden-data holder
    classes (org.tiqian.layout.*) so v1 needs no tiqian-side change. A later
    tiqian task can add @:asset to those classes; registerClass already reads
    the metadata first, so it takes over without touching this file.

    The Rust backend externalizes a large string literal by writing its raw
    bytes to a file beside the generated module and rendering include_str! of
    that file. Other backends consume the same registry with their own native
    resource read.
**/
class AssetModules {
    /** v1 name registry: full module name -> asset namespace label. */
    static final NAME_REGISTRY:Map<String, String> = [
        "org.tiqian.layout.LayoutDumpGoldens" => "layout-dumps",
        "org.tiqian.layout.RecordedLayoutDumpGoldens" => "layout-dumps-recorded",
        "org.tiqian.layout.RecordedShapingEvidenceData" => "shaping-evidence"
    ];

    /** Literals of at least this many UTF-16 code units are externalized. */
    public static final EXTERNALIZE_THRESHOLD:Int = 256;

    // Modules marked as asset during this compile (metadata or name registry).
    static var active:Map<String, Bool> = new Map();

    // Per-module ordinal, per-module content -> filename dedup, and the
    // pending writes flushed by the target's output pass.
    static var counters:Map<String, Int> = new Map();
    static var namesByContent:Map<String, Map<String, String>> = new Map();
    static var pending:Array<{module:String, file:String, content:String}> = [];

    /** True when the class is an asset module: metadata first, name registry fallback. */
    public static function isAssetClass(cls:ClassType):Bool {
        if (cls.meta.has(":asset")) {
            return true;
        }
        return NAME_REGISTRY.exists(cls.module);
    }

    /** Registers a class as an asset module when marked (metadata or registry). */
    public static function registerClass(cls:ClassType):Void {
        if (isAssetClass(cls)) {
            active.set(cls.module, true);
        }
    }

    public static function isAssetModule(module:String):Bool {
        return active.exists(module);
    }

    /** True when this module's literal is large enough to externalize. */
    public static function shouldExternalize(module:String, content:String):Bool {
        return isAssetModule(module) && content.length >= EXTERNALIZE_THRESHOLD;
    }

    /**
        Registers a literal and returns the include_str!-ready filename that
        sits in the same directory as the generated module file. The same
        content within one module reuses one file, so a literal rendered more
        than once still names one asset.
    **/
    public static function externalize(module:String, content:String):String {
        var byContent = namesByContent.get(module);
        if (byContent == null) {
            byContent = new Map();
            namesByContent.set(module, byContent);
        }
        var name = byContent.get(content);
        if (name == null) {
            final n = counters.exists(module) ? counters.get(module) : 0;
            counters.set(module, n + 1);
            name = moduleLeaf(module) + "__asset_" + n + ".txt";
            byContent.set(content, name);
            pending.push({module: module, file: name, content: content});
        }
        return name;
    }

    /** All pending asset writes, in registration order. */
    public static function pendingAssets():Array<{module:String, file:String, content:String}> {
        return pending;
    }

    static function moduleLeaf(module:String):String {
        final idx = module.lastIndexOf(".");
        return idx < 0 ? module : module.substr(idx + 1);
    }

    /** Clears all per-run state. */
    public static function reset():Void {
        active = new Map();
        counters = new Map();
        namesByContent = new Map();
        pending = [];
    }
}

#end

