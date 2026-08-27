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
		for(i in 0...s.length) {
			final c = s.charAt(i);
			if(c == '"') buf.add('\\"');
			else if(c == "\\") buf.add("\\\\");
			else if(c == "\n") buf.add("\\n");
			else if(c == "\r") buf.add("\\r");
			else if(c == "\t") buf.add("\\t");
			else buf.add(c);
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

								// Validate public static Void -> Void
								if (!field.isPublic) {
									Context.error("Test function " + id + " must be public", field.pos);
								}

								final followedType = Context.follow(field.type);
								switch (followedType) {
									case TFun(args, ret):
										final followedRet = Context.follow(ret);
										var isVoid = switch (followedRet) {
											case TAbstract(a, _): a.get().name == "Void";
											case _: false;
										};
										if (args.length != 0 || !isVoid) {
											Context.error("Test function " + id + " must take no arguments and return Void", field.pos);
										}
									case _:
										Context.error("Test function " + id + " must be a function", field.pos);
								}

								var desc:Null<String> = null;
								for (entry in field.meta.extract(":test")) {
									if (entry.params != null && entry.params.length > 0) {
										switch (entry.params[0].expr) {
											case EConst(CString(s)): desc = s;
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
			testCallLines.push('            std.Test.run("' + t.id + '", "' + escapeName(t.name) + '", function() { ' + t.moduleName + '.' + t.fieldName + '(); });');
			testCallLines.push('        } catch (e:haxe.Exception) {');
			testCallLines.push('            failures++;');
			testCallLines.push('            std.Console.log(e.message);');
			testCallLines.push('        } catch (e:Dynamic) {');
			testCallLines.push('            failures++;');
			testCallLines.push('            std.Console.log(Std.string(e));');
			testCallLines.push('        }');
		}

		final runnerSource = 'package;

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
    static var currentTestId:Null<String> = null;

    static function escapeJson(s:String):String {
        var buf = new StringBuf();
        for (i in 0...s.length) {
            var c = s.charAt(i);
            var code = s.charCodeAt(i);
            if (c == \'"\') buf.add(\'\\\\"\');
            else if (c == \'\\\\\') buf.add(\'\\\\\\\\\');
            else if (c == \'\\n\') buf.add(\'\\\\n\');
            else if (c == \'\\r\') buf.add(\'\\\\r\');
            else if (c == \'\\t\') buf.add(\'\\\\t\');
            else if (code < 0x20) {
                var hex = StringTools.hex(code, 4).toLowerCase();
                buf.add(\'\\\\u\' + hex);
            } else {
                buf.add(c);
            }
        }
        return buf.toString();
    }

    static function formatCanonicalMessage(id:String, message:Null<String>, expectedStr:Null<String>, actualStr:Null<String>, isEquals:Bool):String {
        var lines:Array<String> = ["test failed: " + id];
        if (message != null && message.length > 0) {
            lines.push("  message: " + message);
        }
        if (isEquals) {
            lines.push("  expected: " + (expectedStr != null ? expectedStr : ""));
            lines.push("  actual:   " + (actualStr != null ? actualStr : ""));
        }
        return lines.join("\\n");
    }

    static function recordResult(id:String, name:String, verdict:String, message:Null<String>):Void {
        var envPath = NodeProcess.env.get("BORING_TEST_RESULTS");
        var filePath = envPath != null && envPath.length > 0 ? envPath : "out/test-results/haxe.jsonl";
        var jsonLine:String;
        if (verdict == "pass") {
            jsonLine = \'{"id":"\' + escapeJson(id) + \'","name":"\' + escapeJson(name) + \'","verdict":"pass"}\\n\';
        } else {
            jsonLine = \'{"id":"\' + escapeJson(id) + \'","name":"\' + escapeJson(name) + \'","verdict":"fail","message":"\' + escapeJson(message != null ? message : "") + \'"}\\n\';
        }
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
        if (Std.isOfType(v, Bool)) return v ? "true" : "false";
        if (Std.isOfType(v, Int)) return "" + v;
        if (Std.isOfType(v, Float)) {
            if (Math.isNaN(v)) return "NaN";
            if (v == Math.POSITIVE_INFINITY) return "Infinity";
            if (v == Math.NEGATIVE_INFINITY) return "-Infinity";
            if (v == 0.0 || v == -0.0) return "0";
            return "" + v;
        }
        if (Std.isOfType(v, String)) {
            return \'"\' + escapeJson(v) + \'"\';
        }
        if (Std.isOfType(v, haxe.io.Bytes)) {
            return (cast v : haxe.io.Bytes).toHex();
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
                currentTestId = id;
                try {
                    body();
                    currentTestId = null;
                    recordResult(id, name, "pass", null);
                } catch (e:haxe.Exception) {
                    currentTestId = null;
                    recordResult(id, name, "fail", e.message);
                    throw e;
                } catch (e:Dynamic) {
                    currentTestId = null;
                    var msg = Std.string(e);
                    recordResult(id, name, "fail", msg);
                    throw new haxe.Exception(msg);
                }
            },
            ok: function(condition:Bool, message:Null<String> = null):Void {
                if (!condition) {
                    var canonical = formatCanonicalMessage(currentTestId != null ? currentTestId : "", message, null, null, false);
                    throw new haxe.Exception(canonical);
                }
            },
            equals: function(expected:Dynamic, actual:Dynamic, message:Null<String> = null):Void {
                if (!deepEquals(expected, actual)) {
                    var canonical = formatCanonicalMessage(currentTestId != null ? currentTestId : "", message, formatValue(expected), formatValue(actual), true);
                    throw new haxe.Exception(canonical);
                }
            },
            fail: function(message:String):Void {
                var canonical = formatCanonicalMessage(currentTestId != null ? currentTestId : "", message, null, null, false);
                throw new haxe.Exception(canonical);
            }
        };
        js.Syntax.code("globalThis.__test_shim = {0}", testObj);
    }

    public static function main():Void {
        bootstrap();
' + testCallLines.join("\n") + '
        if (failures > 0) {
            std.Process.exit(1);
        }
    }
}
';
		File.saveContent(outDir + "/TestMain.hx", runnerSource);
	}
}
#end
