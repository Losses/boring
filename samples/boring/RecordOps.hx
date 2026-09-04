package boring;

using std.RecordCopy;

typedef ItemRecord = {
    final id:Int;
    final name:String;
    final score:Int;
    final active:Bool;
};

class RecordOps {
    public static function makeItem(id:Int, name:String, score:Int, active:Bool):ItemRecord {
        return {
            id: id,
            name: name,
            score: score,
            active: active
        };
    }

    public static function copyNoOverride(item:ItemRecord):ItemRecord {
        return item.copy();
    }

    public static function copySingleOverride(item:ItemRecord, newScore:Int):ItemRecord {
        return item.copy(score = newScore);
    }

    public static function copyReordered(item:ItemRecord, newActive:Bool, newName:String):ItemRecord {
        return item.copy(active = newActive, name = newName);
    }

    public static function copyMultiple(item:ItemRecord, newId:Int, newName:String, newScore:Int):ItemRecord {
        return item.copy(score = newScore, id = newId, name = newName);
    }
}
