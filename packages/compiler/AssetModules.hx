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
    public static final CHUNK_BYTES:Int = 512 * 1024;

    // Modules marked as asset during this compile (metadata or name registry).
    static var active:Map<String, Bool> = new Map();

    // Per-module ordinal, per-module content -> filename dedup, and the
    // pending writes flushed by the target's output pass.
    static var counters:Map<String, Int> = new Map();
    static var namesByContent:Map<String, Map<String, Array<String>>> = new Map();
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
        Registers a literal and returns the include_str!-ready part filenames
        that sit in the same directory as the generated module file. A literal
        of at least CHUNK_BYTES UTF-8 bytes is split into multiple parts, each
        comfortably under the 1.0 MiB snapshot ceiling; smaller literals keep a
        single file. The same content within one module reuses the same part
        list, so a literal rendered more than once still names one asset set.
    **/
    public static function externalize(module:String, content:String):Array<String> {
        var byContent = namesByContent.get(module);
        if (byContent == null) {
            byContent = new Map();
            namesByContent.set(module, byContent);
        }
        var parts = byContent.get(content);
        if (parts == null) {
            final n = counters.exists(module) ? counters.get(module) : 0;
            counters.set(module, n + 1);
            final base = moduleLeaf(module) + "__asset_" + n;
            final chunks = splitChunks(content);
            parts = [];
            if (chunks.length == 1) {
                final file = base + ".txt";
                parts.push(file);
                pending.push({module: module, file: file, content: chunks[0]});
            } else {
                for (k in 0...chunks.length) {
                    final file = base + ".part_" + k + ".txt";
                    parts.push(file);
                    pending.push({module: module, file: file, content: chunks[k]});
                }
            }
            byContent.set(content, parts);
        }
        return parts;
    }

    /**
        Splits content into parts whose UTF-8 byte size each stays at or
        under CHUNK_BYTES. Surrogate pairs are never split, so concatenating
        the parts reproduces the original bytes exactly.
    **/
    static function splitChunks(content:String):Array<String> {
        if (byteLength(content) <= CHUNK_BYTES)
            return [content];
        final parts:Array<String> = [];
        final len = content.length;
        var start = 0;
        while (start < len) {
            var end = start;
            var bytes = 0;
            while (end < len) {
                final c = content.charCodeAt(end);
                var add = 0;
                var units = 1;
                if (c >= 0xD800 && c <= 0xDBFF && end + 1 < len) {
                    final c2 = content.charCodeAt(end + 1);
                    if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
                        add = 4;
                        units = 2;
                    } else {
                        add = 3;
                    }
                } else if (c < 0x80) {
                    add = 1;
                } else if (c < 0x800) {
                    add = 2;
                } else {
                    add = 3;
                }
                if (end > start && bytes + add > CHUNK_BYTES)
                    break;
                bytes += add;
                end += units;
            }
            parts.push(content.substr(start, end - start));
            start = end;
        }
        return parts;
    }

    static function byteLength(s:String):Int {
        return haxe.io.Bytes.ofString(s).length;
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

