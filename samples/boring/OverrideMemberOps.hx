package boring;

#if kotlin_output
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
}
#else
@:dataClass
class OverrideMemberRecord {
    public final value:Int;
    public function new(value:Int) {
        this.value = value;
    }
    public function hashOf():Int {
        return value;
    }
}
#end

class OverrideMemberOps {
    public static function hash(value:Int):Int {
        #if kotlin_output
        return new OverrideMemberRecord(value).hashCode();
        #else
        return new OverrideMemberRecord(value).hashOf();
        #end
    }
    public static function ordinary():String {
        return "ordinary";
    }
    public static function message(value:String):String {
        #if kotlin_output
        return new OverrideMemberException(Payload(value)).message;
        #else
        return value;
        #end
    }
}
