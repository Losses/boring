package boring;

#if rust_output
/**
    An owned String return slot that receives a borrowed String parameter. The
    parameter renders as a str view, so a String-backed abstract return
    converts the view once at the boundary. The named borrowedStringReturn
    rule covers the fallible abstract-return form.
*/
class BorrowedStringReturnOps {
    public static function requireText(value:String):BorrowedStringReturnId {
        if (value.length == 0) {
            throw new BorrowedStringReturnFault("blank");
        }
        return cast(value, BorrowedStringReturnId);
    }
}

abstract BorrowedStringReturnId(String) {
    public var value(get, never):String;
    inline function get_value():String return this;
}

class BorrowedStringReturnFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}
#else
class BorrowedStringReturnOps {}
#end
