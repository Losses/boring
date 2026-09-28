package enumcomparison;

import std.RecordEq;
import std.SortedMap;

/**
    Bounded investigation subject for the enum record-key comparison.

    `Tag` declares one payload constructor and one parameterless
    constructor. `TagKey` is a `@:dataClass` record whose single stored
    field holds a `Tag`. The key gate in `PolicyQueries.isDataClassFieldKey`
    admits every `TEnum` field, so this record states the case standard
    library spec 16 rule 3 admits and specification 07 parameterless-enum
    ruling excludes. Every value the harness reads is constructed here; the
    harnesses call the generated comparator and the generated record
    equality expansion on these accessors and table reads only.
**/
enum Tag {
    Value(v:Int);
    Blank;
}

@:dataClass
class TagKey {
    public final tag:Tag;

    public function new(tag:Tag) {
        this.tag = tag;
    }
}

class EnumComparisonSubject {
    // Source-provided key values. The harnesses pass these to the generated
    // comparator, so no harness constructs an enum value or a record.
    public static function keyValue1():TagKey
        return new TagKey(Value(1));

    public static function keyValue1Again():TagKey
        return new TagKey(Value(1));

    public static function keyValue2():TagKey
        return new TagKey(Value(2));

    public static function keyBlank():TagKey
        return new TagKey(Blank);

    /**
        Table read for two keys whose payloads differ and whose constructor
        tag agrees. The size and the lookup results expose the generated
        comparison: the builder keeps one entry for a run of keys that the
        comparator reports as equal, and that entry is the last put, and
        `get` follows the same comparator.
    **/
    public static function mapDistinctPayload():String {
        final b:SortedMapBuilder<TagKey, String> = SortedMap.builder();
        b.put(new TagKey(Value(1)), "first");
        b.put(new TagKey(Value(2)), "second");
        final m = b.build();
        return "size="
            + m.size()
            + ";at0="
            + m.valueAt(0)
            + ";get1="
            + m.get(new TagKey(Value(1)))
            + ";get2="
            + m.get(new TagKey(Value(2)));
    }

    /** Table read for two keys with the same tag and the same payload. */
    public static function mapSamePayload():String {
        final b:SortedMapBuilder<TagKey, String> = SortedMap.builder();
        b.put(new TagKey(Value(1)), "first");
        b.put(new TagKey(Value(1)), "second");
        final m = b.build();
        return "size=" + m.size() + ";at0=" + m.valueAt(0) + ";get1=" + m.get(new TagKey(Value(1)));
    }

    /** Table read for two keys with distinct constructor tags. */
    public static function mapDistinctTags():String {
        final b:SortedMapBuilder<TagKey, String> = SortedMap.builder();
        b.put(new TagKey(Value(1)), "first");
        b.put(new TagKey(Blank), "second");
        final m = b.build();
        return "size=" + m.size() + ";at0=" + m.valueAt(0) + ";at1=" + m.valueAt(1);
    }

    /** Generated structural equality for two keys with distinct payloads. */
    public static function eqDistinctPayload():Bool {
        return RecordEq.eq(new TagKey(Value(1)), new TagKey(Value(2)));
    }

    /** Generated structural equality for two keys with the same payload. */
    public static function eqSamePayload():Bool {
        return RecordEq.eq(new TagKey(Value(1)), new TagKey(Value(1)));
    }

    /** Generated structural equality for two keys with distinct tags. */
    public static function eqDistinctTags():Bool {
        return RecordEq.eq(new TagKey(Value(1)), new TagKey(Blank));
    }
}
