package comparison;

import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

/**
    A stored Float field is outside the sorted-key domain, so the builder
    construction fails at the Haxe level with the domain diagnostic. This
    fixture exercises that rejection.
**/
@:dataClass
class RejectFloatKeyRecord {
    public final ratio:Float;
    public final label:String;

    public function new(ratio:Float, label:String) {
        this.ratio = ratio;
        this.label = label;
    }
}

class RejectFloatKey {
    public static function observe():String {
        final builder:SortedMapBuilder<RejectFloatKeyRecord, String> = SortedMap.builder();
        builder.build();
        return "unreached";
    }
}
