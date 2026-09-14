package boring;

#if rust_output
/**
    An owned Int constructor slot that receives a signed i32 rendering while
    the parameter is the business u32 domain. A wrapping binop result and a
    negated i32-domain local reinterpret their bits at the constructor
    boundary. The named signedIntConstructor rule covers the position.
*/
class SignedIntConstructorBox {
    public final value:Int;

    public function new(value:Int) {
        this.value = value;
    }
}

class SignedIntConstructorOps {
    public static function sumIndex(text:String, offset:Int):Int {
        final index = text.indexOf("x");
        final box = new SignedIntConstructorBox(index + offset);
        return box.value;
    }

    public static function negatedIndex(text:String):Int {
        final index = text.indexOf("x");
        final box = new SignedIntConstructorBox(-index);
        return box.value;
    }
}
#else
class SignedIntConstructorOps {}
#end
