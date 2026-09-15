package boring;

#if rust_output
/**
    An owned boundary that receives a borrowed loop item. A loop over an Array
    parameter or an owned local yields a Rust reference, so a constructor
    argument, an object literal field, an ordinary call argument, and an
    Option return slot clone the referent. The named borrowedLoopItem rule
    covers each site.
*/
enum BorrowedLoopItemEntry {
    Entry(label:String);
}

/** A no-argument enum whose loop items stay references in Rust. **/
enum BorrowedLoopMarker {
    MarkerAlpha;
    MarkerBeta;
}

class BorrowedLoopItemHolder {
    public final entry:BorrowedLoopItemEntry;

    public function new(entry:BorrowedLoopItemEntry) {
        this.entry = entry;
    }
}

typedef BorrowedLoopItemRecord = {
    var tag:String;
    var entry:BorrowedLoopItemEntry;
}

class BorrowedLoopItemBoundaryOps {
    public static function describe(entry:BorrowedLoopItemEntry):String {
        return switch (entry) {
            case Entry(label): label;
        };
    }

    public static function firstEntry(entries:Array<BorrowedLoopItemEntry>):Null<BorrowedLoopItemEntry> {
        for (entry in entries) {
            return entry;
        }
        return null;
    }

    public static function wrappedEntries(entries:Array<BorrowedLoopItemEntry>):Array<BorrowedLoopItemHolder> {
        final out = [];
        for (entry in entries) {
            out.push(new BorrowedLoopItemHolder(entry));
        }
        return out;
    }

    public static function describedLabels(entries:Array<BorrowedLoopItemEntry>):Array<String> {
        final out = [];
        for (entry in entries) {
            out.push(describe(entry));
        }
        return out;
    }

    public static function records(entries:Array<BorrowedLoopItemEntry>):Array<BorrowedLoopItemRecord> {
        final out = [];
        for (entry in entries) {
            final record:BorrowedLoopItemRecord = {tag: "tag", entry: entry};
            out.push(record);
        }
        return out;
    }

    public static function hasMarker(markers:Array<BorrowedLoopMarker>, target:BorrowedLoopMarker):Bool {
        for (marker in markers) {
            if (marker == target)
                return true;
        }
        return false;
    }

    public static function indexOfNullableInts(values:Null<Array<Int>>, target:Int):Int {
        return values == null ? -1 : values.indexOf(target);
    }

    public static function indexOfNullableStrings(values:Null<Array<String>>, needle:String):Int {
        return values == null ? -1 : values.indexOf(needle);
    }
}
#else
class BorrowedLoopItemBoundaryOps {}
#end
