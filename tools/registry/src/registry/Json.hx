package registry;

/** An ordered, reflection-free JSON value tree. */
enum JsonValue {
	JObject(fields:Array<JsonField>);
	JArray(values:Array<JsonValue>);
	JString(value:String);
	JNumber(value:Float);
	JBool(value:Bool);
	JNull;
}

typedef JsonField = { name:String, value:JsonValue };

class Json {
	public static function read(text:String):JsonValue {
		return new Reader(text).parse();
	}
	public static function write(value:JsonValue):String {
		return render(value, 0) + "\n";
	}
	static function indent(n:Int):String { var s = ""; for(i in 0...n) s += "  "; return s; }
	static function quote(s:String):String {
		var out = '"';
		for(i in 0...s.length) {
			final c = s.charCodeAt(i);
			switch(c) {
				case 8: out += "\\b"; case 9: out += "\\t"; case 10: out += "\\n";
				case 12: out += "\\f"; case 13: out += "\\r"; case 34: out += '\\"'; case 92: out += "\\\\";
				default: if(c < 32) out += "\\u" + StringTools.hex(c, 4); else out += s.charAt(i);
			}
		}
		return out + '"';
	}
	static function render(v:JsonValue, level:Int):String return switch(v) {
		case JNull: "null"; case JBool(b): b ? "true" : "false"; case JNumber(n): Std.string(n);
		case JString(s): quote(s);
		case JArray(a): if(a.length == 0) "[]" else "[\n" + [for(x in a) indent(level+1) + render(x, level+1)].join(",\n") + "\n" + indent(level) + "]";
		case JObject(fs): if(fs.length == 0) "{}" else "{\n" + [for(f in fs) indent(level+1) + quote(f.name) + ": " + render(f.value, level+1)].join(",\n") + "\n" + indent(level) + "}";
	}
}

private class Reader {
	final text:String; var p:Int = 0;
	public function new(text:String) this.text = text;
	public function parse():JsonValue { skip(); final v = value(); skip(); if(p != text.length) fail(); return v; }
	function value():JsonValue { skip(); if(p >= text.length) fail(); return switch(text.charAt(p)) {
		case "{": object(); case "[": array(); case '"': JString(string()); case "t": word("true"); JBool(true);
		case "f": word("false"); JBool(false); case "n": word("null"); JNull; default: number();
	}; }
	function object():JsonValue { p++; var fs:Array<JsonField> = []; skip(); if(take("}")) return JObject(fs); while(true) { skip(); if(text.charAt(p) != '"') fail(); final n=string(); skip(); if(!take(":")) fail(); fs.push({name:n,value:value()}); skip(); if(take("}")) return JObject(fs); if(!take(",")) fail(); } }
	function array():JsonValue { p++; var a:Array<JsonValue>=[]; skip(); if(take("]")) return JArray(a); while(true) { a.push(value()); skip(); if(take("]")) return JArray(a); if(!take(",")) fail(); } }
	function string():String { p++; var out=""; while(p<text.length) { var c=text.charAt(p++); if(c=='"') return out; if(c=='\\') { if(p>=text.length) fail(); final e=text.charAt(p++); switch(e) { case '"'|'\\'|'/': out+=e; case 'b':out+='\b'; case 'f':out+='\f'; case 'n':out+='\n'; case 'r':out+='\r'; case 't':out+='\t'; case 'u': var h=text.substr(p,4); if(h.length<4) fail(); out+=String.fromCharCode(Std.parseInt("0x"+h)); p+=4; default: fail(); } } else out+=c; } fail(); return ""; }
	function number():JsonValue { var start=p; while(p<text.length && ",]} \t\r\n".indexOf(text.charAt(p))<0) p++; final n=Std.parseFloat(text.substr(start,p-start)); if(Math.isNaN(n)) fail(); return JNumber(n); }
	function word(w:String):Void { if(text.substr(p,w.length)!=w) fail(); p+=w.length; }
	function skip():Void while(p<text.length && " \t\r\n".indexOf(text.charAt(p))>=0) p++;
	function take(c:String):Bool { if(text.charAt(p)==c) {p++; return true;} return false; }
	function fail():Void throw "invalid JSON";
}
