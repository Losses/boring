package boring;

// Regression sample for constructed static defaults. The read site must use
// the module static created for the constructed initializer.
class StaticLazyDefaultOps {
    public static function readDefault():SomeStruct {
        return consume(SomeStruct.DEFAULT_POLICY);
    }

    public static function readLazyValues():Array<String> {
        return StaticLazyAlias.DEFAULT_VALUES;
    }

    private static function consume(policy:SomeStruct):SomeStruct {
        return policy;
    }
}

class StaticLazyAlias {
    public static final DEFAULT_VALUES:Array<String> = ["default"];
}

class SomeStruct {
    public static final DEFAULT_POLICY:SomeStruct = new SomeStruct("default");

    public final name:String;

    public function new(name:String) {
        this.name = name;
    }
}
