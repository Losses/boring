package enumcomparison.rejected;

import std.SortedMap;

/**
    Rejection probe for the payload-enum record-field domain, the flip of the
    former accepted `TagKey` subject after the specification 16 kind 3
    narrowing.

    `Tag` declares one payload constructor and one parameterless constructor.
    `TagKey` is a `@:dataClass` record whose single stored field holds a
    `Tag`. Specification 16 rule 3 as narrowed admits only parameterless enum
    fields, so a payload enum field is any-other-type and the record cannot be
    a sorted key. The compilation must stop with the record-field diagnostic
    naming the record, the field, and the field type.
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

class RejectPayloadEnumField {
    public static function build():Int {
        final b:SortedMapBuilder<TagKey, Int> = SortedMap.builder();
        b.put(new TagKey(Value(1)), 1);
        return b.build().size();
    }
}

