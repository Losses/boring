package rusthandlefixtures;

// owned param: a handle passed by value to a static function.
class OwnedParam {
    public function new() {}
}

class OwnedParamOps {
    public static function consume(value:OwnedParam):Int {
        return 1;
    }

    public static function run():Int {
        final value = new OwnedParam();
        return consume(value);
    }
}
