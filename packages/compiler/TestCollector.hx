#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import sys.FileSystem;
import sys.io.File;

/**
 * Macro collector for in-source @:test declarations across the reference tree
 * (docs/specs/features/19-testing.md).
 *
 * Scans all modules under the guarded test directories, verifies compile-time
 * requirements for test functions (public static, no arguments, returns Void),
 * and generates the runner main under out/haxe/TestMain.hx.
 */
class TestCollector {
    /**
        Escapes a runner name for embedding inside a double-quoted string
        literal in generated source.
    **/
    static function escapeName(s:String):String {
        final buf = new StringBuf();
        for (i in 0...s.length) {
            final c = s.charAt(i);
            if (c == '"')
                buf.add('\\"');
            else if (c == "\\")
                buf.add("\\\\");
            else if (c == "\n")
                buf.add("\\n");
            else if (c == "\r")
                buf.add("\\r");
            else if (c == "\t")
                buf.add("\\t");
            else
                buf.add(c);
        }
        return buf.toString();
    }

    public static function generate(outDir:String = "out/haxe"):Void {
        final tests:Array<{
            id:String,
            name:String,
            moduleName:String,
            className:String,
            fieldName:String
        }> = [];

        final testDir = "samples/tests";
        if (FileSystem.exists(testDir) && FileSystem.isDirectory(testDir)) {
            final files = FileSystem.readDirectory(testDir);
            files.sort(Reflect.compare);
            for (file in files) {
                if (!StringTools.endsWith(file, ".hx")) {
                    continue;
                }
                final baseName = file.substr(0, file.length - 3);
                final moduleName = "tests." + baseName;
                final types = try {
                    Context.getModule(moduleName);
                } catch (e:Dynamic) {
                    continue;
                }

                for (t in types) {
                    switch (t) {
                        case TInst(c, _):
                            final cls = c.get();
                            final statics = cls.statics.get().copy();
                            statics.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));

                            for (field in statics) {
                                if (!field.meta.has(":test")) {
                                    continue;
                                }
                                final id = cls.module + "." + field.name;

                                // Validate public static Void -> Void.
                                // Match the declared signature directly: Context.follow during
                                // the --macro phase forces lazy completion of modules with
                                // @:build or static self-referencing initializers and corrupts
                                // the typer cache (Haxe 4.3.7), so follow is not used here.
                                if (!field.isPublic) {
                                    Context.error("Test function " + id + " must be public", field.pos);
                                }

                                final ftype = field.type;
                                switch (ftype) {
                                    case TFun(args, ret):
                                        var isVoid = switch (ret) {
                                            case TAbstract(a, _): a.get().name == "Void";
                                            case _: false;
                                        };
                                        if (args.length != 0 || !isVoid) {
                                            Context.error("Test function " + id + " must take no arguments and return Void", field.pos);
                                        }
                                    case TLazy(l):
                                        switch (l()) {
                                            case TFun(args, ret):
                                                var isVoid = switch (ret) {
                                                    case TAbstract(a, _): a.get().name == "Void";
                                                    case _: false;
                                                };
                                                if (args.length != 0 || !isVoid) {
                                                    Context.error("Test function " + id + " must take no arguments and return Void", field.pos);
                                                }
                                            case _:
                                                Context.error("Test function " + id + " must be a function", field.pos);
                                        }
                                    case _:
                                        Context.error("Test function " + id + " must be a function", field.pos);
                                }

                                var desc:Null<String> = null;
                                for (entry in field.meta.extract(":test")) {
                                    if (entry.params != null && entry.params.length > 0) {
                                        switch (entry.params[0].expr) {
                                            case EConst(CString(sv)): desc = sv;
                                            case _:
                                        }
                                    }
                                }

                                final runnerName = desc != null ? id + ": " + desc : id;
                                tests.push({
                                    id: id,
                                    name: runnerName,
                                    moduleName: cls.module,
                                    className: cls.name,
                                    fieldName: field.name
                                });
                            }
                        case _:
                    }
                }
            }
        }

        if (!FileSystem.exists(outDir)) {
            FileSystem.createDirectory(outDir);
        }

        final testCallLines:Array<String> = [];
        for (t in tests) {
            testCallLines.push('        try {');
            testCallLines.push('            std.Test.run("' + t.id + '", "' + escapeName(t.name) + '", function() { ' + t.moduleName + '.' + t.fieldName
                + '(); });');
            testCallLines.push('        } catch (e:haxe.Exception) {');
            testCallLines.push('            failures++;');
            testCallLines.push('            std.Console.log(e.message);');
            testCallLines.push('        } catch (e:Dynamic) {');
            testCallLines.push('            failures++;');
            testCallLines.push('            std.Console.log(Std.string(e));');
            testCallLines.push('        }');
        }

        final runnerSource = 'package;

