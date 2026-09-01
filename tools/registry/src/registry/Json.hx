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

/** Failure identity for the reader: malformed JSON text, split by
the two branches parse() actually distinguishes. */
enum JsonFault {
	InvalidJson;
	TrailingInput(position:Int);
}

/** The only exception shape the reader throws, per the error taxonomy
discipline of docs/specs/features/06-errors-and-results.md. */
class JsonException extends haxe.Exception {
	public final fault:JsonFault;

	public function new(fault:JsonFault) {
		this.fault = fault;
		super(JsonException.describe(fault));
	}
	public static function describe(fault:JsonFault):String {
		return switch (fault) {
			case InvalidJson: "invalid JSON";
			case TrailingInput(position): "trailing characters at offset " + position;
		};
	}
}

@:keep
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
	static function hex4(v:Int):String {
		final digits = "0123456789abcdef";
		return digits.charAt((v >> 12) & 15) + digits.charAt((v >> 8) & 15) + digits.charAt((v >> 4) & 15) + digits.charAt(v & 15);
	}
	static function quote(s:String):String {
		var out = '"';
		for(i in 0...s.length) {
			out += escapeOf(s, s.charCodeAt(i), i);
		}
		return out + '"';
	}
	static function escapeOf(s:String, c:Int, i:Int):String {
		if(c == 8) return "\\b";
		if(c == 9) return "\\t";
		if(c == 10) return "\\n";
		if(c == 12) return "\\f";
		if(c == 13) return "\\r";
		if(c == 34) return '\\"';
		if(c == 92) return "\\\\";
		if(c < 32) return "\\u" + hex4(c);
		return s.charAt(i);
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

private class Reader {
	final text:String; var p:Int;
	public function new(text:String) { this.text = text; this.p = 0; }
	public function parse():JsonValue { skip(); final v = value(); skip(); if(p != text.length) throw new JsonException(TrailingInput(p)); return v; }
	function value():JsonValue {
		skip();
		if(p >= text.length) fail();
		final c = text.charAt(p);
		if(c == "{") return object();
		if(c == "[") return array();
		if(c == '"') return JString(string());
		if(c == "t") { word("true"); return JBool(true); }
		if(c == "f") { word("false"); return JBool(false); }
		if(c == "n") { word("null"); return JNull; }
		return number();
	}
	function object():JsonValue { p = p + 1; var fs = new Array<JsonField>(); skip(); if(take("}")) return JObject(fs); while(true) { skip(); if(text.charAt(p) != '"') fail(); final n=string(); skip(); if(!take(":")) fail(); fs.push({name:n,value:value()}); skip(); if(take("}")) return JObject(fs); if(!take(",")) fail(); } }
	function array():JsonValue { p = p + 1; var a = new Array<JsonValue>(); skip(); if(take("]")) return JArray(a); while(true) { a.push(value()); skip(); if(take("]")) return JArray(a); if(!take(",")) fail(); } }
	function string():String {
		p = p + 1; var out="";
		while(p<text.length) {
			var c=text.charAt(p); p = p + 1;
			if(c=='"') return out;
			if(c=='\\') {
				if(p>=text.length) fail();
				final e=text.charAt(p); p = p + 1;
				if(e=='"'||e=='\\'||e=='/') { out+=e; }
				else if(e=='b') { out+=String.fromCharCode(8); }
				else if(e=='f') { out+=String.fromCharCode(12); }
				else if(e=='n') { out+='\n'; }
				else if(e=='r') { out+='\r'; }
				else if(e=='t') { out+='\t'; }
				else if(e=='u') {
					var h=text.substr(p,4); if(h.length<4) fail();
					var code:Null<Int>=Std.parseInt("0x"+h);
					if(code==null) code=0;
					out+=String.fromCharCode(code);
					p = p + 4;
				}
				else fail();
			} else out+=c;
		}
		fail(); return "";
	}
	function number():JsonValue { var start=p; while(p<text.length && ",]} \t\r\n".indexOf(text.charAt(p))<0) p = p + 1; final n=Std.parseFloat(text.substr(start,p-start)); if(Math.isNaN(n)) fail(); return JNumber(n); }
	function word(w:String):Void { if(text.substr(p,w.length)!=w) fail(); p = p + w.length; }
	function skip():Void while(p<text.length && " \t\r\n".indexOf(text.charAt(p))>=0) p = p + 1;
	function take(c:String):Bool { if(text.charAt(p)==c) {p = p + 1; return true;} return false; }
	function fail():Void throw new JsonException(InvalidJson);
}
