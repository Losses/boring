package boring;

import std.StringBuf;

class ArrayAccessOps {
    public static function writeSplit(text:String):String {
        final parts = text.split(",");
        parts[0] = "x";
        return parts[0];
    }

    public static function readSplit(text:String):String {
        final parts = text.split(",");
        return parts[0];
    }

    public static function compositeStringBufPart(value:String):Int {
#if kotlin_output
        final buffer = new StringBuf();
        buffer.add("" + value);
        final rendered = buffer.toString();
        return rendered.charCodeAt(0);
#else
        return value.charCodeAt(0);
#end
    }

    public static function simpleStringBufPart(value:String):Int {
#if kotlin_output
        final buffer = new StringBuf();
        buffer.add(value);
        final rendered = buffer.toString();
        return rendered.charCodeAt(0);
#else
        return value.charCodeAt(0);
#end
    }

    /**
        Haxe's Array grows when an index write reaches past the end and fills
        every skipped slot with the element type's default value, so an index
        write must not depend on the target's list already carrying the slot.
        (ArrayGrowthOnIndexWrite)
    **/
    public static function growNullableSlots():Array<Null<Int>> {
        final slots:Array<Null<Int>> = [];
        slots[3] = 7;
        return slots;
    }

    public static function growValueSlots():Array<Int> {
        final slots:Array<Int> = [];
        slots[2] = 5;
        return slots;
    }

    /** Tail, middle, and the append index, on a list that already carries
        values. The append index also covers an index expression that reads
        the length of the array the write grows. */
    public static function writeInsideSlots():Array<Int> {
        final slots = [1, 2, 3, 4];
        slots[1] = 20;
        slots[3] = 40;
        slots[slots.length] = 50;
        return slots;
    }

    public static function filledHolder(count:Int):Array<Null<Int>> {
        final holder = new ArrayGrowthHolder(count);
        return holder.readAll();
    }
}

/**
    The shape the Kotlin target met in the field: an array field that starts
    empty and an index loop that fills it from slot zero, so every write past
    the first grows the backing list. (ArrayGrowthOnIndexWrite)
**/
class ArrayGrowthHolder {
    public var slots:Array<Null<Int>>;

    public function new(count:Int) {
        slots = [];
        var i = 0;
        while (i <= count) {
            slots[i] = i * 10;
            i++;
        }
    }

    public function readAll():Array<Null<Int>> {
        return slots;
    }
}
