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
	public static function getField(value:JsonValue, name:String):JsonValue {
		return switch(value) {
			case JObject(fields): findField(fields, name);
			case JArray(_): JNull;
			case JString(_): JNull;
			case JNumber(_): JNull;
			case JBool(_): JNull;
			case JNull: JNull;
		};
	}
	static function findField(fields:Array<JsonField>, name:String):JsonValue {
		for(i in 0...fields.length) if(fields[i].name == name) return fields[i].value;
		return JNull;
	}
	public static function write(value:JsonValue):String { return render(value, 0) + "\n"; }
	public static function writeCompact(value:JsonValue):String { return renderCompact(value); }
	static function renderCompact(v:JsonValue):String return switch(v) {
		case JNull: "null";
		case JBool(b): if(b) "true" else "false";
		case JNumber(n): Std.string(n);
		case JString(s): quote(s);
		case JArray(a): compactArray(a);
		case JObject(fs): compactObject(fs);
	};
	static function compactArray(a:Array<JsonValue>):String {
		final parts = new Array<String>();
		for(i in 0...a.length) parts.push(renderCompact(a[i]));
		return "[" + parts.join(",") + "]";
	}
	static function compactObject(fs:Array<JsonField>):String {
		final parts = new Array<String>();
		for(i in 0...fs.length) parts.push(quote(fs[i].name) + ":" + renderCompact(fs[i].value));
		return "{" + parts.join(",") + "}";
	}
	static function indent(n:Int):String { var s = ""; for(i in 0...n) s += "  "; return s; }
	/** Hex digits via fromCharCode arithmetic: charAt-based table lookup
	is outside the string primitive subset the targets map. */
	static function hexDigit(v:Int):String return String.fromCharCode(v < 10 ? 48 + v : 87 + v);
	static function hex4(v:Int):String {
		return hexDigit((v >> 12) & 15) + hexDigit((v >> 8) & 15) + hexDigit((v >> 4) & 15) + hexDigit(v & 15);
	}
	static function quote(s:String):String {
		var out = '"';
		for(i in 0...s.length) {
			out += escapeOf(s.charCodeAt(i));
		}
		return out + '"';
	}
	static function escapeOf(c:Int):String {
		if(c == 8) return "\\b";
		if(c == 9) return "\\t";
		if(c == 10) return "\\n";
		if(c == 12) return "\\f";
		if(c == 13) return "\\r";
		if(c == 34) return '\\"';
		if(c == 92) return "\\\\";
		if(c < 32) return "\\u" + hex4(c);
		return String.fromCharCode(c);
	}
	static function render(v:JsonValue, level:Int):String return switch(v) {
		case JNull: "null";
		case JBool(b): if(b) "true" else "false";
		case JNumber(n): Std.string(n);
		case JString(s): quote(s);
		case JArray(a): renderArray(a, level);
		case JObject(fs): renderObject(fs, level);
	}
	static function renderArray(a:Array<JsonValue>, level:Int):String {
		if(a.length == 0) return "[]";
		final parts = new Array<String>();
		for(i in 0...a.length) parts.push(indent(level + 1) + render(a[i], level + 1));
		return "[\n" + parts.join(",\n") + "\n" + indent(level) + "]";
	}
	static function renderObject(fs:Array<JsonField>, level:Int):String {
		if(fs.length == 0) return "{}";
		final parts = new Array<String>();
		for(i in 0...fs.length) parts.push(indent(level + 1) + quote(fs[i].name) + ": " + render(fs[i].value, level + 1));
		return "{\n" + parts.join(",\n") + "\n" + indent(level) + "}";
	}
}

/** Cursor reader over the source text. Every character decision runs on
charCodeAt code points; charAt and substr stay out of the sources
because the target string mappings do not cover them. The parse
methods are named parseObject/parseArray since `object` is a Kotlin
keyword and would corrupt the generated declaration. */
private class Reader {
	final text:String; var p:Int;
	public function new(text:String) { this.text = text; this.p = 0; }
	public function parse():JsonValue { skip(); final v = value(); skip(); if(p != text.length) throw new JsonException(TrailingInput(p)); return v; }
	function value():JsonValue {
		skip();
		if(p >= text.length) fail();
		final k = text.charCodeAt(p);
		if(k == 123) return parseObject();
		if(k == 91) return parseArray();
		if(k == 34) return JString(string());
		if(k == 116) { word("true"); return JBool(true); }
		if(k == 102) { word("false"); return JBool(false); }
		if(k == 110) { word("null"); return JNull; }
		return number();
	}
	function parseObject():JsonValue { p = p + 1; var fs = new Array<JsonField>(); skip(); if(takeCode(125)) return JObject(fs); while(true) { skip(); if(text.charCodeAt(p) != 34) fail(); final n=string(); skip(); if(!takeCode(58)) fail(); fs.push({name:n,value:value()}); skip(); if(takeCode(125)) return JObject(fs); if(!takeCode(44)) fail(); } }
	function parseArray():JsonValue { p = p + 1; var a = new Array<JsonValue>(); skip(); if(takeCode(93)) return JArray(a); while(true) { a.push(value()); skip(); if(takeCode(93)) return JArray(a); if(!takeCode(44)) fail(); } }
	function string():String {
		p = p + 1; var out="";
		while(p<text.length) {
			var c=text.charCodeAt(p); p = p + 1;
			if(c==34) return out;
			if(c==92) {
				if(p>=text.length) fail();
				final e=text.charCodeAt(p); p = p + 1;
				if(e==34||e==92||e==47) { out+=String.fromCharCode(e); }
				else if(e==98) { out+="\\u0008"; }
				else if(e==102) { out+=String.fromCharCode(12); }
				else if(e==110) { out+='\n'; }
				else if(e==114) { out+='\r'; }
				else if(e==116) { out+='\t'; }
				else if(e==117) {
					var h=text.substring(p,p+4); if(h.length<4) fail();
					var code:Null<Int>=Std.parseInt("0x"+h);
					if(code==null) code=0;
					out+=String.fromCharCode(code);
					p = p + 4;
				}
				else fail();
			} else out+=String.fromCharCode(c);
		}
		fail(); return "";
	}
	function number():JsonValue { var start=p; while(p<text.length && isTerm(text.charCodeAt(p))==false) p = p + 1; final n=Std.parseFloat(text.substring(start,p)); if(Math.isNaN(n)) fail(); return JNumber(n); }
	static function isTerm(k:Int):Bool return k==44 || k==93 || k==125 || k==32 || k==9 || k==10 || k==13;
	function word(w:String):Void { if(text.substring(p,p+w.length)!=w) fail(); p = p + w.length; }
	function skip():Void while(p<text.length && isSpace(text.charCodeAt(p))) p = p + 1;
	static function isSpace(k:Int):Bool return k==32 || k==9 || k==10 || k==13;
	function takeCode(k:Int):Bool { if(text.charCodeAt(p)==k) {p = p + 1; return true;} return false; }
	function fail():Void throw new JsonException(InvalidJson);
}
