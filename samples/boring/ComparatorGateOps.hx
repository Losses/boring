package boring;

import std.ReadOnlyArray;

/** Data classes used to verify that comparator references follow comparator emission. */
@:dataClass
class ComparatorBoolRecord {
    public final id:Int;
    public final enabled:Bool;

    public function new(id:Int, enabled:Bool) {
        this.id = id;
        this.enabled = enabled;
    }
}

@:dataClass
class ComparatorFloatRecord {
    public final id:Int;
    public final weight:Float;

    public function new(id:Int, weight:Float) {
        this.id = id;
        this.weight = weight;
    }
}

@:dataClass
class ComparatorIntStringRecord {
    public final id:Int;
    public final name:String;

    public function new(id:Int, name:String) {
        this.id = id;
        this.name = name;
    }
}

@:dataClass
class ComparatorNestedRecord {
    public final value:ComparatorIntStringRecord;

    public function new(value:ComparatorIntStringRecord) {
        this.value = value;
    }
}

#if dart_output
@:dataClass
class ComparatorReferenceRecord {
    public final boolRecord:ComparatorBoolRecord;
    public final floatRecord:ComparatorFloatRecord;
    public final nullableBoolRecord:Null<ComparatorBoolRecord>;
    public final boolRecords:ReadOnlyArray<ComparatorBoolRecord>;

    public function new(boolRecord:ComparatorBoolRecord, floatRecord:ComparatorFloatRecord,
            nullableBoolRecord:Null<ComparatorBoolRecord>, boolRecords:ReadOnlyArray<ComparatorBoolRecord>) {
        this.boolRecord = boolRecord;
        this.floatRecord = floatRecord;
        this.nullableBoolRecord = nullableBoolRecord;
        this.boolRecords = boolRecords;
    }
}
#end

class ComparatorGateOps {
    public static function comparable():ComparatorNestedRecord {
        return new ComparatorNestedRecord(new ComparatorIntStringRecord(1, "ok"));
    }

#if dart_output
    public static function unsupported():ComparatorReferenceRecord {
        return new ComparatorReferenceRecord(new ComparatorBoolRecord(1, true), new ComparatorFloatRecord(1, 1.5), null,
            [new ComparatorBoolRecord(2, false)]);
    }
#end
}
