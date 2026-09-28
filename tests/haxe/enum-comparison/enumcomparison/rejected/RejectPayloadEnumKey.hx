package enumcomparison.rejected;

import std.SortedMap;

/**
    Rejection probe for the direct payload-enum key domain.

    `SortedMap<PayloadTag, Int>` names a payload enum as the key type, the
    form specification 07 parameterless-enum ruling excludes and the
    `classifyKey` `TEnum` arm rejects. The compilation must stop with the
    common diagnostic naming payload keys. The probe states the boundary the
    accepted record-field case crosses: the same enum inside a `@:dataClass`
    record field is admitted by `isDataClassFieldKey`, which returns true for
    every `TEnum` field.
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