import runtime.Graphemes;
import runtime.SortedTable;
import runtime.TestCore;
import runtime.UString;
import std.UStringException;
import std.UStringFault;

@:jsRequire("node:fs")
extern class Fs {
    static function appendFileSync(path:String, data:String, encoding:String):Void;
    static function mkdirSync(path:String, options:{recursive:Bool}):Void;
    static function existsSync(path:String):Bool;
}

@:jsRequire("node:path")
extern class Path {
    static function dirname(p:String):String;
}

@:jsRequire("node:process")
extern class NodeProcess {
    static final env:haxe.DynamicAccess<String>;
}

class TestMain {
    static var failures:Int = 0;

    static function recordResult(id:String, name:String, verdict:String, message:Null<String>):Void {
        var envPath = NodeProcess.env.get("BORING_TEST_RESULTS");
        var filePath = envPath != null && envPath.length > 0 ? envPath : "out/test-results/haxe.jsonl";
        var jsonLine = TestCore.resultLine(id, name, verdict == "fail", message != null ? message : "");
        var dir = Path.dirname(filePath);
        if (dir != null && dir != "" && dir != ".") {
            try {
                Fs.mkdirSync(dir, {recursive: true});
            } catch (_:Dynamic) {}
        }
        Fs.appendFileSync(filePath, jsonLine, "utf8");
    }

    static function formatValue(v:Dynamic):String {
        if (v == null) return "null";
        if (Std.isOfType(v, Bool)) return TestCore.formatBool(v);
        if (Std.isOfType(v, Int)) return TestCore.formatInt(v);
        if (Std.isOfType(v, Float)) return TestCore.formatFloat(v);
        if (Std.isOfType(v, String)) {
            return \'"\' + TestCore.escapeJson(v) + \'"\';
        }
        if (Std.isOfType(v, haxe.io.Bytes)) {
            return TestCore.formatBytes(cast v);
        }
        if (Std.isOfType(v, Array)) {
            var arr:Array<Dynamic> = cast v;
            var parts = [for (elem in arr) formatValue(elem)];
            return "[" + parts.join(", ") + "]";
        }
        if (Type.getEnum(v) != null) {
            var enumName = Type.enumConstructor(v);
            var params = Type.enumParameters(v);
            if (params == null || params.length == 0) {
                return enumName;
            } else {
                var parts = [for (p in params) formatValue(p)];
                return enumName + "(" + parts.join(", ") + ")";
            }
        }
        var fields = Reflect.fields(v);
        if (fields != null) {
            var parts = [for (f in fields) f + ": " + formatValue(Reflect.field(v, f))];
            return "{" + parts.join(", ") + "}";
        }
        return Std.string(v);
    }

