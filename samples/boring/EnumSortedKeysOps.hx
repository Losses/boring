package boring;

import std.SortedMap;
import std.SortedSet;

enum EnumTier {
    Low;
    Mid;
    High;
}

enum ReverseTier {
    Later;
    Earlier;
}

class EnumSortedKeysOps {
    public static function describe():String {
        final b:SortedSetBuilder<EnumTier> = SortedSet.builder();
        b.put(EnumTier.High); b.put(EnumTier.Low); b.put(EnumTier.Mid);
        final s = b.build();
        var out = "";
        for (i in 0...s.size()) out += (i == 0 ? "" : ",") + Std.string(s.at(i));
        return out;
    }

    public static function mapOrder():String {
        final b:SortedMapBuilder<EnumTier, Int> = SortedMap.builder();
        b.put(EnumTier.High, 3); b.put(EnumTier.Low, 1); b.put(EnumTier.Mid, 2);
        final m = b.build();
        return Std.string(m.keyAt(0)) + ":" + Std.string(m.valueAt(0)) + ";" + Std.string(m.keyAt(1)) + ":" + Std.string(m.valueAt(1)) + ";" + Std.string(m.keyAt(2)) + ":" + Std.string(m.valueAt(2));
    }

    public static function has():Bool {
        final b:SortedSetBuilder<EnumTier> = SortedSet.builder(); b.put(EnumTier.Mid);
        final s = b.build();
        return s.has(EnumTier.Mid) && !s.has(EnumTier.High);
    }

    public static function declarationOrder():String {
        final b:SortedSetBuilder<ReverseTier> = SortedSet.builder(); b.put(ReverseTier.Earlier); b.put(ReverseTier.Later);
        final s = b.build(); return Std.string(s.at(0)) + "," + Std.string(s.at(1));
    }
}
