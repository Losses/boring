package boring;

enum OverrideMemberError {
    Payload(message:String);
}

class OverrideMemberException extends haxe.Exception {
    public final error:OverrideMemberError;
    public function new(error:OverrideMemberError) {
        this.error = error;
        super(describe(error));
    }
    public static function describe(error:OverrideMemberError):String {
        return switch (error) {
            case Payload(message): message;
        };
    }
}

@:dataClass
class OverrideMemberRecord {
    public final value:Int;
    public function new(value:Int) {
        this.value = value;
    }
    public function hashCode():Int {
        return value;
    }
    public function ordinary():String {
        return "ordinary";
    }
}

class OverrideMemberOps {
    public static function hash(value:Int):Int {
        return new OverrideMemberRecord(value).hashCode();
    }
    #if kotlin_output
    public static function ordinary():String {
        return "ordinary";
    }
    #end
    public static function message(value:String):String {
        return new OverrideMemberException(Payload(value)).message;
    }
}
