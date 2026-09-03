package boring;

import std.SortedMap;

enum QuoteType { Open; Close; }

@:dataClass
class TextRange {
	public final start:Int;
	public final end:Int;
	public function new(start:Int, end:Int) { this.start = start; this.end = end; }
	public var isEmpty(get, never):Bool;
	public function get_isEmpty():Bool return start == end;
}

@:dataClass
class RubySpan {
	public final baseRange:TextRange;
	public final text:String;
	public function new(baseRange:TextRange, text:String) { this.baseRange = baseRange; this.text = text; }
}

@:dataClass
class QuotePair {
	public final openIndex:Int;
	public final closeIndex:Int;
	public final quoteType:QuoteType;
	public function new(openIndex:Int, closeIndex:Int, quoteType:QuoteType) { this.openIndex = openIndex; this.closeIndex = closeIndex; this.quoteType = quoteType; }
}

class SortedDataClassKeysOps {
	public static function read():String {
		final b:SortedMapBuilder<TextRange, String> = SortedMap.builder();
		b.put(new TextRange(4, 8), "b"); b.put(new TextRange(1, 2), "a");
		final m = b.build();
		final q = SortedMap.builder();
		q.put(new QuotePair(2, 4, QuoteType.Close), "close"); q.put(new QuotePair(2, 4, QuoteType.Open), "open");
		final qm = q.build();
		final r = SortedMap.builder();
		r.put(new RubySpan(new TextRange(3, 4), "z"), "nested"); r.put(new RubySpan(new TextRange(1, 2), "a"), "nested-first");
		final rm = r.build();
		return m.valueAt(0) + "," + m.valueAt(1) + ";" + qm.valueAt(0) + "," + qm.valueAt(1) + ";" + rm.valueAt(0) + "," + rm.valueAt(1);
	}
}
