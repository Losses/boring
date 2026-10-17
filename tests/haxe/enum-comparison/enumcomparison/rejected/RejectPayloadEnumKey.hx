package enumcomparison.rejected;

import std.SortedMap;

/**
    Rejection probe for the direct payload-enum key domain.

    `SortedMap<PayloadTag, Int>` names a payload enum as the key type, the
    form specification 07 parameterless-enum ruling excludes and the
    `classifyKey` `TEnum` arm rejects. The compilation must stop with the
    common diagnostic naming payload keys. The record-field boundary is
    exercised by the sibling `RejectPayloadEnumField` probe, which names a
    payload enum through a `@:dataClass` record field and is rejected by
    specification 16 rule 3 as narrowed.
**/
enum PayloadTag {
    Item(v:Int);
}

class RejectPayloadEnumKey {
    public static function build():Int {
        final b:SortedMapBuilder<PayloadTag, Int> = SortedMap.builder();
        b.put(Item(1), 1);
        return b.build().size();
    }
}
