import haxe.Json;
import haxe.macro.Context;
import sys.FileSystem;
import sys.io.File;

class SemanticExceptionLedger {
    static final path = "packages/compiler/semantic-exceptions.json";

    public static function validate():Void {
        final root = repoRoot();
        final records = readRecords(root);
        final ids = new Map<String, Bool>();
        final pairs = new Map<String, Bool>();
        for (record in records) {
            final id = field(record, "id");
            for (name in ["mechanism", "target", "shape", "reason", "ruling", "fixture"]) {
                field(record, name);
            }
            if (ids.exists(id))
                fail(id, "duplicate id");
            ids.set(id, true);
            final pair = field(record, "mechanism") + "\u0000" + field(record, "target");
            if (pairs.exists(pair))
                fail(id, "duplicate mechanism-target pair");
            pairs.set(pair, true);
            final fixture = field(record, "fixture");
            if (fixture != "none" && !FileSystem.exists(root + "/" + fixture)) {
                fail(id, "fixture path does not exist");
            }
        }
    }

    public static function emitArtifact():Void {
        final root = repoRoot();
        final records = readRecords(root);
        records.sort(function(a, b) return Reflect.field(a, "id") < Reflect.field(b, "id") ? -1 : 1);
        FileSystem.createDirectory(root + "/out");
        File.saveContent(root + "/out/semantic-pass-exceptions.json", Json.stringify({exceptionCount: records.length, records: records}, null, "  ") + "\n");
    }

    /**
        The ledger file ships inside the compiler repository while this macro
        runs from the working directory of whoever invoked the gates. Resolve
        the file through the compiler class path and strip the known suffix;
        the remainder is the repository root for every caller.
    **/
    public static function repoRoot():String {
        final resolved = Context.resolvePath("semantic-exceptions.json");
        if (resolved == path) {
            return ".";
        }
        if (resolved.length > path.length && resolved.substr(resolved.length - path.length - 1) == "/" + path) {
            return resolved.substr(0, resolved.length - path.length - 1);
        }
        Context.error("semantic exception ledger: cannot locate the repository root from " + resolved, Context.currentPos());
        return ".";
    }

    static function readRecords(root:String):Array<Dynamic> {
        try {
            final value:Dynamic = Json.parse(File.getContent(root + "/" + path));
            if (!Std.isOfType(value, Array))
                Context.error("semantic exception ledger: top-level value is not an array", Context.currentPos());
            return cast value;
        } catch (error:Dynamic) {
            Context.error("semantic exception ledger: invalid JSON (" + Std.string(error) + ")", Context.currentPos());
            return [];
        }
    }

    static function field(record:Dynamic, name:String):String {
        final id = Reflect.hasField(record, "id") ? Std.string(Reflect.field(record, "id")) : "<missing-id>";
        if (!Reflect.hasField(record, name)
            || Reflect.field(record, name) == null
            || Std.string(Reflect.field(record, name)).length == 0) {
            fail(id, "missing or empty " + name);
        }
        return Std.string(Reflect.field(record, name));
    }

    static function fail(id:String, violation:String):Void {
        Context.error("semantic exception ledger " + id + ": " + violation, Context.currentPos());
    }
}
