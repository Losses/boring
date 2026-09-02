package boring;

import std.SortedMap;

enum QuoteType { Open; Close; }

@:dataClass
class TextRange {
	public final start:Int;
	public final end:Int;
	public function new(start:Int, end:Int) { this.start = start; this.end = end; }
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
		return m.valueAt(0) + "," + m.valueAt(1);
	}
}