    static function deepEquals(a:Dynamic, b:Dynamic):Bool {
        if (a == null && b == null) return true;
        if (a == null || b == null) return false;
        if (Std.isOfType(a, Bool) && Std.isOfType(b, Bool)) return a == b;
        if (Std.isOfType(a, Int) && Std.isOfType(b, Int)) return a == b;
        if (Std.isOfType(a, Float) && Std.isOfType(b, Float)) {
            if (Math.isNaN(a) || Math.isNaN(b)) return false;
            return a == b;
        }
        if (Std.isOfType(a, String) && Std.isOfType(b, String)) return a == b;
        if (Std.isOfType(a, haxe.io.Bytes) && Std.isOfType(b, haxe.io.Bytes)) {
            var ba:haxe.io.Bytes = cast a;
            var bb:haxe.io.Bytes = cast b;
            if (ba.length != bb.length) return false;
            for (i in 0...ba.length) {
                if (ba.get(i) != bb.get(i)) return false;
            }
            return true;
        }
        if (Std.isOfType(a, Array) && Std.isOfType(b, Array)) {
            var aa:Array<Dynamic> = cast a;
            var ab:Array<Dynamic> = cast b;
            if (aa.length != ab.length) return false;
            for (i in 0...aa.length) {
                if (!deepEquals(aa[i], ab[i])) return false;
            }
            return true;
        }
        if (Type.getEnum(a) != null && Type.getEnum(b) != null) {
            if (Type.getEnum(a) != Type.getEnum(b)) return false;
            if (Type.enumConstructor(a) != Type.enumConstructor(b)) return false;
            var pa = Type.enumParameters(a);
            var pb = Type.enumParameters(b);
            if (pa.length != pb.length) return false;
            for (i in 0...pa.length) {
                if (!deepEquals(pa[i], pb[i])) return false;
            }
            return true;
        }
        var fa = Reflect.fields(a);
        var fb = Reflect.fields(b);
        if (fa != null && fb != null) {
            if (fa.length != fb.length) return false;
            for (f in fa) {
                if (!Reflect.hasField(b, f)) return false;
                if (!deepEquals(Reflect.field(a, f), Reflect.field(b, f))) return false;
            }
            return true;
        }
        return a == b;
    }

