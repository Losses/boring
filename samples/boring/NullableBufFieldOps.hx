package boring;

import std.StringBuf;
import std.UStringException;

private class NullableBufHolder {
    public final text:StringBuf;

    public function new() {
        this.text = new StringBuf();
    }

    public function render():String {
        return this.text.toString();
    }
}

/**
    A StringBuf field mutation whose owner local is a nullable wrapper. The
    guarded field subject must open the wrapper with `as_mut`, because the
    plain field read borrows through `as_ref` and cannot borrow the unit
    storage mutably.
*/
class NullableBufFieldOps {
    static function findHolder(present:Bool):Null<NullableBufHolder> {
        if (!present) {
            return null;
        }
        return new NullableBufHolder();
    }

    public static function appendGuarded(present:Bool, part:String):String {
        final holder = findHolder(present);
        if (holder == null) {
            return "";
        }
        holder.text.add(part);
        return holder.render();
    }

    public static function caughtFault(present:Bool, lead:Int, part:String):String {
        final holder = findHolder(present);
        if (holder == null) {
            return "";
        }
        try {
            holder.text.addChar(lead);
            holder.text.add(part);
        } catch (error:UStringException) {
            return "fault";
        }
        return holder.render();
    }
}
