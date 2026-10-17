package enumcomparison;

import std.RecordEq;
import std.SortedMap;

/**
    Bounded investigation subject for the parameterless-enum record-key
    comparison, after the specification 16 kind 3 narrowing.

    `Rank` declares two parameterless constructors, `First` and `Second`.
    `RankKey` is a `@:dataClass` record whose single stored field holds a
    `Rank`. Specification 16 rule 3 as narrowed admits only parameterless
    enum fields, so this record states the admitted case: the two constructors
    are ordered by declaration order, and the generated structural equality
    agrees with that order. Every value the harness reads is constructed here;
    the harnesses call the generated comparator and the generated record
    equality expansion on these accessors and table reads only.
**/
enum Rank {
    First;
    Second;
}

@:dataClass
class RankKey {
    public final rank:Rank;

    public function new(rank:Rank) {
        this.rank = rank;
    }
}

class EnumComparisonSubject {
    // Source-provided key values. The harnesses pass these to the generated
    // comparator, so no harness constructs an enum value or a record.
    public static function keyFirst():RankKey
        return new RankKey(First);

    public static function keyFirstAgain():RankKey
        return new RankKey(First);

    public static function keySecond():RankKey
        return new RankKey(Second);

    /** Table read for two keys with distinct constructor tags. */
    public static function mapDistinctTags():String {
        final b:SortedMapBuilder<RankKey, String> = SortedMap.builder();
        b.put(new RankKey(First), "first");
        b.put(new RankKey(Second), "second");
        final m = b.build();
        return "size=" + m.size() + ";at0=" + m.valueAt(0) + ";at1=" + m.valueAt(1);
    }

    /** Generated structural equality for two keys with distinct tags. */
    public static function eqDistinctTags():Bool {
        return RecordEq.eq(new RankKey(First), new RankKey(Second));
    }
}