    static function bootstrap():Void {
        var testObj = {
            run: function(id:String, name:String, body:()->Void):Void {
                TestPlatform.currentId = id;
                try {
                    body();
                    TestPlatform.currentId = null;
                    recordResult(id, name, "pass", null);
                } catch (e:haxe.Exception) {
                    TestPlatform.currentId = null;
                    recordResult(id, name, "fail", e.message);
                    throw e;
                } catch (e:Dynamic) {
                    TestPlatform.currentId = null;
                    var msg = Std.string(e);
                    recordResult(id, name, "fail", msg);
                    throw new haxe.Exception(msg);
                }
            },
            ok: function(condition:Bool, message:Null<String> = null):Void {
                TestCore.ok(condition, message != null ? message : "");
            },
            equals: function(expected:Dynamic, actual:Dynamic, message:Null<String> = null):Void {
                if (!deepEquals(expected, actual)) {
                    TestCore.reportFailure(message != null ? message : "", formatValue(expected), formatValue(actual));
                }
            },
            fail: function(message:String):Void {
                TestCore.fail(message);
            }
        };
        js.Syntax.code("globalThis.__test_shim = {0}", testObj);
        js.Syntax.code("globalThis.FunctionalOracle = {0}", FunctionalOracle);
        js.Syntax.code("globalThis.std = globalThis.std || {}; globalThis.std.StringBuf = {0};", StringBufOracle);
        js.Syntax.code("globalThis.std.UStringRT = {0};", UString);
        js.Syntax.code("globalThis.std.UStringPlatform = {0};", UStringPlatform);
        js.Syntax.code("globalThis.std.Graphemes = {0};", Graphemes);
        js.Syntax.code("globalThis.std.TestPlatform = {0};", TestPlatform);
        js.Syntax.code("globalThis.__runtime_sorted_table = {0};", SortedTable);
        js.Syntax.code("
            function jsCompare(a, b) {
                if (a === b) return 0;
                let ta = typeof a;
                let tb = typeof b;
                if (ta === \\\"number\\\" && tb === \\\"number\\\") {
                    return a - b;
                }
                if (ta === \\\"string\\\" && tb === \\\"string\\\") {
                    return a < b ? -1 : (a > b ? 1 : 0);
                }
                if (ta === \\\"boolean\\\" && tb === \\\"boolean\\\") {
                    return a === b ? 0 : (a ? 1 : -1);
                }
                if (ta === \\\"object\\\" && tb === \\\"object\\\" && a !== null && b !== null) {
                    // Spec 16 orders enum values by constructor
                    // declaration order, which the haxe JS runtime
                    // stores as _hx_index. The member walk below
                    // would order them by _hx_name instead, an
                    // accident of key insertion order.
                    if (typeof a.__enum__ === \\\"string\\\" && typeof b.__enum__ === \\\"string\\\" && a.__enum__ === b.__enum__ && a._hx_index !== b._hx_index) {
                        return a._hx_index - b._hx_index;
                    }
                    let keysA = Object.keys(a);
                    for (let i = 0; i < keysA.length; i++) {
                        let k = keysA[i];
                        let cmp = jsCompare(a[k], b[k]);
                        if (cmp !== 0) return cmp;
                    }
                    return 0;
                }
                return 0;
            }
            class JsFunctional {
                static forEach(arr, fn) {
                    for (let i = 0; i < arr.length; i++) {
                        fn(arr[i]);
                    }
                }
                static associate(arr, fn) {
                    let builder = globalThis.std.SortedMap.builder();
                    for (let i = 0; i < arr.length; i++) {
                        let entry = fn(arr[i]);
                        builder.put(entry.key, entry.value);
                    }
                    return builder.build();
                }
                static sortedBy(arr, keyFn) {
                    let copy = arr.slice();
                    let indexed = [];
                    for (let i = 0; i < copy.length; i++) {
                        indexed.push({item: copy[i], key: keyFn(copy[i]), idx: i});
                    }
                    indexed.sort((a, b) => {
                        let cmp = jsCompare(a.key, b.key);
                        return cmp !== 0 ? cmp : a.idx - b.idx;
                    });
                    let result = [];
                    for (let i = 0; i < indexed.length; i++) {
                        result.push(indexed[i].item);
                    }
                    return result;
                }
                static mapNotNull(arr, fn) {
                    let result = [];
                    for (let i = 0; i < arr.length; i++) {
                        let v = fn(arr[i]);
                        if (v !== null && v !== undefined) {
                            result.push(v);
                        }
                    }
                    return result;
                }
                static groupBy(arr, fn) {
                    let builder = globalThis.std.SortedMap.builder();
                    for (let i = 0; i < arr.length; i++) {
                        let entry = fn(arr[i]);
                        let bucket = builder.get(entry.key);
                        if (bucket === null) {
                            bucket = [];
                            builder.put(entry.key, bucket);
                        }
                        bucket.push(entry.value);
                    }
                    return builder.build();
                }
            }
            globalThis.__functional_shim = JsFunctional;
            const oracle = globalThis.FunctionalOracle;
            if (oracle) {
                JsFunctional.any = oracle.any;
                JsFunctional.all = oracle.all;
                JsFunctional.firstOrNull = oracle.firstOrNull;
                JsFunctional.sumOfInt = oracle.sumOfInt;
                JsFunctional.sumOfFloat = oracle.sumOfFloat;
                JsFunctional.flatMap = oracle.flatMap;
            }
            globalThis.std = globalThis.std || {};
            globalThis.std.Functional = JsFunctional;
            globalThis.std.SortedMap = { builder: () => globalThis.__runtime_sorted_table.mapBuilder(jsCompare) };
            globalThis.std.SortedSet = { builder: () => globalThis.__runtime_sorted_table.setBuilder(jsCompare) };
        ");
    }

    public static function main():Void {
        bootstrap();
'
            + testCallLines.join("\n")
            + '
        if (failures > 0) {
            std.Process.exit(1);
        }
    }
}

@:expose("FunctionalOracle")
class FunctionalOracle {
    public static function any<T>(arr:Array<T>, fn:(item:T) -> Bool):Bool {
        return Lambda.exists(arr, fn);
    }

