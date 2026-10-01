import std.Graphemes;
import std.SortedMap;
import std.SortedSet;
import std.UStringRT;

/**
 * Consumer entry of the resident-closure measurement (t-mum0mp8l-m0a6).
 *
 * Every call goes through the std extern face only: the StringTools
 * statics that no target inlines (lpad, replace), std.UStringRT,
 * std.Graphemes, and the std.SortedMap / std.SortedSet builder
 * externs. The entry never names a runtime.* module; whether the
 * resident modules behind those externs are typed at all is decided
 * by the hxml root list alone:
 *
 *   gen/<target>-a.hxml roots only Consumer (the shape under test);
 *   gen/<target>-b.hxml adds the runtime.* roots the examples list.
 */
class Consumer {
    public static function stringToolsFace(text:String):String {
        return StringTools.replace(StringTools.lpad(text, "0", 6), "0", ".");
    }

    public static function uStringFace(text:String):Int {
        final units:Int = UStringRT.count(text);
        final first:Null<Int> = UStringRT.at(text, 0);
        return units + (first == null ? 0 : 1);
    }

    public static function graphemeFace(text:String):Int {
        return Graphemes.count(text) + Graphemes.parts(text).length + Graphemes.boundaries(text).length;
    }

    public static function sortedMapFace():String {
        final b:SortedMapBuilder<Int, String> = SortedMap.builder();
        b.put(2, "two");
        b.put(1, "one");
        final m = b.build();
        final value:Null<String> = m.get(1);
        return Std.string(m.keyAt(0)) + ":" + (value == null ? "none" : value) + ":" + (m.has(2) ? "yes" : "no") + ":" + Std.string(m.size());
    }
    public static function sortedSetFace():String {
        final b:SortedSetBuilder<Int> = SortedSet.builder();
        b.put(3);
        b.put(1);
        final s = b.build();
        return Std.string(s.at(0)) + ":" + (s.has(3) ? "yes" : "no") + ":" + Std.string(s.size());
    }
}
