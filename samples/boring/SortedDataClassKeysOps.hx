package boring;

import std.SortedMap;
import std.ReadOnlyArray;

enum QuoteType { Open; Close; }
enum RubyKind { Bopomofo; Other; }

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
	public final fontFamilies:ReadOnlyArray<String>;
	public final kind:RubyKind;
	public final enumKinds:ReadOnlyArray<RubyKind>;
	public final ranges:ReadOnlyArray<TextRange>;
	public final locale:Null<String>;
	public function new(baseRange:TextRange, text:String, fontFamilies:ReadOnlyArray<String>, kind:RubyKind, enumKinds:ReadOnlyArray<RubyKind>, ranges:ReadOnlyArray<TextRange>, ?locale:String) {
		this.baseRange = baseRange; this.text = text; this.fontFamilies = fontFamilies; this.kind = kind; this.enumKinds = enumKinds; this.ranges = ranges;
		this.locale = locale == null ? (kind == RubyKind.Bopomofo ? "zh-TW" : null) : locale;
	}
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
		r.put(new RubySpan(new TextRange(3, 4), "z", ["serif"], RubyKind.Other, [RubyKind.Other], [new TextRange(3, 4)]), "nested"); r.put(new RubySpan(new TextRange(1, 2), "a", ["serif"], RubyKind.Other, [RubyKind.Bopomofo], [new TextRange(1, 2)]), "nested-first");
		final rm = r.build();
		return m.valueAt(0) + "," + m.valueAt(1) + ";" + qm.valueAt(0) + "," + qm.valueAt(1) + ";" + rm.valueAt(0) + "," + rm.valueAt(1);
	}

	public static function arrayMutations():String {
		final a = new RubySpan(new TextRange(1, 2), "x", ["serif"], RubyKind.Other, [RubyKind.Bopomofo, RubyKind.Other], [new TextRange(1, 2)]);
		final b = new RubySpan(new TextRange(1, 2), "x", ["serif"], RubyKind.Other, [RubyKind.Other, RubyKind.Other], [new TextRange(1, 2)]);
		final beforeBuilder:SortedMapBuilder<RubySpan, String> = SortedMap.builder();
		beforeBuilder.put(a, "a"); beforeBuilder.put(b, "b");
		final before = beforeBuilder.build();
		final c = new RubySpan(new TextRange(1, 2), "x", ["serif"], RubyKind.Other, [RubyKind.Other, RubyKind.Other], [new TextRange(1, 2)]);
		final d = new RubySpan(new TextRange(1, 2), "x", ["serif"], RubyKind.Other, [RubyKind.Bopomofo, RubyKind.Other], [new TextRange(1, 2)]);
		final afterBuilder:SortedMapBuilder<RubySpan, String> = SortedMap.builder();
		afterBuilder.put(c, "c"); afterBuilder.put(d, "d");
		final after = afterBuilder.build();
		final prefixBuilder:SortedMapBuilder<RubySpan, String> = SortedMap.builder();
		prefixBuilder.put(new RubySpan(new TextRange(1, 2), "x", ["serif"], RubyKind.Other, [RubyKind.Other, RubyKind.Bopomofo], [new TextRange(1, 2)]), "long");
		prefixBuilder.put(new RubySpan(new TextRange(1, 2), "x", ["serif"], RubyKind.Other, [RubyKind.Other], [new TextRange(1, 2)]), "short");
		final prefix = prefixBuilder.build();
		return before.valueAt(0) + before.valueAt(1) + ";" + after.valueAt(0) + after.valueAt(1) + ";" + prefix.valueAt(0) + "long";
	}

	public static function nullableMutation():String {
		final nullKey = new RubySpan(new TextRange(1, 2), "x", ["serif"], RubyKind.Other, [RubyKind.Other], [new TextRange(1, 2)]);
		final valueKey = new RubySpan(new TextRange(1, 2), "x", ["serif"], RubyKind.Other, [RubyKind.Other], [new TextRange(1, 2)], "en");
		final mapBuilder:SortedMapBuilder<RubySpan, String> = SortedMap.builder();
		mapBuilder.put(valueKey, "value"); mapBuilder.put(nullKey, "null");
		final map = mapBuilder.build();
		return map.valueAt(0) + ";value";
	}
}