    public static function all<T>(arr:Array<T>, fn:(item:T) -> Bool):Bool {
        return Lambda.foreach(arr, fn);
    }

    public static function firstOrNull<T>(arr:Array<T>, fn:(item:T) -> Bool):Null<T> {
        return Lambda.find(arr, fn);
    }

    public static function sumOfInt<T>(arr:Array<T>, fn:(item:T) -> Int):Int {
        return Lambda.fold(arr, function(item:T, acc:Int):Int return acc + fn(item), 0);
    }

    public static function sumOfFloat<T>(arr:Array<T>, fn:(item:T) -> Float):Float {
        return Lambda.fold(arr, function(item:T, acc:Float):Float return acc + fn(item), 0.0);
    }

    public static function flatMap<T, R>(arr:Array<T>, fn:(item:T) -> Iterable<Dynamic>):Dynamic {
        return Lambda.flatMap(arr, fn);
    }
}

@:expose("StringBufOracle")
class StringBufOracle {
    var buf:StringBuf;

    public function new() {
        this.buf = new StringBuf();
    }

    public function add(part:String):Void {
        // stdlib/08 boundary check: a nonempty part that strands a held
        // lead faults; one trailing toString snapshot per checked call.
        final content = this.buf.toString();
        final tail = content.length > 0 ? content.charCodeAt(content.length - 1) : -1;
        if (tail >= 55296 && tail <= 56319 && part.length > 0) {
            final head = part.charCodeAt(0);
            if (!(head >= 56320 && head <= 57343)) {
                throw new UStringException(UnpairedSurrogate(tail));
            }
        }
        this.buf.add(part);
    }

    public function addChar(codeUnit:Int):Void {
        // stdlib/08 pairing check: a trail needs a held lead, any other
        // unit needs the absence of one.
        final content = this.buf.toString();
        final tail = content.length > 0 ? content.charCodeAt(content.length - 1) : -1;
        final heldLead = tail >= 55296 && tail <= 56319;
        if (codeUnit >= 56320 && codeUnit <= 57343) {
            if (!heldLead) {
                throw new UStringException(UnpairedSurrogate(codeUnit));
            }
        } else if (heldLead) {
            throw new UStringException(UnpairedSurrogate(tail));
        }
        this.buf.addChar(codeUnit);
    }

    public function get_length():Int {
        return this.buf.length;
    }

    public function toString():String {
        // stdlib/08 dangling-lead check: the trailing lead has no trail.
        final content = this.buf.toString();
        final tail = content.length > 0 ? content.charCodeAt(content.length - 1) : -1;
        if (tail >= 55296 && tail <= 56319) {
            throw new UStringException(UnpairedSurrogate(tail));
        }
        return content;
    }
}

';
        File.saveContent(outDir + "/TestMain.hx", runnerSource);
        // The cursor platform is a tracked source file shared with the typed
        // harness in tests/haxe; stage one compiles the copy next to TestMain
        // and binds it under globalThis.std.UStringPlatform.
        File.saveContent(outDir + "/UStringPlatform.hx", sys.io.File.getContent(Context.resolvePath("tests/haxe/UStringPlatform.hx")));
        // The test host edges of runtime.TestCore: stage one binds this
        // copy as globalThis.std.TestPlatform beside TestMain.
        File.saveContent(outDir + "/TestPlatform.hx", sys.io.File.getContent(Context.resolvePath("tests/haxe/TestPlatform.hx")));
    }
}
#end
