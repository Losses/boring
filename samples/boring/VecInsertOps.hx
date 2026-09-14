package boring;

#if rust_output
/**
    An Array insertion whose position is a Haxe Int (u32) while Vec::insert
    takes a usize index. The named vecInsertIndex rule widens the position
    through the lossless index conversion.
*/
class VecInsertOps {
    public static function insertAt(position:Int, value:Int):Array<Int> {
        final out = [1, 2, 3];
        out.insert(position, value);
        return out;
    }

    public static function firstAt(position:Int, value:Int):Int {
        return insertAt(position, value)[0];
    }
}
#else
class VecInsertOps {}
#end
